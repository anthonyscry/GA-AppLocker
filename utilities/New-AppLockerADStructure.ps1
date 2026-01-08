<#
.SYNOPSIS
    Creates Active Directory OU structure and security groups for AppLocker.

.DESCRIPTION
    This script creates the recommended AD organizational structure for AppLocker
    deployments following enterprise best practices:

    Structure Created:
    ├── OU=AppLocker (or custom name)
    │   ├── OU=Groups
    │   │   ├── AppLocker-Admins (full AppLocker bypass)
    │   │   ├── AppLocker-StandardUsers (standard restrictions)
    │   │   ├── AppLocker-ServiceAccounts (service account exceptions)
    │   │   └── AppLocker-Installers (software installation rights)
    │   └── OU=Policies (for GPO-linked computer accounts)

    Group Purposes:
    - AppLocker-Admins: Members bypass all AppLocker restrictions
    - AppLocker-StandardUsers: Members subject to standard policy
    - AppLocker-ServiceAccounts: Service accounts needing specific app access
    - AppLocker-Installers: Users who can install software (MSI rules)

    Best Practice Placement:
    - Default: Creates under domain root (DC=domain,DC=com)
    - Recommended: Specify -ParentOU to place under existing IT/Security OU
    - Example: OU=Security,OU=IT,DC=contoso,DC=com

.PARAMETER DomainName
    NetBIOS domain name (e.g., "CONTOSO").
    Used for group naming: CONTOSO\AppLocker-Admins

.PARAMETER ParentOU
    Distinguished name of parent OU where AppLocker OU will be created.
    Default: Domain root (e.g., DC=contoso,DC=com)
    Recommended: Place under existing IT or Security OU.

.PARAMETER OUName
    Name of the AppLocker OU to create. Default: "AppLocker"

.PARAMETER GroupPrefix
    Prefix for group names. Default: "AppLocker"
    Groups created: {Prefix}-Admins, {Prefix}-StandardUsers, etc.

.PARAMETER CreatePoliciesOU
    Create a sub-OU for computer accounts that will receive AppLocker GPOs.
    Default: $true

.PARAMETER GroupScope
    Security group scope: DomainLocal, Global, or Universal.
    Default: Global (recommended for single-domain environments)

.PARAMETER WhatIf
    Preview changes without making them.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    # Create at domain root with defaults
    .\New-AppLockerADStructure.ps1 -DomainName "CONTOSO"

.EXAMPLE
    # Create under existing Security OU
    .\New-AppLockerADStructure.ps1 -DomainName "CONTOSO" `
        -ParentOU "OU=Security,OU=IT,DC=contoso,DC=com"

.EXAMPLE
    # Preview what would be created
    .\New-AppLockerADStructure.ps1 -DomainName "CONTOSO" -WhatIf

.EXAMPLE
    # Custom group prefix
    .\New-AppLockerADStructure.ps1 -DomainName "CONTOSO" -GroupPrefix "AppControl"

.NOTES
    Requires: ActiveDirectory PowerShell module
    Requires: Domain Admin or delegated OU creation rights
    Requires: PowerShell 5.1+

    After running this script:
    1. Add IT admins to AppLocker-Admins group
    2. Add service accounts to AppLocker-ServiceAccounts
    3. Add installer accounts to AppLocker-Installers
    4. Use groups in New-AppLockerPolicyFromGuide.ps1:
       -AdminsGroup "DOMAIN\AppLocker-Admins"
       -ServiceAccountsGroup "DOMAIN\AppLocker-ServiceAccounts"

    Author: AaronLocker Simplified Scripts
    Version: 1.0

.LINK
    New-AppLockerPolicyFromGuide.ps1 - Uses these groups for policy generation
    Export-ADUserGroups.ps1 - Export users to add to these groups
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [string]$ParentOU,

    [string]$OUName = "AppLocker",

    [string]$GroupPrefix = "AppLocker",

    [switch]$CreatePoliciesOU = $true,

    [ValidateSet("DomainLocal", "Global", "Universal")]
    [string]$GroupScope = "Global",

    [switch]$Force
)

#Requires -Version 5.1

# Check for ActiveDirectory module
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw @"
ActiveDirectory PowerShell module not found.

Install options:
- Windows Server: Install-WindowsFeature RSAT-AD-PowerShell
- Windows 10/11: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
- Or install RSAT from Settings > Apps > Optional Features
"@
}

Import-Module ActiveDirectory -ErrorAction Stop

#region Determine Domain DN
try {
    $domain = Get-ADDomain -ErrorAction Stop
    $domainDN = $domain.DistinguishedName
    $domainDNS = $domain.DNSRoot
    Write-Host "Connected to domain: $domainDNS ($domainDN)" -ForegroundColor Cyan
}
catch {
    throw "Failed to connect to Active Directory: $_"
}

# Determine parent OU
if ($ParentOU) {
    # Validate parent OU exists
    try {
        $parentOUObj = Get-ADOrganizationalUnit -Identity $ParentOU -ErrorAction Stop
        $targetParentDN = $ParentOU
        Write-Host "Parent OU: $ParentOU" -ForegroundColor Cyan
    }
    catch {
        throw "Parent OU not found: $ParentOU"
    }
}
else {
    $targetParentDN = $domainDN
    Write-Host "Parent: Domain root ($domainDN)" -ForegroundColor Yellow
    Write-Host "  TIP: Use -ParentOU to place under an existing IT/Security OU" -ForegroundColor Gray
}
#endregion

#region Define Structure
$appLockerOUDN = "OU=$OUName,$targetParentDN"
$groupsOUDN = "OU=Groups,$appLockerOUDN"
$policiesOUDN = "OU=Policies,$appLockerOUDN"

# Define groups with descriptions
$groups = @(
    @{
        Name = "$GroupPrefix-Admins"
        Description = "Members bypass all AppLocker restrictions. Add IT administrators and deployment accounts."
        Notes = "Use sparingly - members can run ANY executable"
    },
    @{
        Name = "$GroupPrefix-StandardUsers"
        Description = "Standard users subject to AppLocker policy. Add domain users who need standard restrictions."
        Notes = "Default group for most users"
    },
    @{
        Name = "$GroupPrefix-ServiceAccounts"
        Description = "Service accounts requiring specific application access beyond standard policy."
        Notes = "Add accounts running scheduled tasks or services"
    },
    @{
        Name = "$GroupPrefix-Installers"
        Description = "Users authorized to install software via MSI. More permissive MSI rules apply."
        Notes = "Software deployment accounts and helpdesk staff"
    }
)
#endregion

#region Display Plan
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    AppLocker AD Structure Setup                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "The following will be created:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Organizational Units:" -ForegroundColor White
Write-Host "    [OU] $appLockerOUDN" -ForegroundColor Gray
Write-Host "    [OU] $groupsOUDN" -ForegroundColor Gray
if ($CreatePoliciesOU) {
    Write-Host "    [OU] $policiesOUDN" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Security Groups (in Groups OU):" -ForegroundColor White
foreach ($group in $groups) {
    Write-Host "    [Group] $DomainName\$($group.Name)" -ForegroundColor Gray
    Write-Host "            $($group.Description)" -ForegroundColor DarkGray
}
Write-Host ""

# Confirmation
if (-not $Force -and -not $WhatIfPreference) {
    $confirm = Read-Host "Create this structure? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }
}
#endregion

#region Create OUs
$created = @{
    OUs = @()
    Groups = @()
    Skipped = @()
}

# Create main AppLocker OU
try {
    $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$appLockerOUDN'" -ErrorAction SilentlyContinue
    if ($existingOU) {
        Write-Host "[SKIP] OU already exists: $appLockerOUDN" -ForegroundColor Yellow
        $created.Skipped += $appLockerOUDN
    }
    else {
        if ($PSCmdlet.ShouldProcess($appLockerOUDN, "Create Organizational Unit")) {
            New-ADOrganizationalUnit -Name $OUName -Path $targetParentDN -Description "AppLocker management structure" -ProtectedFromAccidentalDeletion $true
            Write-Host "[CREATED] OU: $appLockerOUDN" -ForegroundColor Green
            $created.OUs += $appLockerOUDN
        }
    }
}
catch {
    Write-Warning "Failed to create OU $appLockerOUDN : $_"
}

# Create Groups sub-OU
try {
    $existingGroupsOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$groupsOUDN'" -ErrorAction SilentlyContinue
    if ($existingGroupsOU) {
        Write-Host "[SKIP] OU already exists: $groupsOUDN" -ForegroundColor Yellow
        $created.Skipped += $groupsOUDN
    }
    else {
        if ($PSCmdlet.ShouldProcess($groupsOUDN, "Create Organizational Unit")) {
            New-ADOrganizationalUnit -Name "Groups" -Path $appLockerOUDN -Description "AppLocker security groups" -ProtectedFromAccidentalDeletion $true
            Write-Host "[CREATED] OU: $groupsOUDN" -ForegroundColor Green
            $created.OUs += $groupsOUDN
        }
    }
}
catch {
    Write-Warning "Failed to create Groups OU: $_"
}

# Create Policies sub-OU (optional)
if ($CreatePoliciesOU) {
    try {
        $existingPoliciesOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$policiesOUDN'" -ErrorAction SilentlyContinue
        if ($existingPoliciesOU) {
            Write-Host "[SKIP] OU already exists: $policiesOUDN" -ForegroundColor Yellow
            $created.Skipped += $policiesOUDN
        }
        else {
            if ($PSCmdlet.ShouldProcess($policiesOUDN, "Create Organizational Unit")) {
                New-ADOrganizationalUnit -Name "Policies" -Path $appLockerOUDN -Description "Computer accounts receiving AppLocker GPOs" -ProtectedFromAccidentalDeletion $true
                Write-Host "[CREATED] OU: $policiesOUDN" -ForegroundColor Green
                $created.OUs += $policiesOUDN
            }
        }
    }
    catch {
        Write-Warning "Failed to create Policies OU: $_"
    }
}
#endregion

#region Create Groups
Write-Host ""
foreach ($group in $groups) {
    $groupName = $group.Name
    try {
        $existingGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
        if ($existingGroup) {
            Write-Host "[SKIP] Group already exists: $groupName" -ForegroundColor Yellow
            $created.Skipped += $groupName
        }
        else {
            if ($PSCmdlet.ShouldProcess("$DomainName\$groupName", "Create Security Group")) {
                New-ADGroup -Name $groupName `
                    -SamAccountName $groupName `
                    -GroupCategory Security `
                    -GroupScope $GroupScope `
                    -DisplayName $groupName `
                    -Path $groupsOUDN `
                    -Description $group.Description

                # Set info/notes attribute
                Set-ADGroup -Identity $groupName -Replace @{info = $group.Notes}

                Write-Host "[CREATED] Group: $DomainName\$groupName" -ForegroundColor Green
                $created.Groups += $groupName
            }
        }
    }
    catch {
        Write-Warning "Failed to create group $groupName : $_"
    }
}
#endregion

#region Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                              SETUP COMPLETE" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Created:" -ForegroundColor Green
Write-Host "  OUs: $($created.OUs.Count)" -ForegroundColor White
Write-Host "  Groups: $($created.Groups.Count)" -ForegroundColor White
if ($created.Skipped.Count -gt 0) {
    Write-Host "Skipped (already existed): $($created.Skipped.Count)" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Add members to groups:" -ForegroundColor White
Write-Host "   # Add IT admins to bypass group" -ForegroundColor Gray
Write-Host "   Add-ADGroupMember -Identity '$GroupPrefix-Admins' -Members 'admin1','admin2'" -ForegroundColor Cyan
Write-Host ""
Write-Host "   # Add service accounts" -ForegroundColor Gray
Write-Host "   Add-ADGroupMember -Identity '$GroupPrefix-ServiceAccounts' -Members 'svc_backup','svc_deploy'" -ForegroundColor Cyan
Write-Host ""
Write-Host "   # Add software installers" -ForegroundColor Gray
Write-Host "   Add-ADGroupMember -Identity '$GroupPrefix-Installers' -Members 'helpdesk1','deploy_svc'" -ForegroundColor Cyan
Write-Host ""

Write-Host "2. Use groups in policy generation:" -ForegroundColor White
Write-Host "   .\New-AppLockerPolicyFromGuide.ps1 -TargetType Workstation -DomainName '$DomainName' ``" -ForegroundColor Cyan
Write-Host "       -AdminsGroup '$DomainName\$GroupPrefix-Admins' ``" -ForegroundColor Cyan
Write-Host "       -ServiceAccountsGroup '$DomainName\$GroupPrefix-ServiceAccounts' ``" -ForegroundColor Cyan
Write-Host "       -InstallersGroup '$DomainName\$GroupPrefix-Installers' ``" -ForegroundColor Cyan
Write-Host "       -Phase 1" -ForegroundColor Cyan
Write-Host ""

Write-Host "3. Link GPOs to the Policies OU:" -ForegroundColor White
Write-Host "   Move computer accounts to: $policiesOUDN" -ForegroundColor Gray
Write-Host "   Link AppLocker GPO to that OU" -ForegroundColor Gray
Write-Host ""

# Return created objects info
return @{
    AppLockerOU = $appLockerOUDN
    GroupsOU = $groupsOUDN
    PoliciesOU = $policiesOUDN
    Groups = @{
        Admins = "$DomainName\$GroupPrefix-Admins"
        StandardUsers = "$DomainName\$GroupPrefix-StandardUsers"
        ServiceAccounts = "$DomainName\$GroupPrefix-ServiceAccounts"
        Installers = "$DomainName\$GroupPrefix-Installers"
    }
}
#endregion
