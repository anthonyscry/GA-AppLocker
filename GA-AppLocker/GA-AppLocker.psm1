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
$script:APP_TITLE = 'GA-AppLocker Dashboard'
#endregion

#region ===== WPF ASSEMBLIES =====
# Load WPF assemblies for GUI
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
#endregion

#region ===== NESTED MODULES =====
# Nested modules are loaded automatically by NestedModules in the .psd1 manifest.
# They are imported in dependency order BEFORE this .psm1 runs, so all functions
# (Write-AppLockerLog, Get-AppLockerDataPath, etc.) are already available here.
# DO NOT manually Import-Module them -- that caused double-loading and WPF deadlocks.
try {
    Write-AppLockerLog -Message 'All nested modules loaded successfully' -NoConsole
}
catch {
    # Core module not loaded -- something is very wrong
    throw "GA-AppLocker.Core nested module failed to load. Ensure NestedModules in .psd1 is correct."
}
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

    $modVer = (Get-Module GA-AppLocker).Version
    Write-AppLockerLog -Message "Starting $script:APP_TITLE v$modVer"

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
                
                # Load toast/loading helpers
                $toastHelpersPath = Join-Path $PSScriptRoot 'GUI\ToastHelpers.ps1'
                if (Test-Path $toastHelpersPath) {
                    . $toastHelpersPath
                    Write-AppLockerLog -Message 'Toast helpers loaded successfully'
                }
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

        # Initialize window (wire up navigation, panels, etc.)
        # Initialize-MainWindow is defined in MainWindow.xaml.ps1, dot-sourced above.
        try {
            Initialize-MainWindow -Window $window
            Write-AppLockerLog -Message 'Window initialization completed'
        }
        catch {
            Write-AppLockerLog -Level Error -Message "Window initialization failed: $($_.Exception.Message)"
            Write-AppLockerLog -Level Error -Message "Stack trace: $($_.ScriptStackTrace)"
        }

        # Show window
        Write-AppLockerLog -Message 'Showing dialog...'

        # Debug: Track why window closes (pure .NET -- cmdlets may be unavailable)
        $window.add_Closing({
            param($s, $e)
            try {
                $ts = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
                $logDir = [System.IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'GA-AppLocker', 'Logs')
                if ([System.IO.Directory]::Exists($logDir)) {
                    $logFile = [System.IO.Path]::Combine($logDir, "GA-AppLocker_$([DateTime]::Now.ToString('yyyy-MM-dd')).log")
                    [System.IO.File]::AppendAllText($logFile, "[$ts] [WARNING] MainWindow Closing. DialogResult=$($s.DialogResult)`r`n")
                }
            } catch { }
        })

        $window.add_Closed({
            param($s, $e)
            try {
                $ts = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
                $logDir = [System.IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'GA-AppLocker', 'Logs')
                if ([System.IO.Directory]::Exists($logDir)) {
                    $logFile = [System.IO.Path]::Combine($logDir, "GA-AppLocker_$([DateTime]::Now.ToString('yyyy-MM-dd')).log")
                    [System.IO.File]::AppendAllText($logFile, "[$ts] [WARNING] MainWindow Closed.`r`n")
                }
            } catch { }
        })

        # Add handler for unhandled dispatcher exceptions
        # MUST use pure .NET -- cmdlets (Write-Warning, Get-Command) are NOT available
        # in WPF timer/closure scopes due to cmdlet resolution loss
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
            param($sender, $e)
            try {
                $ts = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
                $logDir = [System.IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'GA-AppLocker', 'Logs')
                if ([System.IO.Directory]::Exists($logDir)) {
                    $logFile = [System.IO.Path]::Combine($logDir, "GA-AppLocker_$([DateTime]::Now.ToString('yyyy-MM-dd')).log")
                    [System.IO.File]::AppendAllText($logFile, "[$ts] [ERROR] WPF Dispatcher exception: $($e.Exception.Message)`r`n")
                }
            } catch { }
            # Swallow non-fatal dispatcher exceptions (timer scope cmdlet loss)
            # so they don't kill the entire window
            $e.Handled = $true
        })

        # Add loaded event to verify window renders
        $window.add_Loaded({
            try {
                Write-AppLockerLog -Message 'Window Loaded event fired'
            } catch {
                Write-Host '[Info] Window Loaded event fired' -ForegroundColor White
            }
        })

        # Ensure window is activated and visible
        $window.Activate() | Out-Null
        $window.Focus() | Out-Null

        $result = $window.ShowDialog()
        try { Write-AppLockerLog -Message "ShowDialog returned: $result" } catch { }
        try { Write-AppLockerLog -Message 'Application closed' } catch { }
    }
    catch {
        # Use .NET file logging -- cmdlets may not be available after WPF session
        try {
            $ts = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
            $logDir = [System.IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'GA-AppLocker', 'Logs')
            if ([System.IO.Directory]::Exists($logDir)) {
                $logFile = [System.IO.Path]::Combine($logDir, "GA-AppLocker_$([DateTime]::Now.ToString('yyyy-MM-dd')).log")
                [System.IO.File]::AppendAllText($logFile, "[$ts] [ERROR] Failed to start GUI: $($_.Exception.Message)`r`n")
            }
        } catch { }
        # Only show error dialog for real startup failures, not WPF timer scope losses
        $errMsg = $_.Exception.Message
        if ($errMsg -notmatch 'Write-AppLockerLog|Write-Warning|Get-Command') {
            [System.Windows.MessageBox]::Show(
                "Failed to start GA-AppLocker Dashboard:`n`n$errMsg",
                'Startup Error',
                'OK',
                'Error'
            )
        }
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
    'Save-SessionState',
    'Restore-SessionState',
    'Clear-SessionState',
    # Discovery module
    'Get-DomainInfo',
    'Get-OUTree',
    'Get-ComputersByOU',
    'Test-MachineConnectivity',
    'Test-PingConnectivity',
    # LDAP fallback functions
    'Resolve-LdapServer',
    'Get-LdapConnection',
    'Get-LdapSearchResult',
    'Get-DomainInfoViaLdap',
    'Get-OUTreeViaLdap',
    'Get-ComputersByOUViaLdap',
    'Set-LdapConfiguration',
    'Test-LdapConnection',
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
    'Get-AppxArtifacts',
    'Get-AppLockerEventLogs',
    'Start-ArtifactScan',
    'Get-ScanResults',
    'Export-ScanResults',
    # Scanning - Scheduled
    'New-ScheduledScan',
    'Get-ScheduledScans',
    'Remove-ScheduledScan',
    'Set-ScheduledScanEnabled',
    'Invoke-ScheduledScan',
    # Rules module
    'New-PublisherRule',
    'New-HashRule',
    'New-PathRule',
    'ConvertFrom-Artifact',
    'Get-Rule',
    'Get-AllRules',
    'Remove-Rule',
    'Export-RulesToXml',
    'Set-RuleStatus',
    'Get-SuggestedGroup',
    'Get-KnownVendors',
    'Get-RuleTemplates',
    'New-RulesFromTemplate',
    'Get-RuleTemplateCategories',
    # Rules - Bulk Operations
    'Set-BulkRuleStatus',
    'Approve-TrustedVendorRules',
    # Rules - Deduplication
    'Remove-DuplicateRules',
    'Find-DuplicateRules',
    'Find-ExistingHashRule',
    'Find-ExistingPublisherRule',
    # NOTE: Get-ExistingRuleIndex is exported from Storage module
    # Rules - Import
    'Import-RulesFromXml',
    # Rules - History/Versioning
    'Get-RuleHistory',
    'Save-RuleVersion',
    'Restore-RuleVersion',
    'Compare-RuleVersions',
    'Get-RuleVersionContent',
    'Remove-RuleHistory',
    'Invoke-RuleHistoryCleanup',
    # Rules - Batch Generation
    'Invoke-BatchRuleGeneration',
    # Storage module (JSON-based)
    'Get-RuleStoragePath',
    'Get-RuleById',
    'Get-AllRules',
    'Add-Rule',
    'Update-Rule',
    'Get-RuleCounts',
    'Find-RuleByHash',
    'Find-RuleByPublisher',
    'Rebuild-RulesIndex',
    'Reset-RulesIndexCache',
    # Storage - Bulk Operations
    'Save-RulesBulk',
    'Add-RulesToIndex',
    'Get-ExistingRuleIndex',
    'Remove-RulesBulk',
    'Remove-RulesFromIndex',
    'Get-BatchPreview',
    'Update-RuleStatusInIndex',
    # Storage - Index Watcher
    'Start-RuleIndexWatcher',
    'Stop-RuleIndexWatcher',
    'Get-RuleIndexWatcherStatus',
    'Set-RuleIndexWatcherDebounce',
    'Invoke-RuleIndexRebuild',
    # Storage - Maintenance
    'Remove-OrphanedRuleFiles',
    # Storage - Backwards Compatibility Aliases
    'Get-RulesFromDatabase',
    'Get-RuleFromDatabase',
    'Add-RuleToDatabase',
    'Update-RuleInDatabase',
    'Remove-RuleFromDatabase',
    'Initialize-RuleDatabase',
    'Get-RuleDatabasePath',
    'Test-RuleDatabaseExists',
    # Storage - Repository Pattern
    'Get-RuleFromRepository',
    'Save-RuleToRepository',
    'Remove-RuleFromRepository',
    'Find-RulesInRepository',
    'Get-RuleCountsFromRepository',
    'Invoke-RuleBatchOperation',
    'Test-RuleExistsInRepository',
    # Policy module
    'New-Policy',
    'Get-Policy',
    'Get-AllPolicies',
    'Update-Policy',
    'Remove-Policy',
    'Set-PolicyStatus',
    'Add-RuleToPolicy',
    'Remove-RuleFromPolicy',
    'Set-PolicyTarget',
    'Export-PolicyToXml',
    'Test-PolicyCompliance',
    # Policy - Comparison & Snapshots
    'Compare-Policies',
    'Compare-RuleProperties',
    'Get-PolicyDiffReport',
    'New-PolicySnapshot',
    'Get-PolicySnapshots',
    'Get-PolicySnapshot',
    'Restore-PolicySnapshot',
    'Remove-PolicySnapshot',
    'Invoke-PolicySnapshotCleanup',
    # Deployment module
    'New-DeploymentJob',
    'Get-DeploymentJob',
    'Get-AllDeploymentJobs',
    'Start-Deployment',
    'Stop-Deployment',
    'Get-DeploymentStatus',
    'Test-GPOExists',
    'New-AppLockerGPO',
    'Import-PolicyToGPO',
    'Get-DeploymentHistory',
    # Audit Trail
    'Write-AuditLog',
    'Get-AuditLog',
    'Export-AuditLog',
    'Clear-AuditLog',
    'Get-AuditLogPath',
    'Get-AuditLogSummary',
    # Backup & Restore
    'Backup-AppLockerData',
    'Restore-AppLockerData',
    'Get-BackupHistory',
    # Group SID Resolution
    'Resolve-GroupSid',
    # Validation module
    'Test-AppLockerXmlSchema',
    'Test-AppLockerRuleGuids',
    'Test-AppLockerRuleSids',
    'Test-AppLockerRuleConditions',
    'Test-AppLockerPolicyImport',
    'Invoke-AppLockerPolicyValidation',
    # Setup module
    'Initialize-WinRMGPO',
    'Initialize-AppLockerGPOs',
    'Initialize-ADStructure',
    'Initialize-AppLockerEnvironment',
    'Get-SetupStatus',
    'Enable-WinRMGPO',
    'Disable-WinRMGPO',
    'Remove-WinRMGPO',
    'Initialize-DisableWinRMGPO',
    'Remove-DisableWinRMGPO',
    # Cache Management
    'Get-CachedValue',
    'Set-CachedValue',
    'Clear-AppLockerCache',
    'Get-CacheStatistics',
    'Test-CacheKey',
    'Invoke-CacheCleanup',
    # Event System
    'Register-AppLockerEvent',
    'Publish-AppLockerEvent',
    'Unregister-AppLockerEvent',
    'Get-AppLockerEventHandlers',
    'Get-AppLockerEventHistory',
    'Clear-AppLockerEventHistory',
    'Get-AppLockerStandardEvents',
    # Validation Helpers
    'Test-ValidHash',
    'Test-ValidSid',
    'Test-ValidGuid',
    'Test-ValidPath',
    'Test-ValidDistinguishedName',
    'Test-ValidHostname',
    'Test-ValidCollectionType',
    'Test-ValidRuleAction',
    'Test-ValidRuleStatus',
    'Test-ValidPolicyStatus',
    'Test-ValidEnforcementMode',
    'Test-ValidTier',
    'Assert-NotNullOrEmpty',
    'Assert-InRange',
    'Assert-MatchesPattern',
    'Assert-InSet',
    'ConvertTo-SafeFileName',
    'ConvertTo-SafeXmlString',
    'Get-ValidValues'
)
#endregion
