<#
.SYNOPSIS
    Gets the current status of AppLocker environment setup.

.DESCRIPTION
    Checks the status of:
    - WinRM GPO (exists, linked, enabled)
    - AppLocker GPOs (DC, Servers, Workstations)
    - AppLocker OU and security groups

.EXAMPLE
    Get-SetupStatus
    
    Returns the current setup status.

.OUTPUTS
    [PSCustomObject] Status information for all setup components.
#>
function Get-SetupStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $hasGP = Test-ModuleAvailable -ModuleName 'GroupPolicy'
        $hasAD = Test-ModuleAvailable -ModuleName 'ActiveDirectory'

        $status = [PSCustomObject]@{
            ModulesAvailable = [PSCustomObject]@{
                GroupPolicy     = $hasGP
                ActiveDirectory = $hasAD
            }
            WinRM            = $null
            DisableWinRM     = $null
            AppLockerGPOs    = @()
            ADStructure      = $null
            LastChecked      = Get-Date
        }

        # Check WinRM GPO
        if ($hasGP) {
            Import-Module GroupPolicy -ErrorAction SilentlyContinue
            $winrmGPO = Get-GPO -Name $script:DefaultGPONames.WinRM -ErrorAction SilentlyContinue
            
            if ($winrmGPO) {
                $domainDN = Get-DomainDN
                $link = $null
                try {
                    $link = Get-GPInheritance -Target $domainDN -ErrorAction SilentlyContinue | 
                            Select-Object -ExpandProperty GpoLinks | 
                            Where-Object { $_.DisplayName -eq $script:DefaultGPONames.WinRM }
                }
                catch { }

                $status.WinRM = [PSCustomObject]@{
                    Exists    = $true
                    GPOName   = $winrmGPO.DisplayName
                    GPOId     = $winrmGPO.Id
                    Linked    = [bool]$link
                    Enabled   = if ($link) { $link.Enabled } else { $false }
                    Status    = if ($link -and $link.Enabled) { 'Enabled' } elseif ($link) { 'Disabled' } else { 'Not Linked' }
                }
            }
            else {
                $status.WinRM = [PSCustomObject]@{
                    Exists  = $false
                    Status  = 'Not Created'
                }
            }

            # Check DisableWinRM GPO
            $disableGPO = Get-GPO -Name 'AppLocker-DisableWinRM' -ErrorAction SilentlyContinue
            if ($disableGPO) {
                $domainDN2 = Get-DomainDN
                $disableLink = $null
                try {
                    $disableLink = Get-GPInheritance -Target $domainDN2 -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty GpoLinks |
                            Where-Object { $_.DisplayName -eq 'AppLocker-DisableWinRM' }
                }
                catch { }

                $status.DisableWinRM = [PSCustomObject]@{
                    Exists    = $true
                    GPOName   = $disableGPO.DisplayName
                    GPOId     = $disableGPO.Id
                    Linked    = [bool]$disableLink
                    Enabled   = if ($disableLink) { $disableLink.Enabled } else { $false }
                    Status    = if ($disableLink -and $disableLink.Enabled) { 'Enabled' } elseif ($disableLink) { 'Disabled' } else { 'Not Linked' }
                }
            }
            else {
                $status.DisableWinRM = [PSCustomObject]@{
                    Exists  = $false
                    Status  = 'Not Created'
                }
            }

            # Check AppLocker GPOs
            foreach ($gpoType in @('DC', 'Servers', 'Workstations')) {
                $gpoName = $script:DefaultGPONames[$gpoType]
                $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
                
                # Derive friendly GpoStatus label (AllSettingsEnabled -> Enabled, AllSettingsDisabled -> Disabled)
                $gpoStateLabel = $null
                if ($gpo) {
                    $gpoStateLabel = switch ($gpo.GpoStatus.ToString()) {
                        'AllSettingsEnabled'  { 'Enabled' }
                        'AllSettingsDisabled' { 'Disabled' }
                        'UserSettingsDisabled' { 'User Disabled' }
                        'ComputerSettingsDisabled' { 'Computer Disabled' }
                        default { $gpo.GpoStatus.ToString() }
                    }
                }

                $status.AppLockerGPOs += [PSCustomObject]@{
                    Type      = $gpoType
                    Name      = $gpoName
                    Exists    = [bool]$gpo
                    GPOId     = if ($gpo) { $gpo.Id } else { $null }
                    GpoState  = $gpoStateLabel
                    Status    = if ($gpo -and $gpoStateLabel) { "Configured - $gpoStateLabel" } elseif ($gpo) { 'Configured' } else { 'Not Configured' }
                }
            }
        }
        else {
            $status.WinRM = [PSCustomObject]@{ Exists = $false; Status = 'Module Not Available' }
            $status.DisableWinRM = [PSCustomObject]@{ Exists = $false; Status = 'Module Not Available' }
        }

        # Check AD Structure
        if ($hasAD) {
            Import-Module ActiveDirectory -ErrorAction SilentlyContinue
            $domainDN = Get-DomainDN
            
            $ou = Get-ADOrganizationalUnit -Filter "Name -eq '$($script:DefaultOUName)'" -SearchBase $domainDN -ErrorAction SilentlyContinue
            
            $groupStatus = @()
            foreach ($groupDef in $script:DefaultGroups) {
                $group = Get-ADGroup -Filter "Name -eq '$($groupDef.Name)'" -ErrorAction SilentlyContinue
                $groupStatus += [PSCustomObject]@{
                    Name   = $groupDef.Name
                    Exists = [bool]$group
                }
            }

            $status.ADStructure = [PSCustomObject]@{
                OUExists     = [bool]$ou
                OUPath       = if ($ou) { $ou.DistinguishedName } else { $null }
                Groups       = $groupStatus
                GroupsFound  = @($groupStatus | Where-Object { $_.Exists }).Count
                GroupsTotal  = $script:DefaultGroups.Count
                Status       = if ($ou) { 'Configured' } else { 'Not Configured' }
            }
        }
        else {
            $status.ADStructure = [PSCustomObject]@{ OUExists = $false; Status = 'Module Not Available' }
        }

        $result.Success = $true
        $result.Data = $status
    }
    catch {
        $result.Error = "Failed to get setup status: $($_.Exception.Message)"
        Write-SetupLog -Message $result.Error -Level Error
    }

    return $result
}

function Initialize-AppLockerEnvironment {
    <#
    .SYNOPSIS
        Runs all initialization steps at once.

    .DESCRIPTION
        Runs all initialization steps at once. Idempotent - safe to call multiple times.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @{}
        Error   = $null
    }

    try {
        Write-SetupLog -Message "Starting full AppLocker environment initialization"

        # Initialize WinRM GPOs (Enable + Disable)
        $winrmResult = Initialize-WinRMGPO
        $result.Data.WinRM = $winrmResult

        $disableWinrmResult = Initialize-DisableWinRMGPO
        $result.Data.DisableWinRM = $disableWinrmResult

        # Fix link states: Enable GPO active, Disable GPO inactive (ready but not applied)
        try {
            Enable-WinRMGPO -GPOName 'AppLocker-EnableWinRM' -ErrorAction SilentlyContinue
            Disable-WinRMGPO -GPOName 'AppLocker-DisableWinRM' -ErrorAction SilentlyContinue
        }
        catch {
            Write-SetupLog -Message "WinRM GPO link state update failed: $($_.Exception.Message)" -Level Warning
        }

        # Initialize AppLocker GPOs
        $gposResult = Initialize-AppLockerGPOs
        $result.Data.AppLockerGPOs = $gposResult

        # Initialize AD Structure
        $adResult = Initialize-ADStructure
        $result.Data.ADStructure = $adResult

        # Check overall success
        $result.Success = $winrmResult.Success -or $disableWinrmResult.Success -or $gposResult.Success -or $adResult.Success

        Write-SetupLog -Message "Full initialization complete. WinRM: $($winrmResult.Success), DisableWinRM: $($disableWinrmResult.Success), GPOs: $($gposResult.Success), AD: $($adResult.Success)"
    }
    catch {
        $result.Error = "Failed during full initialization: $($_.Exception.Message)"
        Write-SetupLog -Message $result.Error -Level Error
    }

    return $result
}
