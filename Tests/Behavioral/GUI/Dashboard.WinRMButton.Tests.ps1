#Requires -Version 5.1
<#
.SYNOPSIS
    Behavioral test for Dashboard WinRM button label consistency (v1.2.60 bug fix)

.DESCRIPTION
    Verifies that the WinRM toggle button label stays constant as "Enable WinRM"
    regardless of the toggle state (checked/unchecked). This prevents the confusing
    UX where the label changed to "Disable WinRM" when the GPO was enabled.

.NOTES
    Bug: WinRM button label changed from "Enable WinRM" to "Disable WinRM" when toggled
    Fix: Dashboard.ps1 line 103 - label now stays constant
    Version: 1.2.60
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force
}

Describe 'Dashboard WinRM Button Label Consistency' {
    Context 'When GPO status changes' {
        It 'Button label should always be "Enable WinRM" regardless of toggle state' {
            # This is a behavioral test - we verify the fix is in place
            # by checking that the Dashboard.ps1 code no longer changes the label
            
            $dashboardPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Dashboard.ps1'
            $dashboardContent = Get-Content $dashboardPath -Raw
            
            # Verify the fix: label should NOT be set conditionally based on $isEnabled
            # The old buggy code was: $toggleEnableLabel.Text = if ($isEnabled) { 'Disable WinRM' } else { 'Enable WinRM' }
            # The fixed code is: $toggleEnableLabel.Text = 'Enable WinRM'
            
            $dashboardContent | Should -Not -Match "toggleEnableLabel\.Text\s*=\s*if\s*\(\s*\`$isEnabled\s*\)"
            $dashboardContent | Should -Match "toggleEnableLabel\.Text\s*=\s*'Enable WinRM'"
        }
        
        It 'Toggle state (IsChecked) should reflect GPO status, not label' {
            # The toggle's IsChecked property should change based on GPO status
            # but the label should stay constant
            
            $dashboardPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Dashboard.ps1'
            $dashboardContent = Get-Content $dashboardPath -Raw
            
            # Verify IsChecked is set based on $isEnabled
            $dashboardContent | Should -Match "toggleEnable\.IsChecked\s*=\s*\`$isEnabled"
        }
    }
}
