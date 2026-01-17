<#
.SYNOPSIS
    Tests network connectivity and WinRM availability for machines.

.DESCRIPTION
    Performs ping and WinRM connectivity tests on a list of machines.
    Updates IsOnline and WinRMStatus properties on each machine object.

.PARAMETER Machines
    Array of machine objects to test.

.PARAMETER TestWinRM
    Also test WinRM connectivity. Default: $true

.PARAMETER TimeoutSeconds
    Timeout for each test in seconds. Default: 5

.EXAMPLE
    $machines = (Get-ComputersByOU -OUDistinguishedNames @('OU=Workstations,DC=corp,DC=local')).Data
    $tested = Test-MachineConnectivity -Machines $machines
    $tested.Data | Where-Object IsOnline | Format-Table Hostname, WinRMStatus

.OUTPUTS
    [PSCustomObject] Result object with Success, Data (tested machines), and Error.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Test-MachineConnectivity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [array]$Machines,

        [Parameter()]
        [bool]$TestWinRM = $true,

        [Parameter()]
        [int]$TimeoutSeconds = 5
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
        Summary = $null
    }

    try {
        $testedMachines = [System.Collections.ArrayList]::new()
        $onlineCount = 0
        $winrmCount = 0

        foreach ($machine in $Machines) {
            #region --- Ping Test ---
            $pingResult = Test-Connection -ComputerName $machine.Hostname `
                -Count 1 `
                -Quiet `
                -TimeoutSeconds $TimeoutSeconds `
                -ErrorAction SilentlyContinue

            $machine.IsOnline = $pingResult
            if ($pingResult) { $onlineCount++ }
            #endregion

            #region --- WinRM Test ---
            if ($TestWinRM -and $pingResult) {
                try {
                    $winrmTest = Test-WSMan -ComputerName $machine.Hostname `
                        -ErrorAction Stop

                    $machine.WinRMStatus = 'Available'
                    $winrmCount++
                }
                catch {
                    $machine.WinRMStatus = 'Unavailable'
                }
            }
            elseif (-not $pingResult) {
                $machine.WinRMStatus = 'Offline'
            }
            #endregion

            [void]$testedMachines.Add($machine)
        }

        #region --- Build Summary ---
        $result.Data = $testedMachines.ToArray()
        $result.Summary = [PSCustomObject]@{
            TotalMachines  = $Machines.Count
            OnlineCount    = $onlineCount
            OfflineCount   = $Machines.Count - $onlineCount
            WinRMAvailable = $winrmCount
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
