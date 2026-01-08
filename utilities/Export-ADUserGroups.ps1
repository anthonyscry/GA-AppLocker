<#
.SYNOPSIS
    Exports Active Directory users and their group memberships to CSV for editing.

.DESCRIPTION
    This script queries Active Directory to retrieve all users and their group memberships.
    The output CSV can be edited to add users to additional groups, then imported back
    using the companion Import-ADUserGroups.ps1 script.

    Features:
    - Exports user DN, SamAccountName, DisplayName, Email, Enabled status
    - Lists all current group memberships per user
    - Supports OU filtering to limit scope
    - Outputs to CSV format for easy Excel editing
    - Includes template columns for new group assignments

.PARAMETER SearchBase
    The OU distinguished name to search within. If not specified, searches entire domain.
    Example: "OU=Users,DC=contoso,DC=com"

.PARAMETER OutputPath
    Path for the output CSV file. Defaults to .\ADUserGroups-Export.csv

.PARAMETER IncludeDisabled
    Include disabled user accounts in the export. Default is $false.

.PARAMETER Filter
    LDAP filter for user selection. Default is all users.
    Example: "(department=IT)" to filter by department

.EXAMPLE
    # Export all enabled users from entire domain
    .\Export-ADUserGroups.ps1

.EXAMPLE
    # Export users from specific OU
    .\Export-ADUserGroups.ps1 -SearchBase "OU=Employees,DC=contoso,DC=com"

.EXAMPLE
    # Export including disabled accounts
    .\Export-ADUserGroups.ps1 -IncludeDisabled -OutputPath "C:\Exports\AllUsers.csv"

.EXAMPLE
    # Export IT department users only
    .\Export-ADUserGroups.ps1 -Filter "(department=IT)"

.NOTES
    Requires: ActiveDirectory PowerShell module
    Requires: Read access to AD user and group objects
    Author: AaronLocker Utilities
    Version: 1.0

.LINK
    Import-ADUserGroups.ps1 - Companion script to import group changes
#>

#==============================================================================
# PARAMETERS
#==============================================================================
[CmdletBinding()]
param(
    # OU to search within (optional - defaults to entire domain)
    [string]$SearchBase,

    # Output CSV file path
    [string]$OutputPath = ".\ADUserGroups-Export.csv",

    # Include disabled accounts in export
    [switch]$IncludeDisabled,

    # Custom LDAP filter for user selection
    [string]$Filter
)

#==============================================================================
# REQUIREMENTS CHECK
#==============================================================================

# Verify ActiveDirectory module is available
Write-Host "Checking prerequisites..." -ForegroundColor Cyan

# Attempt to import the ActiveDirectory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "  [OK] ActiveDirectory module loaded" -ForegroundColor Green
}
catch {
    # Module not available - provide helpful error message
    Write-Error "ActiveDirectory PowerShell module is required but not installed."
    Write-Host ""
    Write-Host "To install, run one of the following:" -ForegroundColor Yellow
    Write-Host "  Windows 10/11: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
    Write-Host "  Windows Server: Install-WindowsFeature RSAT-AD-PowerShell"
    exit 1
}

#==============================================================================
# BANNER
#==============================================================================
Write-Host @"

================================================================================
                    AD User Group Membership Export Tool
================================================================================
  Exports users and their group memberships to CSV for editing.
  Use Import-ADUserGroups.ps1 to apply changes back to AD.
================================================================================

"@ -ForegroundColor Cyan

#==============================================================================
# BUILD LDAP FILTER
#==============================================================================

# Start with base user filter
$ldapFilter = "(&(objectCategory=person)(objectClass=user)"

# Add enabled/disabled filter based on parameter
if (-not $IncludeDisabled) {
    # Only include enabled accounts (userAccountControl flag 2 = disabled)
    $ldapFilter += "(!(userAccountControl:1.2.840.113556.1.4.803:=2))"
    Write-Host "Filter: Enabled accounts only" -ForegroundColor Gray
}
else {
    Write-Host "Filter: Including disabled accounts" -ForegroundColor Gray
}

# Add custom filter if provided
if ($Filter) {
    $ldapFilter += $Filter
    Write-Host "Custom filter: $Filter" -ForegroundColor Gray
}

# Close the filter
$ldapFilter += ")"

#==============================================================================
# QUERY ACTIVE DIRECTORY
#==============================================================================

Write-Host ""
Write-Host "Querying Active Directory..." -ForegroundColor Yellow

# Build the Get-ADUser parameters
$adParams = @{
    Filter     = "*"                    # We use LDAPFilter instead
    Properties = @(                     # Properties to retrieve
        "DisplayName",
        "EmailAddress",
        "Enabled",
        "Department",
        "Title",
        "MemberOf",                     # Group memberships
        "Description"
    )
}

# Add SearchBase if specified
if ($SearchBase) {
    $adParams.SearchBase = $SearchBase
    Write-Host "  Search scope: $SearchBase" -ForegroundColor Gray
}
else {
    Write-Host "  Search scope: Entire domain" -ForegroundColor Gray
}

# Add LDAP filter
$adParams.LDAPFilter = $ldapFilter

# Execute the query with error handling
try {
    $users = Get-ADUser @adParams
    Write-Host "  Found $($users.Count) users" -ForegroundColor Green
}
catch {
    Write-Error "Failed to query Active Directory: $_"
    exit 1
}

# Check if any users were found
if ($users.Count -eq 0) {
    Write-Warning "No users found matching the specified criteria."
    exit 0
}

#==============================================================================
# PROCESS USERS AND BUILD EXPORT DATA
#==============================================================================

Write-Host ""
Write-Host "Processing user group memberships..." -ForegroundColor Yellow

# Initialize results array
$results = @()

# Initialize progress counter
$counter = 0
$total = $users.Count

foreach ($user in $users) {
    # Update progress bar
    $counter++
    $percentComplete = [math]::Round(($counter / $total) * 100)
    Write-Progress -Activity "Processing Users" `
                   -Status "$counter of $total - $($user.SamAccountName)" `
                   -PercentComplete $percentComplete

    # Get group names from MemberOf attribute
    # MemberOf contains Distinguished Names, we need friendly names
    $groupNames = @()

    if ($user.MemberOf) {
        foreach ($groupDN in $user.MemberOf) {
            try {
                # Extract CN (common name) from DN for readability
                # DN format: CN=GroupName,OU=Groups,DC=domain,DC=com
                $groupName = ($groupDN -split ',')[0] -replace '^CN=', ''
                $groupNames += $groupName
            }
            catch {
                # If parsing fails, use the full DN
                $groupNames += $groupDN
            }
        }
    }

    # Sort group names alphabetically for consistency
    $groupNames = $groupNames | Sort-Object

    # Build the export object
    # Using PSCustomObject for clean CSV output
    $exportObj = [PSCustomObject]@{
        # User identification
        SamAccountName  = $user.SamAccountName
        DisplayName     = $user.DisplayName
        EmailAddress    = $user.EmailAddress

        # User status and info
        Enabled         = $user.Enabled
        Department      = $user.Department
        Title           = $user.Title
        Description     = $user.Description

        # Full distinguished name (needed for import)
        DistinguishedName = $user.DistinguishedName

        # Current group memberships (semicolon-separated list)
        CurrentGroups   = ($groupNames -join "; ")

        # Editable columns for adding/removing groups
        # User fills these in before import
        AddToGroups     = ""    # Groups to add user to (semicolon-separated)
        RemoveFromGroups = ""   # Groups to remove user from (semicolon-separated)
    }

    # Add to results array
    $results += $exportObj
}

# Clear the progress bar
Write-Progress -Activity "Processing Users" -Completed

#==============================================================================
# EXPORT TO CSV
#==============================================================================

Write-Host ""
Write-Host "Exporting to CSV..." -ForegroundColor Yellow

try {
    # Export with UTF8 encoding for international character support
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    # Get full path for display
    $fullPath = (Resolve-Path $OutputPath).Path

    Write-Host ""
    Write-Host "================================================================================"-ForegroundColor Green
    Write-Host "  EXPORT COMPLETE" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Output file: $fullPath" -ForegroundColor Cyan
    Write-Host "  Users exported: $($results.Count)" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Error "Failed to export CSV: $_"
    exit 1
}

#==============================================================================
# USAGE INSTRUCTIONS
#==============================================================================

Write-Host "How to use this export:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Open the CSV in Excel or a text editor" -ForegroundColor White
Write-Host ""
Write-Host "  2. To ADD a user to groups:" -ForegroundColor White
Write-Host "     - Find the user's row" -ForegroundColor Gray
Write-Host "     - In the 'AddToGroups' column, enter group names" -ForegroundColor Gray
Write-Host "     - Separate multiple groups with semicolons (;)" -ForegroundColor Gray
Write-Host "     - Example: AppLocker-Admins; VPN-Users; IT-Staff" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  3. To REMOVE a user from groups:" -ForegroundColor White
Write-Host "     - Find the user's row" -ForegroundColor Gray
Write-Host "     - In the 'RemoveFromGroups' column, enter group names" -ForegroundColor Gray
Write-Host "     - Separate multiple groups with semicolons (;)" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Save the CSV file" -ForegroundColor White
Write-Host ""
Write-Host "  5. Run the import script:" -ForegroundColor White
Write-Host "     .\Import-ADUserGroups.ps1 -InputPath `"$fullPath`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "================================================================================"-ForegroundColor Gray

#==============================================================================
# RETURN OUTPUT PATH
#==============================================================================

# Return the path for pipeline usage
return $fullPath
