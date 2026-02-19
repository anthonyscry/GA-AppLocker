#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for GA-AppLocker.Setup module.

.DESCRIPTION
    Tests orchestration logic for environment initialization, WinRM GPO
    configuration, AppLocker GPO creation, AD structure creation, and
    setup status reporting. All external AD/GPO calls are mocked.

.NOTES
    Stub functions are defined before module import so that Pester can
    mock GroupPolicy and ActiveDirectory cmdlets even when RSAT is not
    installed on the test machine.
#>

BeforeAll {
    # -----------------------------------------------------------------------
    # Step 1: Define the GpoStatus enum stub so Enable/Disable-WinRMGPO can
    # assign enum values without requiring RSAT on the test machine.
    # -----------------------------------------------------------------------
    try {
        Add-Type -TypeDefinition @'
namespace Microsoft.GroupPolicy {
    public enum GpoStatus {
        AllSettingsEnabled       = 0,
        UserSettingsDisabled     = 1,
        ComputerSettingsDisabled = 2,
        AllSettingsDisabled      = 3
    }
}
'@
    }
    catch {
        # Already loaded from RSAT or a prior test run in the same session.
    }

    # -----------------------------------------------------------------------
    # Step 2: Define global stub functions for every RSAT cmdlet the Setup
    # module calls.  Pester's Mock mechanism requires the command to be
    # discoverable; defining stubs here makes them discoverable without RSAT.
    # -----------------------------------------------------------------------
    function global:Get-GPO                  { [CmdletBinding()] param([string]$Name) }
    function global:New-GPO                  { [CmdletBinding()] param([string]$Name, [string]$Comment) }
    function global:Remove-GPO               { [CmdletBinding()] param([string]$Name) }
    function global:Set-GPRegistryValue      { [CmdletBinding()] param([string]$Name, [string]$Key, [string]$ValueName, $Type, $Value) }
    function global:New-GPLink               { [CmdletBinding()] param([string]$Name, [string]$Target) }
    function global:Set-GPLink               { [CmdletBinding()] param([string]$Name, [string]$Target, $Enforced, $LinkEnabled) }
    function global:Get-GPInheritance        { [CmdletBinding()] param([string]$Target) }
    function global:Get-GPOReport            { [CmdletBinding()] param($Guid, $ReportType) }
    function global:Get-ADDomain             { [CmdletBinding()] param() }
    function global:Get-ADOrganizationalUnit { [CmdletBinding()] param($Filter, $SearchBase) }
    function global:New-ADOrganizationalUnit { [CmdletBinding()] param($Name, $Path, $Description) }
    function global:Get-ADGroup              { [CmdletBinding()] param($Filter) }
    function global:New-ADGroup              { [CmdletBinding()] param($Name, $GroupScope, $GroupCategory, $Path, $Description) }
    function global:Get-ADObject             { [CmdletBinding()] param($Identity) }

    # -----------------------------------------------------------------------
    # Step 3: Set the domain environment variable used by Get-DomainDN fallback.
    # -----------------------------------------------------------------------
    $env:USERDNSDOMAIN = 'test.local'

    # -----------------------------------------------------------------------
    # Step 4: Import module under test via root manifest.
    # -----------------------------------------------------------------------
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

# ===========================================================================
# Get-SetupStatus
# ===========================================================================
Describe 'Get-SetupStatus' -Tag @('Unit', 'Setup') {

    Context 'When GroupPolicy module is NOT available' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true even when modules are missing' {
            $result = Get-SetupStatus
            $result.Success | Should -BeTrue
        }

        It 'WinRM.Status is "Module Not Available" when GroupPolicy module missing' {
            $result = Get-SetupStatus
            $result.Data.WinRM.Status | Should -Be 'Module Not Available'
        }

        It 'WinRM.Exists is $false when GroupPolicy module missing' {
            $result = Get-SetupStatus
            $result.Data.WinRM.Exists | Should -BeFalse
        }

        It 'ADStructure.Status is "Module Not Available" when ActiveDirectory module missing' {
            $result = Get-SetupStatus
            $result.Data.ADStructure.Status | Should -Be 'Module Not Available'
        }

        It 'ModulesAvailable.GroupPolicy is $false when module missing' {
            $result = Get-SetupStatus
            $result.Data.ModulesAvailable.GroupPolicy | Should -BeFalse
        }

        It 'ModulesAvailable.ActiveDirectory is $false when module missing' {
            $result = Get-SetupStatus
            $result.Data.ModulesAvailable.ActiveDirectory | Should -BeFalse
        }

        It 'Returns Data object with all required top-level keys' {
            $result = Get-SetupStatus
            $result.Data | Should -Not -BeNullOrEmpty
            $result.Data.PSObject.Properties.Name | Should -Contain 'ModulesAvailable'
            $result.Data.PSObject.Properties.Name | Should -Contain 'WinRM'
            $result.Data.PSObject.Properties.Name | Should -Contain 'DisableWinRM'
            $result.Data.PSObject.Properties.Name | Should -Contain 'AppLockerGPOs'
            $result.Data.PSObject.Properties.Name | Should -Contain 'ADStructure'
        }
    }

    Context 'When GroupPolicy module IS available and WinRM GPO exists' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'

            # WinRM GPO exists
            Mock -CommandName 'Get-GPO' -ParameterFilter { $Name -eq 'AppLocker-EnableWinRM' } -MockWith {
                [PSCustomObject]@{
                    DisplayName = 'AppLocker-EnableWinRM'
                    Id          = 'aaaabbbb-cccc-dddd-eeee-ffffffffffff'
                    GpoStatus   = 'AllSettingsEnabled'
                }
            } -ModuleName 'GA-AppLocker.Setup'

            # Other GPOs do not exist
            Mock -CommandName 'Get-GPO' -ParameterFilter { $Name -ne 'AppLocker-EnableWinRM' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'

            Mock -CommandName 'Get-GPInheritance' -MockWith { [PSCustomObject]@{ GpoLinks = @() } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPOReport' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'WinRM.Exists is $true when WinRM GPO is found' {
            $result = Get-SetupStatus
            $result.Data.WinRM.Exists | Should -BeTrue
        }

        It 'WinRM.GPOName matches the GPO display name' {
            $result = Get-SetupStatus
            $result.Data.WinRM.GPOName | Should -Be 'AppLocker-EnableWinRM'
        }

        It 'WinRM.GPOId matches the GPO Id' {
            $result = Get-SetupStatus
            $result.Data.WinRM.GPOId | Should -Be 'aaaabbbb-cccc-dddd-eeee-ffffffffffff'
        }
    }

    Context 'When GroupPolicy module IS available and WinRM GPO does NOT exist' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPInheritance' -MockWith { [PSCustomObject]@{ GpoLinks = @() } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPOReport' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'WinRM.Exists is $false when GPO not found' {
            $result = Get-SetupStatus
            $result.Data.WinRM.Exists | Should -BeFalse
        }

        It 'WinRM.Status is "Not Created" when GPO not found' {
            $result = Get-SetupStatus
            $result.Data.WinRM.Status | Should -Be 'Not Created'
        }
    }

    Context 'AppLockerGPOs array structure' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPInheritance' -MockWith { [PSCustomObject]@{ GpoLinks = @() } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPOReport' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'AppLockerGPOs array contains exactly 3 entries' {
            $result = Get-SetupStatus
            @($result.Data.AppLockerGPOs).Count | Should -Be 3
        }

        It 'AppLockerGPOs entries have Type, Name, Exists, Status fields' {
            $result = Get-SetupStatus
            $entry = $result.Data.AppLockerGPOs[0]
            $entry.PSObject.Properties.Name | Should -Contain 'Type'
            $entry.PSObject.Properties.Name | Should -Contain 'Name'
            $entry.PSObject.Properties.Name | Should -Contain 'Exists'
            $entry.PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'AppLockerGPOs contains DC, Servers, and Workstations types' {
            $result = Get-SetupStatus
            $types = @($result.Data.AppLockerGPOs | Select-Object -ExpandProperty Type)
            $types | Should -Contain 'DC'
            $types | Should -Contain 'Servers'
            $types | Should -Contain 'Workstations'
        }
    }

    Context 'Partial status-source failures' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'

            Mock -CommandName 'Get-GPO' -MockWith {
                [PSCustomObject]@{
                    DisplayName = $Name
                    Id = [guid]::NewGuid().ToString()
                    GpoStatus = 'AllSettingsEnabled'
                }
            } -ModuleName 'GA-AppLocker.Setup'

            Mock -CommandName 'Get-GPInheritance' -MockWith { throw 'inheritance read failed' } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPOReport' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'reports consistent GPO toggle states when status source partially fails' {
            $status = Get-SetupStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Success | Should -BeTrue
            $status.Data.WinRM | Should -Not -BeNullOrEmpty
            $status.Data.DisableWinRM | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
# Initialize-WinRMGPO
# ===========================================================================
Describe 'Initialize-WinRMGPO' -Tag @('Unit', 'Setup') {

    Context 'When GroupPolicy module is NOT available' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$false when GroupPolicy module missing' {
            $result = Initialize-WinRMGPO
            $result.Success | Should -BeFalse
        }

        It 'Returns an Error message mentioning GroupPolicy when module missing' {
            $result = Initialize-WinRMGPO
            $result.Error | Should -Not -BeNullOrEmpty
            $result.Error | Should -Match 'GroupPolicy'
        }
    }

    Context 'When GPO already exists' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith {
                [PSCustomObject]@{
                    DisplayName = 'AppLocker-EnableWinRM'
                    Id          = 'existing-gpo-id-1234'
                    GpoStatus   = 'AllSettingsEnabled'
                }
            } -ModuleName 'GA-AppLocker.Setup'
            # New-GPO should NOT be called when GPO exists
            Mock -CommandName 'New-GPO' -MockWith { throw 'New-GPO should not be called when GPO exists' } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Set-GPRegistryValue' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Set-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Reuses existing GPO without calling New-GPO' {
            # If New-GPO were called, it would throw — success proves it was not called
            $result = Initialize-WinRMGPO
            $result.Success | Should -BeTrue
        }

        It 'Returns the existing GPOId in Data' {
            $result = Initialize-WinRMGPO
            $result.Data.GPOId | Should -Be 'existing-gpo-id-1234'
        }
    }

    Context 'When GPO does not exist and must be created' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPO' -MockWith {
                [PSCustomObject]@{
                    DisplayName = $Name
                    Id          = 'new-gpo-id-5678'
                    GpoStatus   = 'AllSettingsEnabled'
                }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Set-GPRegistryValue' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Set-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Calls New-GPO to create the GPO' {
            Initialize-WinRMGPO | Out-Null
            Assert-MockCalled -CommandName 'New-GPO' -Times 1 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true after GPO creation' {
            $result = Initialize-WinRMGPO
            $result.Success | Should -BeTrue
        }

        It 'Returns Data with GPOName property matching default name' {
            $result = Initialize-WinRMGPO
            $result.Data.GPOName | Should -Be 'AppLocker-EnableWinRM'
        }

        It 'Sets exactly 6 registry values via Set-GPRegistryValue' {
            # 1: WinRM service auto-start (Start=2, HKLM\SYSTEM)
            # 2: AllowAutoConfig (HKLM\SOFTWARE\Policies\...\WinRM\Service)
            # 3: IPv4Filter
            # 4: IPv6Filter
            # 5: LocalAccountTokenFilterPolicy (UAC remote admin)
            # 6: Firewall rule (WinRM-HTTP-In)
            Initialize-WinRMGPO | Out-Null
            Assert-MockCalled -CommandName 'Set-GPRegistryValue' -Times 6 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'SettingsApplied array has at least 4 entries' {
            # Minimum: WinRM service, AllowAutoConfig group, UAC policy, Firewall
            $result = Initialize-WinRMGPO
            @($result.Data.SettingsApplied).Count | Should -BeGreaterOrEqual 4
        }
    }
}

# ===========================================================================
# Initialize-AppLockerGPOs
# ===========================================================================
Describe 'Initialize-AppLockerGPOs' -Tag @('Unit', 'Setup') {

    Context 'When GroupPolicy module is NOT available' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$false when GroupPolicy module missing' {
            $result = Initialize-AppLockerGPOs
            $result.Success | Should -BeFalse
        }

        It 'Returns an Error message when GroupPolicy module missing' {
            $result = Initialize-AppLockerGPOs
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When all 3 GPOs need to be created' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPO' -MockWith {
                # Return a PSObject whose GpoStatus property can be assigned
                $obj = New-Object PSObject
                $obj | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value $Name
                $obj | Add-Member -MemberType NoteProperty -Name 'Id' -Value ([guid]::NewGuid().ToString())
                $obj | Add-Member -MemberType NoteProperty -Name 'GpoStatus' -Value 'AllSettingsEnabled'
                $obj
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true when all GPOs are created' {
            $result = Initialize-AppLockerGPOs -CreateOnly
            $result.Success | Should -BeTrue
        }

        It 'Creates exactly 3 GPOs via New-GPO' {
            Initialize-AppLockerGPOs -CreateOnly | Out-Null
            Assert-MockCalled -CommandName 'New-GPO' -Times 3 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Data array contains 3 entries' {
            $result = Initialize-AppLockerGPOs -CreateOnly
            @($result.Data).Count | Should -Be 3
        }

        It 'Data array entries include DC, Servers, and Workstations GPO names' {
            $result = Initialize-AppLockerGPOs -CreateOnly
            $names = @($result.Data | Select-Object -ExpandProperty Name)
            $names | Should -Contain 'AppLocker-DC'
            $names | Should -Contain 'AppLocker-Servers'
            $names | Should -Contain 'AppLocker-Workstations'
        }

        It 'Does NOT call New-GPLink when -CreateOnly is specified' {
            Initialize-AppLockerGPOs -CreateOnly | Out-Null
            Assert-MockCalled -CommandName 'New-GPLink' -Times 0 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }
    }

    Context 'When all 3 GPOs already exist' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
            # All GPOs already exist
            Mock -CommandName 'Get-GPO' -MockWith {
                [PSCustomObject]@{
                    DisplayName = $Name
                    Id          = [guid]::NewGuid().ToString()
                    GpoStatus   = 'AllSettingsDisabled'
                }
            } -ModuleName 'GA-AppLocker.Setup'
            # New-GPO should not be called
            Mock -CommandName 'New-GPO' -MockWith { throw 'New-GPO should not be called when GPOs exist' } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Reuses existing GPOs without calling New-GPO' {
            # If New-GPO is called it throws -- success proves it was skipped
            $result = Initialize-AppLockerGPOs -CreateOnly
            $result.Success | Should -BeTrue
        }

        It 'All 3 entries have Status = Existing' {
            $result = Initialize-AppLockerGPOs -CreateOnly
            $statuses = @($result.Data | Select-Object -ExpandProperty Status)
            foreach ($s in $statuses) { $s | Should -Be 'Existing' }
        }
    }
}

# ===========================================================================
# Initialize-ADStructure
# ===========================================================================
Describe 'Initialize-ADStructure' -Tag @('Unit', 'Setup') {

    Context 'When ActiveDirectory module is NOT available' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$false when ActiveDirectory module missing' {
            $result = Initialize-ADStructure
            $result.Success | Should -BeFalse
        }

        It 'Returns an Error message when ActiveDirectory module missing' {
            $result = Initialize-ADStructure
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When OU does not exist and must be created' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { [PSCustomObject]@{ Name = 'ActiveDirectory' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
            # OU does not exist
            Mock -CommandName 'Get-ADOrganizationalUnit' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-ADOrganizationalUnit' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            # No groups exist
            Mock -CommandName 'Get-ADGroup' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-ADGroup' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true after creating OU and groups' {
            $result = Initialize-ADStructure
            $result.Success | Should -BeTrue
        }

        It 'Calls New-ADOrganizationalUnit once for the AppLocker OU' {
            Initialize-ADStructure | Out-Null
            Assert-MockCalled -CommandName 'New-ADOrganizationalUnit' -Times 1 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Creates 6 security groups via New-ADGroup' {
            Initialize-ADStructure | Out-Null
            Assert-MockCalled -CommandName 'New-ADGroup' -Times 6 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Data.TotalGroups is 6' {
            $result = Initialize-ADStructure
            $result.Data.TotalGroups | Should -Be 6
        }

        It 'Data contains OUName and Groups properties' {
            $result = Initialize-ADStructure
            $result.Data.PSObject.Properties.Name | Should -Contain 'OUName'
            $result.Data.PSObject.Properties.Name | Should -Contain 'Groups'
        }

        It 'Data.OUName defaults to "AppLocker"' {
            $result = Initialize-ADStructure
            $result.Data.OUName | Should -Be 'AppLocker'
        }
    }

    Context 'When OU already exists' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -MockWith { [PSCustomObject]@{ Name = 'ActiveDirectory' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
            # OU already exists
            Mock -CommandName 'Get-ADOrganizationalUnit' -MockWith {
                [PSCustomObject]@{ DistinguishedName = 'OU=AppLocker,DC=test,DC=local' }
            } -ModuleName 'GA-AppLocker.Setup'
            # New-ADOrganizationalUnit should NOT be called
            Mock -CommandName 'New-ADOrganizationalUnit' -MockWith { throw 'Should not create OU that exists' } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADGroup' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-ADGroup' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Does NOT call New-ADOrganizationalUnit when OU already exists' {
            # If New-ADOrganizationalUnit is called it throws -- success proves it was skipped
            $result = Initialize-ADStructure
            $result.Success | Should -BeTrue
        }

        It 'Data.OUPath reflects the existing OU distinguished name' {
            $result = Initialize-ADStructure
            $result.Data.OUPath | Should -Be 'OU=AppLocker,DC=test,DC=local'
        }
    }
}

# ===========================================================================
# Initialize-AppLockerEnvironment
# ===========================================================================
Describe 'Initialize-AppLockerEnvironment' -Tag @('Unit', 'Setup') {

    Context 'When all sub-initializers succeed' {
        BeforeEach {
            Mock -CommandName 'Initialize-WinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $true; Data = @{ GPOName = 'AppLocker-EnableWinRM' }; Error = $null }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Initialize-DisableWinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $true; Data = @{}; Error = $null }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Initialize-AppLockerGPOs' -MockWith {
                [PSCustomObject]@{ Success = $true; Data = @(); Error = $null }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Initialize-ADStructure' -MockWith {
                [PSCustomObject]@{ Success = $true; Data = @{}; Error = $null }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Enable-WinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $true; Error = $null }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Disable-WinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $true; Error = $null }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true when all sub-initializers succeed' {
            $result = Initialize-AppLockerEnvironment
            $result.Success | Should -BeTrue
        }

        It 'Calls Initialize-WinRMGPO exactly once' {
            Initialize-AppLockerEnvironment | Out-Null
            Assert-MockCalled -CommandName 'Initialize-WinRMGPO' -Times 1 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Calls Initialize-DisableWinRMGPO exactly once' {
            Initialize-AppLockerEnvironment | Out-Null
            Assert-MockCalled -CommandName 'Initialize-DisableWinRMGPO' -Times 1 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Calls Initialize-AppLockerGPOs exactly once' {
            Initialize-AppLockerEnvironment | Out-Null
            Assert-MockCalled -CommandName 'Initialize-AppLockerGPOs' -Times 1 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Calls Initialize-ADStructure exactly once' {
            Initialize-AppLockerEnvironment | Out-Null
            Assert-MockCalled -CommandName 'Initialize-ADStructure' -Times 1 -Exactly -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Data hashtable has WinRM, DisableWinRM, AppLockerGPOs, and ADStructure keys' {
            $result = Initialize-AppLockerEnvironment
            $result.Data.ContainsKey('WinRM')         | Should -BeTrue
            $result.Data.ContainsKey('DisableWinRM')  | Should -BeTrue
            $result.Data.ContainsKey('AppLockerGPOs') | Should -BeTrue
            $result.Data.ContainsKey('ADStructure')   | Should -BeTrue
        }
    }

    Context 'OR success logic: at least one sub-initializer must succeed' {
        BeforeEach {
            Mock -CommandName 'Initialize-WinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $true; Data = @{}; Error = $null }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Initialize-DisableWinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $false; Data = $null; Error = 'GPO module missing' }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Initialize-AppLockerGPOs' -MockWith {
                [PSCustomObject]@{ Success = $false; Data = @(); Error = 'GPO module missing' }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Initialize-ADStructure' -MockWith {
                [PSCustomObject]@{ Success = $false; Data = $null; Error = 'AD module missing' }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Enable-WinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $false; Error = 'missing' }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Disable-WinRMGPO' -MockWith {
                [PSCustomObject]@{ Success = $false; Error = 'missing' }
            } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true when only WinRM sub-initializer succeeds (OR logic)' {
            $result = Initialize-AppLockerEnvironment
            $result.Success | Should -BeTrue
        }
    }
}

# ===========================================================================
# Enable-WinRMGPO
# ===========================================================================
Describe 'Enable-WinRMGPO' -Tag @('Unit', 'Setup') {

    Context 'When GroupPolicy module is NOT available' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$false when GroupPolicy module missing' {
            $result = Enable-WinRMGPO
            $result.Success | Should -BeFalse
        }

        It 'Returns an Error message when GroupPolicy module missing' {
            $result = Enable-WinRMGPO
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When GPO does not exist' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$false when GPO not found' {
            $result = Enable-WinRMGPO -GPOName 'AppLocker-EnableWinRM'
            $result.Success | Should -BeFalse
        }

        It 'Returns an Error message when GPO not found' {
            $result = Enable-WinRMGPO -GPOName 'AppLocker-EnableWinRM'
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When GPO exists' {
        BeforeEach {
            # Use Add-Member to create a mutable PSObject so GpoStatus assignment works
            $mockGPO = New-Object PSObject
            $mockGPO | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value 'AppLocker-EnableWinRM'
            $mockGPO | Add-Member -MemberType NoteProperty -Name 'Id' -Value 'enable-gpo-test-id'
            $mockGPO | Add-Member -MemberType NoteProperty -Name 'GpoStatus' -Value ([Microsoft.GroupPolicy.GpoStatus]::AllSettingsDisabled)

            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $mockGPO } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Set-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Calls Get-GPO to look up the GPO' {
            Enable-WinRMGPO -GPOName 'AppLocker-EnableWinRM' | Out-Null
            Assert-MockCalled -CommandName 'Get-GPO' -Times 1 -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true when GPO exists and GpoStatus can be set' {
            $result = Enable-WinRMGPO -GPOName 'AppLocker-EnableWinRM'
            $result.Success | Should -BeTrue
        }
    }
}

# ===========================================================================
# Disable-WinRMGPO
# ===========================================================================
Describe 'Disable-WinRMGPO' -Tag @('Unit', 'Setup') {

    Context 'When GroupPolicy module is NOT available' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable } -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$false when GroupPolicy module missing' {
            $result = Disable-WinRMGPO
            $result.Success | Should -BeFalse
        }

        It 'Returns an Error message when GroupPolicy module missing' {
            $result = Disable-WinRMGPO
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When GPO does not exist' {
        BeforeEach {
            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $null } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$false when GPO not found' {
            $result = Disable-WinRMGPO -GPOName 'AppLocker-EnableWinRM'
            $result.Success | Should -BeFalse
        }

        It 'Returns an Error message when GPO not found' {
            $result = Disable-WinRMGPO -GPOName 'AppLocker-EnableWinRM'
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When GPO exists' {
        BeforeEach {
            $mockGPO = New-Object PSObject
            $mockGPO | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value 'AppLocker-EnableWinRM'
            $mockGPO | Add-Member -MemberType NoteProperty -Name 'Id' -Value 'disable-gpo-test-id'
            $mockGPO | Add-Member -MemberType NoteProperty -Name 'GpoStatus' -Value ([Microsoft.GroupPolicy.GpoStatus]::AllSettingsEnabled)

            Mock -CommandName 'Get-Module' -ParameterFilter { $ListAvailable -and $Name -eq 'GroupPolicy' } -MockWith { [PSCustomObject]@{ Name = 'GroupPolicy' } } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Import-Module' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Write-AppLockerLog' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-GPO' -MockWith { $mockGPO } -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'New-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Set-GPLink' -MockWith {} -ModuleName 'GA-AppLocker.Setup'
            Mock -CommandName 'Get-ADDomain' -MockWith { [PSCustomObject]@{ DistinguishedName = 'DC=test,DC=local' } } -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Calls Get-GPO to look up the GPO' {
            Disable-WinRMGPO -GPOName 'AppLocker-EnableWinRM' | Out-Null
            Assert-MockCalled -CommandName 'Get-GPO' -Times 1 -ModuleName 'GA-AppLocker.Setup'
        }

        It 'Returns Success=$true when GPO exists and GpoStatus can be set' {
            $result = Disable-WinRMGPO -GPOName 'AppLocker-EnableWinRM'
            $result.Success | Should -BeTrue
        }
    }
}
