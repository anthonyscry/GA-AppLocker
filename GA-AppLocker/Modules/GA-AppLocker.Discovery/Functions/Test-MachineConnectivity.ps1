<#
.SYNOPSIS
    Tests network connectivity and WinRM availability for machines.

.DESCRIPTION
    Performs parallel ping and WinRM connectivity tests on a list of machines.
    Updates IsOnline and WinRMStatus properties on each machine object.
    Uses parallel jobs for pings to avoid O(n * timeout) sequential delays.

.PARAMETER Machines
    Array of machine objects to test (must have Hostname property).

.PARAMETER TestWinRM
    Also test WinRM connectivity. Default: $true

.PARAMETER TimeoutSeconds
    Timeout for each connectivity test in seconds. Default: 5.
    Applied as WMI Timeout parameter in milliseconds.

.PARAMETER ThrottleLimit
    Maximum concurrent ping jobs. Default: 20.

.EXAMPLE
    $machines = (Get-ComputersByOU -OUDistinguishedNames @('OU=Workstations,DC=corp,DC=local')).Data
    $tested = Test-MachineConnectivity -Machines $machines
    $tested.Data | Where-Object IsOnline | Format-Table Hostname, WinRMStatus

.OUTPUTS
    [PSCustomObject] Result object with Success, Data (tested machines), Error, and Summary.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.2.0
    Fixed: H1 - Parallel ping using PS jobs instead of sequential Test-Connection
    Fixed: H1 - $TimeoutSeconds now wired to actual timeout behavior
    Refactored: Extracted Test-PingConnectivity for testability
#>

function Test-PingConnectivity {
    <#
    .SYNOPSIS
        Tests ping connectivity for a list of hostnames. Returns hashtable of hostname -> $true/$false.
    .DESCRIPTION
        For small lists (<=5), uses sequential Get-WmiObject Win32_PingStatus.
        For larger lists, uses parallel Start-Job with throttled batches.
        Extracted from Test-MachineConnectivity for testability.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Hostnames,

        [Parameter()]
        [int]$TimeoutMs = 5000,

        [Parameter()]
        [int]$TimeoutSeconds = 5,

        [Parameter()]
        [int]$ThrottleLimit = 20
    )

    $pingResults = @{}
    $invalidHostnamePattern = '[^A-Za-z0-9\.-]'
    $effectiveThrottle = if ($ThrottleLimit -gt 0) { $ThrottleLimit } else { 1 }

    if ($PSBoundParameters.ContainsKey('TimeoutSeconds') -and -not $PSBoundParameters.ContainsKey('TimeoutMs')) {
        $TimeoutMs = $TimeoutSeconds * 1000
    }

    if (-not $Hostnames -or $Hostnames.Count -eq 0) {
        return $pingResults
    }

    # For small lists (<=5), use simple sequential to avoid job overhead
    if ($Hostnames.Count -le 5) {
        foreach ($hostname in $Hostnames) {
            if ($null -eq $hostname) {
                try {
                    Write-AppLockerLog -Level Warning -Message "Invalid hostname for ping: <null>"
                }
                catch { }
                continue
            }
            if ([string]::IsNullOrWhiteSpace($hostname) -or $hostname -match $invalidHostnamePattern) {
                try {
                    Write-AppLockerLog -Level Warning -Message "Invalid hostname for ping: '$hostname'"
                }
                catch { }
                $pingResults[$hostname] = $false
                continue
            }
            try {
                $ping = Get-WmiObject -Class Win32_PingStatus -Filter "Address='$hostname' AND Timeout=$TimeoutMs" -ErrorAction SilentlyContinue
                $pingResults[$hostname] = ($null -ne $ping -and $ping.StatusCode -eq 0)
            }
            catch {
                $pingResults[$hostname] = $false
            }
        }
    }
    else {
        # Parallel: use runspace pool (much faster than Start-Job due to lower overhead)
        $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($effectiveThrottle, $Hostnames.Count))
        $runspacePool.Open()
        
        $runspaces = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        foreach ($hostname in $Hostnames) {
            if ($null -eq $hostname) {
                try {
                    Write-AppLockerLog -Level Warning -Message "Invalid hostname for ping: <null>"
                }
                catch { }
                continue
            }
            if ([string]::IsNullOrWhiteSpace($hostname) -or $hostname -match $invalidHostnamePattern) {
                try {
                    Write-AppLockerLog -Level Warning -Message "Invalid hostname for ping: '$hostname'"
                }
                catch { }
                $pingResults[$hostname] = $false
                continue
            }
            $powershell = [PowerShell]::Create()
            $powershell.RunspacePool = $runspacePool
            
            [void]$powershell.AddScript({
                param($h, $t)
                try {
                    $ping = Get-WmiObject -Class Win32_PingStatus -Filter "Address='$h' AND Timeout=$t" -ErrorAction Stop
                    return @{ Hostname = $h; Success = ($null -ne $ping -and $ping.StatusCode -eq 0) }
                }
                catch {
                    return @{ Hostname = $h; Success = $false }
                }
            }).AddArgument($hostname).AddArgument($TimeoutMs)
            
            $handle = $powershell.BeginInvoke()
            [void]$runspaces.Add([PSCustomObject]@{
                PowerShell = $powershell
                Handle     = $handle
                Hostname   = $hostname
            })
        }
        
        # Wait for all runspaces with overall timeout
        $timeoutSecondsForDeadline = [Math]::Ceiling($TimeoutMs / 1000)
        $batchCount = [Math]::Ceiling($Hostnames.Count / $effectiveThrottle)
        $deadline = [datetime]::Now.AddSeconds(($timeoutSecondsForDeadline * $batchCount) + 10)
        
        foreach ($rs in $runspaces) {
            try {
                $remainingMs = [Math]::Max(100, ($deadline - [datetime]::Now).TotalMilliseconds)
                if ($rs.Handle.AsyncWaitHandle.WaitOne([int]$remainingMs)) {
                    $rsResult = $rs.PowerShell.EndInvoke($rs.Handle)
                    if ($rsResult -and $rsResult.Hostname) {
                        $pingResults[$rsResult.Hostname] = $rsResult.Success
                    }
                    else {
                        $pingResults[$rs.Hostname] = $false
                    }
                }
                else {
                    # Timed out
                    $pingResults[$rs.Hostname] = $false
                    try {
                        $rs.PowerShell.Stop()
                    }
                    catch { }
                }
            }
            catch {
                $pingResults[$rs.Hostname] = $false
            }
            finally {
                $rs.PowerShell.Dispose()
            }
        }
        
        $runspacePool.Close()
        $runspacePool.Dispose()
    }

    return $pingResults
}

function Test-MachineConnectivity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Machines,

        [Parameter()]
        [bool]$TestWinRM = $true,

        [Parameter()]
        [int]$TimeoutSeconds = 5,

        [Parameter()]
        [int]$ThrottleLimit = 20
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
        Summary = $null
    }

    # Handle empty input gracefully
    if (-not $Machines -or $Machines.Count -eq 0) {
        $result.Success = $true
        $result.Data = @()
        $result.Summary = [PSCustomObject]@{
            TotalMachines    = 0
            OnlineCount      = 0
            OfflineCount     = 0
            WinRMAvailable   = 0
            WinRMUnavailable = 0
        }
        return $result
    }

    $Machines = @($Machines | Where-Object { $_ -ne $null })
    if (-not $Machines -or $Machines.Count -eq 0) {
        $result.Success = $true
        $result.Data = @()
        $result.Summary = [PSCustomObject]@{
            TotalMachines    = 0
            OnlineCount      = 0
            OfflineCount     = 0
            WinRMAvailable   = 0
            WinRMUnavailable = 0
        }
        return $result
    }

    try {
        $onlineCount = 0
        $winrmCount = 0
        $effectiveThrottle = if ($ThrottleLimit -gt 0) { $ThrottleLimit } else { 1 }

        #region --- Ping Test (delegates to Test-PingConnectivity) ---
        $timeoutMs = $TimeoutSeconds * 1000
        $hostnames = @($Machines | ForEach-Object { $_.Hostname })

        $pingResults = Test-PingConnectivity `
            -Hostnames $hostnames `
            -TimeoutMs $timeoutMs `
            -TimeoutSeconds $TimeoutSeconds `
            -ThrottleLimit $effectiveThrottle
        #endregion

        #region --- Apply Ping Results + WinRM Test (Parallel) ---
        $testedMachines = [System.Collections.ArrayList]::new()
        
        # First pass: apply ping results and identify online machines
        $onlineMachines = [System.Collections.ArrayList]::new()
        foreach ($machine in $Machines) {
            $hostname = $machine.Hostname
            if ([string]::IsNullOrWhiteSpace($hostname)) {
                $machine | Add-Member -NotePropertyName 'IsOnline' -NotePropertyValue $false -Force
                $machine | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue 'Offline' -Force
                [void]$testedMachines.Add($machine)
                continue
            }

            $isOnline = if ($pingResults.ContainsKey($hostname)) { $pingResults[$hostname] } else { $false }
            $machine | Add-Member -NotePropertyName 'IsOnline' -NotePropertyValue $isOnline -Force
            if ($isOnline) { 
                $onlineCount++
                if ($TestWinRM) { [void]$onlineMachines.Add($machine) }
            }
            else {
                $machine | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue 'Offline' -Force
            }
            [void]$testedMachines.Add($machine)
        }
        
        # Parallel WinRM test for online machines using runspace pool (faster than Start-Job)
        if ($TestWinRM -and $onlineMachines.Count -gt 0) {
            $winrmResults = @{}
            
            # Use runspace pool for much lower overhead than Start-Job
            $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($effectiveThrottle, $onlineMachines.Count))
            $runspacePool.Open()
            
            $runspaces = [System.Collections.Generic.List[PSCustomObject]]::new()
            
            foreach ($machine in $onlineMachines) {
                $powershell = [PowerShell]::Create()
                $powershell.RunspacePool = $runspacePool
                
                [void]$powershell.AddScript({
                    param($Hostname)
                    try {
                        $null = Test-WSMan -ComputerName $Hostname -ErrorAction Stop
                        return @{ Hostname = $Hostname; Available = $true }
                    }
                    catch {
                        return @{ Hostname = $Hostname; Available = $false }
                    }
                }).AddArgument($machine.Hostname)
                
                $handle = $powershell.BeginInvoke()
                [void]$runspaces.Add([PSCustomObject]@{
                    PowerShell = $powershell
                    Handle     = $handle
                    Hostname   = $machine.Hostname
                })
            }
            
            # Wait for all runspaces with timeout (3 seconds per machine, min 15 sec total)
            $totalTimeout = [Math]::Max(15, $onlineMachines.Count * 3)
            $deadline = [datetime]::Now.AddSeconds($totalTimeout)
            
            foreach ($rs in $runspaces) {
                try {
                    $remainingMs = [Math]::Max(100, ($deadline - [datetime]::Now).TotalMilliseconds)
                    if ($rs.Handle.AsyncWaitHandle.WaitOne([int]$remainingMs)) {
                        $rsResult = $rs.PowerShell.EndInvoke($rs.Handle)
                        if ($rsResult -and $rsResult.Hostname) {
                            $winrmResults[$rsResult.Hostname] = $rsResult.Available
                        }
                    }
                    else {
                        # Timed out - mark as unavailable
                        $winrmResults[$rs.Hostname] = $false
                        try {
                            $rs.PowerShell.Stop()
                        }
                        catch { }
                    }
                }
                catch {
                    $winrmResults[$rs.Hostname] = $false
                }
                finally {
                    $rs.PowerShell.Dispose()
                }
            }
            
            $runspacePool.Close()
            $runspacePool.Dispose()
            
            # Apply WinRM results
            foreach ($machine in $testedMachines) {
                if ($machine.IsOnline) {
                    $available = if ($winrmResults.ContainsKey($machine.Hostname)) { $winrmResults[$machine.Hostname] } else { $false }
                    $machine | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue $(if ($available) { 'Available' } else { 'Unavailable' }) -Force
                    if ($available) { $winrmCount++ }
                }
            }
        }
        #endregion

        #region --- Build Summary ---
        $result.Data = $testedMachines.ToArray()
        $result.Summary = [PSCustomObject]@{
            TotalMachines    = $Machines.Count
            OnlineCount      = $onlineCount
            OfflineCount     = $Machines.Count - $onlineCount
            WinRMAvailable   = $winrmCount
            WinRMUnavailable = $onlineCount - $winrmCount
        }
        #endregion

        $result.Success = $true
        Write-AppLockerLog -Message "Connectivity test: $onlineCount/$($Machines.Count) online, $winrmCount WinRM available" -NoConsole
    }
    catch {
        $result.Error = "Connectivity test failed: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }

    return $result
}
