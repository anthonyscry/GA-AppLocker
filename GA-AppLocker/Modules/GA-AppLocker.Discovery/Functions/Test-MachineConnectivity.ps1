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

    if (-not $Hostnames -or $Hostnames.Count -eq 0) {
        return $pingResults
    }

    # For small lists (<=5), use simple sequential to avoid job overhead
    if ($Hostnames.Count -le 5) {
        foreach ($hostname in $Hostnames) {
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
        # Parallel: launch pings as background jobs in throttled batches
        $jobs = [System.Collections.Generic.List[object]]::new()

        foreach ($hostname in $Hostnames) {
            # Throttle: wait for a slot if at capacity
            while ($jobs.Count -ge $ThrottleLimit) {
                $completed = @($jobs | Where-Object { $_.State -ne 'Running' })
                if ($completed.Count -gt 0) {
                    foreach ($job in $completed) {
                        $jobResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
                        $pingResults[$job.Name] = ($jobResult -eq $true)
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                        [void]$jobs.Remove($job)
                    }
                }
                else {
                    Start-Sleep -Milliseconds 50
                }
            }

            $job = Start-Job -Name $hostname -ScriptBlock {
                param($h, $t)
                try {
                    $ping = Get-WmiObject -Class Win32_PingStatus -Filter "Address='$h' AND Timeout=$t" -ErrorAction Stop
                    return ($null -ne $ping -and $ping.StatusCode -eq 0)
                }
                catch {
                    return $false
                }
            } -ArgumentList $hostname, $TimeoutMs
            [void]$jobs.Add($job)
        }

        # Wait for remaining jobs with overall timeout
        $overallTimeout = [datetime]::Now.AddSeconds($TimeoutSeconds + 10)
        while ($jobs.Count -gt 0 -and [datetime]::Now -lt $overallTimeout) {
            $completed = @($jobs | Where-Object { $_.State -ne 'Running' })
            if ($completed.Count -gt 0) {
                foreach ($job in $completed) {
                    $jobResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    $pingResults[$job.Name] = ($jobResult -eq $true)
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    [void]$jobs.Remove($job)
                }
            }
            else {
                Start-Sleep -Milliseconds 100
            }
        }

        # Force-stop any timed-out jobs
        foreach ($job in $jobs) {
            $pingResults[$job.Name] = $false
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
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

    try {
        $onlineCount = 0
        $winrmCount = 0

        #region --- Ping Test (delegates to Test-PingConnectivity) ---
        $timeoutMs = $TimeoutSeconds * 1000
        $hostnames = @($Machines | ForEach-Object { $_.Hostname })

        $pingResults = Test-PingConnectivity `
            -Hostnames $hostnames `
            -TimeoutMs $timeoutMs `
            -TimeoutSeconds $TimeoutSeconds `
            -ThrottleLimit $ThrottleLimit
        #endregion

        #region --- Apply Ping Results + WinRM Test ---
        $testedMachines = [System.Collections.ArrayList]::new()

        foreach ($machine in $Machines) {
            $isOnline = if ($pingResults.ContainsKey($machine.Hostname)) { $pingResults[$machine.Hostname] } else { $false }
            # Use Add-Member -Force instead of direct assignment — property may not exist
            # on machine objects from all code paths (AD module, LDAP, DataGrid wrappers)
            $machine | Add-Member -NotePropertyName 'IsOnline' -NotePropertyValue $isOnline -Force
            if ($isOnline) { $onlineCount++ }

            if ($TestWinRM -and $isOnline) {
                try {
                    $null = Test-WSMan -ComputerName $machine.Hostname -ErrorAction Stop
                    $machine | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue 'Available' -Force
                    $winrmCount++
                }
                catch {
                    $machine | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue 'Unavailable' -Force
                }
            }
            elseif (-not $isOnline) {
                $machine | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue 'Offline' -Force
            }

            [void]$testedMachines.Add($machine)
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
