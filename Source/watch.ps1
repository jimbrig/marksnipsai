# File: ~/Downloads/MarkSnips/Source/watch.ps1

<#
.SYNOPSIS
Monitors a folder for markdown files and processes them with AI-enhanced formatting.

.DESCRIPTION
This script watches a specified folder for new markdown files, enhances their formatting using AI,
and organizes them into appropriate folders. It also supports backup and restore functionality.

.PARAMETER ConfigPath
Path to the configuration file. Defaults to config.json in the MarkSnips directory.

.PARAMETER BackupNow
If specified, creates a backup immediately upon startup.

.EXAMPLE
.\watch.ps1
Starts the file watcher with default settings.

.EXAMPLE
.\watch.ps1 -ConfigPath "C:\custom-config.json" -BackupNow
Starts the file watcher with a custom configuration and creates an immediate backup.

.NOTES
Requires the PSAI module and proper configuration to be set up.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -IsValid })]
    [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$BackupNow
)

# Import required scripts
$scriptRoot = $PSScriptRoot
$configModule = Join-Path $scriptRoot "config.ps1"
$enhanceModule = Join-Path $scriptRoot "enhance.ps1"

# Validate script paths
if (-not (Test-Path $configModule -PathType Leaf)) {
    throw "Configuration module not found at: $configModule"
}

if (-not (Test-Path $enhanceModule -PathType Leaf)) {
    throw "Enhancement module not found at: $enhanceModule"
}

# Source the scripts
. $configModule
. $enhanceModule

# Import PSAI module
try {
    Import-Module PSAI -ErrorAction Stop
} catch {
    throw "Failed to import PSAI module: $($_.Exception.Message). Please ensure it's installed with: Install-Module PSAI -Scope CurrentUser"
}

# Load or initialize configuration
$config = Import-MarkSnipsConfig -ConfigPath $ConfigPath
if (-not $config) {
    Write-Verbose "No configuration found, initializing default configuration"
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

# Validate critical paths
foreach ($path in @($baseFolder, $originalFolder, $enhancedFolder, $logDir)) {
    if (-not (Test-Path $path -IsValid)) {
        throw "Invalid path in configuration: $path"
    }
}

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
    if ($PSCmdlet.ShouldProcess($logDir, "Create log directory")) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        Write-Verbose "Created log directory: $logDir"
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [switch]$Warning,
        
        [Parameter(Mandatory = $false)]
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
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter(Mandatory = $true)]
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
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$OriginalName
    )
    
    try {
        # Read the content of the file
        $fileContent = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($fileContent)) {
            Write-Log "File is empty: $FilePath" -Warning
            throw "File content is empty"
        }
        
        # Get the filename prompt from config and replace the content placeholder
        $prompt = $config.AIPrompts.FilenamePrompt -replace '\{content\}', $fileContent
        
        Write-Log "Requesting AI to generate filename for: $OriginalName"
        
        # Show progress
        Write-Progress -Activity "Generating Filename" -Status "Analyzing content..."
        
        # Call OpenAI to generate a filename
        $aiResponse = Invoke-OAIChat $prompt -ErrorAction Stop
        
        Write-Progress -Activity "Generating Filename" -Completed
        
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
        Write-Progress -Activity "Generating Filename" -Completed
        
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
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
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
        $fileContent = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($fileContent)) {
            Write-Log "File is empty: $FilePath" -Warning
            return
        }
        
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
        
        # Show progress
        Write-Progress -Activity "Enhancing Markdown" -Status "Getting AI enhancements..."
        
        # Call the enhancement function
        $enhancedContent = Invoke-OAIChat $prompt -ErrorAction Stop
        
        Write-Progress -Activity "Enhancing Markdown" -Status "Processing response..."
        
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
        
        Write-Progress -Activity "Enhancing Markdown" -Status "Saving file..."
        
        # Create output file
        if (Test-Path $enhancedPath) {
            Remove-Item $enhancedPath -Force
        }
        Set-Content -Path $enhancedPath -Value $cleanContent -Force
        
        Write-Progress -Activity "Enhancing Markdown" -Completed
        
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
        Write-Progress -Activity "Enhancing Markdown" -Completed
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
        Write-Verbose "No previous backup detected, scheduling initial backup"
    } else {
        $lastBackupTime = [datetime]::Parse($lastBackup)
        $nextBackupTime = $lastBackupTime.AddHours($config.Backup.BackupInterval)
        if ((Get-Date) -gt $nextBackupTime) {
            $backupNeeded = $true
            Write-Verbose "Backup interval exceeded, scheduling backup"
        } else {
            Write-Verbose "Next backup scheduled for: $nextBackupTime"
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
    
    # Use a progress bar for processing existing files
    $fileCounter = 0
    $totalFiles = $existingFiles.Count
    
    foreach ($file in $existingFiles) {
        $fileCounter++
        Write-Progress -Activity "Processing Existing Files" -Status "Processing $($file.Name)" -PercentComplete (($fileCounter / $totalFiles) * 100)
        Process-MarkdownFile -FilePath $file.FullName
    }
    
    Write-Progress -Activity "Processing Existing Files" -Completed
}

# Create a hashtable to keep track of processed files
$processedFiles = @{}

# Track file watcher statistics
$watcherStats = @{
    StartTime      = Get-Date
    FilesProcessed = 0
    SuccessCount   = 0
    FailureCount   = 0
    LastActivity   = $null
}

try {
    # Main monitoring loop
    Write-Log "Entering main monitoring loop, checking for files every $pollingInterval seconds"
    
    while ($true) {
        # Get current files in the watch folder
        $currentFiles = Get-ChildItem -Path $baseFolder -Filter $fileFilter -File -ErrorAction SilentlyContinue | 
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
                $watcherStats.LastActivity = Get-Date
                
                # Process the file
                $result = Process-MarkdownFile -FilePath $file.FullName
                $watcherStats.FilesProcessed++
                
                if ($result) {
                    $watcherStats.SuccessCount++
                } else {
                    $watcherStats.FailureCount++
                }
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
            # Calculate uptime
            $uptime = (Get-Date) - $watcherStats.StartTime
            $uptimeFormatted = "{0:D2}d {1:D2}h {2:D2}m {3:D2}s" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds
            
            # Log heartbeat with stats
            Write-Log "Watcher still active... (uptime: $uptimeFormatted, processed: $($watcherStats.FilesProcessed), success: $($watcherStats.SuccessCount), failed: $($watcherStats.FailureCount))"
            
            # Check if backup is needed
            if ($config.Backup.Enabled -and $lastBackup) {
                $lastBackupTime = [datetime]::Parse($lastBackup)
                $nextBackupTime = $lastBackupTime.AddHours($config.Backup.BackupInterval)
                if ((Get-Date) -gt $nextBackupTime) {
                    if ($PSCmdlet.ShouldProcess("MarkSnips data", "Perform scheduled backup")) {
                        Write-Log "Performing scheduled backup"
                        $backupFile = Backup-MarkSnipsData -Config $config
                        if ($backupFile) {
                            Write-Log "Backup created: $backupFile"
                            $lastBackup = (Get-Date).ToString("o")
                        } else {
                            Write-Log "Backup failed" -IsError
                        }
                    }
                }
            }
        }
        
        # Sleep to prevent CPU overuse
        Start-Sleep -Seconds $pollingInterval
    }
} catch {
    Write-Log "Watcher error: $($_.Exception.Message)" -IsError
    throw
} finally {
    # Calculate final statistics
    $uptime = (Get-Date) - $watcherStats.StartTime
    $uptimeFormatted = "{0:D2}d {1:D2}h {2:D2}m {3:D2}s" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds
    
    Write-Log "File monitoring stopped after $uptimeFormatted. Processed $($watcherStats.FilesProcessed) files ($($watcherStats.SuccessCount) successful, $($watcherStats.FailureCount) failed)."
    Show-Notification -Title "Markdown Watcher Stopped" -Message "File monitoring has been stopped."
}