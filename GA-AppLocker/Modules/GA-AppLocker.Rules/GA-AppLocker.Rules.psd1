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
        'Set-RuleStatus'
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
