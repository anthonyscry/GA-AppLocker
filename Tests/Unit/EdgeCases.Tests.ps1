#Requires -Modules Pester
<#
.SYNOPSIS
    Edge case tests for GA-AppLocker - large datasets, permission errors, timeouts.

.DESCRIPTION
    Tests that verify the application handles edge cases gracefully:
    - Large dataset processing (thousands of artifacts/rules)
    - Permission denied scenarios (access errors)
    - Network timeout handling (connectivity issues)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\EdgeCases.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Remove any cached modules first
    Get-Module 'GA-AppLocker*' | Remove-Module -Force -ErrorAction SilentlyContinue
    
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Large Dataset Handling' -Tag 'Unit', 'EdgeCase', 'Performance' {

    Context 'Test-MachineConnectivity with many machines' {
        BeforeAll {
            # Mock the extracted Test-PingConnectivity function which handles both
            # sequential (<=5) and parallel (>5) paths internally.
            # Returns a hashtable of hostname -> $true (all online).
            Mock Test-PingConnectivity {
                $results = @{}
                foreach ($h in $Hostnames) {
                    $results[$h] = $true
                }
                return $results
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Test-WSMan { [PSCustomObject]@{ ProductVersion = 'OS: 10.0.19041' } } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Handles 100 machines without error' {
            $machines = 1..100 | ForEach-Object {
                [PSCustomObject]@{
                    Hostname = "PC$($_)"
                    IsOnline = $false
                    WinRMStatus = 'Unknown'
                }
            }

            $result = Test-MachineConnectivity -Machines $machines
            $result.Success | Should -BeTrue
            $result.Data.Count | Should -Be 100
            $result.Summary.TotalMachines | Should -Be 100
        }

        It 'Returns correct summary for large batch' {
            $machines = 1..50 | ForEach-Object {
                [PSCustomObject]@{
                    Hostname = "PC$($_)"
                    IsOnline = $false
                    WinRMStatus = 'Unknown'
                }
            }

            $result = Test-MachineConnectivity -Machines $machines
            $result.Summary.OnlineCount | Should -Be 50
            $result.Summary.WinRMAvailable | Should -Be 50
        }
    }

    Context 'Get-ComputersByOU with many OUs' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Handles empty OU list gracefully' {
            $result = Get-ComputersByOU -OUDistinguishedNames @()
            $result.Success | Should -BeTrue
            $result.Data.Count | Should -Be 0
        }

        It 'Handles 20 OUs without hanging' {
            $ous = 1..20 | ForEach-Object { "OU=Dept$($_),DC=test,DC=local" }
            
            # Should return quickly even if LDAP fails
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-ComputersByOU -OUDistinguishedNames $ous
            $stopwatch.Stop()
            
            # Should not take more than 60 seconds (allowing for LDAP retry timeouts)
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 60
        }
    }

    Context 'Rule generation at scale' {
        It 'Creates publisher rule without excessive memory use' {
            # Create multiple rules in a loop
            $rules = @()
            1..50 | ForEach-Object {
                $result = New-PublisherRule `
                    -PublisherName "O=VENDOR$($_) INC." `
                    -ProductName "Product $_" `
                    -Name "Test Rule $_"
                
                if ($result.Success) {
                    $rules += $result.Data
                }
            }

            $rules.Count | Should -Be 50
        }

        It 'Creates path rules for many paths' {
            $rules = @()
            $paths = @(
                '%PROGRAMFILES%\App1\*',
                '%PROGRAMFILES%\App2\*',
                '%PROGRAMFILES(X86)%\App3\*',
                '%LOCALAPPDATA%\App4\*',
                '%SYSTEMROOT%\System32\*'
            )

            foreach ($path in $paths) {
                $result = New-PathRule -Path $path -Name "Path: $path"
                if ($result.Success) {
                    $rules += $result.Data
                }
            }

            $rules.Count | Should -Be 5
        }
    }

    Context 'Template functions with all templates' {
        It 'Loads all 17 templates without error' {
            $result = Get-RuleTemplates
            $result.Success | Should -BeTrue
            $result.Data.Count | Should -BeGreaterOrEqual 15
        }

        It 'Creates rules from largest template' {
            # Windows Default Allow has 5 rules
            $result = New-RulesFromTemplate -TemplateName 'Windows Default Allow'
            $result.Success | Should -BeTrue
            $result.Data.RulesCreated | Should -Be 5
        }
    }
}

Describe 'Permission Denied Scenarios' -Tag 'Unit', 'EdgeCase', 'Security' {

    Context 'Get-LocalArtifacts with inaccessible paths' {
        It 'Handles non-existent path gracefully' {
            $result = Get-LocalArtifacts -Paths @('C:\NonExistent\Path\That\Does\Not\Exist')
            
            # Should not throw, should return success with empty data or warning
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Continues scanning when one path is inaccessible' {
            # Mix of valid and invalid paths
            $paths = @(
                $env:TEMP,  # Should be accessible
                'C:\Windows\CSC',  # Often restricted
                'Z:\NonExistentDrive'  # Does not exist
            )

            $result = Get-LocalArtifacts -Paths $paths
            
            # Should still process accessible paths
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Credential operations with invalid credentials' {
        It 'Returns null data for non-existent credential profile' {
            $result = Get-CredentialProfile -Name 'NonExistentProfile12345'
            
            # API returns Success=true but null data for "not found"
            $result.Success | Should -BeTrue
            $result.Data | Should -BeNullOrEmpty
        }

        It 'Handles removal of non-existent profile' {
            $result = Remove-CredentialProfile -Name 'NonExistentProfile12345'
            
            # Should indicate not found without crashing
            $result.Success | Should -BeFalse
        }
    }

    Context 'Policy operations with missing data' {
        It 'Handles non-existent policy gracefully' {
            $result = Get-Policy -PolicyId 'non-existent-policy-id-12345'
            
            # API may return Success=true with null data, or Success=false
            # Either way it should not throw
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Handles rule addition to non-existent policy' {
            $result = Add-RuleToPolicy -PolicyId 'fake-policy' -RuleId 'fake-rule'
            
            $result.Success | Should -BeFalse
        }
    }

    Context 'Session state with corrupted data' {
        It 'Handles corrupted session JSON gracefully' {
            $dataPath = Get-AppLockerDataPath
            $sessionFile = Join-Path $dataPath 'session.json'
            
            # Backup existing if present
            $backup = $null
            if (Test-Path $sessionFile) {
                $backup = Get-Content $sessionFile -Raw
            }

            try {
                # Write corrupted JSON
                '{ invalid json not valid }' | Set-Content $sessionFile -Force

                $result = Restore-SessionState
                
                # Should fail gracefully, not crash
                $result.Success | Should -BeFalse
            }
            finally {
                # Restore backup or remove test file
                if ($backup) {
                    $backup | Set-Content $sessionFile -Force
                }
                elseif (Test-Path $sessionFile) {
                    Remove-Item $sessionFile -Force
                }
            }
        }
    }
}

Describe 'Network Timeout Handling' -Tag 'Unit', 'EdgeCase', 'Network' {

    Context 'Test-MachineConnectivity timeout behavior' {
        BeforeAll {
            # Mock Get-WmiObject Win32_PingStatus (sequential path, <=5 machines)
            # Simulate: TIMEOUT hosts return non-zero StatusCode, others succeed
            Mock Get-WmiObject {
                param($Class, $Filter)
                if ($Filter -match "Address='([^']+)'") {
                    $hostname = $Matches[1]
                    if ($hostname -match 'TIMEOUT') {
                        Start-Sleep -Milliseconds 100  # Small delay to simulate slow response
                        return [PSCustomObject]@{ StatusCode = 11010 }
                    }
                    return [PSCustomObject]@{ StatusCode = 0 }
                }
                return [PSCustomObject]@{ StatusCode = 11010 }
            } -ModuleName 'GA-AppLocker.Discovery'
            
            Mock Test-WSMan { [PSCustomObject]@{ ProductVersion = 'OS: 10.0.19041' } } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Marks timeout hosts as offline' {
            $machines = @(
                [PSCustomObject]@{ Hostname = 'TIMEOUT-PC1'; IsOnline = $false; WinRMStatus = 'Unknown' }
                [PSCustomObject]@{ Hostname = 'ONLINE-PC1'; IsOnline = $false; WinRMStatus = 'Unknown' }
            )

            $result = Test-MachineConnectivity -Machines $machines
            
            $result.Success | Should -BeTrue
            ($result.Data | Where-Object { $_.Hostname -eq 'TIMEOUT-PC1' }).IsOnline | Should -BeFalse
            ($result.Data | Where-Object { $_.Hostname -eq 'ONLINE-PC1' }).IsOnline | Should -BeTrue
        }

        It 'Completes batch even with timeouts' {
            $machines = @(
                [PSCustomObject]@{ Hostname = 'TIMEOUT-PC1'; IsOnline = $false; WinRMStatus = 'Unknown' }
                [PSCustomObject]@{ Hostname = 'TIMEOUT-PC2'; IsOnline = $false; WinRMStatus = 'Unknown' }
                [PSCustomObject]@{ Hostname = 'ONLINE-PC1'; IsOnline = $false; WinRMStatus = 'Unknown' }
            )

            $result = Test-MachineConnectivity -Machines $machines
            
            $result.Data.Count | Should -Be 3
            $result.Summary.TotalMachines | Should -Be 3
        }
    }

    Context 'WinRM connection failures' {
        BeforeAll {
            # All machines ping successfully (StatusCode = 0)
            Mock Get-WmiObject {
                [PSCustomObject]@{ StatusCode = 0 }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Test-WSMan {
                param($ComputerName)
                if ($ComputerName -match 'WINRM-FAIL') {
                    throw 'The WinRM client cannot process the request because the server name cannot be resolved.'
                }
                return [PSCustomObject]@{ ProductVersion = 'OS: 10.0.19041' }
            } -ModuleName 'GA-AppLocker.Discovery'
            Mock Write-AppLockerLog { } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Handles WinRM resolution failures' {
            $machines = @(
                [PSCustomObject]@{ Hostname = 'WINRM-FAIL-PC'; IsOnline = $false; WinRMStatus = 'Unknown' }
            )

            $result = Test-MachineConnectivity -Machines $machines
            
            $result.Success | Should -BeTrue
            $result.Data[0].IsOnline | Should -BeTrue  # Ping worked
            $result.Data[0].WinRMStatus | Should -Be 'Unavailable'  # But WinRM failed
        }

        It 'Counts WinRM failures correctly in summary' {
            $machines = @(
                [PSCustomObject]@{ Hostname = 'WINRM-FAIL-PC1'; IsOnline = $false; WinRMStatus = 'Unknown' }
                [PSCustomObject]@{ Hostname = 'WINRM-FAIL-PC2'; IsOnline = $false; WinRMStatus = 'Unknown' }
                [PSCustomObject]@{ Hostname = 'GOOD-PC'; IsOnline = $false; WinRMStatus = 'Unknown' }
            )

            $result = Test-MachineConnectivity -Machines $machines
            
            $result.Summary.WinRMAvailable | Should -Be 1
            $result.Summary.WinRMUnavailable | Should -Be 2
        }
    }

    Context 'LDAP connection timeouts' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' } -ModuleName 'GA-AppLocker.Discovery'
        }

        It 'Returns error when LDAP is unavailable' {
            $result = Get-DomainInfo
            
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'LDAP|unavailable|connect'
        }

        It 'Get-OUTree fails gracefully without AD/LDAP' {
            $result = Get-OUTree
            
            $result.Success | Should -BeFalse
        }
    }
}

Describe 'Input Validation Edge Cases' -Tag 'Unit', 'EdgeCase', 'Validation' {

    Context 'Rule creation with special characters' {
        It 'Handles publisher name with quotes' {
            $result = New-PublisherRule `
                -PublisherName 'O="COMPANY WITH QUOTES" INC.' `
                -ProductName 'Test Product'
            
            $result.Success | Should -BeTrue
        }

        It 'Handles path with unicode characters' {
            $result = New-PathRule -Path '%PROGRAMFILES%\Tëst Äpp\*'
            
            $result.Success | Should -BeTrue
        }

        It 'Handles very long path' {
            $longPath = '%PROGRAMFILES%\' + ('A' * 200) + '\*'
            $result = New-PathRule -Path $longPath
            
            $result.Success | Should -BeTrue
        }
    }

    Context 'Template operations with edge inputs' {
        It 'Returns error for non-existent template' {
            $result = Get-RuleTemplates -TemplateName 'NonExistentTemplate12345'
            
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'not found'
        }

        It 'New-RulesFromTemplate fails gracefully for invalid template' {
            $result = New-RulesFromTemplate -TemplateName 'FakeTemplate'
            
            $result.Success | Should -BeFalse
        }
    }

    Context 'Empty and null inputs' {
        It 'Get-AllRules returns empty when no rules exist' {
            # This should not throw even with empty storage
            { Get-AllRules } | Should -Not -Throw
        }

        It 'Get-AllPolicies returns empty when no policies exist' {
            { Get-AllPolicies } | Should -Not -Throw
        }

        It 'Get-SuggestedGroup fails with no input' {
            $result = Get-SuggestedGroup
            
            $result.Success | Should -BeFalse
        }
    }
}

Describe 'Module Loading - No Duplicate Nested Module Loading (v1.2.14)' -Tag 'Unit', 'EdgeCase', 'ModuleLoading' {

    Context 'Module loads nested modules exactly once' {
        It 'Should not have manual Import-Module calls in GA-AppLocker.psm1' {
            $psm1Path = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psm1'
            $content = Get-Content $psm1Path -Raw

            # There should be NO Import-Module calls for nested sub-modules
            # NestedModules in .psd1 handles all loading
            $content | Should -Not -Match 'Import-Module.*GA-AppLocker\.(Core|Storage|Discovery|Credentials|Scanning|Rules|Policy|Deployment|Validation|Setup)'
        }

        It 'Should declare all 10 sub-modules in .psd1 NestedModules' {
            $psd1Path = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
            $manifest = Import-PowerShellDataFile -Path $psd1Path

            $manifest.NestedModules.Count | Should -Be 10

            # Verify all expected modules are listed
            $moduleNames = $manifest.NestedModules | ForEach-Object { ($_ -split '\\')[-1] -replace '\.(psd1|psm1)$', '' }
            $moduleNames | Should -Contain 'GA-AppLocker.Core'
            $moduleNames | Should -Contain 'GA-AppLocker.Storage'
            $moduleNames | Should -Contain 'GA-AppLocker.Discovery'
            $moduleNames | Should -Contain 'GA-AppLocker.Credentials'
            $moduleNames | Should -Contain 'GA-AppLocker.Scanning'
            $moduleNames | Should -Contain 'GA-AppLocker.Rules'
            $moduleNames | Should -Contain 'GA-AppLocker.Policy'
            $moduleNames | Should -Contain 'GA-AppLocker.Deployment'
            $moduleNames | Should -Contain 'GA-AppLocker.Validation'
            $moduleNames | Should -Contain 'GA-AppLocker.Setup'
        }
    }
}

Describe 'Concurrent Operations Safety' -Tag 'Unit', 'EdgeCase', 'Concurrency' {

    Context 'Multiple rule creations' {
        It 'Creates rules with unique IDs' {
            $rules = @()
            1..10 | ForEach-Object {
                $result = New-PublisherRule `
                    -PublisherName 'O=TEST CORP' `
                    -ProductName "Product $_"
                
                if ($result.Success) {
                    $rules += $result.Data
                }
            }

            # All IDs should be unique
            $uniqueIds = $rules.Id | Select-Object -Unique
            $uniqueIds.Count | Should -Be 10
        }
    }
}
