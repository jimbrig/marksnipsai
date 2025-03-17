This file is a merged representation of the entire codebase, combined into a single document by Repomix.

# File Summary

## Purpose
This file contains a packed representation of the entire repository's contents.
It is designed to be easily consumable by AI systems for analysis, code review,
or other automated processes.

## File Format
The content is organized as follows:
1. This summary section
2. Repository information
3. Directory structure
4. Multiple file entries, each consisting of:
  a. A header with the file path (## File: path/to/file)
  b. The full contents of the file in a code block

## Usage Guidelines
- This file should be treated as read-only. Any changes should be made to the
  original repository files, not this packed version.
- When processing this file, use the file path to distinguish
  between different files in the repository.
- Be aware that this file may contain sensitive information. Handle it with
  the same level of security as you would the original repository.

## Notes
- Some files may have been excluded based on .gitignore rules and Repomix's configuration
- Binary files are not included in this packed representation. Please refer to the Repository Structure section for a complete list of file paths, including binary files
- Files matching patterns in .gitignore are excluded
- Files matching default ignore patterns are excluded

## Additional Info

# Directory Structure
```
config.ps1
enhance.ps1
watch.ps1
```

# Files

## File: config.ps1
````powershell
# File: ~/Downloads/MarkSnips/Source/config.ps1

<#
.SYNOPSIS
Configuration and backup management module for MarkSnips.

.DESCRIPTION
This module provides functions for managing configuration settings and backup/restore
functionality for the MarkSnips application. It handles reading, writing, and updating
configuration values, as well as creating and restoring backups of user data.

.NOTES
This module is intended to be imported by the main MarkSnips scripts.
#>

<#
.SYNOPSIS
Initializes the default MarkSnips configuration.

.DESCRIPTION
Creates and saves the default configuration file for MarkSnips. If the configuration file
already exists, it will prompt for confirmation before overwriting unless -Force is used.

.PARAMETER ConfigPath
The path where the configuration file should be saved. Defaults to the standard location
in the MarkSnips folder.

.EXAMPLE
Initialize-MarkSnipsConfig
Creates a default configuration file at the standard location.

.EXAMPLE
Initialize-MarkSnipsConfig -ConfigPath "C:\MyConfig\config.json" -WhatIf
Shows what would happen if the configuration file was created at the specified location.

.NOTES
This function automatically creates the necessary folder structure for MarkSnips.
#>
function Initialize-MarkSnipsConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path (Split-Path $_) -IsValid })]
        [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json"
    )
    
    # Default configuration
    $defaultConfig = @{
        Folders       = @{
            Base      = "$env:USERPROFILE\Downloads\MarkSnips"
            Originals = "$env:USERPROFILE\Downloads\MarkSnips\Originals"
            Enhanced  = "$env:USERPROFILE\Downloads\MarkSnips\Enhanced"
            Logs      = "$env:USERPROFILE\Downloads\MarkSnips\Logs"
            Backups   = "$env:USERPROFILE\Downloads\MarkSnips\Backups"
        }
        Files         = @{
            LogFile    = "$env:USERPROFILE\Downloads\MarkSnips\Logs\watcher.log"
            ConfigFile = "$env:USERPROFILE\Downloads\MarkSnips\config.json"
        }
        Watcher       = @{
            FileFilter             = "*.md"
            PollingInterval        = 5  # seconds
            HeartbeatInterval      = 5  # minutes
            ProcessingDelay        = 2  # seconds
            FileTrackingExpiration = 60  # minutes
        }
        AIPrompts     = @{
            EnhancementPrompt = @"
Take the following markdown content and restructure it for better readability, formatting, and consistency:

```markdown
{content}
```
"@
            FilenamePrompt    = @"
Please create a concise, descriptive filename for this markdown document.
The filename should:
1. Clearly summarize the main topic of the document
2. Be between 3-7 words
3. Use only lowercase letters, numbers, and hyphens (no spaces)
4. End with .md extension
5. Be a clean, SEO-friendly URL slug

Here's the document content:

```markdown
{content}
```

Respond with ONLY the filename and nothing else.
"@
        }
        Backup        = @{
            Enabled        = $true
            MaxBackupSets  = 5
            BackupInterval = 24  # hours
            LastBackup     = $null
        }
        Notifications = @{
            Enabled                  = $true
            ShowSuccessNotifications = $true
            ShowErrorNotifications   = $true
        }
    }
    
    # Check if config exists
    if (Test-Path $ConfigPath) {
        Write-Warning "Config file already exists at $ConfigPath"
        if (-not $PSCmdlet.ShouldProcess($ConfigPath, "Overwrite existing configuration")) {
            return Import-MarkSnipsConfig -ConfigPath $ConfigPath
        }
    }
    
    # Ensure the directory exists
    $configDir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $configDir)) {
        if ($PSCmdlet.ShouldProcess($configDir, "Create directory")) {
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $configDir"
        }
    }
    
    # Save the default config
    if ($PSCmdlet.ShouldProcess($ConfigPath, "Create configuration file")) {
        $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Force
        Write-Verbose "Default configuration created at $ConfigPath"
        
        # Ensure all configured folders exist
        foreach ($folder in $defaultConfig.Folders.Values) {
            if (-not (Test-Path $folder)) {
                if ($PSCmdlet.ShouldProcess($folder, "Create folder")) {
                    New-Item -Path $folder -ItemType Directory -Force | Out-Null
                    Write-Verbose "Created folder: $folder"
                }
            }
        }
    }
    
    return $defaultConfig
}

<#
.SYNOPSIS
Imports the MarkSnips configuration from a file.

.DESCRIPTION
Reads and parses the configuration file, converting it to a hashtable for easy manipulation.
If the configuration file doesn't exist, it will create a default one.

.PARAMETER ConfigPath
The path to the configuration file. Defaults to the standard location.

.EXAMPLE
$config = Import-MarkSnipsConfig
Imports the configuration from the default location.

.EXAMPLE
$config = Import-MarkSnipsConfig -ConfigPath "C:\MyConfig\config.json"
Imports the configuration from a custom location.

.OUTPUTS
System.Collections.Hashtable
A hashtable containing the configuration settings.
#>
function Import-MarkSnipsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path (Split-Path $_) -IsValid })]
        [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json"
    )
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Config file not found at $ConfigPath. Creating default config."
        return Initialize-MarkSnipsConfig -ConfigPath $ConfigPath
    }
    
    try {
        $config = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Error "Failed to read or parse configuration file: $($_.Exception.Message)"
        Write-Warning "Creating default configuration instead."
        return Initialize-MarkSnipsConfig -ConfigPath $ConfigPath
    }
    
    # Convert to hashtable for easier manipulation
    $configHash = @{}
    
    # Deep convert from PSObject to hashtable
    function ConvertTo-Hashtable {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject
        )
        
        process {
            if ($null -eq $InputObject) { return $null }
            
            if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                $collection = @(
                    foreach ($object in $InputObject) {
                        ConvertTo-Hashtable $object
                    }
                )
                
                Write-Output -NoEnumerate $collection
            } elseif ($InputObject -is [psobject]) {
                $hash = @{}
                
                foreach ($property in $InputObject.PSObject.Properties) {
                    $hash[$property.Name] = ConvertTo-Hashtable $property.Value
                }
                
                $hash
            } else {
                $InputObject
            }
        }
    }
    
    # Convert the config to a hashtable
    $configHash = ConvertTo-Hashtable $config
    
    # Validate essential configuration settings
    if (-not $configHash.ContainsKey('Folders') -or 
        -not $configHash.ContainsKey('Files') -or 
        -not $configHash.ContainsKey('Watcher')) {
        Write-Warning "Configuration file is missing essential sections. Creating default config."
        return Initialize-MarkSnipsConfig -ConfigPath $ConfigPath
    }
    
    return $configHash
}

<#
.SYNOPSIS
Exports the MarkSnips configuration to a file.

.DESCRIPTION
Saves the configuration hashtable to a JSON file.

.PARAMETER Config
The configuration hashtable to export.

.PARAMETER ConfigPath
The path where the configuration should be saved. Defaults to the standard location.

.EXAMPLE
Export-MarkSnipsConfig -Config $config
Exports the configuration to the default location.

.EXAMPLE
Export-MarkSnipsConfig -Config $config -ConfigPath "C:\MyConfig\config.json" -WhatIf
Shows what would happen if the configuration was saved to the specified location.
#>
function Export-MarkSnipsConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path (Split-Path $_) -IsValid })]
        [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json"
    )
    
    if ($PSCmdlet.ShouldProcess($ConfigPath, "Save configuration")) {
        try {
            # Ensure the directory exists
            $configDir = Split-Path -Parent $ConfigPath
            if (-not (Test-Path $configDir)) {
                New-Item -Path $configDir -ItemType Directory -Force | Out-Null
                Write-Verbose "Created directory: $configDir"
            }
            
            $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Force
            Write-Verbose "Configuration saved to $ConfigPath"
        } catch {
            Write-Error "Failed to save configuration: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Updates a specific property in the MarkSnips configuration.

.DESCRIPTION
Updates a single property in the configuration hashtable and saves the updated configuration.

.PARAMETER ConfigPath
The path to the configuration file. Defaults to the standard location.

.PARAMETER PropertyPath
The path to the property to update, using dot notation (e.g., "Folders.Base").

.PARAMETER Value
The new value to set for the property.

.EXAMPLE
Update-MarkSnipsConfig -PropertyPath "Watcher.PollingInterval" -Value 10
Updates the polling interval in the configuration to 10 seconds.

.EXAMPLE
Update-MarkSnipsConfig -PropertyPath "Backup.Enabled" -Value $false -WhatIf
Shows what would happen if the backup setting was disabled.

.OUTPUTS
System.Collections.Hashtable
The updated configuration hashtable.
#>
function Update-MarkSnipsConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path (Split-Path $_) -IsValid })]
        [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PropertyPath,
        
        [Parameter(Mandatory = $true)]
        $Value
    )
    
    # Load current config
    $config = Import-MarkSnipsConfig -ConfigPath $ConfigPath
    
    # Split the property path
    $pathParts = $PropertyPath -split '\.'
    
    # Navigate to the property
    $current = $config
    for ($i = 0; $i -lt $pathParts.Count - 1; $i++) {
        $part = $pathParts[$i]
        
        if (-not $current.ContainsKey($part)) {
            $current[$part] = @{}
        }
        
        $current = $current[$part]
    }
    
    # Set the value
    if ($PSCmdlet.ShouldProcess("$PropertyPath from $($current[$pathParts[-1]]) to $Value", "Update configuration property")) {
        $current[$pathParts[-1]] = $Value
        
        # Save the updated config
        Export-MarkSnipsConfig -Config $config -ConfigPath $ConfigPath
    }
    
    return $config
}

<#
.SYNOPSIS
Creates a backup of MarkSnips data.

.DESCRIPTION
Creates a backup archive containing the configuration, enhanced markdown files, and original files.
The backup is saved as a ZIP file in the backup folder defined in the configuration.

.PARAMETER Config
The configuration hashtable. If not provided, it will be loaded from the default location.

.EXAMPLE
Backup-MarkSnipsData
Creates a backup using the default configuration.

.EXAMPLE
Backup-MarkSnipsData -Config $config -WhatIf
Shows what would happen if a backup was created with the provided configuration.

.OUTPUTS
System.String
The path to the created backup file, or $null if the backup failed.
#>
function Backup-MarkSnipsData {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = (Import-MarkSnipsConfig)
    )
    
    # Check if backups are enabled
    if (-not $Config.Backup.Enabled) {
        Write-Verbose "Backups are disabled in configuration."
        return
    }
    
    # Check if we need to perform a backup based on interval
    $lastBackup = $Config.Backup.LastBackup
    $backupInterval = $Config.Backup.BackupInterval
    
    if ($lastBackup) {
        $lastBackupTime = [datetime]::Parse($lastBackup)
        $nextBackupTime = $lastBackupTime.AddHours($backupInterval)
        
        if ((Get-Date) -lt $nextBackupTime -and -not $Force) {
            Write-Verbose "Skipping backup - next scheduled backup is at $nextBackupTime"
            return
        }
    }
    
    # Prepare backup folder and filename
    $backupFolder = $Config.Folders.Backups
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupFile = Join-Path $backupFolder "MarkSnips_Backup_$timestamp.zip"
    
    if (-not (Test-Path $backupFolder)) {
        if ($PSCmdlet.ShouldProcess($backupFolder, "Create backup directory")) {
            New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
            Write-Verbose "Created backup folder: $backupFolder"
        }
    }
    
    # Create temporary folder for preparing the backup
    $tempFolder = Join-Path $env:TEMP "MarkSnips_Backup_$timestamp"
    if (Test-Path $tempFolder) {
        Remove-Item -Path $tempFolder -Recurse -Force
    }
    New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
    
    try {
        # Display progress
        Write-Progress -Activity "Creating Backup" -Status "Collecting files..." -PercentComplete 10
        
        # Copy files to temp folder
        if ($PSCmdlet.ShouldProcess("MarkSnips data", "Collect for backup")) {
            # Copy config
            Copy-Item -Path $Config.Files.ConfigFile -Destination $tempFolder -Force
            Write-Progress -Activity "Creating Backup" -Status "Copying configuration..." -PercentComplete 20
            
            # Copy originals
            $originalsPath = Join-Path $Config.Folders.Originals "*"
            if (Test-Path -Path $originalsPath) {
                Copy-Item -Path $originalsPath -Destination $tempFolder -Force -Recurse
            }
            Write-Progress -Activity "Creating Backup" -Status "Copying original files..." -PercentComplete 40
            
            # Copy enhanced files
            $enhancedPath = Join-Path $Config.Folders.Enhanced "*"
            if (Test-Path -Path $enhancedPath) {
                Copy-Item -Path $enhancedPath -Destination $tempFolder -Force -Recurse
            }
            Write-Progress -Activity "Creating Backup" -Status "Copying enhanced files..." -PercentComplete 60
            
            # Copy scripts
            $scriptFolder = Join-Path $tempFolder "Scripts"
            New-Item -Path $scriptFolder -ItemType Directory -Force | Out-Null
            
            $scriptFiles = Get-ChildItem -Path (Split-Path -Parent $Config.Files.ConfigFile) -Filter "*.ps1" -File
            foreach ($scriptFile in $scriptFiles) {
                Copy-Item -Path $scriptFile.FullName -Destination $scriptFolder -Force
            }
            Write-Progress -Activity "Creating Backup" -Status "Copying scripts..." -PercentComplete 80
        }
        
        # Create the zip file
        if ($PSCmdlet.ShouldProcess($backupFile, "Create backup archive")) {
            Write-Progress -Activity "Creating Backup" -Status "Creating ZIP archive..." -PercentComplete 90
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($tempFolder, $backupFile)
            
            Write-Verbose "Backup created successfully: $backupFile"
            Write-Progress -Activity "Creating Backup" -Completed
            
            # Update last backup time in config
            $Config.Backup.LastBackup = (Get-Date).ToString("o")
            Export-MarkSnipsConfig -Config $Config
            
            # Clean up old backups
            $allBackups = Get-ChildItem -Path $backupFolder -Filter "MarkSnips_Backup_*.zip" | Sort-Object -Property LastWriteTime -Descending
            if ($allBackups.Count -gt $Config.Backup.MaxBackupSets) {
                Write-Progress -Activity "Backup Maintenance" -Status "Removing old backups..." -PercentComplete 50
                
                $backupsToRemove = $allBackups | Select-Object -Skip $Config.Backup.MaxBackupSets
                foreach ($backup in $backupsToRemove) {
                    if ($PSCmdlet.ShouldProcess($backup.FullName, "Remove old backup")) {
                        Remove-Item -Path $backup.FullName -Force
                        Write-Verbose "Removed old backup: $($backup.Name)"
                    }
                }
                
                Write-Progress -Activity "Backup Maintenance" -Completed
            }
        }
        
        return $backupFile
    } catch {
        Write-Progress -Activity "Creating Backup" -Completed
        Write-Error "Failed to create backup: $($_.Exception.Message)"
        return $null
    } finally {
        # Clean up temp folder
        if (Test-Path $tempFolder) {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
Restores MarkSnips data from a backup.

.DESCRIPTION
Extracts the contents of a backup archive and restores the configuration, enhanced markdown files,
and original files to their appropriate locations.

.PARAMETER BackupFile
The path to the backup file to restore from.

.PARAMETER Config
The configuration hashtable. If not provided, it will be loaded from the default location.

.EXAMPLE
Restore-MarkSnipsData -BackupFile "C:\Backups\MarkSnips_Backup_2025-03-17_12-34-56.zip"
Restores data from the specified backup file.

.EXAMPLE
Restore-MarkSnipsData -BackupFile "C:\Backups\MarkSnips_Backup_2025-03-17_12-34-56.zip" -WhatIf
Shows what would happen if the backup was restored.

.OUTPUTS
System.Boolean
True if the restore was successful, False otherwise.
#>
function Restore-MarkSnipsData {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$BackupFile,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = (Import-MarkSnipsConfig)
    )
    
    if (-not (Test-Path $BackupFile)) {
        Write-Error "Backup file not found: $BackupFile"
        return $false
    }
    
    # Create temporary extraction folder
    $tempFolder = Join-Path $env:TEMP "MarkSnips_Restore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if (Test-Path $tempFolder) {
        Remove-Item -Path $tempFolder -Recurse -Force
    }
    New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
    
    try {
        # Display progress
        Write-Progress -Activity "Restoring Backup" -Status "Extracting archive..." -PercentComplete 10
        
        # Extract backup
        if ($PSCmdlet.ShouldProcess($BackupFile, "Extract backup archive")) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupFile, $tempFolder)
            Write-Progress -Activity "Restoring Backup" -Status "Archive extracted" -PercentComplete 30
            
            # Restore configuration
            $configFile = Get-ChildItem -Path $tempFolder -Filter "config.json" -File -Recurse | Select-Object -First 1
            if ($configFile) {
                Copy-Item -Path $configFile.FullName -Destination $Config.Files.ConfigFile -Force
                $Config = Import-MarkSnipsConfig
                Write-Progress -Activity "Restoring Backup" -Status "Configuration restored" -PercentComplete 40
            }
            
            # Ensure all target folders exist
            foreach ($folder in $Config.Folders.Values) {
                if (-not (Test-Path $folder)) {
                    New-Item -Path $folder -ItemType Directory -Force | Out-Null
                    Write-Verbose "Created folder: $folder"
                }
            }
            Write-Progress -Activity "Restoring Backup" -Status "Folders verified" -PercentComplete 50
            
            # Restore Originals folder
            $originalsSource = Join-Path $tempFolder "Originals"
            if (Test-Path $originalsSource) {
                Copy-Item -Path (Join-Path $originalsSource "*") -Destination $Config.Folders.Originals -Force -Recurse
                Write-Verbose "Restored original files"
            }
            Write-Progress -Activity "Restoring Backup" -Status "Original files restored" -PercentComplete 70
            
            # Restore Enhanced folder
            $enhancedSource = Join-Path $tempFolder "Enhanced"
            if (Test-Path $enhancedSource) {
                Copy-Item -Path (Join-Path $enhancedSource "*") -Destination $Config.Folders.Enhanced -Force -Recurse
                Write-Verbose "Restored enhanced files"
            }
            Write-Progress -Activity "Restoring Backup" -Status "Enhanced files restored" -PercentComplete 85
            
            # Restore scripts
            $scriptSource = Join-Path $tempFolder "Scripts"
            if (Test-Path $scriptSource) {
                $scriptDestination = Split-Path -Parent $Config.Files.ConfigFile
                Copy-Item -Path (Join-Path $scriptSource "*") -Destination $scriptDestination -Force -Recurse
                Write-Verbose "Restored script files"
            }
            Write-Progress -Activity "Restoring Backup" -Status "Scripts restored" -PercentComplete 95
            
            Write-Progress -Activity "Restoring Backup" -Completed
            Write-Verbose "Restore completed successfully from $BackupFile"
            return $true
        }
    } catch {
        Write-Progress -Activity "Restoring Backup" -Completed
        Write-Error "Failed to restore from backup: $($_.Exception.Message)"
        return $false
    } finally {
        # Clean up temp folder
        if (Test-Path $tempFolder) {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
Gets information about available MarkSnips backups.

.DESCRIPTION
Retrieves a list of available backups and returns information about them.

.PARAMETER Config
The configuration hashtable. If not provided, it will be loaded from the default location.

.EXAMPLE
Get-MarkSnipsBackups | Format-Table
Displays a table of available backups.

.OUTPUTS
System.Management.Automation.PSObject[]
An array of backup information objects.
#>
function Get-MarkSnipsBackups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = (Import-MarkSnipsConfig)
    )
    
    $backupFolder = $Config.Folders.Backups
    
    if (-not (Test-Path $backupFolder)) {
        Write-Warning "Backup folder does not exist: $backupFolder"
        return @()
    }
    
    $backups = Get-ChildItem -Path $backupFolder -Filter "MarkSnips_Backup_*.zip" | 
        Sort-Object -Property LastWriteTime -Descending |
            ForEach-Object {
                # Try to extract date from filename
                $datePattern = "MarkSnips_Backup_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.zip"
                $dateMatch = [regex]::Match($_.Name, $datePattern)
                $creationDate = if ($dateMatch.Success) {
                    try {
                        [datetime]::ParseExact($dateMatch.Groups[1].Value, "yyyy-MM-dd_HH-mm-ss", $null)
                    } catch {
                        $_.CreationTime
                    }
                } else {
                    $_.CreationTime
                }
            
                # Get file size in a readable format
                $sizeInBytes = $_.Length
                $sizeFormatted = if ($sizeInBytes -gt 1GB) {
                    "{0:N2} GB" -f ($sizeInBytes / 1GB)
                } elseif ($sizeInBytes -gt 1MB) {
                    "{0:N2} MB" -f ($sizeInBytes / 1MB)
                } elseif ($sizeInBytes -gt 1KB) {
                    "{0:N2} KB" -f ($sizeInBytes / 1KB)
                } else {
                    "$sizeInBytes bytes"
                }
            
                [PSCustomObject]@{
                    Name      = $_.Name
                    Path      = $_.FullName
                    CreatedOn = $creationDate
                    Size      = $sizeFormatted
                    SizeBytes = $sizeInBytes
                }
            }
    
    return $backups
}
````

## File: enhance.ps1
````powershell
# File: ~/Downloads/MarkSnips/Source/enhance.ps1

Function Invoke-AIEnhanceMarkdown {
    <#
        .SYNOPSIS
        AI-powered markdown enhancement tool for MarkSnips.

        .DESCRIPTION
        Provides functionality to enhance markdown files using OpenAI's API.
        It can process individual files or entire folders, restructuring markdown
        content for better readability, formatting, and consistency.

        .PARAMETER InputFile
        The path to the markdown file to enhance, or the folder to process if -ProcessFolder is specified.

        .PARAMETER OutputFile
        The path where the enhanced markdown will be saved. If not specified, defaults to input file with "-enhanced" suffix.

        .PARAMETER OpenWhenDone
        If specified, the enhanced file will be opened after processing.

        .PARAMETER OutputFolder
        A folder where enhanced files will be saved. Only used when processing a single file and OutputFile is not specified,
        or when processing a folder.

        .PARAMETER ProcessFolder
        If specified, the InputFile is treated as a folder and all markdown files within it are processed.

        .PARAMETER FilePattern
        The file pattern to match when processing a folder. Defaults to "*.md".

        .EXAMPLE
        Invoke-AIEnhanceMarkdown -InputFile "document.md"
        Enhances document.md and saves the result as document-enhanced.md

        .EXAMPLE
        Invoke-AIEnhanceMarkdown -InputFile "C:\Documents" -ProcessFolder -OutputFolder "C:\Enhanced"
        Processes all markdown files in C:\Documents and saves the enhanced versions to C:\Enhanced

        .NOTES
        Requires the PSAI module to be installed and configured with an OpenAI API key.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$InputFile,
        
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$OutputFile,
        
        [Parameter(Mandatory = $false)]
        [switch]$OpenWhenDone,
        
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -PathType Container -IsValid })]
        [string]$OutputFolder,
        
        [Parameter(Mandatory = $false)]
        [switch]$ProcessFolder,
        
        [Parameter(Mandatory = $false)]
        [string]$FilePattern = "*.md"
    )
    
    begin {
        # Validate PSAI module is available
        if (-not (Get-Module -ListAvailable -Name PSAI)) {
            throw "The PSAI module is required but not installed. Please install it with: Install-Module PSAI -Scope CurrentUser"
        }
        
        # Ensure PSAI is imported
        Import-Module PSAI -ErrorAction Stop
        
        # Set up the output folder if specified
        if ($OutputFolder -and -not (Test-Path $OutputFolder)) {
            if ($PSCmdlet.ShouldProcess($OutputFolder, "Create output directory")) {
                New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
                Write-Verbose "Created output folder: $OutputFolder"
            }
        }
        
        # Track statistics
        $stats = @{
            Processed = 0
            Success   = 0
            Failed    = 0
        }
        
        # Start a progress bar if processing a folder
        $progressId = Get-Random
    }
    
    process {
        # If we're processing a folder, handle that
        if ($ProcessFolder) {
            if (Test-Path $InputFile -PathType Container) {
                $files = Get-ChildItem -Path $InputFile -Filter $FilePattern -File
                $totalFiles = $files.Count
                
                if ($totalFiles -eq 0) {
                    Write-Warning "No matching files found in $InputFile with pattern $FilePattern"
                    return
                }
                
                Write-Verbose "Found $totalFiles file(s) to process in $InputFile"
                
                $fileCounter = 0
                foreach ($file in $files) {
                    $fileCounter++
                    Write-Progress -Id $progressId -Activity "Enhancing Markdown Files" -Status "Processing $($file.Name)" -PercentComplete (($fileCounter / $totalFiles) * 100)
                    
                    try {
                        $result = ProcessSingleFile -InputFile $file.FullName -OutputFolder $OutputFolder -OpenWhenDone:$OpenWhenDone
                        if ($result) {
                            $stats.Processed++
                            $stats.Success++
                        }
                    } catch {
                        Write-Error "Failed to process $($file.FullName): $($_.Exception.Message)"
                        $stats.Processed++
                        $stats.Failed++
                    }
                }
                
                Write-Progress -Id $progressId -Activity "Enhancing Markdown Files" -Completed
                return $stats
            } else {
                Write-Error "The specified path is not a directory: $InputFile"
                return $null
            }
        }
        
        # Otherwise process a single file
        try {
            if (-not (Test-Path $InputFile -PathType Leaf)) {
                Write-Error "The specified file does not exist: $InputFile"
                return $null
            }
            
            $result = ProcessSingleFile -InputFile $InputFile -OutputFile $OutputFile -OutputFolder $OutputFolder -OpenWhenDone:$OpenWhenDone
            if ($result) {
                $stats.Processed++
                $stats.Success++
            }
            return $result
        } catch {
            Write-Error "Failed to process $($InputFile): $($_.Exception.Message)"
            $stats.Processed++
            $stats.Failed++
            return $null
        }
    }
    
    end {
        if ($ProcessFolder) {
            Write-Host "Processing complete: $($stats.Processed) files processed, $($stats.Success) succeeded, $($stats.Failed) failed."
        }
    }
}

<#
.SYNOPSIS
Processes a single markdown file with AI enhancement.

.DESCRIPTION
Internal function to process a single markdown file and save the enhanced version.

.PARAMETER InputFile
The path to the markdown file to enhance.

.PARAMETER OutputFile
The path where the enhanced markdown will be saved.

.PARAMETER OutputFolder
A folder where the enhanced file will be saved if OutputFile is not specified.

.PARAMETER OpenWhenDone
If specified, the enhanced file will be opened after processing.

.NOTES
This is an internal function used by Invoke-AIEnhanceMarkdown.
#>
function ProcessSingleFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$InputFile,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFile,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFolder,
        
        [Parameter(Mandatory = $false)]
        [switch]$OpenWhenDone
    )
    
    # Resolve full path and validate input file exists
    $inputFilePath = Resolve-Path $InputFile
    Write-Verbose "Processing file: $inputFilePath"
    
    # Determine output file path
    if (-not $OutputFile) {
        if ($OutputFolder) {
            $fileName = Split-Path $InputFile -Leaf
            $OutputFile = Join-Path $OutputFolder $fileName
        } else {
            $OutputFile = $InputFile -replace '\.md$', '-enhanced.md'
        }
    }
    
    # Inform about the operation
    $operationDescription = "Enhance markdown file"
    $operationTarget = "from $InputFile to $OutputFile"
    
    if (-not $PSCmdlet.ShouldProcess($operationTarget, $operationDescription)) {
        return $null
    }
    
    # Read content
    try {
        $content = Get-Content -Path $inputFilePath -Raw -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Warning "The file $InputFile is empty."
            return $null
        }
    } catch {
        Write-Error "Failed to read input file: $_"
        return $null
    }
    
    # Define newline
    $nl = [Environment]::NewLine
    
    # Use a here-string for the prompt with correctly escaped backticks
    $prompt = @"
Take the following markdown content and restructure it for better readability, formatting, and consistency:

```markdown
$content
```
"@

    # Make the API call
    Write-Verbose "Calling AI service..."
    try {
        # Show an indeterminate progress bar for the AI processing
        Write-Progress -Activity "Enhancing Markdown" -Status "Waiting for AI response..." -Id 1
        
        $enhanced = Invoke-OAIChat $prompt -ErrorAction Stop
        
        Write-Progress -Activity "Enhancing Markdown" -Status "Processing response..." -Id 1
        
        $enhancedLines = $enhanced.Split("`n")
        
        # Check for code fence at the beginning
        $startIndex = 0
        $endIndex = $enhancedLines.Length - 1
        
        if ($enhancedLines[0] -match "^```markdown" -or $enhancedLines[0] -match "^```$") {
            $startIndex = 1
        }
        
        # Check for code fence at the end
        if ($enhancedLines[$endIndex] -match "^```$") {
            $endIndex -= 1
        }
        
        # Join the lines without code fences
        $enhancedContent = $enhancedLines[$startIndex..$endIndex] -join "`n"
        
        Write-Progress -Activity "Enhancing Markdown" -Completed -Id 1
    } catch {
        Write-Progress -Activity "Enhancing Markdown" -Completed -Id 1
        Write-Error "AI service error: $($_.Exception.Message)"
        return $null
    }

    # Create or overwrite the output file
    try {
        if (Test-Path $OutputFile) {
            Remove-Item $OutputFile -Force -ErrorAction Stop
        } else {
            $outputDir = Split-Path -Parent $OutputFile
            if (-not [string]::IsNullOrEmpty($outputDir) -and -not (Test-Path $outputDir)) {
                New-Item -Path $outputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            New-Item -Path $OutputFile -ItemType File -Force -ErrorAction Stop | Out-Null
        }

        # Write content
        Set-Content -Path $OutputFile -Value $enhancedContent -Force -ErrorAction Stop
        Write-Verbose "Successfully wrote enhanced content to: $OutputFile"
    } catch {
        Write-Error "Failed to write output file: $($_.Exception.Message)"
        return $null
    }

    # Open the file if requested
    if ($OpenWhenDone) {
        try {
            Start-Process $OutputFile
        } catch {
            Write-Warning "Could not open the enhanced file: $($_.Exception.Message)"
        }
    }

    # Return the file path
    return $OutputFile
}

<#
.SYNOPSIS
Scheduled enhancement of markdown files in a specified folder.

.DESCRIPTION
Scans a specified folder for markdown files and enhances them using the OpenAI API.
Designed to be run on a schedule through Windows Task Scheduler.

.PARAMETER SnippetsFolder
The folder to scan for markdown files. Defaults to the MarkSnips folder in the user's Downloads directory.

.PARAMETER OutputFolder
The folder where enhanced files will be saved. Defaults to the Enhanced subfolder in the SnippetsFolder.

.PARAMETER LogFile
The file where processing logs will be written. Defaults to enhancement_log.txt in the SnippetsFolder.

.EXAMPLE
Invoke-ScheduledMarkdownEnhancement
Processes files in the default locations.

.EXAMPLE
Invoke-ScheduledMarkdownEnhancement -SnippetsFolder "C:\Documents" -OutputFolder "C:\Enhanced" -LogFile "C:\Logs\process.log"
Processes markdown files in C:\Documents, saving enhanced versions to C:\Enhanced and logs to C:\Logs\process.log.
#>
function Invoke-ScheduledMarkdownEnhancement {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -IsValid })]
        [string]$SnippetsFolder = "$env:USERPROFILE\Downloads\MarkSnips",
        
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -IsValid })]
        [string]$OutputFolder = "$env:USERPROFILE\Downloads\MarkSnips\Enhanced",
        
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path (Split-Path $_) -IsValid })]
        [string]$LogFile = "$env:USERPROFILE\Downloads\MarkSnips\enhancement_log.txt"
    )
    
    # Ensure the folders exist
    if (-not (Test-Path $SnippetsFolder)) {
        if ($PSCmdlet.ShouldProcess($SnippetsFolder, "Create directory")) {
            New-Item -Path $SnippetsFolder -ItemType Directory -Force | Out-Null
        }
    }
    
    if (-not (Test-Path $OutputFolder)) {
        if ($PSCmdlet.ShouldProcess($OutputFolder, "Create directory")) {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
        }
    }
    
    # Start logging
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($PSCmdlet.ShouldProcess($LogFile, "Write log entry")) {
        "[$timestamp] Starting scheduled markdown enhancement" | Out-File -FilePath $LogFile -Append
    }
    
    try {
        # Find all unprocessed markdown files
        $files = Get-ChildItem -Path $SnippetsFolder -Filter "*.md" -File | 
            Where-Object { $_.FullName -notlike "*-enhanced.md" -and $_.FullName -notlike "*.backup.md" }
        
        $fileCount = $files.Count
        if ($PSCmdlet.ShouldProcess($LogFile, "Write log entry")) {
            "[$timestamp] Found $fileCount files to process" | Out-File -FilePath $LogFile -Append
        }
        
        # Process each file
        $fileCounter = 0
        foreach ($file in $files) {
            $fileCounter++
            $fileTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            
            if ($PSCmdlet.ShouldProcess($LogFile, "Write log entry")) {
                "[$fileTimestamp] Processing: $($file.Name)" | Out-File -FilePath $LogFile -Append
            }
            
            try {
                # Show progress
                if ($fileCount -gt 1) {
                    Write-Progress -Activity "Scheduled Markdown Enhancement" -Status "Processing $($file.Name)" -PercentComplete (($fileCounter / $fileCount) * 100)
                }
                
                # Process the file
                $outputPath = Join-Path $OutputFolder $file.Name
                if ($PSCmdlet.ShouldProcess($file.FullName, "Enhance markdown")) {
                    Invoke-AIEnhanceMarkdown -InputFile $file.FullName -OutputFile $outputPath
                }
                
                if ($PSCmdlet.ShouldProcess($LogFile, "Write log entry")) {
                    "[$fileTimestamp] Successfully enhanced: $($file.Name)" | Out-File -FilePath $LogFile -Append
                }
            } catch {
                if ($PSCmdlet.ShouldProcess($LogFile, "Write log entry")) {
                    "[$fileTimestamp] ERROR processing $($file.Name): $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append
                }
            }
        }
        
        # Complete progress
        if ($fileCount -gt 1) {
            Write-Progress -Activity "Scheduled Markdown Enhancement" -Completed
        }
    } catch {
        if ($PSCmdlet.ShouldProcess($LogFile, "Write log entry")) {
            "[$timestamp] ERROR in main process: $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append
        }
    }
    
    $endTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($PSCmdlet.ShouldProcess($LogFile, "Write log entry")) {
        "[$endTimestamp] Completed scheduled markdown enhancement" | Out-File -FilePath $LogFile -Append
    }
}

# Add an alias for convenience
Set-Alias -Name Enhance-Markdown -Value Invoke-AIEnhanceMarkdown
````

## File: watch.ps1
````powershell
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
````
