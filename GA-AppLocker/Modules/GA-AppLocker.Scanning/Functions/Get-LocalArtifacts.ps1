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
        [string[]]$Paths = $null,

        [Parameter()]
        [string[]]$Extensions = $script:ArtifactExtensions,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [int]$MaxDepth = 0,

        [Parameter()]
        [switch]$SkipDllScanning,

        [Parameter()]
        [switch]$SkipWshScanning,

        [Parameter()]
        [switch]$SkipShellScanning,

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
        
        # Diagnostic logging for runspace context
        $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Write-ScanLog -Message "Elevation status: $isElevated"
        Write-ScanLog -Message "Paths parameter: $($Paths -join ', ')"
        Write-ScanLog -Message "Extensions parameter: $($Extensions -join ', ')"
        Write-ScanLog -Message "SkipDllScanning: $SkipDllScanning, SkipWshScanning: $SkipWshScanning, SkipShellScanning: $SkipShellScanning"
        
        # If caller didn't supply paths, attempt module defaults first.
        if (-not $Paths -or $Paths.Count -eq 0) {
            try {
                $Paths = @(Get-DefaultScanPaths)
            }
            catch {
                Write-ScanLog -Message "[Get-LocalArtifacts] Failed to get default scan paths: $_" -Level DEBUG
            }
        }

        # Defensive: fall back to hardcoded defaults when default resolver is unavailable.
        if (-not $Paths -or $Paths.Count -eq 0) {
            $Paths = @(
                'C:\Program Files',
                'C:\Program Files (x86)',
                'C:\ProgramData',
                'C:\Users\*\AppData\Local\Programs',
                'C:\Users\*\AppData\Local\Microsoft\WindowsApps'
            )
            Write-ScanLog -Level Warning -Message "Paths parameter was null; using hardcoded fallback paths"
        }
        
        # Defensive: If $Extensions is null (can happen in runspace contexts where
        # $script:ArtifactExtensions is not yet set when parameter defaults evaluate),
        # fall back to a hardcoded list.
        if (-not $Extensions -or $Extensions.Count -eq 0) {
            $Extensions = @(
                '.exe', '.dll', '.msi', '.msp',
                '.ps1', '.psm1', '.psd1',
                '.bat', '.cmd',
                '.vbs', '.js', '.wsf',
                '.appx', '.msix'
            )
            Write-ScanLog -Level Warning -Message "Extensions parameter was null; using hardcoded fallback list"
        }
        
        # Filter out DLL extensions if SkipDllScanning is enabled
        if ($SkipDllScanning) {
            $Extensions = @($Extensions | Where-Object { $_ -ne '.dll' })
            Write-ScanLog -Message "Skipping DLL scanning (performance optimization)"
        }
        
        # Filter out WSH script extensions (.js, .vbs, .wsf) if SkipWshScanning is enabled
        if ($SkipWshScanning) {
            $wshExts = @('.vbs', '.js', '.wsf')
            $Extensions = @($Extensions | Where-Object { $_ -notin $wshExts })
            Write-ScanLog -Message "Skipping WSH script scanning (.js, .vbs, .wsf)"
        }
        
        # Filter out shell script extensions (.ps1, .bat, .cmd) if SkipShellScanning is enabled
        if ($SkipShellScanning) {
            $shellExts = @('.ps1', '.psm1', '.psd1', '.bat', '.cmd')
            $Extensions = @($Extensions | Where-Object { $_ -notin $shellExts })
            Write-ScanLog -Message "Skipping shell script scanning (.ps1, .bat, .cmd)"
        }
        
        # Use List<T> for O(n) performance instead of array += O(n²)
        $artifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
        $stats = @{
            PathsScanned   = 0
            FilesFound     = 0
            FilesProcessed = 0
            Errors         = 0
        }

        #region --- Phase 1: Collect all files from all paths first ---
        # Read progress range from SyncHash (set by Start-ArtifactScan) or use defaults
        $progressMin = 10
        $progressMax = 88
        if ($SyncHash) {
            if ($SyncHash.LocalProgressMin) { $progressMin = [int]$SyncHash.LocalProgressMin }
            if ($SyncHash.LocalProgressMax) { $progressMax = [int]$SyncHash.LocalProgressMax }
        }
        # Split range: discovery gets first 25%, file processing gets remaining 75%
        $discoveryEnd = $progressMin + [int](($progressMax - $progressMin) * 0.25)
        $processingStart = $discoveryEnd
        $processingSpan = $progressMax - $processingStart
        
        if ($SyncHash) {
            $SyncHash.StatusText = "Discovering files..."
            $SyncHash.Progress = $progressMin
        }
        
        $allFiles = [System.Collections.Generic.List[object]]::new()
        $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        
        foreach ($scanPath in $Paths) {
            if (-not (Test-Path $scanPath)) {
                Write-ScanLog -Level Warning -Message "Scan path not found: $scanPath"
                continue
            }

            $stats.PathsScanned++
            Write-ScanLog -Message "Scanning: $scanPath"
            $loggedAccessDenied = $false

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
                    ErrorVariable = 'accessErrors'
                }
                if ($MaxDepth -gt 0) {
                    $getChildParams.Depth = $MaxDepth
                }
                try {
                    $accessErrors = $null
                    $foundFiles = Get-ChildItem @getChildParams
                    if ($foundFiles) {
                        foreach ($f in $foundFiles) {
                            if ($seenPaths.Add($f.FullName)) {
                                [void]$allFiles.Add($f)
                            }
                        }
                    }
                    if ($accessErrors) {
                        foreach ($err in $accessErrors) {
                            if ($err.Exception -is [System.UnauthorizedAccessException]) {
                                if (-not $loggedAccessDenied) {
                                    Write-ScanLog -Level Warning -Message "Access denied scanning: $scanPath"
                                    $stats.Errors++
                                    $loggedAccessDenied = $true
                                }
                                break
                            }
                        }
                    }
                }
                catch [System.UnauthorizedAccessException] {
                    Write-ScanLog -Level Warning -Message "Access denied scanning: $scanPath"
                    $stats.Errors++
                    continue
                }
            }
            else {
                # Non-recursive: use wildcard paths for each extension
                foreach ($ext in $Extensions) {
                    $wildcardPath = Join-Path $scanPath "*$ext"
                    try {
                        $extErrors = $null
                        $extFiles = Get-ChildItem -Path $wildcardPath -File -ErrorAction SilentlyContinue -ErrorVariable extErrors
                        if ($extFiles) {
                            foreach ($f in $extFiles) {
                                if ($seenPaths.Add($f.FullName)) {
                                    [void]$allFiles.Add($f)
                                }
                            }
                        }
                        if ($extErrors) {
                            foreach ($err in $extErrors) {
                                if ($err.Exception -is [System.UnauthorizedAccessException]) {
                                    if (-not $loggedAccessDenied) {
                                        Write-ScanLog -Level Warning -Message "Access denied scanning: $scanPath"
                                        $stats.Errors++
                                        $loggedAccessDenied = $true
                                    }
                                    break
                                }
                            }
                        }
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-ScanLog -Level Warning -Message "Access denied scanning: $scanPath"
                        $stats.Errors++
                        $loggedAccessDenied = $true
                        continue
                    }
                }
            }
            
            # Update progress during discovery phase
            if ($SyncHash) {
                $SyncHash.StatusText = "Discovering files... ($($allFiles.Count) found in $($stats.PathsScanned) paths)"
                $SyncHash.Progress = [math]::Min($discoveryEnd, $progressMin + $stats.PathsScanned)
            }
        }
        
        $stats.FilesFound = $allFiles.Count
        Write-ScanLog -Message "Discovery complete: $($stats.FilesFound) files found"
        #endregion

        #region --- Phase 2: Process all files (parallel with RunspacePool for large sets) ---
        $totalFiles = $allFiles.Count
        $parallelThreshold = 100  # Use RunspacePool only when worth the overhead
        
        if ($totalFiles -gt $parallelThreshold) {
            #region --- Parallel processing with RunspacePool ---
            $threadCount = [Math]::Min([Environment]::ProcessorCount, 8)
            # ~200 files per batch balances overhead vs. granularity
            $batchSize = [Math]::Max(50, [Math]::Min(200, [int]($totalFiles / ($threadCount * 4))))
            
            Write-ScanLog -Message "Parallel processing: $totalFiles files across $threadCount threads (batch size: $batchSize)"
            if ($SyncHash) {
                $SyncHash.StatusText = "Processing $totalFiles files ($threadCount threads)..."
                $SyncHash.Progress = $processingStart
            }
            
            # Self-contained scriptblock -- runspaces cannot access module script: scope.
            # IMPORTANT: This duplicates the file-processing logic from Get-FileArtifact
            # in GA-AppLocker.Scanning.psm1 for parallel execution. If you change artifact
            # fields, hash logic, or signature extraction here, update Get-FileArtifact too.
            $processBlock = {
                param([string[]]$FilePaths, [string]$ComputerName)
                
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $results = [System.Collections.Generic.List[PSCustomObject]]::new()
                
                foreach ($filePath in $FilePaths) {
                    try {
                        $file = Get-Item -Path $filePath -ErrorAction Stop
                        
                        # .NET SHA256 hash
                        $hashString = $null
                        try {
                            $stream = [System.IO.File]::OpenRead($filePath)
                            try {
                                $hashBytes = $sha256.ComputeHash($stream)
                                $hashString = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                            }
                            finally {
                                $stream.Close()
                                $stream.Dispose()
                            }
                        }
                        catch {
                            # Hash failure — rare (access denied, locked file)
                            # NOTE: Write-AppLockerLog is NOT available inside RunspacePool scriptblocks
                        }
                        
                        # Version info
                        $versionInfo = $null
                        try {
                            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($filePath)
                        }
                        catch {
                            # Version info unavailable — acceptable for some files
                        }
                        
                        # Digital signature — .NET cert extraction (no CRL/OCSP)
                        $isSigned = $false
                        $signerSubject = $null
                        $sigStatus = 'NotSigned'
                        try {
                            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($filePath)
                            if ($cert) {
                                $isSigned = $true
                                $signerSubject = $cert.Subject
                                $sigStatus = 'Valid'
                            }
                        } catch {
                            # No embedded Authenticode certificate — file is unsigned (expected for most files)
                        }
                        
                        # Artifact type mapping
                        $artType = switch ($file.Extension.ToLower()) {
                            '.exe'  { 'EXE' }
                            '.dll'  { 'DLL' }
                            '.msi'  { 'MSI' }
                            '.msp'  { 'MSP' }
                            '.ps1'  { 'PS1' }
                            '.psm1' { 'PS1' }
                            '.psd1' { 'PS1' }
                            '.bat'  { 'BAT' }
                            '.cmd'  { 'CMD' }
                            '.vbs'  { 'VBS' }
                            '.js'   { 'JS' }
                            '.wsf'  { 'WSF' }
                            '.appx' { 'APPX' }
                            '.msix' { 'APPX' }
                            default { 'Unknown' }
                        }
                        
                        [void]$results.Add([PSCustomObject]@{
                            FilePath         = $filePath
                            FileName         = $file.Name
                            Extension        = $file.Extension.ToLower()
                            Directory        = $file.DirectoryName
                            ComputerName     = $ComputerName
                            SizeBytes        = $file.Length
                            CreatedDate      = $file.CreationTime
                            ModifiedDate     = $file.LastWriteTime
                            SHA256Hash       = $hashString
                            Publisher        = $versionInfo.CompanyName
                            ProductName      = $versionInfo.ProductName
                            ProductVersion   = $versionInfo.ProductVersion
                            FileVersion      = $versionInfo.FileVersion
                            FileDescription  = $versionInfo.FileDescription
                            OriginalFilename = $versionInfo.OriginalFilename
                            IsSigned         = $isSigned
                            SignerCertificate = $signerSubject
                            SignatureStatus  = $sigStatus
                            CollectedDate    = [DateTime]::Now
                            ArtifactType     = $artType
                            CollectionType   = switch ($artType) {
                                'EXE'     { 'Exe' }
                                'DLL'     { 'Dll' }
                                { $_ -in 'MSI','MSP' } { 'Msi' }
                                { $_ -in 'PS1','BAT','CMD','VBS','JS','WSF' } { 'Script' }
                                'APPX'    { 'Appx' }
                                default   { 'Exe' }
                            }
                        })
                    }
                    catch {
                        # Skip files that can't be processed (access denied, locked, etc.)
                    }
                }
                
                $sha256.Dispose()
                return ,@($results.ToArray())
            }
            
            # Create RunspacePool
            $pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
            $pool.Open()
            
            # Extract file paths and split into batches
            $filePaths = [string[]]($allFiles | ForEach-Object { $_.FullName })
            $handles = [System.Collections.Generic.List[hashtable]]::new()
            
            for ($i = 0; $i -lt $totalFiles; $i += $batchSize) {
                $end = [Math]::Min($i + $batchSize - 1, $totalFiles - 1)
                $batch = $filePaths[$i..$end]
                
                $ps = [powershell]::Create()
                [void]$ps.AddScript($processBlock)
                [void]$ps.AddArgument($batch)
                [void]$ps.AddArgument($env:COMPUTERNAME)
                $ps.RunspacePool = $pool
                
                [void]$handles.Add(@{
                    PowerShell = $ps
                    Handle     = $ps.BeginInvoke()
                    BatchSize  = $batch.Count
                })
            }
            
            Write-ScanLog -Message "Queued $($handles.Count) batches across $threadCount threads"
            
            # Collect results as batches complete
            $completedFiles = 0
            foreach ($h in $handles) {
                try {
                    $batchResults = $h.PowerShell.EndInvoke($h.Handle)
                    if ($batchResults) {
                        foreach ($item in $batchResults) {
                            if ($null -eq $item) { continue }
                            # EndInvoke may return nested arrays — flatten
                            if ($item -is [System.Array]) {
                                foreach ($subItem in $item) {
                                    if ($subItem) { [void]$artifacts.Add($subItem) }
                                }
                            }
                            else {
                                [void]$artifacts.Add($item)
                            }
                        }
                    }
                }
                catch {
                    $stats.Errors += $h.BatchSize
                    Write-ScanLog -Level Warning -Message "Batch processing error: $($_.Exception.Message)"
                }
                finally {
                    $h.PowerShell.Dispose()
                }
                
                $completedFiles += $h.BatchSize
                $stats.FilesProcessed = $artifacts.Count
                
                # Update progress after each batch
                if ($SyncHash) {
                    $pct = [math]::Min($progressMax, $processingStart + [int]($processingSpan * $completedFiles / [math]::Max(1, $totalFiles)))
                    $SyncHash.Progress = $pct
                    $SyncHash.StatusText = "Processing: $completedFiles / $totalFiles files ($($artifacts.Count) artifacts, $threadCount threads)"
                }
                if (($completedFiles % 500 -lt $batchSize) -or ($completedFiles -eq $totalFiles)) {
                    Write-ScanLog -Message "Local scan progress: $completedFiles / $totalFiles files ($($artifacts.Count) artifacts, $($stats.Errors) errors)"
                }
            }
            
            # Cleanup RunspacePool
            $pool.Close()
            $pool.Dispose()
            $stats.Errors = [Math]::Max($stats.Errors, $totalFiles - $artifacts.Count)
            #endregion
        }
        else {
            #region --- Sequential processing for small file sets (≤ threshold) ---
            if ($SyncHash) {
                $SyncHash.StatusText = "Processing $totalFiles files..."
                $SyncHash.Progress = $processingStart
            }
            
            $fileIndex = 0
            foreach ($file in $allFiles) {
                try {
                    if (-not $file -or -not $file.FullName) {
                        $stats.Errors++
                        continue
                    }
                    $artifact = Get-FileArtifact -FilePath $file.FullName
                    if ($artifact) {
                        [void]$artifacts.Add($artifact)
                        $stats.FilesProcessed++
                    }
                }
                catch {
                    $stats.Errors++
                    $errFile = if ($file) { $file.FullName } else { '(null)' }
                    Write-ScanLog -Level Warning -Message "Error processing file: $errFile - $($_.Exception.Message)"
                }
                
                $fileIndex++
                if (($fileIndex % 100 -eq 0) -or ($fileIndex -eq $totalFiles)) {
                    if ($SyncHash) {
                        $pct = [math]::Min($progressMax, $processingStart + [int]($processingSpan * $fileIndex / [math]::Max(1, $totalFiles)))
                        $SyncHash.Progress = $pct
                        $SyncHash.StatusText = "Processing: $fileIndex / $totalFiles files ($($stats.FilesProcessed) artifacts)"
                    }
                }
            }
            #endregion
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
