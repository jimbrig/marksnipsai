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
