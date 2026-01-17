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
        [string[]]$Paths = $script:DefaultScanPaths,

        [Parameter()]
        [string[]]$Extensions = $script:ArtifactExtensions,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [int]$MaxDepth = 0
    )

    $result = [PSCustomObject]@{
        Success  = $false
        Data     = @()
        Error    = $null
        Summary  = $null
    }

    try {
        Write-ScanLog -Message "Starting local artifact scan on $env:COMPUTERNAME"
        
        $artifacts = @()
        $stats = @{
            PathsScanned   = 0
            FilesFound     = 0
            FilesProcessed = 0
            Errors         = 0
        }

        foreach ($scanPath in $Paths) {
            if (-not (Test-Path $scanPath)) {
                Write-ScanLog -Level Warning -Message "Scan path not found: $scanPath"
                continue
            }

            $stats.PathsScanned++
            Write-ScanLog -Message "Scanning: $scanPath"

            #region --- Get files ---
            # Note: -Include only works properly with -Recurse
            # For non-recursive scans, use -Filter with multiple calls or wildcard in path
            $files = @()
            
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
                $files = Get-ChildItem @getChildParams
            }
            else {
                # Non-recursive: use wildcard paths for each extension
                foreach ($ext in $Extensions) {
                    $wildcardPath = Join-Path $scanPath "*$ext"
                    $extFiles = Get-ChildItem -Path $wildcardPath -File -ErrorAction SilentlyContinue
                    if ($extFiles) {
                        $files += $extFiles
                    }
                }
            }
            $stats.FilesFound += $files.Count
            #endregion

            #region --- Process each file ---
            foreach ($file in $files) {
                try {
                    $artifact = Get-FileArtifact -FilePath $file.FullName
                    if ($artifact) {
                        $artifacts += $artifact
                        $stats.FilesProcessed++
                    }
                }
                catch {
                    $stats.Errors++
                    Write-ScanLog -Level Warning -Message "Error processing file: $($file.FullName)"
                }
            }
            #endregion
        }

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
