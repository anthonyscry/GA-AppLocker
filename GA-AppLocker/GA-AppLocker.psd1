#
# Module manifest for module 'GA-AppLocker'
# GA-AppLocker Dashboard - Enterprise AppLocker Policy Management
# Generated: 2026-01-17
#

@{
    # Script module file associated with this manifest
    RootModule = 'GA-AppLocker.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # ID used to uniquely identify this module
    GUID = 'f1e2d3c4-b5a6-7890-1234-567890abcdef'

    # Author of this module
    Author = 'GA-AppLocker Team'

    # Company or vendor of this module
    CompanyName = 'GA-AppLocker'

    # Copyright statement for this module
    Copyright = '(c) 2026 GA-AppLocker Team. All rights reserved.'

    # Description of the functionality provided by this module
    Description = @'
GA-AppLocker Dashboard - Enterprise AppLocker Policy Management for Air-Gapped Environments

Features:
- Scan Active Directory for hosts by OU
- Collect AppLocker artifacts via WinRM with tiered credential support
- Auto-generate rules using best practices (Publisher > Hash > Path)
- Create and merge policies by machine type (Workstation/Server/DC)
- Deploy to GPOs with phase-based enforcement (Audit -> Enforce)
- WPF GUI with code-behind pattern and central button dispatcher
'@

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion = '4.0'

    # Minimum version of Microsoft .NET Framework required by this module
    DotNetFrameworkVersion = '4.7.2'

    # Nested modules to load
    NestedModules = @(
        'Modules\GA-AppLocker.Core\GA-AppLocker.Core.psd1',
        'Modules\GA-AppLocker.Storage\GA-AppLocker.Storage.psd1',
        'Modules\GA-AppLocker.Discovery\GA-AppLocker.Discovery.psd1',
        'Modules\GA-AppLocker.Credentials\GA-AppLocker.Credentials.psd1',
        'Modules\GA-AppLocker.Scanning\GA-AppLocker.Scanning.psd1',
        'Modules\GA-AppLocker.Rules\GA-AppLocker.Rules.psd1',
        'Modules\GA-AppLocker.Policy\GA-AppLocker.Policy.psd1',
        'Modules\GA-AppLocker.Deployment\GA-AppLocker.Deployment.psd1',
        'Modules\GA-AppLocker.Setup\GA-AppLocker.Setup.psm1'
    )

    # Functions to export from this module (re-export from nested modules + GUI)
    FunctionsToExport = @(
        # Core module
        'Write-AppLockerLog',
        'Get-AppLockerConfig',
        'Set-AppLockerConfig',
        'Test-Prerequisites',
        'Get-AppLockerDataPath',
        'Invoke-WithRetry',
        'Save-SessionState',
        'Restore-SessionState',
        'Clear-SessionState',
        # Discovery module
        'Get-DomainInfo',
        'Get-OUTree',
        'Get-ComputersByOU',
        'Test-MachineConnectivity',
        # LDAP fallback functions
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
        # Rules - Batch Generation (10x faster)
        'Invoke-BatchRuleGeneration',
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
        # Storage module (JSON-based)
        'Get-RuleStoragePath',
        'Get-RuleById',
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
        # Storage - Index Maintenance
        'Reset-RulesIndexCache',
        'Rebuild-RulesIndex',
        'Remove-OrphanedRuleFiles',
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
        'Get-PolicyDiffReport',
        'New-PolicySnapshot',
        'Get-PolicySnapshots',
        'Restore-PolicySnapshot',
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
        # Setup module
        'Initialize-WinRMGPO',
        'Initialize-AppLockerGPOs',
        'Initialize-ADStructure',
        'Initialize-AppLockerEnvironment',
        'Get-SetupStatus',
        'Enable-WinRMGPO',
        'Disable-WinRMGPO',
        # Audit Trail
        'Write-AuditLog',
        'Get-AuditLog',
        'Export-AuditLog',
        'Clear-AuditLog',
        'Get-AuditLogPath',
        'Get-AuditLogSummary',
        # Email Notifications
        'Get-EmailSettings',
        'Set-EmailSettings',
        'Set-EmailNotifyOn',
        'Send-AppLockerNotification',
        'Test-EmailSettings',
        # Reporting Export
        'Export-AppLockerReport',
        'Export-ForPowerBI',
        # Backup & Restore
        'Backup-AppLockerData',
        'Restore-AppLockerData',
        'Get-BackupHistory',
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
        'Get-ValidValues',
        # Main module
        'Start-AppLockerDashboard'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Required modules
    RequiredModules = @()

    # Files to package with this module
    FileList = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module
            Tags = @(
                'AppLocker',
                'Security',
                'PolicyManagement',
                'Windows',
                'ActiveDirectory',
                'GPO',
                'WPF',
                'Enterprise'
            )

            # A URL to the license for this module
            LicenseUri = ''

            # A URL to the main website for this project
            ProjectUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 1.0.0 - Development
============================
Phase 1: Foundation (Complete)
- Core module with logging, configuration, and prerequisites check
- Basic WPF window shell with navigation
- Session context persistence

Phase 2: AD Discovery (Complete)
- Domain info retrieval
- OU tree discovery
- Machine enumeration by OU
- Connectivity testing (ping/WinRM)

Phase 3: Credential Management (Complete)
- Tiered credential model (T0: DCs, T1: Servers, T2: Workstations)
- DPAPI-encrypted credential storage
- Credential testing against target machines
- Settings panel with credential UI

Planned:
- Phase 4: Artifact Scanning
- Phase 5: Rule Generation
- Phase 6: Policy & Deployment
- Phase 7: Polish & Testing
'@
        }
    }
}

