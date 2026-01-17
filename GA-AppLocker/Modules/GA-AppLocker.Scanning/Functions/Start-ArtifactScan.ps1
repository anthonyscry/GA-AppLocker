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

.EXAMPLE
    $machines = (Get-ComputersByOU -OUDistinguishedNames 'OU=Servers,DC=domain,DC=com').Data
    Start-ArtifactScan -Machines $machines -IncludeEventLogs

.EXAMPLE
    Start-ArtifactScan -ScanLocal -SaveResults -ScanName 'LocalBaseline'

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
        [string]$ScanName = "Scan_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
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

        $allArtifacts = @()
        $allEvents = @()
        $machineResults = @{}

        #region --- Local Scan ---
        if ($ScanLocal) {
            Write-ScanLog -Message "Scanning local machine..."

            $localParams = @{}
            if ($Paths) { $localParams.Paths = $Paths }
            $localParams.Recurse = $true

            $localResult = Get-LocalArtifacts @localParams
            if ($localResult.Success) {
                $allArtifacts += $localResult.Data
                $machineResults[$env:COMPUTERNAME] = @{
                    Success       = $true
                    ArtifactCount = $localResult.Data.Count
                    Type          = 'Local'
                }
            }

            if ($IncludeEventLogs) {
                $eventResult = Get-AppLockerEventLogs
                if ($eventResult.Success) {
                    $allEvents += $eventResult.Data
                }
            }
        }
        #endregion

        #region --- Remote Scans ---
        if ($Machines.Count -gt 0) {
            # Group machines by tier for credential selection
            $machinesByTier = $Machines | Group-Object { 
                switch ($_.MachineType) {
                    'DomainController' { 0 }
                    'Server' { 1 }
                    default { 2 }
                }
            }

            foreach ($tierGroup in $machinesByTier) {
                $tier = [int]$tierGroup.Name
                $tierMachines = $tierGroup.Group

                Write-ScanLog -Message "Scanning Tier $tier machines ($($tierMachines.Count) hosts)..."

                # Get credential for this tier
                $credResult = Get-CredentialForTier -Tier $tier
                $credential = if ($credResult.Success) { $credResult.Data } else { $null }

                if (-not $credential) {
                    Write-ScanLog -Level Warning -Message "No credential available for Tier $tier, skipping remote scan"
                    foreach ($machine in $tierMachines) {
                        $machineResults[$machine.Hostname] = @{
                            Success = $false
                            Error   = 'No credential available'
                            Type    = 'Remote'
                        }
                    }
                    continue
                }

                # Scan machines in this tier
                $computerNames = $tierMachines | Select-Object -ExpandProperty Hostname

                $remoteParams = @{
                    ComputerName = $computerNames
                    Credential   = $credential
                    Recurse      = $true
                }
                if ($Paths) { $remoteParams.Paths = $Paths }

                $remoteResult = Get-RemoteArtifacts @remoteParams
                if ($remoteResult.Success) {
                    $allArtifacts += $remoteResult.Data

                    foreach ($machine in $computerNames) {
                        $machineInfo = $remoteResult.PerMachine[$machine]
                        $machineResults[$machine] = @{
                            Success       = $machineInfo.Success
                            ArtifactCount = $machineInfo.ArtifactCount
                            Error         = $machineInfo.Error
                            Type          = 'Remote'
                        }
                    }
                }

                # Collect event logs if requested
                if ($IncludeEventLogs) {
                    foreach ($machine in $tierMachines) {
                        if ($machineResults[$machine.Hostname].Success) {
                            $eventResult = Get-AppLockerEventLogs -ComputerName $machine.Hostname -Credential $credential
                            if ($eventResult.Success) {
                                $allEvents += $eventResult.Data
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

        $successfulMachines = ($machineResults.Values | Where-Object { $_.Success }).Count
        $failedMachines = ($machineResults.Values | Where-Object { -not $_.Success }).Count

        $result.Success = ($successfulMachines -gt 0 -or $ScanLocal)
        $result.Data.Artifacts = $allArtifacts
        $result.Data.EventLogs = $allEvents
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
            UniquePublishers    = ($allArtifacts | Where-Object { $_.Publisher } | Select-Object -Unique Publisher).Count
            SignedArtifacts     = ($allArtifacts | Where-Object { $_.IsSigned }).Count
            UnsignedArtifacts   = ($allArtifacts | Where-Object { -not $_.IsSigned }).Count
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

            $saveData | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $scanFile -Encoding UTF8
            Write-ScanLog -Message "Scan results saved: $scanFile"
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
    [CmdletBinding()]
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
            # Return list of all scans
            $result.Success = $true
            $result.Data = $scanFiles | ForEach-Object {
                $content = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
                [PSCustomObject]@{
                    ScanId    = $content.ScanId
                    ScanName  = $content.ScanName
                    Date      = $_.LastWriteTime
                    Artifacts = $content.Artifacts.Count
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
