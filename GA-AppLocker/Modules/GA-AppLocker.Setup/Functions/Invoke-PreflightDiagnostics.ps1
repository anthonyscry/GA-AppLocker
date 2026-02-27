function Invoke-PreflightDiagnostics {
    <#
    .SYNOPSIS
        Runs Bundle A preflight diagnostics for Setup initialization.

    .DESCRIPTION
        Aggregates Test-Prerequisites checks with Get-SetupStatus insight and
        returns a normalized list of Pass/Warn/Fail checks plus counts for
        downstream callers (UI gating, toasts, dashboards).
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $checks = [System.Collections.Generic.List[PSCustomObject]]::new()
        $prereqs = $null
        $setupStatus = $null

        try {
            $prereqs = Test-Prerequisites
        }
        catch {
            [void]$checks.Add([PSCustomObject]@{
                Name    = 'Prerequisites command'
                Status  = 'Fail'
                Message = "Failed to run Test-Prerequisites: $($_.Exception.Message)"
            })
        }

        if (-not $prereqs) {
            $prereqs = [PSCustomObject]@{ AllPassed = $false; Checks = @() }
            [void]$checks.Add([PSCustomObject]@{
                Name    = 'Prerequisites data'
                Status  = 'Fail'
                Message = 'No prerequisite results returned.'
            })
        }

        foreach ($check in @($prereqs.Checks)) {
            $status = if ($check.Passed) { 'Pass' } else { 'Fail' }
            [void]$checks.Add([PSCustomObject]@{
                Name    = "Prerequisite: $($check.Name)"
                Status  = $status
                Message = $check.Message
            })
        }

        try {
            $setupStatus = Get-SetupStatus
        }
        catch {
            [void]$checks.Add([PSCustomObject]@{
                Name    = 'Setup status command'
                Status  = 'Warn'
                Message = "Failed to run Get-SetupStatus: $($_.Exception.Message)"
            })
        }

        if ($setupStatus -and $setupStatus.Data) {
            $modules = $setupStatus.Data.ModulesAvailable
            if ($modules) {
                foreach ($property in $modules.PSObject.Properties) {
                    $moduleName = $property.Name
                    $available = [bool]$property.Value
                    $status = if ($available) { 'Pass' } else { 'Warn' }
                    $message = if ($available) { 'Available' } else { 'Requires RSAT module' }
                    [void]$checks.Add([PSCustomObject]@{
                        Name    = "Module: $moduleName"
                        Status  = $status
                        Message = $message
                    })
                }
            }

            if ($setupStatus.Data.WinRM) {
                $exists = $setupStatus.Data.WinRM.Exists
                $status = if ($exists) { 'Pass' } else { 'Warn' }
                $message = if ($exists) { $setupStatus.Data.WinRM.Status } else { 'WinRM GPO not created' }
                [void]$checks.Add([PSCustomObject]@{
                    Name    = 'WinRM GPO'
                    Status  = $status
                    Message = $message
                })
            }

            if ($setupStatus.Data.DisableWinRM) {
                $exists = $setupStatus.Data.DisableWinRM.Exists
                $status = if ($exists) { 'Pass' } else { 'Warn' }
                $message = if ($exists) { $setupStatus.Data.DisableWinRM.Status } else { 'Disable WinRM GPO not created' }
                [void]$checks.Add([PSCustomObject]@{
                    Name    = 'Disable WinRM GPO'
                    Status  = $status
                    Message = $message
                })
            }

            $appLockerGPOs = @($setupStatus.Data.AppLockerGPOs)
            if ($appLockerGPOs.Count -gt 0) {
                $missing = @($appLockerGPOs | Where-Object { -not $_.Exists })
                if ($missing.Count -eq 0) {
                    [void]$checks.Add([PSCustomObject]@{
                        Name    = 'AppLocker GPOs'
                        Status  = 'Pass'
                        Message = 'DC, Servers, Workstations present'
                    })
                }
                else {
                    $missingNames = @($missing | Select-Object -ExpandProperty Type)
                    [void]$checks.Add([PSCustomObject]@{
                        Name    = 'AppLocker GPOs'
                        Status  = 'Warn'
                        Message = "Missing: $($missingNames -join ', ')"
                    })
                }
            }
            else {
                [void]$checks.Add([PSCustomObject]@{
                    Name    = 'AppLocker GPOs'
                    Status  = 'Warn'
                    Message = 'GPO information unavailable'
                })
            }
        }
        else {
            [void]$checks.Add([PSCustomObject]@{
                Name    = 'Setup status data'
                Status  = 'Warn'
                Message = 'Setup status details are unavailable.'
            })
        }

        $passCount = 0
        $warnCount = 0
        $failCount = 0

        foreach ($check in @($checks)) {
            switch ($check.Status) {
                'Pass' { $passCount++ }
                'Warn' { $warnCount++ }
                'Fail' { $failCount++ }
            }
        }

        $summary = [PSCustomObject]@{
            Pass = $passCount
            Warn = $warnCount
            Fail = $failCount
        }

        $success = ($summary.Fail -eq 0)

        $result.Success = $success
        $result.Data = [PSCustomObject]@{
            Prerequisites = $prereqs
            SetupStatus   = $setupStatus
            Checks        = @($checks.ToArray())
            Summary       = $summary
        }

        if (-not $success) {
            $result.Error = 'Preflight diagnostics detected failed prerequisites'
        }
    }
    catch {
        $result.Error = "Failed to run preflight diagnostics: $($_.Exception.Message)"
    }

    return $result
}
