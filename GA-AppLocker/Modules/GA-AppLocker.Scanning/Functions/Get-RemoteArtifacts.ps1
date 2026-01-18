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
        [string[]]$Paths = (Get-DefaultScanPaths),

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

            # Helper function to determine artifact type (runs on remote machine)
            function Get-RemoteArtifactType {
                param([string]$Extension)
                
                # Return UI-compatible artifact type values
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
                    default { 'Unknown' }
                }
            }

            function Get-RemoteFileArtifact {
                param([string]$FilePath)
                
                try {
                    $file = Get-Item -Path $FilePath -ErrorAction Stop
                    $hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
                    
                    $versionInfo = $null
                    try {
                        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
                    }
                    catch { 
                        # Version info not available for some files - acceptable, continue with null
                    }
                    
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
                        ArtifactType     = Get-RemoteArtifactType -Extension $file.Extension
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

        #region --- Execute on machines in parallel ---
        Write-ScanLog -Message "Scanning $($ComputerName.Count) machines in parallel (ThrottleLimit: $ThrottleLimit)"

        # Build Invoke-Command parameters for parallel execution
        $invokeParams = @{
            ComputerName  = $ComputerName
            ScriptBlock   = $remoteScriptBlock
            ArgumentList  = @($Paths, $Extensions, $Recurse.IsPresent)
            ThrottleLimit = $ThrottleLimit
            ErrorAction   = 'SilentlyContinue'
            ErrorVariable = 'remoteErrors'
        }

        if ($Credential) {
            $invokeParams.Credential = $Credential
        }

        # Execute in parallel - Invoke-Command handles multiple computers natively
        $remoteResults = Invoke-Command @invokeParams

        # Process results - group by PSComputerName
        if ($remoteResults) {
            $allArtifacts = @($remoteResults)
            
            # Build per-machine results from successful returns
            $remoteResults | Group-Object PSComputerName | ForEach-Object {
                $computerName = $_.Name
                $machineArtifacts = $_.Group
                $machineResults[$computerName] = @{
                    Success       = $true
                    ArtifactCount = $machineArtifacts.Count
                    Error         = $null
                }
                Write-ScanLog -Message "Collected $($machineArtifacts.Count) artifacts from $computerName"
            }
        }

        # Process errors - machines that failed
        if ($remoteErrors) {
            foreach ($err in $remoteErrors) {
                # Extract computer name from error
                $failedComputer = if ($err.TargetObject) { 
                    $err.TargetObject.ToString() 
                } elseif ($err.Exception.Message -match '(\S+)') {
                    # Try to extract from message
                    $ComputerName | Where-Object { $err.Exception.Message -match [regex]::Escape($_) } | Select-Object -First 1
                } else {
                    'Unknown'
                }
                
                if ($failedComputer -and -not $machineResults.ContainsKey($failedComputer)) {
                    $machineResults[$failedComputer] = @{
                        Success       = $false
                        ArtifactCount = 0
                        Error         = $err.Exception.Message
                    }
                    Write-ScanLog -Level Warning -Message "Failed to scan $failedComputer`: $($err.Exception.Message)"
                }
            }
        }

        # Mark machines with no results and no errors as having 0 artifacts
        foreach ($computer in $ComputerName) {
            if (-not $machineResults.ContainsKey($computer)) {
                $machineResults[$computer] = @{
                    Success       = $true
                    ArtifactCount = 0
                    Error         = $null
                }
            }
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
