#
# Module manifest for module 'GA-AppLocker.Policy'
# Generated: 2026-01-17
#
# Policy management module for combining rules into AppLocker policies.
# Supports policy XML generation and GPO targeting.
#

@{
    RootModule        = 'GA-AppLocker.Policy.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f6a7b8c9-d0e1-2345-6789-abcdef012345'
    Author            = 'GA-AppLocker Team'
    CompanyName       = 'GA-AppLocker'
    Copyright         = '(c) 2026 GA-AppLocker. All rights reserved.'
    Description       = 'AppLocker policy management for GA-AppLocker Dashboard'
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    FunctionsToExport = @(
        'New-Policy',
        'Get-Policy',
        'Get-AllPolicies',
        'Get-PolicyCount',
        'Update-Policy',
        'Remove-Policy',
        'Set-PolicyStatus',
        'Add-RuleToPolicy',
        'Remove-RuleFromPolicy',
        'Set-PolicyTarget',
        'Export-PolicyToXml',
        'Test-PolicyCompliance',
        # Policy Comparison
        'Compare-Policies',
        'Compare-RuleProperties',
        'Get-PolicyDiffReport',
        # Policy Snapshots
        'New-PolicySnapshot',
        'Get-PolicySnapshots',
        'Get-PolicySnapshot',
        'Restore-PolicySnapshot',
        'Remove-PolicySnapshot',
        'Invoke-PolicySnapshotCleanup'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AppLocker', 'Policy', 'Security', 'GPO')
            ProjectUri = ''
        }
    }
}
