#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Discovery

.DESCRIPTION
    Active Directory discovery module for GA-AppLocker Dashboard.
    Provides functions for domain detection, OU tree building,
    and machine discovery.

.DEPENDENCIES
    - GA-AppLocker.Core (logging)
    - ActiveDirectory module (RSAT)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release - Phase 2

.NOTES
    Requires RSAT Active Directory module.
    Domain-joined machine required.
#>
#endregion

#region ===== FUNCTION LOADING =====
$functionPath = Join-Path $PSScriptRoot 'Functions'

if (Test-Path $functionPath) {
    $functionFiles = Get-ChildItem -Path $functionPath -Filter '*.ps1' -ErrorAction SilentlyContinue

    foreach ($file in $functionFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Warning "Failed to load function file: $($file.Name). Error: $($_.Exception.Message)"
        }
    }
}
#endregion

#region ===== EXPORTS =====
Export-ModuleMember -Function @(
    # Main discovery functions (with LDAP fallback)
    'Get-DomainInfo',
    'Get-OUTree',
    'Get-ComputersByOU',
    'Test-MachineConnectivity',
    # LDAP-specific functions
    'Get-LdapConnection',
    'Get-LdapSearchResult',
    'Get-DomainInfoViaLdap',
    'Get-OUTreeViaLdap',
    'Get-ComputersByOUViaLdap',
    'Set-LdapConfiguration',
    'Test-LdapConnection'
)
#endregion
