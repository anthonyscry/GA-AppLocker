<#
.SYNOPSIS
    Exports diagnostic health report for troubleshooting.

.DESCRIPTION
    Generates a comprehensive health report containing:
    - Application version
    - System information (OS, PowerShell)
    - Configuration (sanitized, no credentials)
    - Data counts (rules, policies, scans, deployments)
    - Recent log entries (last 50 lines)

    Designed for air-gapped environments where external
    troubleshooting tools may not be available.

.PARAMETER OutputPath
    Optional output path for health report.
    Default: %LOCALAPPDATA%\GA-AppLocker\HealthReport_YYYYMMDD_HHMMSS.json

.EXAMPLE
    Export-AppLockerHealthReport
    # Creates: C:\Users\user\AppData\Local\GA-AppLocker\HealthReport_20260204_130000.json

.EXAMPLE
    Export-AppLockerHealthReport -OutputPath "C:\Temp\my-report.json"
    # Creates report at specified path

.OUTPUTS
    Result object with Success and Data properties.
    Data contains the file path of the generated report.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>
function Export-AppLockerHealthReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$OutputPath
    )

    $sw = [Diagnostics.Stopwatch]::StartNew()

    try {
        #region --- Get Application Version ---
        $appVersion = try {
            $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) '..\GA-AppLocker.psd1'
            if (Test-Path $manifestPath) {
                $manifestData = Import-PowerShellDataFile -Path $manifestPath
                $manifestData.ModuleVersion
            } else {
                'Unknown'
            }
        }
        catch {
            'Unknown'
        }
        #endregion

        #region --- Get System Information ---
        $osInfo = @{
            Caption     = [System.Environment]::OSVersion.VersionString
            Version     = [System.Environment]::OSVersion.Version.ToString()
            BuildNumber = [System.Environment]::OSVersion.Version.Build.ToString()
            ServicePack = [System.Environment]::OSVersion.ServicePack
        }

        $psInfo = @{
            Version = $PSVersionTable.PSVersion
            Edition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Unknown' }
            CLRVersion = if ($PSVersionTable.CLRVersion) { $PSVersionTable.CLRVersion } else { 'Unknown' }
        }
        #endregion

        #region --- Get Configuration (Sanitized) ---
        try {
            $config = Get-AppLockerConfig

            # Remove sensitive data
            $sanitizedConfig = [ordered]@{}
            foreach ($key in $config.Keys) {
                # Skip credential-related keys
                if ($key -notmatch 'Credential|Password|Secret|Key') {
                    $sanitizedConfig[$key] = $config[$key]
                }
            }
        }
        catch {
            $sanitizedConfig = @{ Error = "Failed to load configuration" }
        }
        #endregion

        #region --- Get Data Counts ---
        try {
            $dataPath = Get-AppLockerDataPath

            $rulesPath = Join-Path $dataPath 'Rules'
            $policiesPath = Join-Path $dataPath 'Policies'
            $scansPath = Join-Path $dataPath 'Scans'
            $deploymentsPath = Join-Path $dataPath 'Deployments'

            $rulesCount = if (Test-Path $rulesPath) {
                @(Get-ChildItem $rulesPath -Filter '*.json' -ErrorAction SilentlyContinue).Count
            } else { 0 }

            $policiesCount = if (Test-Path $policiesPath) {
                @(Get-ChildItem $policiesPath -Filter '*.json' -ErrorAction SilentlyContinue).Count
            } else { 0 }

            $scansCount = if (Test-Path $scansPath) {
                @(Get-ChildItem $scansPath -ErrorAction SilentlyContinue).Count
            } else { 0 }

            $deploymentsCount = if (Test-Path $deploymentsPath) {
                @(Get-ChildItem $deploymentsPath -Filter '*.json' -ErrorAction SilentlyContinue).Count
            } else { 0 }

            $dataCounts = @{
                Rules = $rulesCount
                Policies = $policiesCount
                Scans = $scansCount
                Deployments = $deploymentsCount
                Total = $rulesCount + $policiesCount + $scansCount + $deploymentsCount
            }
        }
        catch {
            $dataCounts = @{ Error = "Failed to count data files" }
        }
        #endregion

        #region --- Get Recent Logs ---
        try {
            $logDir = Join-Path (Get-AppLockerDataPath) 'Logs'
            $logFiles = Get-ChildItem $logDir -Filter 'GA-AppLocker_*.log' -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending

            if ($logFiles.Count -gt 0) {
                $latestLog = $logFiles[0].FullName
                $recentLogs = Get-Content $latestLog -Tail 50 -ErrorAction SilentlyContinue

                # Parse log entries (limit to last 50)
                $logEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($line in $recentLogs) {
                    if ($line -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[(\w+)\] (.+)') {
                        [void]$logEntries.Add([PSCustomObject]@{
                            Timestamp = $Matches[1]
                            Level = $Matches[2]
                            Message = $Matches[3].Trim()
                        })
                    }
                }
                $logEntries = @($logEntries)
            } else {
                $logEntries = @()
            }
        }
        catch {
            $logEntries = @(@{ Error = "Failed to read log files" })
        }
        #endregion

        #region --- Build Report ---
        $report = [ordered]@{
            ReportInfo = @{
                Generated = Get-Date -Format ISO8601
                GeneratedBy = $env:USERNAME
                ComputerName = $env:COMPUTERNAME
            }
            Application = @{
                Name = 'GA-AppLocker'
                Version = $appVersion
            }
            System = @{
                OS = $osInfo
                PowerShell = $psInfo
            }
            Configuration = $sanitizedConfig
            DataCounts = $dataCounts
            RecentLogs = $logEntries
        }
        #endregion

        #region --- Export Report ---
        if ($OutputPath) {
            $outputFile = $OutputPath
        }
        else {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $outputFile = Join-Path (Get-AppLockerDataPath) "HealthReport_${timestamp}.json"
        }

        # Ensure output directory exists
        $outputDir = Split-Path $outputFile -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # Convert to JSON (use depth 3 for reasonable verbosity)
        $json = $report | ConvertTo-Json -Depth 3 -Compress

        # Write to file
        [System.IO.File]::WriteAllText($outputFile, $json)
        #endregion

        $sw.Stop()

        Write-AppLockerLog -Message "Health report exported to $outputFile ($($sw.Elapsed.TotalMilliseconds)ms)" -Level Info

        return @{
            Success = $true
            Data = $outputFile
            Message = "Health report exported successfully"
        }
    }
    catch {
        $sw.Stop()
        Write-AppLockerLog -Message "Health report export failed: $($_.Exception.Message)" -Level Error

        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}
