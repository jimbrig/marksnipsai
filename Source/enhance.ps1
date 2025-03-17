Import-Module PSAI

Function Invoke-AIEnhanceMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$InputFile,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFile,
        
        [Parameter(Mandatory = $false)]
        [switch]$OpenWhenDone,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFolder,
        
        [Parameter(Mandatory = $false)]
        [switch]$ProcessFolder,
        
        [Parameter(Mandatory = $false)]
        [string]$FilePattern = "*.md"
    )
    
    begin {
        # Set up the output folder if specified
        if ($OutputFolder -and -not (Test-Path $OutputFolder)) {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
            Write-Verbose "Created output folder: $OutputFolder"
        }
        
        # Track statistics
        $stats = @{
            Processed = 0
            Success   = 0
            Failed    = 0
        }
    }
    
    process {
        # If we're processing a folder, handle that
        if ($ProcessFolder) {
            if (Test-Path $InputFile -PathType Container) {
                $files = Get-ChildItem -Path $InputFile -Filter $FilePattern -File
                foreach ($file in $files) {
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
                return $stats
            } else {
                Write-Error "The specified path is not a directory: $InputFile"
                return $null
            }
        }
        
        # Otherwise process a single file
        try {
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

function ProcessSingleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
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
    
    # Read content
    $content = Get-Content -Path $inputFilePath -Raw
    
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
        $enhanced = Invoke-OAIChat $prompt
        $enhancedSplitted = $enhanced.Split("`n")[1..($enhanced.Split("`n").Length - 2)] -join "`n"
        $enhancedContent = $enhancedSplitted
    } catch {
        Write-Error "AI service error: $($_.Exception.Message)"
        return $null
    }

    # Create or overwrite the output file
    if (Test-Path $OutputFile) {
        Remove-Item $OutputFile -Force
    } else {
        $outputDir = Split-Path -Parent $OutputFile
        if (-not [string]::IsNullOrEmpty($outputDir) -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        New-Item -Path $OutputFile -ItemType File -Force | Out-Null
    }

    # Write content
    Set-Content -Path $OutputFile -Value $enhancedContent -Force
    Write-Verbose "Successfully wrote enhanced content to: $OutputFile"

    # Open the file if requested
    if ($OpenWhenDone) {
        Start-Process $OutputFile
    }

    # Return the file path
    return $OutputFile
}

# Add an alias for convenience
Set-Alias -Name Enhance-Markdown -Value Invoke-AIEnhanceMarkdown

# For use in Task Scheduler, add this sample command
function Invoke-ScheduledMarkdownEnhancement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SnippetsFolder = "$env:USERPROFILE\Downloads\MarkSnips",
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFolder = "$env:USERPROFILE\Downloads\MarkSnips\Enhanced",
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile = "$env:USERPROFILE\Downloads\MarkSnips\enhancement_log.txt"
    )
    
    # Ensure the folders exist
    if (-not (Test-Path $SnippetsFolder)) {
        New-Item -Path $SnippetsFolder -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }
    
    # Start logging
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] Starting scheduled markdown enhancement" | Out-File -FilePath $LogFile -Append
    
    try {
        # Find all unprocessed markdown files
        $files = Get-ChildItem -Path $SnippetsFolder -Filter "*.md" -File | 
            Where-Object { $_.FullName -notlike "*-enhanced.md" -and $_.FullName -notlike "*.backup.md" }
        
        "[$timestamp] Found $($files.Count) files to process" | Out-File -FilePath $LogFile -Append
        
        # Process each file
        foreach ($file in $files) {
            $fileTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            try {
                "[$fileTimestamp] Processing: $($file.Name)" | Out-File -FilePath $LogFile -Append
                
                $outputPath = Join-Path $OutputFolder $file.Name
                Invoke-AIEnhanceMarkdown -InputFile $file.FullName -OutputFile $outputPath
                
                "[$fileTimestamp] Successfully enhanced: $($file.Name)" | Out-File -FilePath $LogFile -Append
            } catch {
                "[$fileTimestamp] ERROR processing $($file.Name): $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append
            }
        }
    } catch {
        "[$timestamp] ERROR in main process: $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append
    }
    
    $endTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$endTimestamp] Completed scheduled markdown enhancement" | Out-File -FilePath $LogFile -Append
}