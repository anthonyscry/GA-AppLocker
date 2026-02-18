#
# Module manifest for module 'GA-AppLocker.Scanning'
# Generated: 2026-01-17
#
# Artifact scanning module for discovering executables and collect metadata.
# Supports local and remote scanning via WinRM with parallel execution.
#

@{
    RootModule        = 'GA-AppLocker.Scanning.psm1'
    ModuleVersion     = '1.2.0'
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
        'Get-AppxArtifacts',
        'Get-AppLockerEventLogs',
        'Invoke-AppLockerEventQuery',
        'Start-ArtifactScan',
        'Get-ScanResults',
        'Get-DefaultScanPaths',
        'Write-ScanLog',
        'Export-ScanResults',
        # Scheduled Scans
        'New-ScheduledScan',
        'Get-ScheduledScans',
        'Remove-ScheduledScan',
        'Set-ScheduledScanEnabled',
        'Invoke-ScheduledScan'
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
