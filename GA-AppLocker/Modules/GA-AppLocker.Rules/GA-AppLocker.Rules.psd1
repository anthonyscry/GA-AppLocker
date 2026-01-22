#
# Module manifest for module 'GA-AppLocker.Rules'
# Generated: 2026-01-17
#
# Rule generation module for creating AppLocker policies from artifacts.
# Supports Publisher, Hash, and Path rules with template support.
#

@{
    RootModule        = 'GA-AppLocker.Rules.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'e5f6a7b8-c9d0-1234-ef56-789012345678'
    Author            = 'GA-AppLocker Team'
    CompanyName       = 'GA-AppLocker'
    Copyright         = '(c) 2026 GA-AppLocker. All rights reserved.'
    Description       = 'AppLocker rule generation for GA-AppLocker Dashboard'
    PowerShellVersion = '5.1'
    # Note: Dependencies handled by parent module GA-AppLocker
    RequiredModules   = @()
    FunctionsToExport = @(
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
        # Rule Templates
        'Get-RuleTemplates',
        'New-RulesFromTemplate',
        'Get-RuleTemplateCategories',
        # Bulk Operations
        'Set-BulkRuleStatus',
        'Approve-TrustedVendorRules',
        # Deduplication
        'Remove-DuplicateRules',
        'Find-DuplicateRules',
        'Find-ExistingHashRule',
        'Find-ExistingPublisherRule',
        'Get-ExistingRuleIndex'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AppLocker', 'Rules', 'Security', 'PolicyGeneration')
            ProjectUri = ''
        }
    }
}
