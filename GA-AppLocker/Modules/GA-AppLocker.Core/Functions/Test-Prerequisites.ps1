<#
.SYNOPSIS
    Validates that all prerequisites for GA-AppLocker are met.

.DESCRIPTION
    Checks for required PowerShell modules (RSAT), .NET Framework version,
    domain membership, and administrator privileges. Returns a detailed
    result object with pass/fail status for each check.

.EXAMPLE
    $prereqs = Test-Prerequisites
    if (-not $prereqs.AllPassed) {
        $prereqs.Checks | Where-Object { -not $_.Passed }
    }

    Checks prerequisites and displays any failures.

.OUTPUTS
    [PSCustomObject] Object with AllPassed boolean and Checks array.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Test-Prerequisites {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        AllPassed = $true
        Checks    = @()
    }

    #region --- Check 1: PowerShell Version ---
    $psCheck = [PSCustomObject]@{
        Name    = 'PowerShell Version'
        Passed  = $false
        Message = ''
    }

    if ($PSVersionTable.PSVersion.Major -ge 5) {
        $psCheck.Passed = $true
        $psCheck.Message = "Version $($PSVersionTable.PSVersion)"
    }
    else {
        $psCheck.Message = "PowerShell 5.1+ required. Current: $($PSVersionTable.PSVersion)"
        $result.AllPassed = $false
    }
    $result.Checks += $psCheck
    #endregion

    #region --- Check 2: Required Modules (RSAT) ---
    $requiredModules = @('ActiveDirectory', 'GroupPolicy')

    foreach ($moduleName in $requiredModules) {
        $moduleCheck = [PSCustomObject]@{
            Name    = "Module: $moduleName"
            Passed  = $false
            Message = ''
        }

        if (Get-Module -ListAvailable -Name $moduleName) {
            $moduleCheck.Passed = $true
            $moduleCheck.Message = 'Installed'
        }
        else {
            $moduleCheck.Message = 'Not installed. Install RSAT: Add-WindowsCapability -Online -Name Rsat.*'
            $result.AllPassed = $false
        }
        $result.Checks += $moduleCheck
    }
    #endregion

    #region --- Check 3: Administrator Privileges ---
    $adminCheck = [PSCustomObject]@{
        Name    = 'Administrator Privileges'
        Passed  = $false
        Message = ''
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        $adminCheck.Passed = $true
        $adminCheck.Message = 'Running as Administrator'
    }
    else {
        $adminCheck.Message = 'Run as Administrator required'
        $result.AllPassed = $false
    }
    $result.Checks += $adminCheck
    #endregion

    #region --- Check 4: Domain Membership ---
    $domainCheck = [PSCustomObject]@{
        Name    = 'Domain Membership'
        Passed  = $false
        Message = ''
    }

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($computerSystem.PartOfDomain) {
            $domainCheck.Passed = $true
            $domainCheck.Message = "Domain: $($computerSystem.Domain)"
        }
        else {
            $domainCheck.Message = 'Machine is not domain-joined'
            $result.AllPassed = $false
        }
    }
    catch {
        $domainCheck.Message = "Unable to determine: $($_.Exception.Message)"
        $result.AllPassed = $false
    }
    $result.Checks += $domainCheck
    #endregion

    #region --- Check 5: .NET Framework ---
    $netCheck = [PSCustomObject]@{
        Name    = '.NET Framework 4.7.2+'
        Passed  = $false
        Message = ''
    }

    try {
        $netKey = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
        $netRelease = (Get-ItemProperty -Path $netKey -ErrorAction Stop).Release

        # 461808 = .NET 4.7.2
        if ($netRelease -ge 461808) {
            $netCheck.Passed = $true
            $netCheck.Message = "Release: $netRelease"
        }
        else {
            $netCheck.Message = '.NET 4.7.2+ required. Update from Windows Update.'
            $result.AllPassed = $false
        }
    }
    catch {
        $netCheck.Message = '.NET Framework 4.7.2+ not detected'
        $result.AllPassed = $false
    }
    $result.Checks += $netCheck
    #endregion

    #region --- Log Results ---
    $passedCount = ($result.Checks | Where-Object { $_.Passed }).Count
    $totalCount = $result.Checks.Count
    $status = if ($result.AllPassed) { 'All passed' } else { 'Some failed' }

    Write-AppLockerLog -Message "Prerequisites check: $passedCount/$totalCount ($status)" -NoConsole
    #endregion

    return $result
}
