<#
.SYNOPSIS
    Imports group membership changes from CSV back into Active Directory.

.DESCRIPTION
    This script reads a CSV file (created by Export-ADUserGroups.ps1) and applies
    group membership changes to Active Directory. It processes the 'AddToGroups'
    and 'RemoveFromGroups' columns to modify user group memberships.

    Features:
    - Adds users to groups specified in AddToGroups column
    - Removes users from groups specified in RemoveFromGroups column
    - Validates groups exist before making changes
    - Supports -WhatIf for preview mode (no changes made)
    - Detailed logging of all changes
    - Generates change report CSV

.PARAMETER InputPath
    Path to the CSV file with group membership changes (from Export-ADUserGroups.ps1).

.PARAMETER WhatIf
    Preview mode - shows what changes would be made without actually making them.
    HIGHLY RECOMMENDED for first run to verify changes.

.PARAMETER LogPath
    Path for the change log file. Defaults to .\ADUserGroups-ChangeLog.csv

.PARAMETER SkipValidation
    Skip validation of group names (not recommended).

.EXAMPLE
    # Preview changes without making them (RECOMMENDED FIRST STEP)
    .\Import-ADUserGroups.ps1 -InputPath ".\ADUserGroups-Export.csv" -WhatIf

.EXAMPLE
    # Apply changes
    .\Import-ADUserGroups.ps1 -InputPath ".\ADUserGroups-Export.csv"

.EXAMPLE
    # Apply changes with custom log path
    .\Import-ADUserGroups.ps1 -InputPath ".\ADUserGroups-Export.csv" -LogPath "C:\Logs\GroupChanges.csv"

.NOTES
    Requires: ActiveDirectory PowerShell module
    Requires: Write access to AD group objects
    Author: AaronLocker Utilities
    Version: 1.0

    IMPORTANT: Always run with -WhatIf first to preview changes!

.LINK
    Export-ADUserGroups.ps1 - Companion script to export user groups
#>

#==============================================================================
# PARAMETERS
#==============================================================================
[CmdletBinding(SupportsShouldProcess)]
param(
    # Input CSV file with group changes
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InputPath,

    # Change log output path
    [string]$LogPath = ".\ADUserGroups-ChangeLog.csv",

    # Skip group validation (not recommended)
    [switch]$SkipValidation
)

#==============================================================================
# REQUIREMENTS CHECK
#==============================================================================

Write-Host "Checking prerequisites..." -ForegroundColor Cyan

# Attempt to import the ActiveDirectory module
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

#==============================================================================
# BANNER
#==============================================================================

# Determine if we're in WhatIf mode
$previewMode = $WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf')

Write-Host @"

================================================================================
                    AD User Group Membership Import Tool
================================================================================
"@ -ForegroundColor Cyan

if ($previewMode) {
    Write-Host @"
                         *** PREVIEW MODE (WhatIf) ***
                    No changes will be made to Active Directory
"@ -ForegroundColor Yellow
}

Write-Host @"
================================================================================

"@ -ForegroundColor Cyan

#==============================================================================
# LOAD AND VALIDATE CSV
#==============================================================================

Write-Host "Loading CSV file..." -ForegroundColor Yellow
Write-Host "  Input: $InputPath" -ForegroundColor Gray

try {
    # Import the CSV file
    $csvData = Import-Csv -Path $InputPath -Encoding UTF8

    # Validate required columns exist
    $requiredColumns = @('SamAccountName', 'AddToGroups', 'RemoveFromGroups')
    $csvColumns = $csvData[0].PSObject.Properties.Name

    foreach ($col in $requiredColumns) {
        if ($col -notin $csvColumns) {
            Write-Error "Required column '$col' not found in CSV file."
            Write-Host "Expected columns: $($requiredColumns -join ', ')" -ForegroundColor Yellow
            exit 1
        }
    }

    Write-Host "  [OK] CSV loaded - $($csvData.Count) rows" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load CSV: $_"
    exit 1
}

#==============================================================================
# IDENTIFY ROWS WITH CHANGES
#==============================================================================

Write-Host ""
Write-Host "Analyzing changes..." -ForegroundColor Yellow

# Filter to only rows that have changes (non-empty AddToGroups or RemoveFromGroups)
$rowsWithChanges = $csvData | Where-Object {
    ($_.AddToGroups -and $_.AddToGroups.Trim() -ne "") -or
    ($_.RemoveFromGroups -and $_.RemoveFromGroups.Trim() -ne "")
}

if ($rowsWithChanges.Count -eq 0) {
    Write-Host ""
    Write-Host "  No changes detected in CSV file." -ForegroundColor Yellow
    Write-Host "  To make changes, edit the 'AddToGroups' or 'RemoveFromGroups' columns." -ForegroundColor Gray
    exit 0
}

Write-Host "  Found $($rowsWithChanges.Count) users with pending changes" -ForegroundColor Cyan

#==============================================================================
# COLLECT ALL UNIQUE GROUP NAMES FOR VALIDATION
#==============================================================================

$allGroupNames = @()

foreach ($row in $rowsWithChanges) {
    # Parse AddToGroups column (semicolon-separated)
    if ($row.AddToGroups -and $row.AddToGroups.Trim() -ne "") {
        $groups = $row.AddToGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $allGroupNames += $groups
    }

    # Parse RemoveFromGroups column (semicolon-separated)
    if ($row.RemoveFromGroups -and $row.RemoveFromGroups.Trim() -ne "") {
        $groups = $row.RemoveFromGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $allGroupNames += $groups
    }
}

# Get unique group names
$uniqueGroups = $allGroupNames | Select-Object -Unique

Write-Host "  Unique groups referenced: $($uniqueGroups.Count)" -ForegroundColor Gray

#==============================================================================
# VALIDATE GROUPS EXIST IN AD
#==============================================================================

if (-not $SkipValidation) {
    Write-Host ""
    Write-Host "Validating groups in Active Directory..." -ForegroundColor Yellow

    $validGroups = @{}
    $invalidGroups = @()

    foreach ($groupName in $uniqueGroups) {
        try {
            # Try to find the group in AD
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

    # Stop if there are invalid groups
    if ($invalidGroups.Count -gt 0) {
        Write-Host ""
        Write-Error "The following groups were not found in Active Directory:"
        $invalidGroups | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "Please correct the group names in the CSV and try again." -ForegroundColor Yellow
        Write-Host "Use -SkipValidation to bypass this check (not recommended)." -ForegroundColor Gray
        exit 1
    }
}

#==============================================================================
# PROCESS CHANGES
#==============================================================================

Write-Host ""
Write-Host "Processing group membership changes..." -ForegroundColor Yellow
Write-Host ""

# Initialize change log
$changeLog = @()

# Initialize counters
$addSuccess = 0
$addFailed = 0
$removeSuccess = 0
$removeFailed = 0

foreach ($row in $rowsWithChanges) {
    $username = $row.SamAccountName

    Write-Host "Processing: $username" -ForegroundColor Cyan

    # Get the AD user object
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

    #--------------------------------------------------------------------------
    # PROCESS ADDITIONS
    #--------------------------------------------------------------------------
    if ($row.AddToGroups -and $row.AddToGroups.Trim() -ne "") {
        # Split by semicolon and clean up whitespace
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
                # WhatIf mode - just report what would happen
                Write-Host "  [WOULD ADD] $username -> $groupName" -ForegroundColor Yellow
                $logEntry.Result = "PREVIEW - Would add"
            }
            else {
                try {
                    # Add user to group
                    Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                    Write-Host "  [ADDED] $username -> $groupName" -ForegroundColor Green
                    $logEntry.Result = "SUCCESS"
                    $addSuccess++
                }
                catch {
                    # Check if already a member (common error)
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

    #--------------------------------------------------------------------------
    # PROCESS REMOVALS
    #--------------------------------------------------------------------------
    if ($row.RemoveFromGroups -and $row.RemoveFromGroups.Trim() -ne "") {
        # Split by semicolon and clean up whitespace
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
                # WhatIf mode - just report what would happen
                Write-Host "  [WOULD REMOVE] $username <- $groupName" -ForegroundColor Yellow
                $logEntry.Result = "PREVIEW - Would remove"
            }
            else {
                try {
                    # Remove user from group
                    Remove-ADGroupMember -Identity $groupName -Members $user -Confirm:$false -ErrorAction Stop
                    Write-Host "  [REMOVED] $username <- $groupName" -ForegroundColor Green
                    $logEntry.Result = "SUCCESS"
                    $removeSuccess++
                }
                catch {
                    # Check if not a member (common error)
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

#==============================================================================
# EXPORT CHANGE LOG
#==============================================================================

if ($changeLog.Count -gt 0) {
    try {
        $changeLog | Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8
        $fullLogPath = (Resolve-Path $LogPath).Path
        Write-Host "Change log saved: $fullLogPath" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to save change log: $_"
    }
}

#==============================================================================
# SUMMARY
#==============================================================================

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
if ($previewMode) {
    Write-Host "  PREVIEW COMPLETE (No changes made)" -ForegroundColor Yellow
}
else {
    Write-Host "  IMPORT COMPLETE" -ForegroundColor Green
}
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan

if ($previewMode) {
    $wouldAdd = ($changeLog | Where-Object { $_.Action -eq "ADD" }).Count
    $wouldRemove = ($changeLog | Where-Object { $_.Action -eq "REMOVE" }).Count
    Write-Host "  Would add to groups:      $wouldAdd" -ForegroundColor Yellow
    Write-Host "  Would remove from groups: $wouldRemove" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To apply these changes, run without -WhatIf:" -ForegroundColor Cyan
    Write-Host "  .\Import-ADUserGroups.ps1 -InputPath `"$InputPath`"" -ForegroundColor White
}
else {
    Write-Host "  Successful additions:     $addSuccess" -ForegroundColor Green
    Write-Host "  Failed additions:         $addFailed" -ForegroundColor $(if($addFailed -gt 0){"Red"}else{"Gray"})
    Write-Host "  Successful removals:      $removeSuccess" -ForegroundColor Green
    Write-Host "  Failed removals:          $removeFailed" -ForegroundColor $(if($removeFailed -gt 0){"Red"}else{"Gray"})
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Gray
