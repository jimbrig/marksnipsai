# File: ~/Downloads/MarkSnips/Source/config.ps1

# Configuration and backup management module for MarkSnips

function Initialize-MarkSnipsConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
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

function Import-MarkSnipsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json"
    )
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Config file not found at $ConfigPath. Creating default config."
        return Initialize-MarkSnipsConfig -ConfigPath $ConfigPath
    }
    
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    
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
    
    return $configHash
}

function Export-MarkSnipsConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json"
    )
    
    if ($PSCmdlet.ShouldProcess($ConfigPath, "Save configuration")) {
        $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Force
        Write-Verbose "Configuration saved to $ConfigPath"
    }
}

function Update-MarkSnipsConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = "$env:USERPROFILE\Downloads\MarkSnips\config.json",
        
        [Parameter(Mandatory = $true)]
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
    if ($PSCmdlet.ShouldProcess($PropertyPath, "Update configuration property")) {
        $current[$pathParts[-1]] = $Value
        
        # Save the updated config
        Export-MarkSnipsConfig -Config $config -ConfigPath $ConfigPath
    }
    
    return $config
}

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
        
        if ((Get-Date) -lt $nextBackupTime) {
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
        # Copy files to temp folder
        if ($PSCmdlet.ShouldProcess("MarkSnips data", "Collect for backup")) {
            Copy-Item -Path $Config.Files.ConfigFile -Destination $tempFolder -Force
            Copy-Item -Path (Join-Path $Config.Folders.Originals "*") -Destination $tempFolder -Force -Recurse
            Copy-Item -Path (Join-Path $Config.Folders.Enhanced "*") -Destination $tempFolder -Force -Recurse
            
            # Copy scripts
            $scriptFolder = Join-Path $tempFolder "Scripts"
            New-Item -Path $scriptFolder -ItemType Directory -Force | Out-Null
            
            $scriptFiles = Get-ChildItem -Path (Split-Path -Parent $Config.Files.ConfigFile) -Filter "*.ps1" -File
            foreach ($scriptFile in $scriptFiles) {
                Copy-Item -Path $scriptFile.FullName -Destination $scriptFolder -Force
            }
        }
        
        # Create the zip file
        if ($PSCmdlet.ShouldProcess($backupFile, "Create backup archive")) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($tempFolder, $backupFile)
            
            Write-Verbose "Backup created successfully: $backupFile"
            
            # Update last backup time in config
            $Config.Backup.LastBackup = (Get-Date).ToString("o")
            Export-MarkSnipsConfig -Config $Config
            
            # Clean up old backups
            $allBackups = Get-ChildItem -Path $backupFolder -Filter "MarkSnips_Backup_*.zip" | Sort-Object -Property LastWriteTime -Descending
            if ($allBackups.Count -gt $Config.Backup.MaxBackupSets) {
                $backupsToRemove = $allBackups | Select-Object -Skip $Config.Backup.MaxBackupSets
                foreach ($backup in $backupsToRemove) {
                    if ($PSCmdlet.ShouldProcess($backup.FullName, "Remove old backup")) {
                        Remove-Item -Path $backup.FullName -Force
                        Write-Verbose "Removed old backup: $($backup.Name)"
                    }
                }
            }
        }
        
        return $backupFile
    } catch {
        Write-Error "Failed to create backup: $($_.Exception.Message)"
        return $null
    } finally {
        # Clean up temp folder
        if (Test-Path $tempFolder) {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Restore-MarkSnipsData {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
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
        # Extract backup
        if ($PSCmdlet.ShouldProcess($BackupFile, "Extract backup archive")) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupFile, $tempFolder)
            
            # Restore configuration
            $configFile = Get-ChildItem -Path $tempFolder -Filter "config.json" -File -Recurse | Select-Object -First 1
            if ($configFile) {
                Copy-Item -Path $configFile.FullName -Destination $Config.Files.ConfigFile -Force
                $Config = Import-MarkSnipsConfig
            }
            
            # Ensure all target folders exist
            foreach ($folder in $Config.Folders.Values) {
                if (-not (Test-Path $folder)) {
                    New-Item -Path $folder -ItemType Directory -Force | Out-Null
                }
            }
            
            # Restore Originals folder
            $originalsSource = Join-Path $tempFolder "Originals"
            if (Test-Path $originalsSource) {
                Copy-Item -Path (Join-Path $originalsSource "*") -Destination $Config.Folders.Originals -Force -Recurse
            }
            
            # Restore Enhanced folder
            $enhancedSource = Join-Path $tempFolder "Enhanced"
            if (Test-Path $enhancedSource) {
                Copy-Item -Path (Join-Path $enhancedSource "*") -Destination $Config.Folders.Enhanced -Force -Recurse
            }
            
            # Restore scripts
            $scriptSource = Join-Path $tempFolder "Scripts"
            if (Test-Path $scriptSource) {
                $scriptDestination = Split-Path -Parent $Config.Files.ConfigFile
                Copy-Item -Path (Join-Path $scriptSource "*") -Destination $scriptDestination -Force -Recurse
            }
            
            Write-Verbose "Restore completed successfully from $BackupFile"
            return $true
        }
    } catch {
        Write-Error "Failed to restore from backup: $($_.Exception.Message)"
        return $false
    } finally {
        # Clean up temp folder
        if (Test-Path $tempFolder) {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
