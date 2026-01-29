#
# Module manifest for module 'GA-AppLocker.Discovery'
# Generated: 2026-01-17
#
# Active Directory discovery module with LDAP fallback for air-gapped environments.
# Provides domain, OU, and computer discovery without requiring RSAT.
#

@{
    RootModule        = 'GA-AppLocker.Discovery.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-234567890abc'
    Author            = 'GA-AppLocker Team'
    CompanyName       = 'GA-AppLocker'
    Copyright         = '(c) 2026 GA-AppLocker. All rights reserved.'
    Description       = 'Active Directory discovery module for GA-AppLocker Dashboard with LDAP fallback'
    PowerShellVersion = '5.1'
    RequiredModules   = @(
        @{ ModuleName = 'GA-AppLocker.Core'; ModuleVersion = '1.0.0' }
    )
    FunctionsToExport = @(
        # Main discovery functions (with LDAP fallback)
        'Get-DomainInfo',
        'Get-OUTree',
        'Get-ComputersByOU',
        'Test-MachineConnectivity',
        # LDAP-specific functions
        'Resolve-LdapServer',
        'Get-LdapConnection',
        'Get-LdapSearchResult',
        'Get-DomainInfoViaLdap',
        'Get-OUTreeViaLdap',
        'Get-ComputersByOUViaLdap',
        'Set-LdapConfiguration',
        'Test-LdapConnection'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AppLocker', 'ActiveDirectory', 'Discovery', 'LDAP')
            ProjectUri = ''
        }
    }
}
