@{
    RootModule        = 'GA-AppLocker.Scanning.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd4e5f6a7-b8c9-0123-def4-567890123456'
    Author            = 'GA-AppLocker Team'
    CompanyName       = 'GA-AppLocker'
    Copyright         = '(c) 2026 GA-AppLocker. All rights reserved.'
    Description       = 'Artifact scanning and collection for GA-AppLocker Dashboard'
    PowerShellVersion = '5.1'
    # Note: Dependencies handled by parent module GA-AppLocker
    RequiredModules   = @()
    FunctionsToExport = @(
        'Get-LocalArtifacts',
        'Get-RemoteArtifacts',
        'Get-AppLockerEventLogs',
        'Start-ArtifactScan',
        'Get-ScanResults',
        'Export-ScanResults'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AppLocker', 'Scanning', 'Artifacts', 'Security')
            ProjectUri = ''
        }
    }
}
