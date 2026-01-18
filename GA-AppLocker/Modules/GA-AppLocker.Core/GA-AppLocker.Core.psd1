#
# Module manifest for module 'GA-AppLocker.Core'
# Generated: 2026-01-17
#

@{
    # Script module file associated with this manifest
    RootModule = 'GA-AppLocker.Core.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'GA-AppLocker Team'

    # Company or vendor of this module
    CompanyName = 'GA-AppLocker'

    # Copyright statement for this module
    Copyright = '(c) 2026 GA-AppLocker Team. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Core module providing logging, configuration, and utility functions for GA-AppLocker Dashboard.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion = '4.0'

    # Minimum version of Microsoft .NET Framework required by this module
    DotNetFrameworkVersion = '4.7.2'

    # Functions to export from this module
    FunctionsToExport = @(
        'Write-AppLockerLog',
        'Get-AppLockerConfig',
        'Set-AppLockerConfig',
        'Test-Prerequisites',
        'Get-AppLockerDataPath',
        'Invoke-WithRetry',
        'Save-SessionState',
        'Restore-SessionState',
        'Clear-SessionState'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module
            Tags = @('AppLocker', 'Security', 'PolicyManagement', 'Windows')

            # A URL to the license for this module
            LicenseUri = ''

            # A URL to the main website for this project
            ProjectUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 1.0.0:
- Initial release
- Write-AppLockerLog: Centralized logging with file and console output
- Get-AppLockerConfig: Configuration management with JSON persistence
- Test-Prerequisites: Startup validation for RSAT, .NET, domain membership
'@
        }
    }
}
