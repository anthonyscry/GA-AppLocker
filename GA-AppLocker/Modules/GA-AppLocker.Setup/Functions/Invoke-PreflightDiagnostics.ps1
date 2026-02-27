function script:New-PreflightCheck {
    param(
        [string]$Source,
        [string]$Name,
        [ValidateSet('Pass','Warn','Fail')] [string]$Status,
        [string]$Message = 'No details provided'
    )

    return [PSCustomObject]@{
        Source  = $Source
        Name    = $Name
        Status  = $Status
        Message = if ($Message) { $Message } else { 'No details provided' }
    }
}

function script:Add-PreflightCheckEntry {
    param(
        [System.Collections.Generic.List[PSCustomObject]]$CheckList,
        [string]$Source,
        [string]$Name,
        [ValidateSet('Pass','Warn','Fail')] [string]$Status,
        [string]$Message
    )

    $entry = New-PreflightCheck -Source $Source -Name $Name -Status $Status -Message $Message
    [void]$CheckList.Add($entry)
}

function Invoke-PreflightDiagnostics {
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

        $preReqResult = $null
        try {
            $preReqResult = Test-Prerequisites
        }
        catch {
            Write-SetupLog -Message "[Invoke-PreflightDiagnostics] Test-Prerequisites failed: $($_.Exception.Message)" -Level 'Warning'
        }

        if ($preReqResult -and $preReqResult.Checks) {
            foreach ($check in @($preReqResult.Checks)) {
                $status = if ($check.Passed) { 'Pass' } else { 'Fail' }
                $message = if ($check.Message) { $check.Message } else { 'No details provided' }
                Add-PreflightCheckEntry -CheckList $checks -Source 'Prerequisites' -Name $check.Name -Status $status -Message $message
            }
        }
        else {
            Add-PreflightCheckEntry -CheckList $checks -Source 'Prerequisites' -Name 'Prerequisites evaluation' -Status 'Warn' -Message 'Prerequisites service unavailable'
        }

        $setupStatus = $null
        try {
            $setupStatus = Get-SetupStatus
        }
        catch {
            Write-SetupLog -Message "[Invoke-PreflightDiagnostics] Get-SetupStatus failed: $($_.Exception.Message)" -Level 'Warning'
        }

        if ($setupStatus -and $setupStatus.Success -and $setupStatus.Data) {
            $setupData = $setupStatus.Data

            if ($setupData.ModulesAvailable) {
                foreach ($moduleProperty in $setupData.ModulesAvailable.PSObject.Properties) {
                    $available = [bool]$moduleProperty.Value
                    $status = if ($available) { 'Pass' } else { 'Fail' }
                    $message = if ($available) { 'Available' } else { "Module $($moduleProperty.Name) is not available" }
                    Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name "Module: $($moduleProperty.Name)" -Status $status -Message $message
                }
            }
            else {
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'Module availability' -Status 'Warn' -Message 'Module availability unknown'
            }

            if ($setupData.WinRM) {
                $winrmStatus = if ($setupData.WinRM.Exists) { 'Pass' } else { 'Warn' }
                $message = if ($setupData.WinRM.Status) { $setupData.WinRM.Status } else { 'WinRM GPO status unavailable' }
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'WinRM GPO' -Status $winrmStatus -Message $message
            }
            else {
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'WinRM GPO' -Status 'Warn' -Message 'WinRM GPO status unavailable'
            }

            if ($setupData.DisableWinRM) {
                $disableStatus = if ($setupData.DisableWinRM.Exists) { 'Pass' } else { 'Warn' }
                $message = if ($setupData.DisableWinRM.Status) { $setupData.DisableWinRM.Status } else { 'Disable WinRM GPO status unavailable' }
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'Disable WinRM GPO' -Status $disableStatus -Message $message
            }
            else {
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'Disable WinRM GPO' -Status 'Warn' -Message 'Disable WinRM GPO status unavailable'
            }

            foreach ($gpo in @($setupData.AppLockerGPOs)) {
                $gpoStatus = if ($gpo.Exists) { 'Pass' } else { 'Warn' }
                $message = if ($gpo.Status) { $gpo.Status } else { 'AppLocker GPO status unavailable' }
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name "AppLocker GPO: $($gpo.Type)" -Status $gpoStatus -Message $message
            }

            if ($setupData.ADStructure) {
                $adStatus = 'Warn'
                if ($setupData.ADStructure.OUExists -and ($setupData.ADStructure.GroupsFound -eq $setupData.ADStructure.GroupsTotal)) {
                    $adStatus = 'Pass'
                }

                $message = if ($setupData.ADStructure.Status) { $setupData.ADStructure.Status } else { 'AD structure status unavailable' }
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'AD Structure' -Status $adStatus -Message $message
            }
            else {
                Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'AD Structure' -Status 'Warn' -Message 'AD structure status unavailable'
            }
        }
        else {
            Add-PreflightCheckEntry -CheckList $checks -Source 'Setup Status' -Name 'Setup status' -Status 'Warn' -Message 'Unable to read setup status'
        }

        $allChecks = @($checks)

        if ($allChecks.Count -eq 0) {
            Add-PreflightCheckEntry -CheckList $checks -Source 'Preflight' -Name 'Diagnostics' -Status 'Warn' -Message 'No diagnostic checks executed'
            $allChecks = @($checks)
        }

        $summary = [PSCustomObject]@{
            Pass = 0
            Warn = 0
            Fail = 0
        }

        foreach ($check in $allChecks) {
            switch ($check.Status) {
                'Pass' { $summary.Pass++ }
                'Warn' { $summary.Warn++ }
                'Fail' { $summary.Fail++ }
            }
        }

        $hasFailures = $summary.Fail -gt 0
        $result.Success = -not $hasFailures
        $result.Data = [PSCustomObject]@{
            Checks           = $allChecks
            Summary          = $summary
            BlockingFailures = $hasFailures
        }

        Write-SetupLog -Message "Preflight diagnostics summary: Pass=$($summary.Pass) Warn=$($summary.Warn) Fail=$($summary.Fail)" -Level 'Info'
    }
    catch {
        $result.Error = "Preflight diagnostics failed: $($_.Exception.Message)"
        Write-SetupLog -Message $result.Error -Level 'Error'
    }

    return $result
}
