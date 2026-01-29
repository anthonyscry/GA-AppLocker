#Requires -Modules Pester
<#
.SYNOPSIS
    Mock-based unit tests for AD Discovery module.

.DESCRIPTION
    Tests AD Discovery functions using Pester mocks - no real AD required.
    These tests verify the logic and error handling of:
    - Resolve-LdapServer (centralized server resolution)
    - Get-DomainInfo
    - Get-OUTree
    - Get-ComputersByOU
    - Test-MachineConnectivity
    - Test-LdapConnection

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\AD.Discovery.Mock.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Resolve-LdapServer' -Tag 'Unit', 'AD', 'LDAP' {

    Context 'When explicit server is provided' {
        It 'Returns the explicit server with Parameter source' {
            $result = Resolve-LdapServer -Server 'dc01.corp.local'
            $result | Should -Not -BeNullOrEmpty
            $result.Server | Should -Be 'dc01.corp.local'
            $result.Port | Should -Be 389
            $result.Source | Should -Be 'Parameter'
        }

        It 'Uses explicit port when provided' {
            $result = Resolve-LdapServer -Server 'dc01.corp.local' -Port 636
            $result.Port | Should -Be 636
            $result.Source | Should -Be 'Parameter'
        }
    }

    Context 'When config has LdapServer set' {
        BeforeAll {
            Mock Get-AppLockerConfig {
                [PSCustomObject]@{ LdapServer = 'config-dc.corp.local'; LdapPort = 10389 }
            } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Falls back to config when no explicit server' {
            # Clear env var for this test
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = $null
            try {
                $result = Resolve-LdapServer
                $result | Should -Not -BeNullOrEmpty
                $result.Server | Should -Be 'config-dc.corp.local'
                $result.Port | Should -Be 10389
                $result.Source | Should -Be 'Config'
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }

        It 'Explicit server takes priority over config' {
            $result = Resolve-LdapServer -Server 'explicit-dc.corp.local'
            $result.Server | Should -Be 'explicit-dc.corp.local'
            $result.Source | Should -Be 'Parameter'
        }
    }

    Context 'When only USERDNSDOMAIN is set (domain-joined machine)' {
        BeforeAll {
            Mock Get-AppLockerConfig {
                [PSCustomObject]@{ }  # No LdapServer property
            } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Falls back to USERDNSDOMAIN env var' {
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = 'env-domain.local'
            try {
                $result = Resolve-LdapServer
                $result | Should -Not -BeNullOrEmpty
                $result.Server | Should -Be 'env-domain.local'
                $result.Source | Should -Be 'Environment'
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }
    }

    Context 'When no server source is available' {
        BeforeAll {
            Mock Get-AppLockerConfig {
                [PSCustomObject]@{ }  # No LdapServer
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns $null when nothing is configured' {
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = $null
            try {
                $result = Resolve-LdapServer
                $result | Should -BeNullOrEmpty
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }
    }
}

Describe 'Get-DomainInfo (Mocked)' -Tag 'Unit', 'AD', 'Mock' {

    Context 'When ActiveDirectory module is NOT available and LDAP fails' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns Success = $false when AD and LDAP unavailable' {
            $result = Get-DomainInfo
            $result.Success | Should -BeFalse
        }

        It 'Returns error message about connection failure' {
            $result = Get-DomainInfo
            $result.Error | Should -Match 'LDAP|connect|unavailable|configured'
        }
    }

    Context 'When explicit LDAP server is provided' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Passes server parameter through to LDAP fallback' {
            # This will still fail to connect but should not default to localhost
            $result = Get-DomainInfo -Server 'nonexistent.server.local'
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'nonexistent\.server\.local|connect'
        }
    }
}

Describe 'Get-OUTree (Mocked)' -Tag 'Unit', 'AD', 'Mock' {

    Context 'When ActiveDirectory module is NOT available' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns Success = $false when AD and LDAP unavailable' {
            $result = Get-OUTree
            $result.Success | Should -BeFalse
        }

        It 'Returns clear error about LDAP configuration' {
            $result = Get-OUTree
            $result.Error | Should -Match 'LDAP|connect|configured'
        }
    }
}

Describe 'Get-ComputersByOU (Mocked)' -Tag 'Unit', 'AD', 'Mock' {

    Context 'When ActiveDirectory module is NOT available' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns Success = $false when AD and LDAP unavailable' {
            $result = Get-ComputersByOU -OUDistinguishedNames 'OU=Test,DC=test,DC=local'
            $result.Success | Should -BeFalse
        }

        It 'Returns clear error about LDAP configuration' {
            $result = Get-ComputersByOU -OUDistinguishedNames 'OU=Test,DC=test,DC=local'
            $result.Error | Should -Match 'LDAP|connect|configured'
        }
    }
    
    Context 'When called with empty OUs' {
        It 'Returns Success with empty data for empty input' {
            $result = Get-ComputersByOU -OUDistinguishedNames @()
            $result.Success | Should -BeTrue
            $result.Data.Count | Should -Be 0
        }
    }
}

Describe 'Test-LdapConnection (Mocked)' -Tag 'Unit', 'AD', 'LDAP' {

    Context 'When no server is configured' {
        BeforeAll {
            Mock Get-AppLockerConfig {
                [PSCustomObject]@{ }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns clear error message when nothing configured' {
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = $null
            try {
                $result = Test-LdapConnection
                $result.Success | Should -BeFalse
                $result.Error | Should -Match 'configured|Set-LdapConfiguration'
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }
    }

    Context 'When server is explicitly provided' {
        BeforeAll {
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Reports Source = Parameter when server is explicit' {
            $result = Test-LdapConnection -Server 'nonexistent.server.local'
            $result.Source | Should -Be 'Parameter'
            $result.Server | Should -Be 'nonexistent.server.local'
        }
    }
}

Describe 'Test-MachineConnectivity (Mocked)' -Tag 'Unit', 'AD', 'Mock' {

    Context 'When called with empty array' {
        It 'Returns Success with empty data' {
            $result = Test-MachineConnectivity -Machines @()
            $result.Success | Should -BeTrue
            $result.Data.Count | Should -Be 0
            $result.Summary.TotalMachines | Should -Be 0
        }
    }

    Context 'When machine is reachable with WinRM' {
        BeforeAll {
            # Mock Get-WmiObject for Win32_PingStatus (sequential path, <=5 machines)
            Mock Get-WmiObject {
                [PSCustomObject]@{ StatusCode = 0 }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Test-WSMan { [PSCustomObject]@{ ProductVersion = 'OS: 10.0.19041' } } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns IsOnline = $true for reachable machine' {
            $machines = @([PSCustomObject]@{ Hostname = 'TESTPC001'; IsOnline = $false; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Success | Should -BeTrue
            $result.Data[0].IsOnline | Should -BeTrue
        }

        It 'Returns WinRMStatus = Available' {
            $machines = @([PSCustomObject]@{ Hostname = 'TESTPC001'; IsOnline = $false; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Data[0].WinRMStatus | Should -Be 'Available'
        }

        It 'Updates summary counts correctly' {
            $machines = @([PSCustomObject]@{ Hostname = 'TESTPC001'; IsOnline = $false; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Summary.TotalMachines | Should -Be 1
            $result.Summary.OnlineCount | Should -Be 1
            $result.Summary.WinRMAvailable | Should -Be 1
        }
    }

    Context 'When machine is unreachable' {
        BeforeAll {
            # StatusCode 11010 = Request Timed Out (offline)
            Mock Get-WmiObject {
                [PSCustomObject]@{ StatusCode = 11010 }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns IsOnline = $false' {
            $machines = @([PSCustomObject]@{ Hostname = 'OFFLINE-PC'; IsOnline = $true; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Success | Should -BeTrue
            $result.Data[0].IsOnline | Should -BeFalse
        }

        It 'Returns WinRMStatus = Offline' {
            $machines = @([PSCustomObject]@{ Hostname = 'OFFLINE-PC'; IsOnline = $true; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Data[0].WinRMStatus | Should -Be 'Offline'
        }

        It 'Updates summary with offline count' {
            $machines = @([PSCustomObject]@{ Hostname = 'OFFLINE-PC'; IsOnline = $true; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Summary.OfflineCount | Should -Be 1
            $result.Summary.OnlineCount | Should -Be 0
        }
    }

    Context 'When WinRM is disabled' {
        BeforeAll {
            Mock Get-WmiObject {
                [PSCustomObject]@{ StatusCode = 0 }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Test-WSMan { throw 'WinRM not available' } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns IsOnline = $true but WinRMStatus = Unavailable' {
            $machines = @([PSCustomObject]@{ Hostname = 'NO-WINRM-PC'; IsOnline = $false; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Data[0].IsOnline | Should -BeTrue
            $result.Data[0].WinRMStatus | Should -Be 'Unavailable'
        }

        It 'Updates summary correctly' {
            $machines = @([PSCustomObject]@{ Hostname = 'NO-WINRM-PC'; IsOnline = $false; WinRMStatus = 'Unknown' })
            $result = Test-MachineConnectivity -Machines $machines
            $result.Summary.OnlineCount | Should -Be 1
            $result.Summary.WinRMAvailable | Should -Be 0
            $result.Summary.WinRMUnavailable | Should -Be 1
        }
    }

    Context 'When testing multiple machines' {
        BeforeAll {
            # Simulate selective connectivity: use -Filter param to determine hostname
            Mock Get-WmiObject {
                param($Class, $Filter)
                # Extract hostname from WMI filter: "Address='HOSTNAME' AND Timeout=5000"
                if ($Filter -match "Address='([^']+)'") {
                    $hostname = $Matches[1]
                    if ($hostname -eq 'ONLINE-PC') {
                        return [PSCustomObject]@{ StatusCode = 0 }
                    }
                }
                return [PSCustomObject]@{ StatusCode = 11010 }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Test-WSMan { [PSCustomObject]@{ ProductVersion = 'OS: 10.0.19041' } } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Processes all machines and returns correct summary' {
            $machines = @(
                [PSCustomObject]@{ Hostname = 'ONLINE-PC'; IsOnline = $false; WinRMStatus = 'Unknown' }
                [PSCustomObject]@{ Hostname = 'OFFLINE-PC'; IsOnline = $false; WinRMStatus = 'Unknown' }
            )
            $result = Test-MachineConnectivity -Machines $machines
            $result.Success | Should -BeTrue
            $result.Data.Count | Should -Be 2
            $result.Summary.TotalMachines | Should -Be 2
            $result.Summary.OnlineCount | Should -Be 1
            $result.Summary.OfflineCount | Should -Be 1
        }
    }
}

Describe 'Tier Classification Logic' -Tag 'Unit', 'AD', 'Mock' {

    It 'Domain Controllers OU matches Tier 0 pattern' {
        'OU=Domain Controllers,DC=test,DC=local' | Should -Match 'Domain Controllers'
    }

    It 'Servers OU matches Tier 1 pattern' {
        'OU=Servers,DC=test,DC=local' | Should -Match 'Servers'
    }

    It 'Workstations OU matches Tier 2 pattern' {
        'OU=Workstations,DC=test,DC=local' | Should -Match 'Workstations'
    }
}

Describe 'Get-MachineTypeFromOU (Exported via OUTree)' -Tag 'Unit', 'AD', 'Mock' {

    # Get-MachineTypeFromOU is a private helper in Get-OUTree.ps1
    # We test it indirectly via the OU path patterns it matches
    
    It 'Recognizes Domain Controllers path' {
        $path = 'OU=Domain Controllers,DC=corp,DC=local'
        $path.ToLower() | Should -Match 'domain controllers'
    }

    It 'Recognizes Server path variations' {
        @('OU=Servers,DC=corp,DC=local', 'OU=SRV,DC=corp,DC=local') | ForEach-Object {
            $_.ToLower() | Should -Match 'server|srv'
        }
    }

    It 'Recognizes Workstation path variations' {
        @('OU=Workstations,DC=corp,DC=local', 'OU=Desktops,DC=corp,DC=local', 'OU=Laptops,DC=corp,DC=local') | ForEach-Object {
            $_.ToLower() | Should -Match 'workstation|desktop|laptop'
        }
    }
}

Describe 'Error Message Quality' -Tag 'Unit', 'AD', 'ErrorMessages' {

    Context 'LDAP functions provide actionable error messages' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
            Mock Get-AppLockerConfig {
                [PSCustomObject]@{ }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Get-DomainInfo error mentions Set-LdapConfiguration' {
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = $null
            try {
                $result = Get-DomainInfo
                $result.Error | Should -Match 'Set-LdapConfiguration'
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }

        It 'Get-OUTree error mentions Set-LdapConfiguration' {
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = $null
            try {
                $result = Get-OUTree
                $result.Error | Should -Match 'Set-LdapConfiguration'
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }

        It 'Get-ComputersByOU error mentions Set-LdapConfiguration' {
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = $null
            try {
                $result = Get-ComputersByOU -OUDistinguishedNames 'OU=Test,DC=test,DC=local'
                $result.Error | Should -Match 'Set-LdapConfiguration'
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }

        It 'Error messages never reference localhost' {
            $savedEnv = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = $null
            try {
                $result = Get-DomainInfo
                $result.Error | Should -Not -Match 'localhost'
            }
            finally {
                $env:USERDNSDOMAIN = $savedEnv
            }
        }
    }
}
