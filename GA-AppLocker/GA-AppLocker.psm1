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
            . $codeBehindPath
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
            Initialize-MainWindow -Window $window
        }

        # Show window
        $window.ShowDialog() | Out-Null

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
Export-ModuleMember -Function @(
    'Start-AppLockerDashboard'
)
#endregion
