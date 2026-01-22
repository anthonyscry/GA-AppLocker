<#
.SYNOPSIS
    Collects AppLocker-relevant artifacts from the local machine.

.DESCRIPTION
    Scans specified paths on the local machine for executable files
    and collects metadata including hash, publisher, and signature info.

.PARAMETER Paths
    Array of paths to scan. Defaults to Program Files and System32.

.PARAMETER Extensions
    File extensions to collect. Defaults to exe, dll, msi, ps1, etc.

.PARAMETER Recurse
    Scan subdirectories recursively.

.PARAMETER MaxDepth
    Maximum recursion depth (default: unlimited).

.EXAMPLE
    Get-LocalArtifacts

.EXAMPLE
    Get-LocalArtifacts -Paths 'C:\CustomApps' -Recurse

.OUTPUTS
    [PSCustomObject] Result with Success, Data (artifacts array), and Summary.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Get-LocalArtifacts {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Paths = (Get-DefaultScanPaths),

        [Parameter()]
        [string[]]$Extensions = $script:ArtifactExtensions,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [int]$MaxDepth = 0,

        [Parameter()]
        [hashtable]$SyncHash = $null
    )

    $result = [PSCustomObject]@{
        Success  = $false
        Data     = @()
        Error    = $null
        Summary  = $null
    }

    try {
        Write-ScanLog -Message "Starting local artifact scan on $env:COMPUTERNAME"
        
        # Use List<T> for O(n) performance instead of array += O(n²)
        $artifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
        $stats = @{
            PathsScanned   = 0
            FilesFound     = 0
            FilesProcessed = 0
            Errors         = 0
        }

        #region --- Phase 1: Collect all files from all paths first ---
        if ($SyncHash) {
            $SyncHash.StatusText = "Discovering files..."
            $SyncHash.Progress = 26
        }
        
        $allFiles = [System.Collections.Generic.List[object]]::new()
        
        foreach ($scanPath in $Paths) {
            if (-not (Test-Path $scanPath)) {
                Write-ScanLog -Level Warning -Message "Scan path not found: $scanPath"
                continue
            }

            $stats.PathsScanned++
            Write-ScanLog -Message "Scanning: $scanPath"

            # Note: -Include only works properly with -Recurse
            # For non-recursive scans, use -Filter with multiple calls or wildcard in path
            if ($Recurse) {
                $extensionFilter = $Extensions | ForEach-Object { "*$_" }
                $getChildParams = @{
                    Path        = $scanPath
                    Include     = $extensionFilter
                    File        = $true
                    Recurse     = $true
                    ErrorAction = 'SilentlyContinue'
                }
                if ($MaxDepth -gt 0) {
                    $getChildParams.Depth = $MaxDepth
                }
                $foundFiles = Get-ChildItem @getChildParams
                if ($foundFiles) {
                    foreach ($f in $foundFiles) { $allFiles.Add($f) }
                }
            }
            else {
                # Non-recursive: use wildcard paths for each extension
                foreach ($ext in $Extensions) {
                    $wildcardPath = Join-Path $scanPath "*$ext"
                    $extFiles = Get-ChildItem -Path $wildcardPath -File -ErrorAction SilentlyContinue
                    if ($extFiles) {
                        foreach ($f in $extFiles) { $allFiles.Add($f) }
                    }
                }
            }
            
            # Update progress during discovery phase
            if ($SyncHash) {
                $SyncHash.StatusText = "Discovering files... ($($allFiles.Count) found in $($stats.PathsScanned) paths)"
                $SyncHash.Progress = [math]::Min(35, 26 + $stats.PathsScanned)
            }
        }
        
        $stats.FilesFound = $allFiles.Count
        Write-ScanLog -Message "Discovery complete: $($stats.FilesFound) files found"
        #endregion

        #region --- Phase 2: Process all files with unified progress ---
        if ($SyncHash) {
            $SyncHash.StatusText = "Processing $($stats.FilesFound) files..."
            $SyncHash.Progress = 36
        }
        
        $totalFiles = $allFiles.Count
        $fileIndex = 0
        
        foreach ($file in $allFiles) {
            try {
                $artifact = Get-FileArtifact -FilePath $file.FullName
                if ($artifact) {
                    $artifacts.Add($artifact)
                    $stats.FilesProcessed++
                }
            }
            catch {
                $stats.Errors++
                Write-ScanLog -Level Warning -Message "Error processing file: $($file.FullName)"
            }
            
            # Update progress every 100 files or at end (unified across all paths)
            $fileIndex++
            if ($SyncHash -and (($fileIndex % 100 -eq 0) -or ($fileIndex -eq $totalFiles))) {
                # Progress range: 36 to 88 (52% span for file processing)
                $pct = [math]::Min(88, 36 + [int](52 * $fileIndex / [math]::Max(1, $totalFiles)))
                $SyncHash.Progress = $pct
                $SyncHash.StatusText = "Processing: $fileIndex / $totalFiles files ($($stats.FilesProcessed) artifacts)"
            }
        }
        #endregion

        $result.Success = $true
        $result.Data = $artifacts
        $result.Summary = [PSCustomObject]@{
            ComputerName   = $env:COMPUTERNAME
            ScanDate       = Get-Date
            PathsScanned   = $stats.PathsScanned
            FilesFound     = $stats.FilesFound
            FilesProcessed = $stats.FilesProcessed
            Errors         = $stats.Errors
            ArtifactTypes  = ($artifacts | Group-Object ArtifactType | Select-Object Name, Count)
        }

        Write-ScanLog -Message "Local scan complete: $($stats.FilesProcessed) artifacts collected"
    }
    catch {
        $result.Error = "Local artifact scan failed: $($_.Exception.Message)"
        Write-ScanLog -Level Error -Message $result.Error
    }

    return $result
}
