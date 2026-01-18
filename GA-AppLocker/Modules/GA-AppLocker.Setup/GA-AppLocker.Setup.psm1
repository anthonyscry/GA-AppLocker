#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Setup

.DESCRIPTION
    AppLocker environment initialization module for GA-AppLocker Dashboard.
    Creates WinRM GPO, AppLocker GPOs, AD OU structure, and security groups.

.FEATURES
    - WinRM GPO creation and configuration (AppLocker-EnableWinRM)
    - AppLocker GPOs for DC, Servers, Workstations
    - AD OU structure creation (OU=AppLocker)
    - Security groups creation for role-based access

.DEPENDENCIES
    - GA-AppLocker.Core (logging, config)
    - GroupPolicy module (for GPO management)
    - ActiveDirectory module (for AD management)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release

.NOTES
    Requires Domain Admin or equivalent permissions.
    Air-gapped environment compatible.
#>
#endregion

#region ===== MODULE CONFIGURATION =====

# Default GPO names
$script:DefaultGPONames = @{
    WinRM        = 'AppLocker-EnableWinRM'
    DC           = 'AppLocker-DC'
    Servers      = 'AppLocker-Servers'
    Workstations = 'AppLocker-Workstations'
}

# Default OU name
$script:DefaultOUName = 'AppLocker'

# Default security groups
$script:DefaultGroups = @(
    @{ Name = 'AppLocker-Admins';     Description = 'AppLocker administrators with full management rights' }
    @{ Name = 'AppLocker-Exempt';     Description = 'Users exempt from AppLocker policies' }
    @{ Name = 'AppLocker-Audit';      Description = 'Users in audit-only mode' }
    @{ Name = 'AppLocker-Users';      Description = 'Standard users subject to AppLocker policies' }
    @{ Name = 'AppLocker-Installers'; Description = 'Users allowed to install approved software' }
    @{ Name = 'AppLocker-Developers'; Description = 'Developers with expanded execution rights' }
)

# WinRM firewall rules
$script:WinRMFirewallRules = @(
    'Windows Remote Management (HTTP-In)'
    'Windows Remote Management (HTTPS-In)'
)

#endregion

#region ===== SAFE LOGGING WRAPPER =====
function script:Write-SetupLog {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== HELPER FUNCTIONS =====

function script:Test-ModuleAvailable {
    param([string]$ModuleName)
    return [bool](Get-Module -ListAvailable -Name $ModuleName)
}

function script:Get-DomainDN {
    <#
    .SYNOPSIS
        Gets the domain distinguished name.
    #>
    try {
        if (Test-ModuleAvailable -ModuleName 'ActiveDirectory') {
            Import-Module ActiveDirectory -ErrorAction Stop
            $domain = Get-ADDomain -ErrorAction Stop
            return $domain.DistinguishedName
        }
        else {
            # Fallback: try to get from environment
            $domain = $env:USERDNSDOMAIN
            if ($domain) {
                $parts = $domain.Split('.')
                return ($parts | ForEach-Object { "DC=$_" }) -join ','
            }
        }
    }
    catch {
        Write-SetupLog -Message "Failed to get domain DN: $($_.Exception.Message)" -Level Error
    }
    return $null
}

function script:Get-DefaultOUPath {
    <#
    .SYNOPSIS
        Gets the default OU paths for different machine types.
    #>
    param([string]$Type)
    
    $domainDN = Get-DomainDN
    if (-not $domainDN) { return $null }
    
    switch ($Type) {
        'DC'           { return "OU=Domain Controllers,$domainDN" }
        'Servers'      { return "CN=Computers,$domainDN" }  # Default Computers container, or could be custom Servers OU
        'Workstations' { return "CN=Computers,$domainDN" }
        'Root'         { return $domainDN }
        default        { return $domainDN }
    }
}

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
    'Initialize-WinRMGPO',
    'Initialize-AppLockerGPOs',
    'Initialize-ADStructure',
    'Initialize-AppLockerEnvironment',
    'Get-SetupStatus',
    'Enable-WinRMGPO',
    'Disable-WinRMGPO'
)
#endregion
