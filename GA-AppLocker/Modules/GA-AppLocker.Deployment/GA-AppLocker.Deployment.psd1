@{
    RootModule        = 'GA-AppLocker.Deployment.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'GA-AppLocker Team'
    CompanyName       = 'GA-AppLocker'
    Copyright         = '(c) 2026 GA-AppLocker. All rights reserved.'
    Description       = 'AppLocker policy deployment for GA-AppLocker Dashboard'
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    FunctionsToExport = @(
        'New-DeploymentJob',
        'Get-DeploymentJob',
        'Get-AllDeploymentJobs',
        'Start-Deployment',
        'Stop-Deployment',
        'Get-DeploymentStatus',
        'Test-GPOExists',
        'New-AppLockerGPO',
        'Import-PolicyToGPO',
        'Get-DeploymentHistory'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AppLocker', 'Deployment', 'GPO', 'Security')
            ProjectUri = ''
        }
    }
}
