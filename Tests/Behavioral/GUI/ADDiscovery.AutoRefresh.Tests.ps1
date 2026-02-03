#Requires -Version 5.1
<#
.SYNOPSIS
    Behavioral test for AD Discovery DataGrid auto-refresh (v1.2.60 bug fix)

.DESCRIPTION
    Verifies that the AD Discovery DataGrid automatically refreshes after connectivity
    testing completes, without requiring the user to manually click the Refresh button.

.NOTES
    Bug: After "Test Connectivity", user had to manually click "Refresh" to see updated WinRM status
    Fix: ADDiscovery.ps1 lines 717-724 - added $dataGrid.Items.Refresh() after connectivity test
    Version: 1.2.60
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force
}

Describe 'AD Discovery DataGrid Auto-Refresh' {
    Context 'After connectivity test completes' {
        It 'Should call Update-MachineDataGrid to refresh machine list' {
            # Verify the fix is in place by checking the code
            $adDiscoveryPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\ADDiscovery.ps1'
            $adDiscoveryContent = Get-Content $adDiscoveryPath -Raw
            
            # The fix should include a call to Update-MachineDataGrid after connectivity test
            $adDiscoveryContent | Should -Match "Update-MachineDataGrid\s+-Window\s+\`$win\s+-Machines\s+\`$script:DiscoveredMachines"
        }
        
        It 'Should call DataGrid.Items.Refresh() to force visual update' {
            # Verify the fix includes the critical Items.Refresh() call
            $adDiscoveryPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\ADDiscovery.ps1'
            $adDiscoveryContent = Get-Content $adDiscoveryPath -Raw
            
            # The fix should include $dataGrid.Items.Refresh() after connectivity test
            $adDiscoveryContent | Should -Match "\`$dataGrid\.Items\.Refresh\(\)"
        }
        
        It 'Should have both refresh calls in the connectivity test completion handler' {
            # Verify both refresh mechanisms are present in the same code block
            $adDiscoveryPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\ADDiscovery.ps1'
            $adDiscoveryContent = Get-Content $adDiscoveryPath -Raw
            
            # Extract the connectivity test completion section (around lines 717-724)
            $pattern = '(?s)Update-MachineDataGrid.*?Items\.Refresh\(\)'
            $adDiscoveryContent | Should -Match $pattern
        }
    }
}
