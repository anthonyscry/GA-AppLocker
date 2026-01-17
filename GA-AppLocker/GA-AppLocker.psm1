#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker

.DESCRIPTION
    GA-AppLocker Dashboard - Enterprise AppLocker Policy Management
    for air-gapped classified computing environments.

    This is the main module that loads all sub-modules and provides
    the GUI entry point.

.DEPENDENCIES
    - GA-AppLocker.Core (logging, config, utilities)
    - PresentationFramework (WPF)
    - PresentationCore (WPF)
    - WindowsBase (WPF)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release - Phase 1 Foundation

.NOTES
    Target Environment:
    - Windows Server 2019+ / Windows 10+
    - Domain-joined machines only
    - Air-gapped network (no internet)
    - PowerShell 5.1+
    - .NET Framework 4.7.2+
#>
#endregion

#region ===== MODULE CONFIGURATION =====
$script:APP_NAME = 'GA-AppLocker'
$script:APP_VERSION = '1.0.0'
$script:APP_TITLE = 'GA-AppLocker Dashboard'
#endregion

#region ===== WPF ASSEMBLIES =====
# Load WPF assemblies for GUI
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
#endregion

#region ===== GUI ENTRY POINT =====
<#
.SYNOPSIS
    Launches the GA-AppLocker Dashboard WPF application.

.DESCRIPTION
    Main entry point for the GA-AppLocker GUI. Validates prerequisites,
    loads the main window, and starts the WPF application loop.

.PARAMETER SkipPrerequisites
    Skip prerequisite validation at startup (for development/testing).

.EXAMPLE
    Start-AppLockerDashboard

    Launches the dashboard with full prerequisite validation.

.EXAMPLE
    Start-AppLockerDashboard -SkipPrerequisites

    Launches the dashboard without checking prerequisites.

.OUTPUTS
    None. Launches WPF window.
#>
function Start-AppLockerDashboard {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$SkipPrerequisites
    )

    Write-AppLockerLog -Message "Starting $script:APP_TITLE v$script:APP_VERSION"

    #region --- Prerequisites Check ---
    if (-not $SkipPrerequisites) {
        Write-AppLockerLog -Message 'Validating prerequisites...'
        $prereqs = Test-Prerequisites

        if (-not $prereqs.AllPassed) {
            $failures = $prereqs.Checks | Where-Object { -not $_.Passed }
            Write-AppLockerLog -Level Warning -Message "Prerequisites check failed:"

            foreach ($failure in $failures) {
                Write-AppLockerLog -Level Warning -Message "  - $($failure.Name): $($failure.Message)"
            }

            # Show message box with failures
            $failureText = ($failures | ForEach-Object { "- $($_.Name): $($_.Message)" }) -join "`n"
            [System.Windows.MessageBox]::Show(
                "The following prerequisites are not met:`n`n$failureText`n`nSome features may not work correctly.",
                'Prerequisites Warning',
                'OK',
                'Warning'
            )
        }
        else {
            Write-AppLockerLog -Message 'All prerequisites passed'
        }
    }
    #endregion

    #region --- Load Main Window ---
    try {
        $xamlPath = Join-Path $PSScriptRoot 'GUI\MainWindow.xaml'
        $codeBehindPath = Join-Path $PSScriptRoot 'GUI\MainWindow.xaml.ps1'

        if (-not (Test-Path $xamlPath)) {
            Write-AppLockerLog -Level Error -Message "MainWindow.xaml not found at: $xamlPath"
            throw "GUI files not found. Please ensure GA-AppLocker is properly installed."
        }

        # Load code-behind (contains navigation helpers)
        if (Test-Path $codeBehindPath) {
            try {
                . $codeBehindPath
                Write-AppLockerLog -Message 'Code-behind loaded successfully'
            }
            catch {
                Write-AppLockerLog -Level Error -Message "Code-behind load failed: $($_.Exception.Message)"
                throw
            }
        }

        # Load XAML
        $xamlContent = Get-Content -Path $xamlPath -Raw
        $xaml = [xml]$xamlContent

        # Remove x:Class attribute if present (not needed for PowerShell)
        $xaml.Window.RemoveAttribute('x:Class') 2>$null

        # Create WPF reader
        $reader = [System.Xml.XmlNodeReader]::new($xaml)
        $window = [System.Windows.Markup.XamlReader]::Load($reader)

        Write-AppLockerLog -Message 'Main window loaded successfully'

        # Initialize window (wire up navigation, etc.)
        if (Get-Command -Name 'Initialize-MainWindow' -ErrorAction SilentlyContinue) {
            try {
                Initialize-MainWindow -Window $window
                Write-AppLockerLog -Message 'Window initialization completed'
            }
            catch {
                Write-AppLockerLog -Level Error -Message "Window initialization failed: $($_.Exception.Message)"
                Write-AppLockerLog -Level Error -Message "Stack trace: $($_.ScriptStackTrace)"
            }
        }

        # Show window
        Write-AppLockerLog -Message 'Showing dialog...'

        # Add handler for unhandled dispatcher exceptions
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
            param($sender, $e)
            Write-AppLockerLog -Level Error -Message "WPF Dispatcher exception: $($e.Exception.Message)"
            $e.Handled = $true
        })

        # Add loaded event to verify window renders
        $window.add_Loaded({
            Write-AppLockerLog -Message 'Window Loaded event fired'
        })

        # Ensure window is activated and visible
        $window.Activate() | Out-Null
        $window.Focus() | Out-Null

        $result = $window.ShowDialog()
        Write-AppLockerLog -Message "ShowDialog returned: $result"

        Write-AppLockerLog -Message 'Application closed'
    }
    catch {
        Write-AppLockerLog -Level Error -Message "Failed to start GUI: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Failed to start GA-AppLocker Dashboard:`n`n$($_.Exception.Message)",
            'Startup Error',
            'OK',
            'Error'
        )
    }
    #endregion
}
#endregion

#region ===== EXPORTS =====
# Export all functions from this module and nested modules
# The FunctionsToExport in .psd1 filters what's actually visible
Export-ModuleMember -Function @(
    # Main module
    'Start-AppLockerDashboard',
    # Core module
    'Write-AppLockerLog',
    'Get-AppLockerConfig',
    'Set-AppLockerConfig',
    'Test-Prerequisites',
    'Get-AppLockerDataPath',
    # Discovery module
    'Get-DomainInfo',
    'Get-OUTree',
    'Get-ComputersByOU',
    'Test-MachineConnectivity',
    # Credentials module
    'New-CredentialProfile',
    'Get-CredentialProfile',
    'Get-AllCredentialProfiles',
    'Remove-CredentialProfile',
    'Test-CredentialProfile',
    'Get-CredentialForTier',
    'Get-CredentialStoragePath',
    # Scanning module
    'Get-LocalArtifacts',
    'Get-RemoteArtifacts',
    'Get-AppLockerEventLogs',
    'Start-ArtifactScan',
    'Get-ScanResults',
    'Export-ScanResults',
    # Rules module
    'New-PublisherRule',
    'New-HashRule',
    'New-PathRule',
    'ConvertFrom-Artifact',
    'Get-Rule',
    'Get-AllRules',
    'Remove-Rule',
    'Export-RulesToXml',
    'Set-RuleStatus'
)
#endregion
