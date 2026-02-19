#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    try {
        Add-Type -TypeDefinition @'
namespace System.Windows.Media {
    public class BrushConverter {
        public object ConvertFromString(string value) { return new object(); }
    }
    public class Color {
        public static Color FromRgb(byte r, byte g, byte b) { return new Color(); }
    }
    public class SolidColorBrush {
        public SolidColorBrush(Color color) { }
    }
    public static class Brushes {
        public static readonly object Transparent = new object();
        public static readonly object White = new object();
    }
}
namespace System.Windows.Controls {
    public class ComboBoxItem {
        public object Content { get; set; }
        public object Tag { get; set; }
    }
}
'@ -ErrorAction Stop
    }
    catch {
        # Types may already exist.
    }

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Deploy.ps1')

    function global:Write-Log {
        param([string]$Message, [string]$Level = 'Info')
    }

    function global:Show-Toast {
        param([string]$Message, [string]$Type = 'Info')
    }

    function global:Show-AppLockerMessageBox {
        param($Message, $Title, $Button, $Icon)
        return 'Yes'
    }

    function global:New-DeploymentJob {
        @{ Success = $true; Data = [PSCustomObject]@{ JobId = 'stub-job' }; Error = $null }
    }

    function global:Get-AllDeploymentJobs {
        @{ Success = $true; Data = @(); Error = $null }
    }

    function global:Remove-DeploymentJob {
        param([string]$Status)
        @{ Success = $true; Data = 0; Error = $null }
    }

    function global:Write-AppLockerLog {
        param([string]$Message, [string]$Level = 'Info')
    }
}

Describe 'Deploy panel workflow matrix' -Tag @('Behavioral', 'GUI', 'Deploy') {
    BeforeEach {
        $script:CurrentDeploymentFilter = 'All'
        $script:SelectedDeploymentJobId = $null
        $script:DeploymentInProgress = $false
        $script:DeploymentCancelled = $false
        $script:DeployPrevFilter = $null
    }

    It 'loads baseline UI state and toggles deploy or stop controls during long operations' {
        $win = New-MockWpfWindow -Elements @{
            BtnDeployJob = New-MockButton -Name 'BtnDeployJob'
            BtnStopDeployment = New-MockButton -Name 'BtnStopDeployment' -IsEnabled $false
        }

        Update-DeploymentUIState -Window $win -Deploying $true
        $win.FindName('BtnDeployJob').IsEnabled | Should -BeFalse
        $win.FindName('BtnStopDeployment').IsEnabled | Should -BeTrue

        Update-DeploymentUIState -Window $win -Deploying $false
        $win.FindName('BtnDeployJob').IsEnabled | Should -BeTrue
        $win.FindName('BtnStopDeployment').IsEnabled | Should -BeFalse
    }

    It 'creates deployment jobs only when a policy and target gpo exist' {
        $policyCombo = New-MockComboBox -Items @() -SelectedIndex -1
        $win = New-MockWpfWindow -Elements @{ CboDeployPolicy = $policyCombo }

        Mock Show-AppLockerMessageBox { 'OK' }
        Invoke-CreateDeploymentJob -Window $win
        Assert-MockCalled Show-AppLockerMessageBox -Times 1 -Exactly -ParameterFilter { $Message -like '*select a policy*' }

        $policyCombo.Items.Clear()
        [void]$policyCombo.Items.Add([PSCustomObject]@{ Tag = [PSCustomObject]@{ PolicyId = 'p1'; Name = 'Policy 1'; TargetGPO = '' } })
        $policyCombo.SelectedIndex = 0
        $policyCombo.SelectedItem = $policyCombo.Items[0]

        Invoke-CreateDeploymentJob -Window $win
        Assert-MockCalled Show-AppLockerMessageBox -Times 1 -Exactly -ParameterFilter { $Message -like '*no Target GPO*' }

        $policyCombo.Items.Clear()
        [void]$policyCombo.Items.Add([PSCustomObject]@{ Tag = [PSCustomObject]@{ PolicyId = 'p2'; Name = 'Policy 2'; TargetGPO = 'AppLocker-Servers' } })
        $policyCombo.SelectedItem = $policyCombo.Items[0]

        Mock New-DeploymentJob { @{ Success = $true; Data = [PSCustomObject]@{ JobId = 'job-1' }; Error = $null } }
        Mock Update-DeploymentJobsDataGrid { }

        { Invoke-CreateDeploymentJob -Window $win } | Should -Not -Throw
    }

    It 'applies filter transitions and supports empty-state deployment list rendering' {
        $win = New-MockWpfWindow -Elements @{
            BtnFilterAllJobs = New-MockButton
            BtnFilterPendingJobs = New-MockButton
            BtnFilterRunningJobs = New-MockButton
            BtnFilterCompletedJobs = New-MockButton
            BtnFilterFailedJobs = New-MockButton
            DeploymentJobsDataGrid = New-MockDataGrid
        }

        Mock Get-AllDeploymentJobs { @{ Success = $true; Data = @(); Error = $null } }

        Update-DeploymentFilter -Window $win -Filter 'Running'
        $script:CurrentDeploymentFilter | Should -Be 'Running'
        $win.FindName('DeploymentJobsDataGrid').ItemsSource | Should -BeNullOrEmpty
    }

    It 'blocks start deployment when no job is selected and supports cancel path' {
        $win = New-MockWpfWindow
        Mock Show-Toast { }
        Mock Update-SelectedJobInfo { $script:SelectedDeploymentJobId = $null }

        Invoke-DeploySelectedJob -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter { $Type -eq 'Warning' -and $Message -like '*select a deployment job*' }

        $script:DeploymentInProgress = $true
        Invoke-StopDeployment -Window $win
        $script:DeploymentCancelled | Should -BeTrue
    }

    It 'handles clear completed jobs with zero and non-zero removals' {
        $win = New-MockWpfWindow

        Mock Remove-DeploymentJob { @{ Success = $true; Data = 0; Error = $null } }
        Mock Update-DeploymentJobsDataGrid { }
        Mock Show-Toast { }

        Invoke-ClearCompletedJobs -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter { $Type -eq 'Info' -and $Message -like '*No completed*' }

        Mock Remove-DeploymentJob {
            param($Status)
            if ($Status -eq 'Completed') { return @{ Success = $true; Data = 2; Error = $null } }
            if ($Status -eq 'Failed') { return @{ Success = $true; Data = 1; Error = $null } }
            @{ Success = $true; Data = 0; Error = $null }
        }

        Invoke-ClearCompletedJobs -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter { $Type -eq 'Success' -and $Message -like '*3 job(s) cleared*' }
    }

    It 'surfaces create-job exceptions as operator-facing errors' {
        $policyCombo = New-MockComboBox -Items @([PSCustomObject]@{ Tag = [PSCustomObject]@{ PolicyId = 'p3'; Name = 'Policy 3'; TargetGPO = 'AppLocker-DC' } }) -SelectedIndex 0
        $win = New-MockWpfWindow -Elements @{ CboDeployPolicy = $policyCombo }

        Mock New-DeploymentJob { throw 'disk failure' }
        Mock Show-Toast { }
        Mock Show-AppLockerMessageBox { 'OK' }

        Invoke-CreateDeploymentJob -Window $win

        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'Error' -and $Message -like '*creation failed*'
        }
    }
}
