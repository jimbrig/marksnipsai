# MarkSnips: AI Markdown Enhancement Tool

<!-- BADGES:START -->
[![Automate Changelog](https://github.com/jimbrig/marksnipsai/actions/workflows/changelog.yml/badge.svg)](https://github.com/jimbrig/marksnipsai/actions/workflows/changelog.yml)
[![Run Repomix](https://github.com/jimbrig/marksnipsai/actions/workflows/repomix.yml/badge.svg)](https://github.com/jimbrig/marksnipsai/actions/workflows/repomix.yml)
<!-- BADGES:END -->

MarkSnips is a PowerShell-based tool that automatically enhances markdown files created from web page snippets. It uses OpenAI's API to improve formatting, structure, and readability, while also intelligently renaming files based on their content.

## Features

- **AI-powered markdown enhancement** - Restructures content for better readability and consistency
- **Intelligent file renaming** - Analyzes content to create descriptive, SEO-friendly filenames
- **Automated file organization** - Organizes files into Originals and Enhanced folders
- **Configuration system** - Customizable settings stored in a JSON config file
- **Backup and restore** - Automated backup system with configurable intervals
- **Windows notifications** - Desktop notifications for processing events
- **Reliable file monitoring** - Polling-based file detection that won't miss files

## Setup

### Prerequisites

1. PowerShell 5.1 or higher
2. [PSAI Module](https://github.com/dfinke/PowerShellAI) - Install using:

   ```
   Install-Module -Name PSAI
   ```

3. OpenAI API key configured for PSAI

### Installation

1. Create a base directory structure:

   ```
   mkdir "$env:USERPROFILE\Downloads\MarkSnips"
   mkdir "$env:USERPROFILE\Downloads\MarkSnips\Source"
   ```

2. Copy the script files to the Source directory:
   - `config.ps1`
   - `enhance.ps1`
   - `watch.ps1`

3. Copy `run.ps1` to the base MarkSnips directory

4. Initialize the configuration:

   ```
   cd "$env:USERPROFILE\Downloads\MarkSnips"
   .\run.ps1 -InitializeConfig
   ```

## Usage

### Basic Usage

Run the script to start monitoring for new markdown files:

```
cd "$env:USERPROFILE\Downloads\MarkSnips"
.\run.ps1
```

Any markdown files added to the MarkSnips folder will be automatically:

1. Moved to the Originals folder
2. Enhanced using AI
3. Saved to the Enhanced folder with an intelligent, content-based filename

### Command-Line Options

The `run.ps1` script supports several options:

- `-InitializeConfig`: Create a new configuration file
- `-Configure`: Launch interactive configuration mode
- `-Backup`: Create a backup immediately
- `-Restore`: Restore from a backup (interactive selection)
- `-RestoreFile "path/to/backup.zip"`: Restore from a specific backup file
- `-Force`: Override confirmations for potentially destructive actions
- `-Verbose`: Show more detailed logs while running

### Examples

Initialize configuration:

```
.\run.ps1 -InitializeConfig
```

Configure settings interactively:

```
.\run.ps1 -Configure
```

Create a backup:

```
.\run.ps1 -Backup
```

Restore from the most recent backup:

```
.\run.ps1 -Restore
```

## Integration with Task Scheduler

You can set up Windows Task Scheduler to run MarkSnips at startup:

1. Open Task Scheduler
2. Create a new basic task named "MarkSnips Watcher"
3. Trigger: When the computer starts
4. Action: Start a program
5. Program/script: `powershell.exe`
6. Arguments: `-ExecutionPolicy Bypass -WindowStyle Hidden -File "%USERPROFILE%\Downloads\MarkSnips\run.ps1"`
7. Finish the wizard and check properties:
   - General tab: Select "Run whether user is logged on or not" and "Run with highest privileges"
   - Settings tab: Check "Allow task to be run on demand"

## Folder Structure

```
MarkSnips/
├── run.ps1                  # Main launcher script
├── config.json              # Configuration file
├── Source/                  # Script files
│   ├── config.ps1           # Configuration management module
│   ├── enhance.ps1          # Markdown enhancement functionality
│   └── watch.ps1            # File watching and processing logic
├── Enhanced/                # Enhanced markdown files
├── Originals/               # Original source files
├── Logs/                    # Log files
│   └── watcher.log          # Operation log
└── Backups/                 # Backup files
    └── MarkSnips_Backup_*.zip  # Backup archives
```

## Customization

Edit the configuration file (`config.json`) to customize:

- File paths and folder locations
- AI prompts for enhancement and filename generation
- Backup settings (frequency, retention)
- Notification preferences
- Process timing and intervals

You can also use `.\run.ps1 -Configure` for an interactive configuration experience.

## Troubleshooting

- Check the log file at `%USERPROFILE%\Downloads\MarkSnips\Logs\watcher.log`
- Run with `-Verbose` for more detailed console output
- Ensure your OpenAI API key is properly configured in PSAI
- Make sure all required folders exist with proper permissions

## License

MIT License
