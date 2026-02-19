<#
.SYNOPSIS
    Orchestrates artifact scanning across multiple machines.

.DESCRIPTION
    Main entry point for artifact scanning. Manages credential selection,
    parallel execution, and result aggregation for multi-machine scans.

.PARAMETER Machines
    Array of machine objects from Get-ComputersByOU or similar.

.PARAMETER ScanLocal
    Include the local machine in the scan.

.PARAMETER IncludeEventLogs
    Also collect AppLocker event logs.

.PARAMETER Paths
    Custom paths to scan (defaults to Program Files).

.PARAMETER SaveResults
    Save results to scan storage folder.

.PARAMETER ScanName
    Name for this scan (used for saved results).

.PARAMETER ThrottleLimit
    Maximum concurrent remote sessions (default: 5).

.PARAMETER BatchSize
    Number of machines to process per batch (default: 50).

.EXAMPLE
    $machines = (Get-ComputersByOU -OUDistinguishedNames 'OU=Servers,DC=domain,DC=com').Data
    Start-ArtifactScan -Machines $machines -IncludeEventLogs

.EXAMPLE
    Start-ArtifactScan -ScanLocal -SaveResults -ScanName 'LocalBaseline'

.EXAMPLE
    Start-ArtifactScan -Machines $machines -ThrottleLimit 10 -BatchSize 25

.OUTPUTS
    [PSCustomObject] Result with Success, Data (all artifacts), and Summary.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Start-ArtifactScan {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [array]$Machines = @(),

        [Parameter()]
        [switch]$ScanLocal,

        [Parameter()]
        [switch]$IncludeEventLogs,

        [Parameter()]
        [string[]]$Paths,

        [Parameter()]
        [switch]$SaveResults,

        [Parameter()]
        [string]$ScanName = "Scan_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

        [Parameter()]
        [int]$ThrottleLimit = 32,

        [Parameter()]
        [int]$BatchSize = 100,

        [Parameter()]
        [switch]$SkipDllScanning,

        [Parameter()]
        [switch]$SkipWshScanning,

        [Parameter()]
        [switch]$SkipShellScanning,

        [Parameter()]
        [switch]$IncludeAppx,

        [Parameter()]
        [hashtable]$SyncHash = $null
    )

    $result = [PSCustomObject]@{
        Success    = $false
        Data       = @{
            Artifacts  = @()
            EventLogs  = @()
        }
        Error      = $null
        Summary    = $null
        ScanId     = [guid]::NewGuid().ToString()
        ScanName   = $ScanName
    }

    try {
        Write-ScanLog -Message "Starting artifact scan: $ScanName"
        $startTime = Get-Date

        $allArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
        $allEvents = [System.Collections.Generic.List[PSCustomObject]]::new()
        $machineResults = @{}
        $normalizationState = @{
            CanNormalize = ($null -ne (Get-Command -Name 'Normalize-ArtifactRecord' -ErrorAction SilentlyContinue))
            Warned       = $false
            ExceptionWarned = $false
        }

        function Resolve-ScanTierNumber {
            param(
                [object]$Value,
                [int]$DefaultTier = 2
            )

            if ($null -eq $Value) { return $DefaultTier }

            if ($Value -is [int] -or $Value -is [long] -or $Value -is [byte]) {
                $candidate = [int]$Value
                if ($candidate -in @(0, 1, 2)) { return $candidate }
                return $DefaultTier
            }

            $rawValue = [string]$Value
            if ([string]::IsNullOrWhiteSpace($rawValue)) { return $DefaultTier }

            $normalized = $rawValue.Trim()
            $tierMatch = [regex]::Match($normalized, '^(?:[Tt](?:ier)?)?\s*([0-2])$')
            if ($tierMatch.Success) {
                return [int]$tierMatch.Groups[1].Value
            }

            switch ($normalized.ToLowerInvariant()) {
                'domaincontroller' { return 0 }
                'domain controller' { return 0 }
                'dc' { return 0 }
                'server' { return 1 }
                'srv' { return 1 }
                'workstation' { return 2 }
                'desktop' { return 2 }
                'laptop' { return 2 }
                'unknown' { return 2 }
            }

            return $DefaultTier
        }

        function Normalize-ScanMachineTypeKey {
            param([string]$MachineType)

            if ([string]::IsNullOrWhiteSpace($MachineType)) { return 'Unknown' }

            $normalized = $MachineType.Trim().ToLowerInvariant()

            switch ($normalized) {
                'domaincontroller' { return 'DomainController' }
                'domain controller' { return 'DomainController' }
                'dc' { return 'DomainController' }
                'server' { return 'Server' }
                'srv' { return 'Server' }
                'workstation' { return 'Workstation' }
                'desktop' { return 'Workstation' }
                'laptop' { return 'Workstation' }
                'unknown' { return 'Unknown' }
                default { return $MachineType.Trim() }
            }
        }

        function Get-DefaultTierForMachineType {
            param([string]$MachineType)

            $normalizedType = Normalize-ScanMachineTypeKey -MachineType $MachineType

            switch ($normalizedType) {
                'DomainController' { return 0 }
                'Server' { return 1 }
                default { return 2 }
            }
        }

        function Add-NormalizedArtifacts {
            param(
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[PSCustomObject]]$Target,

                [Parameter()]
                [array]$Artifacts = @()
            )

            if (-not $normalizationState.CanNormalize -and -not $normalizationState.Warned) {
                Write-ScanLog -Level 'Warning' -Message 'Normalize-ArtifactRecord unavailable in scan scope; falling back to raw artifact records.'
                $normalizationState.Warned = $true
            }

            foreach ($artifact in @($Artifacts)) {
                if ($null -eq $artifact) { continue }

                $artifactToAdd = $artifact
                $artifactName = [string]$artifact.FileName
                if ([string]::IsNullOrWhiteSpace($artifactName)) { $artifactName = '<unknown>' }
                $artifactPath = [string]$artifact.FilePath
                if ([string]::IsNullOrWhiteSpace($artifactPath)) { $artifactPath = '<unknown>' }
                $artifactComputer = [string]$artifact.ComputerName
                if ([string]::IsNullOrWhiteSpace($artifactComputer)) { $artifactComputer = '<unknown>' }
                $artifactContext = "FileName='$artifactName', FilePath='$artifactPath', ComputerName='$artifactComputer'"

                if ($normalizationState.CanNormalize) {
                    try {
                        $normalizedArtifact = Normalize-ArtifactRecord -Artifact $artifact
                        if ($null -ne $normalizedArtifact) {
                            $artifactToAdd = $normalizedArtifact
                        }
                        else {
                            Write-ScanLog -Level 'DEBUG' -Message 'Normalize-ArtifactRecord returned null; using raw artifact record.'
                        }
                    }
                    catch {
                        if (-not $normalizationState.ExceptionWarned) {
                            Write-ScanLog -Level 'Warning' -Message "Normalize-ArtifactRecord failed for artifact ($artifactContext); using raw artifact record. Subsequent normalization exceptions will be logged at DEBUG. Error: $($_.Exception.Message)"
                            $normalizationState.ExceptionWarned = $true
                        }
                        else {
                            Write-ScanLog -Level 'DEBUG' -Message "Normalize-ArtifactRecord failed; using raw artifact record. Artifact: $artifactContext. Error: $($_.Exception.Message)"
                        }
                    }
                }

                [void]$Target.Add($artifactToAdd)
            }
        }

        # Configure progress ranges based on what's being scanned
        # to prevent local and remote progress bars from overlapping
        $hasLocal = $ScanLocal.IsPresent
        $hasRemote = ($Machines.Count -gt 0)
        if ($SyncHash) {
            if ($hasLocal -and $hasRemote) {
                # Both: Local 10-45%, Remote 45-85%, Appx/Summary 85-100%
                $SyncHash.LocalProgressMin = 10
                $SyncHash.LocalProgressMax = 45
                $SyncHash.RemoteProgressMin = 45
                $SyncHash.RemoteProgressMax = 85
            }
            elseif ($hasLocal) {
                # Local only: 10-88%, Appx/Summary 88-100%
                $SyncHash.LocalProgressMin = 10
                $SyncHash.LocalProgressMax = 88
            }
            elseif ($hasRemote) {
                # Remote only: 10-88%, Summary 88-100%
                $SyncHash.RemoteProgressMin = 10
                $SyncHash.RemoteProgressMax = 88
            }
        }

        #region --- Local Scan ---
        if ($ScanLocal) {
            Write-ScanLog -Message "Scanning local machine..."

            $localParams = @{}
            if ($Paths) { $localParams.Paths = $Paths }
            $localParams.Recurse = $true
            if ($SyncHash) { $localParams.SyncHash = $SyncHash }
            if ($SkipDllScanning) { $localParams.SkipDllScanning = $true }
            if ($SkipWshScanning) { $localParams.SkipWshScanning = $true }
            if ($SkipShellScanning) { $localParams.SkipShellScanning = $true }

            $localResult = Get-LocalArtifacts @localParams
            if ($localResult.Success) {
                Add-NormalizedArtifacts -Target $allArtifacts -Artifacts $localResult.Data
                $machineResults[$env:COMPUTERNAME] = @{
                    Success       = $true
                    ArtifactCount = $localResult.Data.Count
                    Type          = 'Local'
                }
            }

            if ($IncludeEventLogs) {
                $eventResult = Get-AppLockerEventLogs
                if ($eventResult.Success) {
                    foreach ($evt in @($eventResult.Data)) { [void]$allEvents.Add($evt) }
                }
            }

            # Scan Appx/MSIX packages if requested
            if ($IncludeAppx) {
                Write-ScanLog -Message "Scanning Appx/MSIX packages..."
                if ($SyncHash) { 
                    $SyncHash.StatusText = "Scanning Appx/MSIX packages..."
                    $SyncHash.Progress = 89
                }

                # Include system apps, frameworks, and all users by default —
                # AppLocker needs visibility into ALL installed packages to generate rules.
                # On Server 2019, nearly all Appx packages are system/framework.
                $appxParams = @{
                    IncludeSystemApps = $true
                    IncludeFrameworks = $true
                    AllUsers          = $true
                }
                if ($SyncHash) { $appxParams.SyncHash = $SyncHash }

                $appxResult = Get-AppxArtifacts @appxParams
                if ($appxResult.Success) {
                    Add-NormalizedArtifacts -Target $allArtifacts -Artifacts $appxResult.Data
                    Write-ScanLog -Message "Found $($appxResult.Data.Count) Appx packages"
                }
                else {
                    Write-ScanLog -Level Warning -Message "Appx enumeration failed: $($appxResult.Error)"
                }
            }
        }
        #endregion

        #region --- Remote Scans ---
        if ($Machines.Count -gt 0) {
            # Load tier mapping from config
            $machineTypeTiers = @{ DomainController = 0; Server = 1; Workstation = 2; Unknown = 2 }
            try {
                $config = Get-AppLockerConfig
                if ($config -and $config.MachineTypeTiers) {
                    $resolvedMap = @{}
                    $tierSource = $config.MachineTypeTiers

                    if ($tierSource -is [System.Collections.IDictionary]) {
                        foreach ($entry in $tierSource.GetEnumerator()) {
                            $machineType = Normalize-ScanMachineTypeKey -MachineType ([string]$entry.Key)
                            if ([string]::IsNullOrWhiteSpace($machineType)) { continue }
                            $defaultTier = Get-DefaultTierForMachineType -MachineType $machineType
                            $resolvedMap[$machineType] = Resolve-ScanTierNumber -Value $entry.Value -DefaultTier $defaultTier
                        }
                    }
                    else {
                        foreach ($prop in $tierSource.PSObject.Properties) {
                            $machineType = Normalize-ScanMachineTypeKey -MachineType ([string]$prop.Name)
                            if ([string]::IsNullOrWhiteSpace($machineType)) { continue }
                            $defaultTier = Get-DefaultTierForMachineType -MachineType $machineType
                            $resolvedMap[$machineType] = Resolve-ScanTierNumber -Value $prop.Value -DefaultTier $defaultTier
                        }
                    }

                    if ($resolvedMap.Count -gt 0) {
                        foreach ($defaultKey in @($machineTypeTiers.Keys)) {
                            if (-not $resolvedMap.ContainsKey($defaultKey)) {
                                $resolvedMap[$defaultKey] = $machineTypeTiers[$defaultKey]
                            }
                        }
                        $machineTypeTiers = $resolvedMap
                    }
                }
            }
            catch { Write-AppLockerLog -Message "Failed to load MachineTypeTiers config: $($_.Exception.Message)" -Level 'DEBUG' }

            # Group machines by tier for credential selection
            $machinesByTier = $Machines | Group-Object { 
                $type = Normalize-ScanMachineTypeKey -MachineType ([string]$_.MachineType)
                if ([string]::IsNullOrWhiteSpace($type)) { $type = 'Unknown' }
                if ($machineTypeTiers.ContainsKey($type)) { $machineTypeTiers[$type] } else { 2 }
            }

            $tierIndex = 0
            $totalTiers = @($machinesByTier).Count

            foreach ($tierGroup in $machinesByTier) {
                $tier = Resolve-ScanTierNumber -Value $tierGroup.Name -DefaultTier 2
                $tierMachines = $tierGroup.Group
                $tierIndex++

                $tierTypes = ($tierMachines | ForEach-Object { "$($_.Hostname)[$($_.MachineType)]" }) -join ', '
                Write-ScanLog -Message "Scanning Tier $tier machines ($($tierMachines.Count) hosts): $tierTypes"
                
                # Update progress for UI — show which machines are being scanned
                if ($SyncHash) {
                    $remoteMin = if ($SyncHash.RemoteProgressMin) { [int]$SyncHash.RemoteProgressMin } else { 30 }
                    $remoteMax = if ($SyncHash.RemoteProgressMax) { [int]$SyncHash.RemoteProgressMax } else { 85 }
                    $remoteSpan = $remoteMax - $remoteMin
                    $machineNames = ($tierMachines | ForEach-Object { $_.Hostname }) -join ', '
                    $SyncHash.StatusText = "Scanning Tier $tier ($tierIndex/$totalTiers): $machineNames"
                    # Scale remote progress across configured range
                    $SyncHash.Progress = [Math]::Min($remoteMax, $remoteMin + [int](($tierIndex - 1) / [Math]::Max(1, $totalTiers) * $remoteSpan))
                }

                # Get credential for this tier with fallback chain:
                # 1. Try exact tier match
                # 2. Try other tiers (domain admin cred often works for all)
                # 3. Fall back to implicit Windows auth (current user context)
                $credential = $null
                $credSource = 'none'
                
                $credResult = Get-CredentialForTier -Tier $tier
                if ($credResult.Success) {
                    $credential = $credResult.Data
                    $credSource = "Tier $tier"
                }
                else {
                    # Fallback: try other tiers (higher privilege first: T0 → T1 → T2)
                    $fallbackTiers = @(0, 1, 2) | Where-Object { $_ -ne $tier }
                    foreach ($fallbackTier in $fallbackTiers) {
                        $fallbackResult = Get-CredentialForTier -Tier $fallbackTier
                        if ($fallbackResult.Success) {
                            $credential = $fallbackResult.Data
                            $credSource = "Tier $fallbackTier (fallback)"
                            Write-ScanLog -Level Warning -Message "No credential for Tier $tier, using Tier $fallbackTier credential as fallback"
                            break
                        }
                    }
                }

                if ($credential) {
                    Write-ScanLog -Message "Using credential: $credSource (User: $($credential.UserName)) for $($tierMachines.Count) machine(s): $($tierMachines.Hostname -join ', ')"
                }
                else {
                    # Last resort: try without explicit credential (uses current Windows identity)
                    Write-ScanLog -Level Warning -Message "No stored credentials found for Tier $tier (or any tier). Attempting with current Windows identity."
                    $credSource = 'implicit (current user)'
                }

                # Scan machines in this tier
                $computerNames = $tierMachines | Select-Object -ExpandProperty Hostname

                $remoteParams = @{
                    ComputerName  = $computerNames
                    Recurse       = $true
                    ThrottleLimit = $ThrottleLimit
                    BatchSize     = $BatchSize
                }
                # Only pass -Credential if we have an explicit one (null = use current Windows identity)
                if ($credential) { $remoteParams.Credential = $credential }
                if ($Paths) { $remoteParams.Paths = $Paths }
                if ($SkipDllScanning) { $remoteParams.SkipDllScanning = $true }
                if ($SkipWshScanning) { $remoteParams.SkipWshScanning = $true }
                if ($SkipShellScanning) { $remoteParams.SkipShellScanning = $true }

                $remoteResult = Get-RemoteArtifacts @remoteParams
                if ($remoteResult.Success) {
                    Add-NormalizedArtifacts -Target $allArtifacts -Artifacts $remoteResult.Data

                    foreach ($machine in $computerNames) {
                        $machineInfo = $remoteResult.PerMachine[$machine]
                        $machineResults[$machine] = @{
                            Success       = $machineInfo.Success
                            ArtifactCount = $machineInfo.ArtifactCount
                            Error         = $machineInfo.Error
                            Type          = 'Remote'
                        }
                    }
                    
                    # Update progress after tier completes
                    if ($SyncHash) {
                        $successCount = @($remoteResult.PerMachine.Values | Where-Object { $_.Success }).Count
                        $SyncHash.StatusText = "Tier $tier done: $($remoteResult.Data.Count) artifacts from $successCount/$($computerNames.Count) machines"
                        $SyncHash.Progress = [Math]::Min($remoteMax, $remoteMin + [int]($tierIndex / [Math]::Max(1, $totalTiers) * $remoteSpan))
                    }
                }
                else {
                    # Remote scan returned failure — update progress to show which tier failed
                    if ($SyncHash) {
                        $SyncHash.StatusText = "Tier $tier scan failed: $($remoteResult.Error)"
                    }
                }

                # Collect event logs if requested
                if ($IncludeEventLogs) {
                    foreach ($machine in $tierMachines) {
                        if ($machineResults[$machine.Hostname].Success) {
                            $eventResult = Get-AppLockerEventLogs -ComputerName $machine.Hostname -Credential $credential
                            if ($eventResult.Success) {
                                foreach ($evt in @($eventResult.Data)) { [void]$allEvents.Add($evt) }
                            }
                        }
                    }
                }
            }
        }
        #endregion

        #region --- Build Summary ---
        $endTime = Get-Date
        $duration = $endTime - $startTime

        $successfulMachines = @($machineResults.Values | Where-Object { $_.Success }).Count
        $failedMachines = @($machineResults.Values | Where-Object { -not $_.Success }).Count

        $result.Success = ($successfulMachines -gt 0 -or $ScanLocal)
        $result.Data.Artifacts = @($allArtifacts)
        $result.Data.EventLogs = @($allEvents)
        $result.Summary = [PSCustomObject]@{
            ScanId              = $result.ScanId
            ScanName            = $ScanName
            StartTime           = $startTime
            EndTime             = $endTime
            Duration            = $duration.ToString()
            TotalMachines       = $machineResults.Count
            SuccessfulMachines  = $successfulMachines
            FailedMachines      = $failedMachines
            TotalArtifacts      = $allArtifacts.Count
            TotalEvents         = $allEvents.Count
            UniquePublishers    = @($allArtifacts | Where-Object { $_.Publisher } | Select-Object -Unique Publisher).Count
            SignedArtifacts     = @($allArtifacts | Where-Object { $_.IsSigned }).Count
            UnsignedArtifacts   = @($allArtifacts | Where-Object { -not $_.IsSigned }).Count
            AppxArtifacts       = @($allArtifacts | Where-Object { $_.CollectionType -eq 'Appx' }).Count
            MachineResults      = $machineResults
            ArtifactsByType     = $allArtifacts | Group-Object ArtifactType | Select-Object Name, Count
        }
        #endregion

        #region --- Save Results ---
        if ($SaveResults) {
            $scanPath = Get-ScanStoragePath
            $scanFile = Join-Path $scanPath "$($result.ScanId).json"

            $saveData = @{
                ScanId    = $result.ScanId
                ScanName  = $ScanName
                Summary   = $result.Summary
                Artifacts = $allArtifacts
                EventLogs = $allEvents
            }

            $saveData | ConvertTo-Json -Depth 3 -Compress | Set-Content -Path $scanFile -Encoding UTF8
            Write-ScanLog -Message "Scan results saved: $scanFile"
        }
        #endregion

        #region --- Auto-Export Per-Host CSVs ---
        # Always export one CSV per host to the Scans folder
        # Wrapped in try/catch so export failures never crash the scan
        try {
            if ($allArtifacts.Count -gt 0) {
                $scanPath = Get-ScanStoragePath
                # Ensure every artifact has a ComputerName (Appx/local may be null)
                foreach ($a in $allArtifacts) {
                    if (-not $a.ComputerName) {
                        $a | Add-Member -NotePropertyName 'ComputerName' -NotePropertyValue $env:COMPUTERNAME -Force
                    }
                }
                $hostGroups = $allArtifacts | Group-Object -Property ComputerName
                $dateStamp = Get-Date -Format 'ddMMMyy'
                foreach ($group in $hostGroups) {
                    $hostName = if ($group.Name) { $group.Name } else { $env:COMPUTERNAME }
                    $safeHost = $hostName -replace '[\\/:*?"<>|]', '_'
                    $hostFile = Join-Path $scanPath "${safeHost}_artifacts_${dateStamp}.csv"
                    $group.Group | Select-Object FileName, FilePath, ArtifactType, CollectionType,
                        Publisher, PublisherName, ProductName, ProductVersion, FileVersion,
                        IsSigned, SignerCertificate, SignatureStatus,
                        SHA256Hash, FileSize, SizeBytes, ComputerName |
                        Export-Csv -Path $hostFile -NoTypeInformation -Encoding UTF8
                    Write-ScanLog -Message "Per-host CSV export: $hostFile ($($group.Count) artifacts)"
                }
                Write-ScanLog -Message "Exported CSVs for $($hostGroups.Count) host(s) to $scanPath"
            }
        }
        catch {
            Write-ScanLog -Level Warning -Message "Per-host CSV export failed (scan results unaffected): $($_.Exception.Message)"
        }
        #endregion

        Write-ScanLog -Message "Scan complete: $($allArtifacts.Count) artifacts from $successfulMachines machine(s)"
    }
    catch {
        $result.Error = "Artifact scan failed: $($_.Exception.Message)"
        Write-ScanLog -Level Error -Message $result.Error
    }

    return $result
}

<#
.SYNOPSIS
    Retrieves saved scan results.

.DESCRIPTION
    Loads previously saved scan results from storage.

.PARAMETER ScanId
    GUID of a specific scan to retrieve.

.PARAMETER Latest
    Get the most recent scan.

.EXAMPLE
    Get-ScanResults -Latest

.OUTPUTS
    [PSCustomObject] Scan data.
#>
function Get-ScanResults {
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [string]$ScanId,

        [Parameter(ParameterSetName = 'Latest')]
        [switch]$Latest
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $scanPath = Get-ScanStoragePath
        $scanFiles = Get-ChildItem -Path $scanPath -Filter '*.json' -ErrorAction SilentlyContinue | 
                     Sort-Object LastWriteTime -Descending

        if ($Latest) {
            $targetFile = $scanFiles | Select-Object -First 1
        }
        elseif ($ScanId) {
            $targetFile = $scanFiles | Where-Object { $_.BaseName -eq $ScanId }
        }
        else {
            # Return list of all scans — read only first 1KB for metadata (avoid parsing multi-MB files)
            $result.Success = $true
            $result.Data = $scanFiles | ForEach-Object {
                $scanId = $_.BaseName
                $scanName = $scanId
                $artifactCount = 0
                try {
                    # Read only the first 1024 bytes to extract summary metadata
                    $stream = [System.IO.File]::OpenRead($_.FullName)
                    try {
                        $buffer = New-Object byte[] 1024
                        $bytesRead = $stream.Read($buffer, 0, 1024)
                        $header = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                    }
                    finally {
                        $stream.Close()
                        $stream.Dispose()
                    }
                    # Extract ScanId from header
                    if ($header -match '"ScanId"\s*:\s*"([^"]+)"') {
                        $scanId = $Matches[1]
                    }
                    # Extract ScanName from header
                    if ($header -match '"ScanName"\s*:\s*"([^"]+)"') {
                        $scanName = $Matches[1]
                    }
                    # Extract TotalArtifacts from Summary header
                    if ($header -match '"TotalArtifacts"\s*:\s*(\d+)') {
                        $artifactCount = [int]$Matches[1]
                    }
                }
                catch {
                    # Fallback: use filename as ID
                }
                [PSCustomObject]@{
                    ScanId    = $scanId
                    ScanName  = $scanName
                    Date      = $_.LastWriteTime
                    Artifacts = $artifactCount
                }
            }
            return $result
        }

        if ($targetFile) {
            $result.Success = $true
            $result.Data = Get-Content -Path $targetFile.FullName -Raw | ConvertFrom-Json
        }
        else {
            $result.Error = "Scan not found"
        }
    }
    catch {
        $result.Error = "Failed to retrieve scan results: $($_.Exception.Message)"
    }

    return $result
}

<#
.SYNOPSIS
    Exports scan results to CSV or JSON.

.DESCRIPTION
    Exports artifact data from a scan to external formats.

.PARAMETER ScanId
    ID of scan to export.

.PARAMETER OutputPath
    Destination file path.

.PARAMETER Format
    Output format: CSV or JSON.

.EXAMPLE
    Export-ScanResults -ScanId '12345...' -OutputPath 'C:\Reports\scan.csv' -Format CSV
#>
function Export-ScanResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScanId,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('CSV', 'JSON')]
        [string]$Format = 'CSV'
    )

    $result = [PSCustomObject]@{
        Success = $false
        Error   = $null
    }

    try {
        $scanResult = Get-ScanResults -ScanId $ScanId
        if (-not $scanResult.Success) {
            $result.Error = $scanResult.Error
            return $result
        }

        $artifacts = $scanResult.Data.Artifacts

        switch ($Format) {
            'CSV' {
                $artifacts | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }
            'JSON' {
                $artifacts | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
            }
        }

        $result.Success = $true
        Write-ScanLog -Message "Exported $($artifacts.Count) artifacts to $OutputPath"
    }
    catch {
        $result.Error = "Export failed: $($_.Exception.Message)"
        Write-ScanLog -Level Error -Message $result.Error
    }

    return $result
}
