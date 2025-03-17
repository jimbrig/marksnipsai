# File: ~/Downloads/MarkSnips/Source/watch.ps1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$BackupNow
)

# Import required scripts
$scriptRoot = $PSScriptRoot
$configModule = Join-Path $scriptRoot "config.ps1"
$enhanceModule = Join-Path $scriptRoot "enhance.ps1"

# Source the scripts
. $configModule
. $enhanceModule

# Import PSAI module
Import-Module PSAI

# Load or initialize configuration
$config = Import-MarkSnipsConfig -ConfigPath $ConfigPath
if (-not $config) {
    $config = Initialize-MarkSnipsConfig -ConfigPath $ConfigPath
    Write-Host "Created new configuration file at $ConfigPath" -ForegroundColor Green
}

# Extract configuration values
$baseFolder = $config.Folders.Base
$originalFolder = $config.Folders.Originals
$enhancedFolder = $config.Folders.Enhanced
$logDir = $config.Folders.Logs
$logFile = $config.Files.LogFile
$fileFilter = $config.Watcher.FileFilter
$pollingInterval = $config.Watcher.PollingInterval
$heartbeatInterval = $config.Watcher.HeartbeatInterval
$processingDelay = $config.Watcher.ProcessingDelay
$fileTrackingExpiration = $config.Watcher.FileTrackingExpiration

# Run immediate backup if requested
if ($BackupNow) {
    if ($PSCmdlet.ShouldProcess("MarkSnips data", "Create backup")) {
        Write-Host "Creating backup..." -ForegroundColor Yellow
        $backupPath = Backup-MarkSnipsData -Config $config
        if ($backupPath) {
            Write-Host "Backup created successfully at: $backupPath" -ForegroundColor Green
        } else {
            Write-Host "Backup failed" -ForegroundColor Red
        }
    }
}

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [switch]$Warning,
        [switch]$IsError
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    # Log to file
    $logMessage | Out-File -Append -FilePath $logFile
    
    # Log to console with appropriate color
    if ($IsError) {
        Write-Host $logMessage -ForegroundColor Red
    } elseif ($Warning) {
        Write-Host $logMessage -ForegroundColor Yellow
    } else {
        Write-Host $logMessage
        Write-Verbose $Message
    }
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message
    )
    
    # Check if notifications are enabled in config
    if (-not $config.Notifications.Enabled) {
        return
    }
    
    # For success notifications, check if they're enabled
    if ($Title -like "*Success*" -and -not $config.Notifications.ShowSuccessNotifications) {
        return
    }
    
    # For error notifications, check if they're enabled
    if ($Title -like "*Error*" -and -not $config.Notifications.ShowErrorNotifications) {
        return
    }
    
    try {
        # Try Windows 10/11 notification API
        Add-Type -AssemblyName System.Windows.Forms
        $notification = New-Object System.Windows.Forms.NotifyIcon
        $notification.Icon = [System.Drawing.SystemIcons]::Information
        $notification.BalloonTipTitle = $Title
        $notification.BalloonTipText = $Message
        $notification.Visible = $true
        $notification.ShowBalloonTip(5000)
        
        # Force garbage collection to prevent icon persisting
        [System.GC]::Collect()
        Write-Log "Notification displayed: $Title - $Message"
    } catch {
        Write-Log "Failed to display notification: $($_.Exception.Message)" -Warning
    }
}

function Get-AIGeneratedFileName {
    param(
        [string]$FilePath,
        [string]$OriginalName
    )
    
    try {
        # Read the content of the file
        $fileContent = Get-Content -Path $FilePath -Raw
        
        # Get the filename prompt from config and replace the content placeholder
        $prompt = $config.AIPrompts.FilenamePrompt -replace '\{content\}', $fileContent
        
        Write-Log "Requesting AI to generate filename for: $OriginalName"
        
        # Call OpenAI to generate a filename
        $aiResponse = Invoke-OAIChat $prompt -ErrorAction Stop
        
        # Clean up the response (just in case it contains extra text)
        $aiFilename = $aiResponse.Trim()
        
        # Ensure it has .md extension
        if (-not $aiFilename.EndsWith('.md')) {
            $aiFilename = $aiFilename + '.md'
        }
        
        # Add date prefix
        $datePrefix = Get-Date -Format "yyyy-MM-dd"
        $finalName = "$datePrefix-$aiFilename"
        
        # Replace any invalid characters that AI might have included
        $finalName = $finalName -replace '[\\/:*?"<>|]', '-'
        
        Write-Log "AI generated filename: $finalName"
        return $finalName
    } catch {
        # If AI rename fails, fall back to date-based naming
        Write-Log "Failed to generate AI filename: $($_.Exception.Message)" -Warning
        
        # Remove common prefix patterns and clean up
        $cleanName = $OriginalName -replace '^MarkSnips_', ''
        $cleanName = $cleanName -replace '[-_\s]', '-'
        
        # Add date prefix
        $datePrefix = Get-Date -Format "yyyy-MM-dd"
        return "$datePrefix-$cleanName"
    }
}

function Process-MarkdownFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$FilePath
    )
    
    $name = Split-Path $FilePath -Leaf
    
    # Skip files that appear to be enhanced versions or in subdirectories
    if ($name -like "README.md" -or
        $name -like "CHANGELOG.md" -or
        $name -like "*-enhanced.md" -or 
        $name -like "*.backup.md" -or 
        $FilePath -like "*\Enhanced\*" -or 
        $FilePath -like "*\Originals\*" -or 
        $name -eq "watcher-test-file.tmp") {
        
        Write-Log "Skipping processing for: $name"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess($name, "Process markdown file")) {
        return
    }
    
    try {
        # First make sure we have access to the file
        $fileContent = Get-Content -Path $FilePath -Raw
        Write-Log "File content accessed successfully"
        
        # Copy to originals first
        $originalPath = Join-Path $originalFolder $name
        Copy-Item -Path $FilePath -Destination $originalPath -Force
        Write-Log "Copied original file to: $originalPath"
        
        # Get AI-generated filename
        $aiFilename = Get-AIGeneratedFileName -FilePath $originalPath -OriginalName $name
        $enhancedPath = Join-Path $enhancedFolder $aiFilename
        
        Write-Log "Processing file from original location: $originalPath -> $enhancedPath"
        
        # Get the enhancement prompt from config and replace the content placeholder
        $prompt = $config.AIPrompts.EnhancementPrompt -replace '\{content\}', $fileContent
        
        # Call the enhancement function
        $enhancedContent = Invoke-OAIChat $prompt
        
        # Process the response - strip code fences
        $enhancedLines = $enhancedContent.Split("`n")
        $startIndex = 0
        $endIndex = $enhancedLines.Length - 1
        
        # Check for code fences
        if ($enhancedLines[0] -match "^```markdown" -or $enhancedLines[0] -match "^```$") {
            $startIndex = 1
        }
        if ($enhancedLines[$endIndex] -match "^```$") {
            $endIndex -= 1
        }
        
        # Join without code fences
        $cleanContent = $enhancedLines[$startIndex..$endIndex] -join "`n"
        
        # Create output file
        if (Test-Path $enhancedPath) {
            Remove-Item $enhancedPath -Force
        }
        Set-Content -Path $enhancedPath -Value $cleanContent -Force
        
        # Now remove the original from the watch folder
        if (Test-Path $FilePath) {
            Remove-Item -Path $FilePath -Force
            Write-Log "Removed original file from watch folder"
        } else {
            Write-Log "Original file no longer exists in watch folder" -Warning
        }
        
        Write-Log "Successfully enhanced: $name -> $aiFilename"
        
        # Show notification
        Show-Notification -Title "Markdown Enhanced" -Message "Successfully enhanced: $aiFilename"
        
        return $true
    } catch {
        Write-Log "ERROR processing $name`: $($_.Exception.Message)" -IsError
        Show-Notification -Title "Enhancement Error" -Message "Failed to process: $name"
        return $false
    }
}

# Ensure folders exist
foreach ($folder in @($baseFolder, $originalFolder, $enhancedFolder, $logDir)) {
    if (-not (Test-Path $folder)) {
        if ($PSCmdlet.ShouldProcess($folder, "Create folder")) {
            Write-Log "Creating folder: $folder"
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            
            # Verify folder was created successfully
            if (Test-Path $folder) {
                Write-Log "Folder created successfully: $folder"
            } else {
                Write-Log "Failed to create folder: $folder" -IsError
            }
        }
    } else {
        Write-Verbose "Folder already exists: $folder"
    }
}

Write-Log "=== Starting file watcher ==="
Write-Log "Monitoring folder: $baseFolder"
Write-Log "Log file: $logFile"
Write-Log "Config file: $ConfigPath"

# Write the correct paths to confirm they're working
Write-Verbose "Current folder ($PWD): $PWD"
Write-Verbose "PSScriptRoot: $PSScriptRoot"
Write-Verbose "Base folder: $baseFolder"
Write-Verbose "Enhanced folder: $enhancedFolder"
Write-Verbose "Originals folder: $originalFolder"

# Starting polling-based watcher
Write-Log "Starting polling-based file watcher"
Show-Notification -Title "Markdown Watcher Active" -Message "Monitoring for new files in: $baseFolder"

# Check if backup is needed on startup
if ($config.Backup.Enabled) {
    $lastBackup = $config.Backup.LastBackup
    $backupNeeded = $false
    
    if (-not $lastBackup) {
        $backupNeeded = $true
    } else {
        $lastBackupTime = [datetime]::Parse($lastBackup)
        $nextBackupTime = $lastBackupTime.AddHours($config.Backup.BackupInterval)
        if ((Get-Date) -gt $nextBackupTime) {
            $backupNeeded = $true
        }
    }
    
    if ($backupNeeded) {
        if ($PSCmdlet.ShouldProcess("MarkSnips data", "Perform scheduled backup")) {
            Write-Log "Performing scheduled backup"
            $backupFile = Backup-MarkSnipsData -Config $config
            if ($backupFile) {
                Write-Log "Backup created: $backupFile"
            } else {
                Write-Log "Backup failed" -IsError
            }
        }
    }
}

# Process existing files on startup
$existingFiles = Get-ChildItem -Path $baseFolder -Filter $fileFilter -File | 
    Where-Object { $_.FullName -notlike "*\Enhanced\*" -and $_.FullName -notlike "*\Originals\*" }

if ($existingFiles.Count -gt 0) {
    Write-Log "Found $($existingFiles.Count) existing files to process on startup"
    
    foreach ($file in $existingFiles) {
        Process-MarkdownFile -FilePath $file.FullName
    }
}

# Create a hashtable to keep track of processed files
$processedFiles = @{}

try {
    # Main monitoring loop
    while ($true) {
        # Get current files in the watch folder
        $currentFiles = Get-ChildItem -Path $baseFolder -Filter $fileFilter -File | 
            Where-Object { $_.FullName -notlike "*\Enhanced\*" -and $_.FullName -notlike "*\Originals\*" }
        
        # Log file count but only when verbose or files exist
        if ($VerbosePreference -eq 'Continue' -or $currentFiles.Count -gt 0) {
            Write-Verbose "Checking for new files. Found $($currentFiles.Count) files in watch folder."
        }
        
        # Process any new files
        foreach ($file in $currentFiles) {
            # If we haven't seen this file before
            if (-not $processedFiles.ContainsKey($file.FullName)) {
                Write-Log "New file detected: $($file.Name)"
                
                # Add to processed files list
                $processedFiles[$file.FullName] = (Get-Date)
                
                # Process the file
                Process-MarkdownFile -FilePath $file.FullName
            }
        }
        
        # Clean up processed files list (remove entries older than tracking expiration)
        $cutoffTime = (Get-Date).AddMinutes(-$fileTrackingExpiration)
        $keysToRemove = $processedFiles.Keys | Where-Object { $processedFiles[$_] -lt $cutoffTime }
        
        foreach ($key in $keysToRemove) {
            $processedFiles.Remove($key)
            Write-Verbose "Removed old entry from processed files tracking: $key"
        }
        
        # Heartbeat logging
        $currentMinute = (Get-Date).Minute
        if ($currentMinute % $heartbeatInterval -eq 0 -and (Get-Date).Second -lt 10) {
            Write-Log "Watcher still active... (heartbeat check)"
        }
        
        # Sleep to prevent CPU overuse
        Start-Sleep -Seconds $pollingInterval
    }
} finally {
    Write-Log "File monitoring stopped."
    Show-Notification -Title "Markdown Watcher Stopped" -Message "File monitoring has been stopped."
}