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
    File extensions to collect.

.PARAMETER Recurse
    Scan subdirectories recursively.

.PARAMETER ThrottleLimit
    Maximum concurrent remote sessions.

.EXAMPLE
    Get-RemoteArtifacts -ComputerName 'Server01', 'Server02'

.EXAMPLE
    $cred = Get-Credential
    Get-RemoteArtifacts -ComputerName 'Workstation01' -Credential $cred -Recurse

.OUTPUTS
    [PSCustomObject] Result with Success, Data (artifacts array), and Summary.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
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
        [string[]]$Paths = @(
            'C:\Program Files',
            'C:\Program Files (x86)'
        ),

        [Parameter()]
        [string[]]$Extensions = @('.exe', '.dll', '.msi', '.ps1'),

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [int]$ThrottleLimit = 5
    )

    $result = [PSCustomObject]@{
        Success  = $false
        Data     = @()
        Error    = $null
        Summary  = $null
        PerMachine = @{}
    }

    try {
        Write-ScanLog -Message "Starting remote artifact scan on $($ComputerName.Count) machine(s)"

        $allArtifacts = @()
        $machineResults = @{}

        #region --- Define remote script block ---
        $remoteScriptBlock = {
            param($ScanPaths, $FileExtensions, $DoRecurse)

            function Get-RemoteFileArtifact {
                param([string]$FilePath)
                
                try {
                    $file = Get-Item -Path $FilePath -ErrorAction Stop
                    $hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
                    
                    $versionInfo = $null
                    try {
                        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
                    }
                    catch { }
                    
                    $signature = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue
                    
                    [PSCustomObject]@{
                        FilePath         = $FilePath
                        FileName         = $file.Name
                        Extension        = $file.Extension.ToLower()
                        Directory        = $file.DirectoryName
                        ComputerName     = $env:COMPUTERNAME
                        SizeBytes        = $file.Length
                        CreatedDate      = $file.CreationTime
                        ModifiedDate     = $file.LastWriteTime
                        SHA256Hash       = $hash.Hash
                        Publisher        = $versionInfo.CompanyName
                        ProductName      = $versionInfo.ProductName
                        ProductVersion   = $versionInfo.ProductVersion
                        FileVersion      = $versionInfo.FileVersion
                        FileDescription  = $versionInfo.FileDescription
                        OriginalFilename = $versionInfo.OriginalFilename
                        IsSigned         = ($signature.Status -eq 'Valid')
                        SignerCertificate = $signature.SignerCertificate.Subject
                        SignatureStatus  = $signature.Status.ToString()
                        CollectedDate    = Get-Date
                    }
                }
                catch {
                    return $null
                }
            }

            $artifacts = @()
            $extensionFilter = $FileExtensions | ForEach-Object { "*$_" }

            foreach ($path in $ScanPaths) {
                if (-not (Test-Path $path)) { continue }

                $params = @{
                    Path        = $path
                    Include     = $extensionFilter
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }

                if ($DoRecurse) {
                    $params.Recurse = $true
                }

                $files = Get-ChildItem @params

                foreach ($file in $files) {
                    $artifact = Get-RemoteFileArtifact -FilePath $file.FullName
                    if ($artifact) {
                        $artifacts += $artifact
                    }
                }
            }

            return $artifacts
        }
        #endregion

        #region --- Execute on each machine ---
        foreach ($computer in $ComputerName) {
            Write-ScanLog -Message "Scanning remote machine: $computer"

            $machineResult = @{
                Success     = $false
                ArtifactCount = 0
                Error       = $null
            }

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $remoteScriptBlock
                    ArgumentList = @($Paths, $Extensions, $Recurse.IsPresent)
                    ErrorAction  = 'Stop'
                }

                if ($Credential) {
                    $invokeParams.Credential = $Credential
                }

                $remoteArtifacts = Invoke-Command @invokeParams

                if ($remoteArtifacts) {
                    $allArtifacts += $remoteArtifacts
                    $machineResult.Success = $true
                    $machineResult.ArtifactCount = $remoteArtifacts.Count
                }
                else {
                    $machineResult.Success = $true
                    $machineResult.ArtifactCount = 0
                }

                Write-ScanLog -Message "Collected $($machineResult.ArtifactCount) artifacts from $computer"
            }
            catch {
                $machineResult.Error = $_.Exception.Message
                Write-ScanLog -Level Warning -Message "Failed to scan $computer`: $($_.Exception.Message)"
            }

            $machineResults[$computer] = $machineResult
        }
        #endregion

        #region --- Build summary ---
        $successCount = ($machineResults.Values | Where-Object { $_.Success }).Count
        $failCount = ($machineResults.Values | Where-Object { -not $_.Success }).Count

        $result.Success = ($successCount -gt 0)
        $result.Data = $allArtifacts
        $result.PerMachine = $machineResults
        $result.Summary = [PSCustomObject]@{
            ScanDate           = Get-Date
            MachinesAttempted  = $ComputerName.Count
            MachinesSucceeded  = $successCount
            MachinesFailed     = $failCount
            TotalArtifacts     = $allArtifacts.Count
            ArtifactsByMachine = $allArtifacts | Group-Object ComputerName | Select-Object Name, Count
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
