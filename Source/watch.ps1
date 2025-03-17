# File: ~/Downloads/MarkSnips/Source/watch.ps1
param(
    [string]$FolderToWatch = "$env:USERPROFILE\Downloads\MarkSnips",
    [string]$FileFilter = "*.md",
    [switch]$VerboseLogging
)

# Import the enhancement script - getting the path correctly
$enhanceScriptPath = Join-Path $PSScriptRoot "enhance.ps1"
. $enhanceScriptPath

# Import PSAI module
Import-Module PSAI

# Define folder structure
$baseFolder = $FolderToWatch
$originalFolder = Join-Path $baseFolder "Originals"
$enhancedFolder = Join-Path $baseFolder "Enhanced"

# Log file for monitoring events
$logDir = Join-Path $baseFolder "Logs"
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
$logFile = Join-Path $logDir "watcher.log"

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
    }
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message
    )
    
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
        Write-Log "Notification displayed using Windows Forms"
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
        
        # Prepare a prompt for AI to generate a descriptive filename
        $prompt = @"
Please create a concise, descriptive filename for this markdown document.
The filename should:
1. Clearly summarize the main topic of the document
2. Be between 3-7 words
3. Use only lowercase letters, numbers, and hyphens (no spaces)
4. End with .md extension
5. Be a clean, SEO-friendly URL slug

Here's the document content:

\`\`\`markdown
$fileContent
\`\`\`

Respond with ONLY the filename and nothing else.
"@
        
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
    param(
        [string]$FilePath
    )
    
    $name = Split-Path $FilePath -Leaf
    
    # Skip files that appear to be enhanced versions or in subdirectories
    if ($name -like "README.md" -or
        $name -like "*-enhanced.md" -or 
        $name -like "*.backup.md" -or 
        $FilePath -like "*\Enhanced\*" -or 
        $FilePath -like "*\Originals\*" -or 
        $name -eq "watcher-test-file.tmp") {
        
        Write-Log "Skipping processing for: $name"
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
        
        # Call the enhancement function
        Invoke-AIEnhanceMarkdown -InputFile $originalPath -OutputFile $enhancedPath
        
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
        Write-Log "ERROR processing $name : $($_.Exception.Message)" -IsError
        Show-Notification -Title "Enhancement Error" -Message "Failed to process: $name"
        return $false
    }
}

# Ensure folders exist - very explicitly
try {
    foreach ($folder in @($baseFolder, $originalFolder, $enhancedFolder)) {
        if (-not (Test-Path $folder)) {
            Write-Log "Creating folder: $folder"
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            
            # Verify folder was created successfully
            if (Test-Path $folder) {
                Write-Log "Folder created successfully: $folder"
            } else {
                Write-Log "Failed to create folder: $folder" -IsError
            }
        } else {
            Write-Log "Folder already exists: $folder"
        }
    }
} catch {
    Write-Log "ERROR creating folders: $($_.Exception.Message)" -IsError
}

Write-Log "=== Starting file watcher ==="
Write-Log "Monitoring folder: $FolderToWatch"
Write-Log "Log file: $logFile"
Write-Log "Enhancement script: $enhanceScriptPath"

# Write the correct paths to confirm they're working
Write-Log "Current folder ($PWD): $PWD"
Write-Log "PSScriptRoot: $PSScriptRoot"
Write-Log "Base folder: $baseFolder"
Write-Log "Enhanced folder: $enhancedFolder"
Write-Log "Originals folder: $originalFolder"

# Starting polling-based watcher
Write-Log "Starting polling-based file watcher"
Show-Notification -Title "Markdown Watcher Active" -Message "Monitoring for new files in: $FolderToWatch"

# Process existing files on startup
$existingFiles = Get-ChildItem -Path $FolderToWatch -Filter $FileFilter | 
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
        $currentFiles = Get-ChildItem -Path $FolderToWatch -Filter $FileFilter | 
            Where-Object { $_.FullName -notlike "*\Enhanced\*" -and $_.FullName -notlike "*\Originals\*" }
        
        if ($VerboseLogging -or $currentFiles.Count -gt 0) {
            Write-Log "Checking for new files. Found $($currentFiles.Count) files in watch folder."
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
        
        # Clean up processed files list (remove entries older than 1 hour)
        $cutoffTime = (Get-Date).AddHours(-1)
        $keysToRemove = $processedFiles.Keys | Where-Object { $processedFiles[$_] -lt $cutoffTime }
        
        foreach ($key in $keysToRemove) {
            $processedFiles.Remove($key)
            if ($VerboseLogging) {
                Write-Log "Removed old entry from processed files tracking: $key"
            }
        }
        
        # Heartbeat logging (every 5 minutes)
        $currentMinute = (Get-Date).Minute
        if ($currentMinute % 5 -eq 0 -and (Get-Date).Second -lt 10) {
            Write-Log "Watcher still active... (heartbeat check)"
        }
        
        # Sleep to prevent CPU overuse (check every 5 seconds)
        Start-Sleep -Seconds 5
    }
} finally {
    Write-Log "File monitoring stopped."
    Show-Notification -Title "Markdown Watcher Stopped" -Message "File monitoring has been stopped."
}