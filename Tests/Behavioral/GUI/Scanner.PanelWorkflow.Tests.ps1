#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    try {
        Add-Type -TypeDefinition @'
namespace System.Windows.Input {
    public static class Cursors {
        public static readonly string Wait = "Wait";
        public static readonly string Arrow = "Arrow";
    }
}
namespace System.Windows.Media {
    public class Color {
        public static Color FromRgb(byte r, byte g, byte b) { return new Color(); }
    }
    public class SolidColorBrush {
        public SolidColorBrush(Color color) { }
    }
    public class BrushConverter {
        public object ConvertFromString(string value) { return new object(); }
    }
    public static class Brushes {
        public static readonly object Transparent = new object();
        public static readonly object White = new object();
        public static readonly object Gold = new object();
        public static readonly object Orange = new object();
        public static readonly object OrangeRed = new object();
        public static readonly object LightGreen = new object();
        public static readonly object LightBlue = new object();
    }
}
'@ -ErrorAction Stop
    }
    catch {
        # Types already available in environments with PresentationFramework.
    }

    if (-not ('System.Windows.Input.Cursors' -as [type])) {
        Add-Type -TypeDefinition @'
namespace System.Windows.Input {
    public static class Cursors {
        public static readonly string Wait = "Wait";
        public static readonly string Arrow = "Arrow";
    }
}
'@
    }

    if (-not ('System.Windows.Media.BrushConverter' -as [type])) {
        Add-Type -TypeDefinition @'
namespace System.Windows.Media {
    public class BrushConverter {
        public object ConvertFromString(string value) { return new object(); }
    }
}
'@
    }

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    Import-Module (Join-Path $PSScriptRoot '..\MockData\New-MockTestData.psm1') -Force
    . (Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Scanner.ps1')

    function global:Write-Log {
        param([string]$Message, [string]$Level = 'Info')
    }

    function global:Show-Toast {
        param([string]$Message, [string]$Type = 'Info')
    }

    function global:Show-LoadingOverlay {
        param([string]$Message, [string]$SubMessage)
    }

    function global:Hide-LoadingOverlay {
    }

    function global:Request-UiRender {
        param($Window)
    }

    function global:Get-ScanResults {
        @{ Success = $true; Data = @(); Error = $null }
    }
}

Describe 'Scanner panel workflow matrix' -Tag @('Behavioral', 'GUI', 'Scanner') {
    BeforeEach {
        $script:CurrentArtifactFilter = 'All'
        $script:CurrentScanArtifacts = @()
        $script:CurrentScanEventLogs = @()
        $script:CurrentEventMetricsFilter = $null
        $script:ScanInProgress = $false
        $script:ScanCancelled = $false
        $script:SelectedScanMachines = @()
    }

    It 'loads baseline control state and toggles busy or idle buttons' {
        $win = New-MockWpfWindow -Elements @{
            BtnStartScan = New-MockButton -Name 'BtnStartScan'
            BtnStopScan = New-MockButton -Name 'BtnStopScan' -IsEnabled $false
        }
        $win | Add-Member -MemberType NoteProperty -Name Cursor -Value $null -Force

        Update-ScanUIState -Window $win -Scanning $true
        $win.FindName('BtnStartScan').IsEnabled | Should -BeFalse
        $win.FindName('BtnStopScan').IsEnabled | Should -BeTrue

        Update-ScanUIState -Window $win -Scanning $false
        $win.FindName('BtnStartScan').IsEnabled | Should -BeTrue
        $win.FindName('BtnStopScan').IsEnabled | Should -BeFalse
    }

    It 'applies type and text filtering and resets back to all artifacts' {
        $fixtures = New-MockScannerRuleWorkflowFixtures -ComputerCount 2 -ArtifactsPerComputer 8

        $artifactGrid = New-MockDataGrid
        $artifactSearch = New-MockTextBox -Text ''
        $win = New-MockWpfWindow -Elements @{
            ArtifactDataGrid = $artifactGrid
            ArtifactFilterBox = $artifactSearch
            BtnFilterAllArtifacts = New-MockButton -Name 'BtnFilterAllArtifacts'
            BtnFilterExe = New-MockButton -Name 'BtnFilterExe'
            BtnFilterDll = New-MockButton -Name 'BtnFilterDll'
            BtnFilterMsi = New-MockButton -Name 'BtnFilterMsi'
            BtnFilterScript = New-MockButton -Name 'BtnFilterScript'
            BtnFilterAppx = New-MockButton -Name 'BtnFilterAppx'
            BtnFilterSigned = New-MockButton -Name 'BtnFilterSigned'
            BtnFilterUnsigned = New-MockButton -Name 'BtnFilterUnsigned'
            TxtArtifactTotalCount = New-MockTextBlock
            TxtArtifactFilteredCount = New-MockTextBlock
            TxtSelectedArtifactCount = New-MockTextBlock
        }

        $script:CurrentScanArtifacts = @($fixtures.Artifacts)

        Update-ArtifactFilter -Window $win -Filter 'EXE'
        @($artifactGrid.ItemsSource).Count | Should -BeGreaterThan 0
        (@($artifactGrid.ItemsSource | Where-Object { $_.ArtifactType -ne 'EXE' }).Count) | Should -Be 0

        $artifactSearch.Text = 'artifact-'
        Update-ArtifactDataGrid -Window $win
        @($artifactGrid.ItemsSource).Count | Should -BeGreaterThan 0

        Update-ArtifactFilter -Window $win -Filter 'All'
        @($artifactGrid.ItemsSource).Count | Should -Be $fixtures.Artifacts.Count
    }

    It 'blocks start action when neither local nor remote scan is selected' {
        $win = New-MockWpfWindow -Elements @{
            ChkScanLocal = New-MockCheckBox -IsChecked $false
            ChkScanRemote = New-MockCheckBox -IsChecked $false
            TxtScanName = New-MockTextBox -Text 'NoTypes'
            TxtScanPaths = New-MockTextBox -Text 'C:\Windows\System32'
        }

        Mock Show-Toast { }

        Invoke-StartArtifactScan -Window $win

        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'Warning' -and $Message -like '*select at least one scan type*'
        }
    }

    It 'blocks remote scan with no machine selection and supports cancel signal' {
        $win = New-MockWpfWindow -Elements @{
            ChkScanLocal = New-MockCheckBox -IsChecked $false
            ChkScanRemote = New-MockCheckBox -IsChecked $true
            TxtScanName = New-MockTextBox -Text 'RemoteOnly'
            TxtScanPaths = New-MockTextBox -Text 'C:\Windows\System32'
        }

        Mock Show-Toast { }

        Invoke-StartArtifactScan -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'Warning' -and $Message -like '*no machines*'
        }

        Invoke-StopArtifactScan -Window $win
        $script:ScanCancelled | Should -BeTrue
    }

    It 'shows empty event metrics state and recovers on retry after data is restored' {
        $eventGrid = New-MockDataGrid
        $emptyLabel = New-MockTextBlock -Visibility 'Collapsed'
        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
            TxtEventMetricsEmpty = $emptyLabel
            TxtEventTotalCount = New-MockTextBlock
            TxtEventBlockedCount = New-MockTextBlock
            TxtEventAuditCount = New-MockTextBlock
            CboEventMode = New-MockComboBox -Items @('All', 'Blocked', 'Audit', 'Allowed') -SelectedIndex 0
            CboEventMachine = New-MockComboBox -Items @('All') -SelectedIndex 0
            ArtifactFilterBox = New-MockTextBox -Text ''
            EventArtifactFilterBox = New-MockTextBox -Text ''
        }

        Set-EventMetricsFilterDefaults -Window $win
        $emptyLabel.Visibility | Should -Be 'Visible'
        $eventGrid.ItemsSource | Should -BeNullOrEmpty

        $script:CurrentScanEventLogs = @($fixtures = (New-MockWorkflowStageFixtures -Scenario HappyPath).Scan.Events)
        Initialize-ScanEventMetricsState -Window $win
        Update-EventMetricsUI -Window $win

        @($eventGrid.ItemsSource).Count | Should -BeGreaterThan 0
    }

    It 'surfaces backend list load failures and succeeds on retry' {
        $savedScansList = New-MockListBox
        $win = New-MockWpfWindow -Elements @{ SavedScansList = $savedScansList }

        Mock Get-ScanResults {
            @{ Success = $false; Data = $null; Error = 'store unavailable' }
        }

        Update-SavedScansList -Window $win
        $savedScansList.ItemsSource | Should -BeNullOrEmpty

        Mock Get-ScanResults {
            @{ Success = $true; Data = @([PSCustomObject]@{ ScanId = 'scan-1'; ScanName = 'Recovered' }); Error = $null }
        }

        Update-SavedScansList -Window $win
        @($savedScansList.ItemsSource).Count | Should -Be 1
    }
}
