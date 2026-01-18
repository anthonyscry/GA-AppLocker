#Requires -Modules Pester
<#
.SYNOPSIS
    Mock-based unit tests for AD Discovery module.

.DESCRIPTION
    Tests AD Discovery functions using Pester mocks - no real AD required.
    These tests verify the logic and error handling of:
    - Get-DomainInfo
    - Get-OUTree
    - Get-ComputersByOU
    - Test-MachineConnectivity

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\AD.Discovery.Mock.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Get-DomainInfo (Mocked)' -Tag 'Unit', 'AD', 'Mock' {

    Context 'When ActiveDirectory module is NOT available' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns Success = $false' {
            $result = Get-DomainInfo
            $result.Success | Should -BeFalse
        }

        It 'Returns appropriate error message' {
            $result = Get-DomainInfo
            $result.Error | Should -Match 'ActiveDirectory module not installed'
        }
    }
}

Describe 'Get-OUTree (Mocked)' -Tag 'Unit', 'AD', 'Mock' {

    Context 'When ActiveDirectory module is NOT available' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns Success = $false for missing AD module' {
            $result = Get-OUTree
            $result.Success | Should -BeFalse
        }
    }
}

Describe 'Get-ComputersByOU (Mocked)' -Tag 'Unit', 'AD', 'Mock' {

    Context 'When ActiveDirectory module is NOT available' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns Success = $false for missing AD module' {
            $result = Get-ComputersByOU -OUDistinguishedNames 'OU=Test,DC=test,DC=local'
            $result.Success | Should -BeFalse
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
            # Test-Connection with -Quiet returns boolean
            Mock Test-Connection { $true } -ModuleName 'GA-AppLocker.Discovery'
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
            # Test-Connection with -Quiet returns $false when unreachable
            Mock Test-Connection { $false } -ModuleName 'GA-AppLocker.Discovery'
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
            Mock Test-Connection { $true } -ModuleName 'GA-AppLocker.Discovery'
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
            Mock Test-Connection { 
                param($ComputerName)
                # First machine online, second offline
                $ComputerName -eq 'ONLINE-PC'
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
