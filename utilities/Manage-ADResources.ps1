<#
.SYNOPSIS
    Consolidated Active Directory management for AppLocker deployments.

.DESCRIPTION
    This script combines AD resource management functions into a single tool:

    - CreateStructure: Creates AppLocker OUs and security groups in AD
    - ExportUsers: Exports AD users and their group memberships to CSV
    - ImportUsers: Applies group membership changes from CSV to AD

    This consolidation simplifies AD management for AppLocker deployments by
    providing a single entry point for all AD operations.

.PARAMETER Action
    The action to perform:
    - CreateStructure: Create AppLocker AD OUs and security groups
    - ExportUsers: Export user group memberships to CSV for editing
    - ImportUsers: Import group membership changes from CSV

.PARAMETER DomainName
    NetBIOS domain name for CreateStructure action.

.PARAMETER ParentOU
    Parent OU distinguished name for CreateStructure action.

.PARAMETER OUName
    Name for the AppLocker OU (default: "AppLocker").

.PARAMETER GroupPrefix
    Prefix for security group names (default: "AppLocker").

.PARAMETER GroupScope
    Security group scope: DomainLocal, Global, or Universal (default: Global).

.PARAMETER SearchBase
    OU to search for ExportUsers action.

.PARAMETER InputPath
    CSV file path for ImportUsers action.

.PARAMETER OutputPath
    Output file path for ExportUsers action.

.PARAMETER IncludeDisabled
    Include disabled user accounts in ExportUsers.

.PARAMETER Filter
    LDAP filter for ExportUsers action.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    # Create AppLocker AD structure
    .\Manage-ADResources.ps1 -Action CreateStructure -DomainName "CONTOSO"

.EXAMPLE
    # Export users for editing
    .\Manage-ADResources.ps1 -Action ExportUsers -OutputPath ".\Users.csv"

.EXAMPLE
    # Preview group changes
    .\Manage-ADResources.ps1 -Action ImportUsers -InputPath ".\Users.csv" -WhatIf

.EXAMPLE
    # Apply group changes
    .\Manage-ADResources.ps1 -Action ImportUsers -InputPath ".\Users.csv"

.NOTES
    Part of GA-AppLocker toolkit.
    Requires: ActiveDirectory PowerShell module
    Requires: Domain Admin or delegated permissions
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("CreateStructure", "ExportUsers", "ImportUsers")]
    [string]$Action,

    # CreateStructure parameters
    [string]$DomainName,
    [string]$ParentOU,
    [string]$OUName = "AppLocker",
    [string]$GroupPrefix = "AppLocker",
    [ValidateSet("DomainLocal", "Global", "Universal")]
    [string]$GroupScope = "Global",
    [switch]$CreatePoliciesOU = $true,

    # ExportUsers parameters
    [string]$SearchBase,
    [switch]$IncludeDisabled,
    [string]$Filter,

    # ImportUsers parameters
    [string]$InputPath,
    [switch]$SkipValidation,

    # Common parameters
    [string]$OutputPath,
    [string]$LogPath,
    [switch]$Force
)

#Requires -Version 5.1

#region Module Check
Write-Host "Checking prerequisites..." -ForegroundColor Cyan

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "  [OK] ActiveDirectory module loaded" -ForegroundColor Green
}
catch {
    Write-Error "ActiveDirectory PowerShell module is required but not installed."
    Write-Host ""
    Write-Host "To install, run one of the following:" -ForegroundColor Yellow
    Write-Host "  Windows 10/11: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
    Write-Host "  Windows Server: Install-WindowsFeature RSAT-AD-PowerShell"
    exit 1
}
#endregion

#region CreateStructure Function
function Invoke-CreateStructure {
    param(
        [string]$Domain,
        [string]$Parent,
        [string]$OU,
        [string]$Prefix,
        [string]$Scope,
        [switch]$Policies,
        [switch]$NoConfirm
    )

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        $Domain = Read-Host "Enter domain name (e.g., CONTOSO)"
    }

    # Determine Domain DN
    try {
        $domainObj = Get-ADDomain -ErrorAction Stop
        $domainDN = $domainObj.DistinguishedName
        $domainDNS = $domainObj.DNSRoot
        Write-Host "Connected to domain: $domainDNS ($domainDN)" -ForegroundColor Cyan
    }
    catch {
        throw "Failed to connect to Active Directory: $_"
    }

    # Determine parent OU
    if ($Parent) {
        try {
            Get-ADOrganizationalUnit -Identity $Parent -ErrorAction Stop | Out-Null
            $targetParentDN = $Parent
            Write-Host "Parent OU: $Parent" -ForegroundColor Cyan
        }
        catch {
            throw "Parent OU not found: $Parent"
        }
    }
    else {
        $targetParentDN = $domainDN
        Write-Host "Parent: Domain root ($domainDN)" -ForegroundColor Yellow
        Write-Host "  TIP: Use -ParentOU to place under an existing IT/Security OU" -ForegroundColor Gray
    }

    # Define structure
    $appLockerOUDN = "OU=$OU,$targetParentDN"
    $groupsOUDN = "OU=Groups,$appLockerOUDN"
    $policiesOUDN = "OU=Policies,$appLockerOUDN"

    $groups = @(
        @{
            Name        = "$Prefix-Admins"
            Description = "Members bypass all AppLocker restrictions. Add IT administrators and deployment accounts."
            Notes       = "Use sparingly - members can run ANY executable"
        },
        @{
            Name        = "$Prefix-StandardUsers"
            Description = "Standard users subject to AppLocker policy. Add domain users who need standard restrictions."
            Notes       = "Default group for most users"
        },
        @{
            Name        = "$Prefix-ServiceAccounts"
            Description = "Service accounts requiring specific application access beyond standard policy."
            Notes       = "Add accounts running scheduled tasks or services"
        },
        @{
            Name        = "$Prefix-Installers"
            Description = "Users authorized to install software via MSI. More permissive MSI rules apply."
            Notes       = "Software deployment accounts and helpdesk staff"
        }
    )

    # Display plan
    Write-Host ""
    Write-Host "The following will be created:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Organizational Units:" -ForegroundColor White
    Write-Host "    [OU] $appLockerOUDN" -ForegroundColor Gray
    Write-Host "    [OU] $groupsOUDN" -ForegroundColor Gray
    if ($Policies) {
        Write-Host "    [OU] $policiesOUDN" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  Security Groups (in Groups OU):" -ForegroundColor White
    foreach ($group in $groups) {
        Write-Host "    [Group] $Domain\$($group.Name)" -ForegroundColor Gray
    }
    Write-Host ""

    # Confirmation
    if (-not $NoConfirm -and -not $WhatIfPreference) {
        $confirm = Read-Host "Create this structure? (Y/N)"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Create OUs
    $created = @{ OUs = @(); Groups = @(); Skipped = @() }

    # Main OU
    try {
        $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$appLockerOUDN'" -ErrorAction SilentlyContinue
        if ($existingOU) {
            Write-Host "[SKIP] OU already exists: $appLockerOUDN" -ForegroundColor Yellow
            $created.Skipped += $appLockerOUDN
        }
        else {
            if ($PSCmdlet.ShouldProcess($appLockerOUDN, "Create Organizational Unit")) {
                New-ADOrganizationalUnit -Name $OU -Path $targetParentDN -Description "AppLocker management structure" -ProtectedFromAccidentalDeletion $true
                Write-Host "[CREATED] OU: $appLockerOUDN" -ForegroundColor Green
                $created.OUs += $appLockerOUDN
            }
        }
    }
    catch {
        Write-Warning "Failed to create OU $appLockerOUDN : $_"
    }

    # Groups OU
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

    # Policies OU
    if ($Policies) {
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

    # Create Groups
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
                if ($PSCmdlet.ShouldProcess("$Domain\$groupName", "Create Security Group")) {
                    New-ADGroup -Name $groupName `
                        -SamAccountName $groupName `
                        -GroupCategory Security `
                        -GroupScope $Scope `
                        -DisplayName $groupName `
                        -Path $groupsOUDN `
                        -Description $group.Description

                    Set-ADGroup -Identity $groupName -Replace @{info = $group.Notes }

                    Write-Host "[CREATED] Group: $Domain\$groupName" -ForegroundColor Green
                    $created.Groups += $groupName
                }
            }
        }
        catch {
            Write-Warning "Failed to create group $groupName : $_"
        }
    }

    # Summary
    Write-Host ""
    Write-Host "=== SETUP COMPLETE ===" -ForegroundColor Cyan
    Write-Host "Created: $($created.OUs.Count) OUs, $($created.Groups.Count) Groups" -ForegroundColor White
    if ($created.Skipped.Count -gt 0) {
        Write-Host "Skipped (already existed): $($created.Skipped.Count)" -ForegroundColor Yellow
    }

    return @{
        AppLockerOU     = $appLockerOUDN
        GroupsOU        = $groupsOUDN
        PoliciesOU      = $policiesOUDN
        Groups          = @{
            Admins          = "$Domain\$Prefix-Admins"
            StandardUsers   = "$Domain\$Prefix-StandardUsers"
            ServiceAccounts = "$Domain\$Prefix-ServiceAccounts"
            Installers      = "$Domain\$Prefix-Installers"
        }
    }
}
#endregion

#region ExportUsers Function
function Invoke-ExportUsers {
    param(
        [string]$Search,
        [string]$Output,
        [switch]$Disabled,
        [string]$UserFilter
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        $Output = ".\ADUserGroups-Export.csv"
    }

    Write-Host @"

================================================================================
                    AD User Group Membership Export Tool
================================================================================
"@ -ForegroundColor Cyan

    # Build LDAP filter
    $ldapFilter = "(&(objectCategory=person)(objectClass=user)"
    if (-not $Disabled) {
        $ldapFilter += "(!(userAccountControl:1.2.840.113556.1.4.803:=2))"
        Write-Host "Filter: Enabled accounts only" -ForegroundColor Gray
    }
    else {
        Write-Host "Filter: Including disabled accounts" -ForegroundColor Gray
    }

    if ($UserFilter) {
        $ldapFilter += $UserFilter
        Write-Host "Custom filter: $UserFilter" -ForegroundColor Gray
    }
    $ldapFilter += ")"

    # Query AD
    Write-Host ""
    Write-Host "Querying Active Directory..." -ForegroundColor Yellow

    $adParams = @{
        LDAPFilter = $ldapFilter
        Properties = @("DisplayName", "EmailAddress", "Enabled", "Department", "Title", "MemberOf", "Description")
    }

    if ($Search) {
        $adParams.SearchBase = $Search
        Write-Host "  Search scope: $Search" -ForegroundColor Gray
    }
    else {
        Write-Host "  Search scope: Entire domain" -ForegroundColor Gray
    }

    try {
        $users = Get-ADUser @adParams
        Write-Host "  Found $($users.Count) users" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to query Active Directory: $_"
        return
    }

    if ($users.Count -eq 0) {
        Write-Warning "No users found matching the specified criteria."
        return
    }

    # Process users
    Write-Host ""
    Write-Host "Processing user group memberships..." -ForegroundColor Yellow

    $results = @()
    $counter = 0
    $total = $users.Count

    foreach ($user in $users) {
        $counter++
        $percentComplete = [math]::Round(($counter / $total) * 100)
        Write-Progress -Activity "Processing Users" -Status "$counter of $total - $($user.SamAccountName)" -PercentComplete $percentComplete

        $groupNames = @()
        if ($user.MemberOf) {
            foreach ($groupDN in $user.MemberOf) {
                try {
                    $groupName = ($groupDN -split ',')[0] -replace '^CN=', ''
                    $groupNames += $groupName
                }
                catch {
                    $groupNames += $groupDN
                }
            }
        }
        $groupNames = $groupNames | Sort-Object

        $results += [PSCustomObject]@{
            SamAccountName    = $user.SamAccountName
            DisplayName       = $user.DisplayName
            EmailAddress      = $user.EmailAddress
            Enabled           = $user.Enabled
            Department        = $user.Department
            Title             = $user.Title
            Description       = $user.Description
            DistinguishedName = $user.DistinguishedName
            CurrentGroups     = ($groupNames -join "; ")
            AddToGroups       = ""
            RemoveFromGroups  = ""
        }
    }

    Write-Progress -Activity "Processing Users" -Completed

    # Export
    Write-Host ""
    Write-Host "Exporting to CSV..." -ForegroundColor Yellow

    try {
        $results | Export-Csv -Path $Output -NoTypeInformation -Encoding UTF8
        $fullPath = (Resolve-Path $Output).Path

        Write-Host ""
        Write-Host "=== EXPORT COMPLETE ===" -ForegroundColor Green
        Write-Host "  Output file: $fullPath" -ForegroundColor Cyan
        Write-Host "  Users exported: $($results.Count)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Edit the CSV and use:" -ForegroundColor Yellow
        Write-Host "  .\Manage-ADResources.ps1 -Action ImportUsers -InputPath `"$fullPath`"" -ForegroundColor Cyan

        return $fullPath
    }
    catch {
        Write-Error "Failed to export CSV: $_"
    }
}
#endregion

#region ImportUsers Function
function Invoke-ImportUsers {
    param(
        [string]$Input,
        [string]$Log,
        [switch]$NoValidation
    )

    if ([string]::IsNullOrWhiteSpace($Log)) {
        $Log = ".\ADUserGroups-ChangeLog.csv"
    }

    $previewMode = $WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf')

    Write-Host @"

================================================================================
                    AD User Group Membership Import Tool
================================================================================
"@ -ForegroundColor Cyan

    if ($previewMode) {
        Write-Host "                         *** PREVIEW MODE (WhatIf) ***" -ForegroundColor Yellow
        Write-Host "                    No changes will be made to Active Directory" -ForegroundColor Yellow
    }

    # Load CSV
    Write-Host ""
    Write-Host "Loading CSV file..." -ForegroundColor Yellow
    Write-Host "  Input: $Input" -ForegroundColor Gray

    try {
        $csvData = Import-Csv -Path $Input -Encoding UTF8

        $requiredColumns = @('SamAccountName', 'AddToGroups', 'RemoveFromGroups')
        $csvColumns = $csvData[0].PSObject.Properties.Name

        foreach ($col in $requiredColumns) {
            if ($col -notin $csvColumns) {
                Write-Error "Required column '$col' not found in CSV file."
                return
            }
        }

        Write-Host "  [OK] CSV loaded - $($csvData.Count) rows" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to load CSV: $_"
        return
    }

    # Find rows with changes
    Write-Host ""
    Write-Host "Analyzing changes..." -ForegroundColor Yellow

    $rowsWithChanges = $csvData | Where-Object {
        ($_.AddToGroups -and $_.AddToGroups.Trim() -ne "") -or
        ($_.RemoveFromGroups -and $_.RemoveFromGroups.Trim() -ne "")
    }

    if ($rowsWithChanges.Count -eq 0) {
        Write-Host "  No changes detected in CSV file." -ForegroundColor Yellow
        return
    }

    Write-Host "  Found $($rowsWithChanges.Count) users with pending changes" -ForegroundColor Cyan

    # Collect unique groups
    $allGroupNames = @()
    foreach ($row in $rowsWithChanges) {
        if ($row.AddToGroups -and $row.AddToGroups.Trim() -ne "") {
            $groups = $row.AddToGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            $allGroupNames += $groups
        }
        if ($row.RemoveFromGroups -and $row.RemoveFromGroups.Trim() -ne "") {
            $groups = $row.RemoveFromGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            $allGroupNames += $groups
        }
    }
    $uniqueGroups = $allGroupNames | Select-Object -Unique
    Write-Host "  Unique groups referenced: $($uniqueGroups.Count)" -ForegroundColor Gray

    # Validate groups
    if (-not $NoValidation) {
        Write-Host ""
        Write-Host "Validating groups in Active Directory..." -ForegroundColor Yellow

        $validGroups = @{}
        $invalidGroups = @()

        foreach ($groupName in $uniqueGroups) {
            try {
                $group = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction Stop
                if ($group) {
                    $validGroups[$groupName] = $group.DistinguishedName
                    Write-Host "  [OK] $groupName" -ForegroundColor Green
                }
                else {
                    $invalidGroups += $groupName
                    Write-Host "  [NOT FOUND] $groupName" -ForegroundColor Red
                }
            }
            catch {
                $invalidGroups += $groupName
                Write-Host "  [ERROR] $groupName - $_" -ForegroundColor Red
            }
        }

        if ($invalidGroups.Count -gt 0) {
            Write-Error "The following groups were not found in Active Directory:"
            $invalidGroups | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            Write-Host ""
            Write-Host "Use -SkipValidation to bypass this check (not recommended)." -ForegroundColor Gray
            return
        }
    }

    # Process changes
    Write-Host ""
    Write-Host "Processing group membership changes..." -ForegroundColor Yellow
    Write-Host ""

    $changeLog = @()
    $addSuccess = 0
    $addFailed = 0
    $removeSuccess = 0
    $removeFailed = 0

    foreach ($row in $rowsWithChanges) {
        $username = $row.SamAccountName
        Write-Host "Processing: $username" -ForegroundColor Cyan

        try {
            $user = Get-ADUser -Identity $username -ErrorAction Stop
        }
        catch {
            Write-Host "  [ERROR] User not found: $username" -ForegroundColor Red
            $changeLog += [PSCustomObject]@{
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                User      = $username
                Action    = "ERROR"
                Group     = "N/A"
                Result    = "User not found in AD"
            }
            continue
        }

        # Process additions
        if ($row.AddToGroups -and $row.AddToGroups.Trim() -ne "") {
            $groupsToAdd = $row.AddToGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

            foreach ($groupName in $groupsToAdd) {
                $logEntry = [PSCustomObject]@{
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    User      = $username
                    Action    = "ADD"
                    Group     = $groupName
                    Result    = ""
                }

                if ($previewMode) {
                    Write-Host "  [WOULD ADD] $username -> $groupName" -ForegroundColor Yellow
                    $logEntry.Result = "PREVIEW - Would add"
                }
                else {
                    try {
                        Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                        Write-Host "  [ADDED] $username -> $groupName" -ForegroundColor Green
                        $logEntry.Result = "SUCCESS"
                        $addSuccess++
                    }
                    catch {
                        if ($_ -match "already a member") {
                            Write-Host "  [SKIP] $username already member of $groupName" -ForegroundColor Gray
                            $logEntry.Result = "SKIPPED - Already member"
                        }
                        else {
                            Write-Host "  [FAILED] Add $username to $groupName - $_" -ForegroundColor Red
                            $logEntry.Result = "FAILED - $_"
                            $addFailed++
                        }
                    }
                }
                $changeLog += $logEntry
            }
        }

        # Process removals
        if ($row.RemoveFromGroups -and $row.RemoveFromGroups.Trim() -ne "") {
            $groupsToRemove = $row.RemoveFromGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

            foreach ($groupName in $groupsToRemove) {
                $logEntry = [PSCustomObject]@{
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    User      = $username
                    Action    = "REMOVE"
                    Group     = $groupName
                    Result    = ""
                }

                if ($previewMode) {
                    Write-Host "  [WOULD REMOVE] $username <- $groupName" -ForegroundColor Yellow
                    $logEntry.Result = "PREVIEW - Would remove"
                }
                else {
                    try {
                        Remove-ADGroupMember -Identity $groupName -Members $user -Confirm:$false -ErrorAction Stop
                        Write-Host "  [REMOVED] $username <- $groupName" -ForegroundColor Green
                        $logEntry.Result = "SUCCESS"
                        $removeSuccess++
                    }
                    catch {
                        if ($_ -match "not a member") {
                            Write-Host "  [SKIP] $username not a member of $groupName" -ForegroundColor Gray
                            $logEntry.Result = "SKIPPED - Not a member"
                        }
                        else {
                            Write-Host "  [FAILED] Remove $username from $groupName - $_" -ForegroundColor Red
                            $logEntry.Result = "FAILED - $_"
                            $removeFailed++
                        }
                    }
                }
                $changeLog += $logEntry
            }
        }
        Write-Host ""
    }

    # Export log
    if ($changeLog.Count -gt 0) {
        try {
            $changeLog | Export-Csv -Path $Log -NoTypeInformation -Encoding UTF8
            $fullLogPath = (Resolve-Path $Log).Path
            Write-Host "Change log saved: $fullLogPath" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to save change log: $_"
        }
    }

    # Summary
    Write-Host ""
    Write-Host "=== IMPORT COMPLETE ===" -ForegroundColor Green

    if ($previewMode) {
        $wouldAdd = ($changeLog | Where-Object { $_.Action -eq "ADD" }).Count
        $wouldRemove = ($changeLog | Where-Object { $_.Action -eq "REMOVE" }).Count
        Write-Host "  Would add to groups:      $wouldAdd" -ForegroundColor Yellow
        Write-Host "  Would remove from groups: $wouldRemove" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To apply these changes, run without -WhatIf" -ForegroundColor Cyan
    }
    else {
        Write-Host "  Successful additions:     $addSuccess" -ForegroundColor Green
        Write-Host "  Failed additions:         $addFailed" -ForegroundColor $(if ($addFailed -gt 0) { "Red" } else { "Gray" })
        Write-Host "  Successful removals:      $removeSuccess" -ForegroundColor Green
        Write-Host "  Failed removals:          $removeFailed" -ForegroundColor $(if ($removeFailed -gt 0) { "Red" } else { "Gray" })
    }
}
#endregion

#region Main Execution

switch ($Action) {
    "CreateStructure" {
        Invoke-CreateStructure -Domain $DomainName -Parent $ParentOU -OU $OUName -Prefix $GroupPrefix -Scope $GroupScope -Policies:$CreatePoliciesOU -NoConfirm:$Force
    }
    "ExportUsers" {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $OutputPath = ".\ADUserGroups-Export.csv"
        }
        Invoke-ExportUsers -Search $SearchBase -Output $OutputPath -Disabled:$IncludeDisabled -UserFilter $Filter
    }
    "ImportUsers" {
        if ([string]::IsNullOrWhiteSpace($InputPath)) {
            $InputPath = Read-Host "Enter path to CSV file with group changes"
        }
        if (-not (Test-Path $InputPath -PathType Leaf)) {
            Write-Error "Input file not found: $InputPath"
            exit 1
        }
        if ([string]::IsNullOrWhiteSpace($LogPath)) {
            $LogPath = ".\ADUserGroups-ChangeLog.csv"
        }
        Invoke-ImportUsers -Input $InputPath -Log $LogPath -NoValidation:$SkipValidation
    }
}

#endregion
