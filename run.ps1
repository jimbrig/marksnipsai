<#
.SYNOPSIS
Runs the MarkSnips file watcher script.

.DESCRIPTION
This script is the entry point for the MarkSnips file watcher. It can be used to initialize the configuration, 
create backups, restore from backups, and run the watcher script.

.PARAMETER InitializeConfig
If specified, the script will initialize the configuration file.

.PARAMETER Backup
If specified, the script will create a backup of the MarkSnips data.

.PARAMETER Restore
If specified, the script will restore from a backup.

.PARAMETER RestoreFile
The path to the backup file to restore from.

.PARAMETER Configure
If specified, the script will interactively configure the MarkSnips settings.

.EXAMPLE
.\run.ps1 -InitializeConfig
Initializes the configuration file.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$InitializeConfig,
    
    [Parameter(Mandatory = $false)]
    [switch]$Backup,
    
    [Parameter(Mandatory = $false)]
    [switch]$Restore,
    
    [Parameter(Mandatory = $false)]
    [string]$RestoreFile,
    
    [Parameter(Mandatory = $false)]
    [switch]$Configure
)

# Register for Control+C event to ensure clean shutdown
$null = Register-EngineEvent -SourceIdentifier ([System.Console]::CancelKeyPress) -Action {
    Write-Host "Stopping MarkSnips gracefully..." -ForegroundColor Yellow
    # Cleanup code here
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    exit
}

# Register for process exit
$null = Register-EngineEvent -SourceIdentifier ([System.AppDomain]::CurrentDomain.ProcessExit) -Action {
    Write-Host "Process exiting, performing cleanup..." -ForegroundColor Yellow
    # Cleanup code here
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

# Set base paths
$baseDir = "$env:USERPROFILE\Downloads\MarkSnips"
$sourceDir = Join-Path $baseDir "Source"
$configPath = Join-Path $baseDir "config.json"

# Import config module
$configModule = Join-Path $sourceDir "config.ps1"
if (Test-Path $configModule) {
    . $configModule
} else {
    Write-Error "Configuration module not found at $configModule"
    Write-Error "Please ensure the Source directory contains the required scripts."
    exit 1
}

# Initialize configuration if requested or if no config exists
if ($InitializeConfig -or (-not (Test-Path $configPath))) {
    Write-Host "Initializing configuration..." -ForegroundColor Yellow
    $config = Initialize-MarkSnipsConfig -ConfigPath $configPath
    Write-Host "Configuration initialized at $configPath" -ForegroundColor Green
    
    if (-not $Configure) {
        # If not configuring further, exit
        exit 0
    }
}

# Load existing configuration
$config = Import-MarkSnipsConfig -ConfigPath $configPath

# Interactive configuration
if ($Configure) {
    Write-Host "=== MarkSnips Configuration ===" -ForegroundColor Cyan
    Write-Host "Current configuration loaded from: $configPath" -ForegroundColor Cyan
    
    # Base folder configuration
    $baseFolder = Read-Host "Base folder [$($config.Folders.Base)]"
    if ($baseFolder) {
        $config.Folders.Base = $baseFolder
        $config.Folders.Originals = Join-Path $baseFolder "Originals"
        $config.Folders.Enhanced = Join-Path $baseFolder "Enhanced"
        $config.Folders.Logs = Join-Path $baseFolder "Logs"
        $config.Folders.Backups = Join-Path $baseFolder "Backups"
        $config.Files.LogFile = Join-Path $config.Folders.Logs "watcher.log"
    }
    
    # Backup configuration
    $enableBackups = Read-Host "Enable automatic backups? (Y/N) [$(if ($config.Backup.Enabled) { "Y" } else { "N" })]"
    if ($enableBackups) {
        $config.Backup.Enabled = $enableBackups.ToUpper() -eq "Y"
    }
    
    if ($config.Backup.Enabled) {
        $backupInterval = Read-Host "Backup interval in hours [$($config.Backup.BackupInterval)]"
        if ($backupInterval) {
            $config.Backup.BackupInterval = [int]$backupInterval
        }
        
        $maxBackups = Read-Host "Maximum number of backup sets to keep [$($config.Backup.MaxBackupSets)]"
        if ($maxBackups) {
            $config.Backup.MaxBackupSets = [int]$maxBackups
        }
    }
    
    # Notification configuration
    $enableNotifications = Read-Host "Enable notifications? (Y/N) [$(if ($config.Notifications.Enabled) { "Y" } else { "N" })]"
    if ($enableNotifications) {
        $config.Notifications.Enabled = $enableNotifications.ToUpper() -eq "Y"
    }
    
    # Save the updated configuration
    Export-MarkSnipsConfig -Config $config -ConfigPath $configPath
    Write-Host "Configuration saved successfully." -ForegroundColor Green
    exit 0
}

# Backup functionality
if ($Backup) {
    if ($PSCmdlet.ShouldProcess("MarkSnips data", "Create backup")) {
        Write-Host "Creating backup..." -ForegroundColor Yellow
        $backupFile = Backup-MarkSnipsData -Config $config
        if ($backupFile) {
            Write-Host "Backup created successfully at: $backupFile" -ForegroundColor Green
        } else {
            Write-Error "Backup failed"
        }
        exit 0
    }
}

# Restore functionality
if ($Restore) {
    if (-not $RestoreFile) {
        # If no specific file provided, show available backups
        $backupFolder = $config.Folders.Backups
        $backups = Get-ChildItem -Path $backupFolder -Filter "MarkSnips_Backup_*.zip" | Sort-Object -Property LastWriteTime -Descending
        
        if ($backups.Count -eq 0) {
            Write-Error "No backups found in $backupFolder"
            exit 1
        }
        
        Write-Host "Available backups:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $backups.Count; $i++) {
            Write-Host "$($i + 1). $($backups[$i].Name) ($(Get-Date -Date $backups[$i].LastWriteTime -Format 'yyyy-MM-dd HH:mm:ss'))"
        }
        
        $selection = Read-Host "Enter the number of the backup to restore (or 'q' to quit)"
        if ($selection -eq "q") {
            exit 0
        }
        
        try {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $backups.Count) {
                $RestoreFile = $backups[$index].FullName
            } else {
                Write-Error "Invalid selection"
                exit 1
            }
        } catch {
            Write-Error "Invalid selection"
            exit 1
        }
    }
    
    $confirmMessage = "This will replace existing files with content from $RestoreFile"
    if ($PSCmdlet.ShouldProcess($RestoreFile, "Restore from backup")) {
        Write-Host "Restoring from backup: $RestoreFile" -ForegroundColor Yellow
        $result = Restore-MarkSnipsData -BackupFile $RestoreFile -Config $config
        
        if ($result) {
            Write-Host "Restore completed successfully" -ForegroundColor Green
        } else {
            Write-Error "Restore failed"
        }
        
        exit 0
    }
}

# Default action: Run the watcher script
$watcherScript = Join-Path $sourceDir "watch.ps1"
if (-not (Test-Path $watcherScript)) {
    Write-Error "Watcher script not found at $watcherScript"
    exit 1
}

# Import PSAI module
try {
    Import-Module PSAI -ErrorAction Stop
} catch {
    Write-Error "Failed to import PSAI module. Make sure it's installed."
    Write-Verbose "Error details: $($_.Exception.Message)"
    exit 1
}

# Run the watcher script
Write-Host "Starting MarkSnips file watcher..." -ForegroundColor Green

# Pass through common parameters
$commonParams = @{}
foreach ($param in @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable')) {
    if ($PSBoundParameters.ContainsKey($param)) {
        $commonParams[$param] = $PSBoundParameters[$param]
    }
}

# Call the watcher script with parameters
& $watcherScript -ConfigPath $configPath @commonParams