<#
.SYNOPSIS
    Collects AppLocker-relevant artifacts from remote machines via WinRM.

.DESCRIPTION
    Uses PowerShell remoting to scan remote machines for executable files
    and collect metadata including hash, publisher, and signature info.

.PARAMETER ComputerName
    Name(s) of remote computer(s) to scan.

.PARAMETER Credential
    PSCredential for authentication. If not provided, uses default for machine tier.

.PARAMETER Paths
    Array of paths to scan on remote machines.

.PARAMETER Extensions
    File extensions to collect. Defaults to all AppLocker-relevant extensions.

.PARAMETER Recurse
    Scan subdirectories recursively.

.PARAMETER SkipDllScanning
    Skip DLL files during scanning for performance.

.PARAMETER ThrottleLimit
    Maximum concurrent remote sessions.

.PARAMETER BatchSize
    Number of machines per batch for large-scale scans.

.EXAMPLE
    Get-RemoteArtifacts -ComputerName 'Server01', 'Server02'

.EXAMPLE
    $cred = Get-Credential
    Get-RemoteArtifacts -ComputerName 'Workstation01' -Credential $cred -Recurse

.OUTPUTS
    [PSCustomObject] Result with Success, Data (artifacts array), Summary, and PerMachine.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.1.0
    Fixed: C1 - Results now properly returned (was returning empty array)
    Fixed: C2 - Extensions aligned with $script:ArtifactExtensions (14 types)
    Fixed: C3 - Non-recursive scans now use -Filter instead of -Include
    Fixed: H3 - Remote scriptblock uses List<T> instead of O(n²) array concat
#>
function Get-RemoteArtifacts {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [string[]]$Paths = (Get-DefaultScanPaths),

        [Parameter()]
        [string[]]$Extensions = $script:ArtifactExtensions,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [switch]$SkipDllScanning,

        [Parameter()]
        [switch]$SkipWshScanning,

        [Parameter()]
        [switch]$SkipShellScanning,

        [Parameter()]
        [int]$ThrottleLimit = 32,

        [Parameter()]
        [int]$BatchSize = 100
    )

    $result = [PSCustomObject]@{
        Success    = $false
        Data       = @()
        Error      = $null
        Summary    = $null
        PerMachine = @{}
    }

    try {
        Write-ScanLog -Message "Starting remote artifact scan on $($ComputerName.Count) machine(s)"

        # Defensive: if $Extensions is null (runspace context), fall back to hardcoded list
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
            Write-ScanLog -Message "Skipping DLL scanning for remote machines (performance optimization)"
        }
        
        # Filter out WSH script extensions if SkipWshScanning is enabled
        if ($SkipWshScanning) {
            $wshExts = @('.vbs', '.js', '.wsf')
            $Extensions = @($Extensions | Where-Object { $_ -notin $wshExts })
            Write-ScanLog -Message "Skipping WSH script scanning for remote machines (.js, .vbs, .wsf)"
        }
        
        # Filter out shell script extensions if SkipShellScanning is enabled
        if ($SkipShellScanning) {
            $shellExts = @('.ps1', '.psm1', '.psd1', '.bat', '.cmd')
            $Extensions = @($Extensions | Where-Object { $_ -notin $shellExts })
            Write-ScanLog -Message "Skipping shell script scanning for remote machines (.ps1, .bat, .cmd)"
        }

        $allArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
        $machineResults = @{}

        #region --- Define remote script block ---
        $remoteScriptBlock = {
            param($ScanPaths, $FileExtensions, $DoRecurse)

            # Helper function to determine artifact type (runs on remote machine)
            function Get-RemoteArtifactType {
                param([string]$Extension)
                
                switch ($Extension.ToLower()) {
                    '.exe' { 'EXE' }
                    '.dll' { 'DLL' }
                    '.msi' { 'MSI' }
                    '.msp' { 'MSP' }
                    '.ps1' { 'PS1' }
                    '.psm1' { 'PS1' }
                    '.psd1' { 'PS1' }
                    '.bat' { 'BAT' }
                    '.cmd' { 'CMD' }
                    '.vbs' { 'VBS' }
                    '.js' { 'JS' }
                    '.wsf' { 'WSF' }
                    '.appx' { 'APPX' }
                    '.msix' { 'APPX' }
                    default { 'Unknown' }
                }
            }

            function Get-RemoteFileArtifact {
                param([string]$FilePath)
                
                try {
                    $file = Get-Item -Path $FilePath -ErrorAction Stop
                    
                    # Direct .NET SHA256 — ~30% faster than Get-FileHash cmdlet
                    $hashString = $null
                    try {
                        $sha256 = [System.Security.Cryptography.SHA256]::Create()
                        $stream = [System.IO.File]::OpenRead($FilePath)
                        try {
                            $hashBytes = $sha256.ComputeHash($stream)
                            $hashString = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                        }
                        finally {
                            $stream.Close()
                            $stream.Dispose()
                            $sha256.Dispose()
                        }
                    }
                    catch { }
                    
                    $versionInfo = $null
                    try {
                        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
                    }
                    catch { 
                        # Version info not available for some files - acceptable
                    }
                    
                    # Use .NET cert extraction — no CRL/OCSP network calls
                    # Get-AuthenticodeSignature triggers revocation checks that timeout on air-gapped networks
                    $isSigned = $false
                    $signerSubject = $null
                    $sigStatus = 'NotSigned'
                    try {
                        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($FilePath)
                        if ($cert) {
                            $isSigned = $true
                            $signerSubject = $cert.Subject
                            $sigStatus = 'Valid'
                        }
                    } catch {
                        # File has no embedded Authenticode signature (or is catalog-signed)
                    }
                    
                    [PSCustomObject]@{
                        FilePath         = $FilePath
                        FileName         = $file.Name
                        Extension        = $file.Extension.ToLower()
                        Directory        = $file.DirectoryName
                        ComputerName     = $env:COMPUTERNAME
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
                        CollectedDate    = Get-Date
                        ArtifactType     = Get-RemoteArtifactType -Extension $file.Extension
                    }
                }
                catch {
                    return $null
                }
            }

            # Use List<T> to avoid O(n²) array concatenation on remote machines
            $artifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
            $extensionFilter = @($FileExtensions | ForEach-Object { "*$_" })

            foreach ($path in $ScanPaths) {
                if (-not (Test-Path $path)) { continue }

                $params = @{
                    Path        = $path
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }

                if ($DoRecurse) {
                    # -Include works with -Recurse in PS 5.1
                    $params.Recurse = $true
                    $params.Include = $extensionFilter
                }
                else {
                    # PS 5.1 quirk: -Include requires -Recurse to work.
                    # For non-recursive scans, enumerate files and filter manually.
                    $params.Recurse = $false
                }

                $files = Get-ChildItem @params

                # If non-recursive, apply extension filter manually
                if (-not $DoRecurse -and $files) {
                    $extSet = [System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase
                    )
                    foreach ($ext in $FileExtensions) { [void]$extSet.Add($ext) }
                    $files = @($files | Where-Object { $extSet.Contains($_.Extension) })
                }

                foreach ($file in $files) {
                    $artifact = Get-RemoteFileArtifact -FilePath $file.FullName
                    if ($artifact) {
                        [void]$artifacts.Add($artifact)
                    }
                }
            }

            # Return individual artifacts — do NOT wrap with @(,...) because
            # Invoke-Command with multiple computers would nest arrays (1 per machine)
            # causing "2 artifacts" instead of thousands. Pipeline unrolling is fine here
            # since Invoke-Command adds PSComputerName to each object.
            return $artifacts.ToArray()
        }
        #endregion

        #region --- Execute on machines in parallel with batching ---
        Write-ScanLog -Message "Scanning $($ComputerName.Count) machines in parallel (ThrottleLimit: $ThrottleLimit, BatchSize: $BatchSize)"

        # WinRM session options — fail fast on unreachable machines instead of hanging
        # OpenTimeout: 30s to establish connection (default is infinite)
        # OperationTimeout: 10min for the actual scan to complete (large dirs take time)
        $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 600000 -CancelTimeout 10000

        # Build Invoke-Command parameters for parallel execution
        $invokeParams = @{
            ScriptBlock   = $remoteScriptBlock
            ArgumentList  = @($Paths, $Extensions, $Recurse.IsPresent)
            ThrottleLimit = $ThrottleLimit
            SessionOption = $sessionOption
            ErrorAction   = 'SilentlyContinue'
            ErrorVariable = 'remoteErrors'
        }

        if ($Credential) {
            $invokeParams.Credential = $Credential
        }

        # Process machines in batches to handle large-scale scans
        $batchedResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        $batchNumber = 0
        $batches = [System.Collections.ArrayList]::new()

        if ($ComputerName.Count -le $BatchSize) {
            [void]$batches.Add($ComputerName)
        } else {
            for ($i = 0; $i -lt $ComputerName.Count; $i += $BatchSize) {
                $batch = $ComputerName[$i..[Math]::Min($i + $BatchSize - 1, $ComputerName.Count - 1)]
                [void]$batches.Add($batch)
            }
        }

        foreach ($batch in $batches) {
            $batchNumber++
            if ($batches.Count -gt 1) {
                Write-ScanLog -Message "Processing batch $batchNumber of $($batches.Count) ($($batch.Count) machines)..."
            }

            Write-ScanLog -Message "Connecting to: $($batch -join ', ')"
            $invokeParams.ComputerName = $batch
            $batchResults = Invoke-Command @invokeParams

            if ($batchResults) {
                # Flatten results — Invoke-Command may return nested arrays if remote
                # scriptblock returns array objects, or flat stream of individual artifacts
                $flatCount = 0
                foreach ($item in $batchResults) {
                    if ($item -is [System.Array] -or $item -is [System.Collections.IList]) {
                        # Nested array from a machine — flatten it
                        foreach ($subItem in $item) {
                            if ($subItem) { $batchedResults.Add($subItem); $flatCount++ }
                        }
                    } else {
                        if ($item) { $batchedResults.Add($item); $flatCount++ }
                    }
                }
                Write-ScanLog -Message "Received $flatCount artifact(s) from batch $batchNumber"
            }
            else {
                Write-ScanLog -Level Warning -Message "Batch $batchNumber returned no results (WinRM unreachable or scan empty)"
            }
            Start-Sleep -Milliseconds 100  # Brief pause between batches
        }
        #endregion

        #region --- Process results into allArtifacts and machineResults (C1 fix) ---
        # Invoke-Command returns artifacts with PSComputerName property added by PS remoting.
        # Group results by source machine and build per-machine tracking.
        $succeededMachines = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        foreach ($artifact in $batchedResults) {
            if ($null -eq $artifact) { continue }
            [void]$allArtifacts.Add($artifact)

            # Track which machine returned results
            $machineName = if ($artifact.PSComputerName) { $artifact.PSComputerName }
                           elseif ($artifact.ComputerName) { $artifact.ComputerName }
                           else { 'Unknown' }
            [void]$succeededMachines.Add($machineName)
        }

        # Build per-machine results
        foreach ($name in $ComputerName) {
            $machineArtifacts = @($allArtifacts | Where-Object {
                ($_.PSComputerName -eq $name) -or ($_.ComputerName -eq $name)
            })
            $machineResults[$name] = [PSCustomObject]@{
                Success        = $succeededMachines.Contains($name)
                ArtifactCount  = $machineArtifacts.Count
            }
        }

        # Check for remote errors to identify failed machines
        if ($remoteErrors) {
            foreach ($err in $remoteErrors) {
                $errTarget = if ($err.TargetObject) { $err.TargetObject.ToString() } else { 'Unknown' }
                Write-ScanLog -Level Warning -Message "Remote scan error on ${errTarget}: $($err.Exception.Message)"
                # If the machine isn't in succeededMachines, mark it as failed
                foreach ($name in $ComputerName) {
                    if ($errTarget -match [regex]::Escape($name) -and -not $succeededMachines.Contains($name)) {
                        $machineResults[$name] = [PSCustomObject]@{
                            Success       = $false
                            ArtifactCount = 0
                            Error         = $err.Exception.Message
                        }
                    }
                }
            }
        }
        #endregion

        #region --- Build summary ---
        $successCount = @($machineResults.Values | Where-Object { $_.Success }).Count
        $failCount = $ComputerName.Count - $successCount

        # Success if at least one machine returned results, OR if no errors occurred
        $result.Success = ($successCount -gt 0) -or ($allArtifacts.Count -gt 0)
        $result.Data = $allArtifacts.ToArray()
        $result.PerMachine = $machineResults
        $result.Summary = [PSCustomObject]@{
            ScanDate           = Get-Date
            MachinesAttempted  = $ComputerName.Count
            MachinesSucceeded  = $successCount
            MachinesFailed     = $failCount
            TotalArtifacts     = $allArtifacts.Count
            ArtifactsByMachine = @($allArtifacts | Group-Object ComputerName | Select-Object Name, Count)
        }
        #endregion

        Write-ScanLog -Message "Remote scan complete: $($allArtifacts.Count) total artifacts from $successCount machine(s)"
    }
    catch {
        $result.Error = "Remote artifact scan failed: $($_.Exception.Message)"
        Write-ScanLog -Level Error -Message $result.Error
    }

    return $result
}
