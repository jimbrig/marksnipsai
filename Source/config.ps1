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
