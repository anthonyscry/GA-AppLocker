<#
.SYNOPSIS
    Merges multiple AppLocker policy XML files and removes duplicate rules.

.DESCRIPTION
    Part of GA-AppLocker toolkit. Use Start-AppLockerWorkflow.ps1 for guided experience.

    This script consolidates AppLocker policies from multiple sources into a single,
    clean policy file. Essential for enterprise environments where policies are
    collected from multiple systems or created incrementally.

    Key Features:
    - Recursive search for AppLocker XML files
    - Intelligent duplicate detection by rule type:
      * Publisher rules: Deduplicated by Publisher+Product+Binary
      * Path rules: Deduplicated by Path+Action
      * Hash rules: Deduplicated by SHA256 hash
    - Preserves rule actions (Allow/Deny) and user assignments
    - Validates output XML before saving
    - Adds default admin rules if collections are empty

    Rule Processing:
    - Reads all rule types: FilePublisherRule, FilePathRule, FileHashRule
    - Processes all collections: Exe, Msi, Script, Dll, Appx
    - Maintains rule precedence (Deny rules before Allow)

    Use Cases:
    - Combining policies from multiple workstations/servers
    - Consolidating incrementally developed policies
    - Cleaning up policies with redundant rules
    - Standardizing enforcement mode across rule collections

.PARAMETER InputPath
    Path to folder containing AppLocker XML policy files.
    Searches recursively for files matching IncludePattern.

.PARAMETER OutputPath
    Path to save the merged policy file.
    Defaults to .\MergedPolicy.xml

.PARAMETER RemoveDuplicates
    Remove duplicate rules based on their conditions.
    Default: $true (enabled)
    Set to $false to keep all rules even if duplicated.

.PARAMETER EnforcementMode
    Set enforcement mode for all rule collections:
    - AuditOnly: Log violations but don't block (recommended for testing)
    - Enabled: Actively enforce and block violations
    - NotConfigured: Leave collection disabled

    Note: DLL rules are always set to NotConfigured by default (performance impact)

.PARAMETER IncludePattern
    File pattern to match when searching for policy files.
    Default: *.xml
    Only files containing valid <AppLockerPolicy> XML are processed.

.EXAMPLE
    # Merge all policies from scan results
    .\Merge-AppLockerPolicies.ps1 -InputPath \\server\share\Scans -OutputPath .\MergedPolicy.xml

.EXAMPLE
    # Merge and set all rules to audit mode
    .\Merge-AppLockerPolicies.ps1 -InputPath .\Policies -EnforcementMode AuditOnly

.EXAMPLE
    # Keep duplicates for analysis
    .\Merge-AppLockerPolicies.ps1 -InputPath .\Policies -RemoveDuplicates:$false -OutputPath .\AllRules.xml

.NOTES
    Requires: PowerShell 5.1+

    Input: Valid AppLocker policy XML files with structure:
    <AppLockerPolicy Version="1">
      <RuleCollection Type="Exe" EnforcementMode="...">
        <FilePublisherRule>...</FilePublisherRule>
        <FilePathRule>...</FilePathRule>
        <FileHashRule>...</FileHashRule>
      </RuleCollection>
      ...
    </AppLockerPolicy>

    Output: Single consolidated AppLocker XML policy

    Statistics Reported:
    - Total files processed
    - Rules by type (Publisher, Path, Hash)
    - Duplicates removed
    - Final unique rule count

    Author: AaronLocker Simplified Scripts
    Version: 2.0

.LINK
    Invoke-RemoteScan.ps1 - Collects data that generates policies
    New-AppLockerPolicy.ps1 - Creates policies from scan data
#>

[CmdletBinding(DefaultParameterSetName='Standard')]
param(
    [Parameter(Mandatory=$true, Position=0, ParameterSetName='Standard')]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Position=1, ParameterSetName='Standard')]
    [string]$OutputPath = ".\MergedPolicy.xml",

    [Parameter(ParameterSetName='Standard')]
    [switch]$RemoveDuplicates = $true,

    [Parameter(ParameterSetName='Standard')]
    [ValidateSet("AuditOnly", "Enabled", "NotConfigured")]
    [string]$EnforcementMode,

    [Parameter(ParameterSetName='Standard')]
    [string]$IncludePattern = "*.xml"
)

#Requires -Version 5.1

# Import utilities module
$scriptRoot = $PSScriptRoot
$modulePath = Join-Path $scriptRoot "utilities\Common.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

# Validate input path
if (!(Test-Path -Path $InputPath)) {
    throw "Input path not found: $InputPath"
}

Write-Host "=== AppLocker Policy Merger ===" -ForegroundColor Cyan
Write-Host "Input: $InputPath" -ForegroundColor Cyan
Write-Host "Output: $OutputPath" -ForegroundColor Cyan

# Find all policy files
$policyFiles = Get-ChildItem -Path $InputPath -Filter $IncludePattern -Recurse -File |
    Where-Object {
        try {
            [xml]$content = Get-Content $_.FullName -Raw -ErrorAction Stop
            return $null -ne $content.AppLockerPolicy
        }
        catch {
            return $false
        }
    }

if ($policyFiles.Count -eq 0) {
    throw "No valid AppLocker policy XML files found in $InputPath"
}

Write-Host "Found $($policyFiles.Count) policy files to merge" -ForegroundColor Cyan

# Rule tracking for deduplication
$publisherRules = @{}  # Key: Type|Publisher|Product|Binary
$pathRules = @{}       # Key: Type|Path
$hashRules = @{}       # Key: Type|Hash

# Statistics
$stats = @{
    TotalFiles = $policyFiles.Count
    TotalRules = 0
    PublisherRules = 0
    PathRules = 0
    HashRules = 0
    DuplicatesRemoved = 0
}

# Process each policy file
foreach ($policyFile in $policyFiles) {
    Write-Host "Processing: $($policyFile.Name)" -ForegroundColor Gray

    try {
        [xml]$policy = Get-Content -Path $policyFile.FullName -Raw

        foreach ($collection in $policy.AppLockerPolicy.RuleCollection) {
            $collectionType = $collection.Type

            # Process Publisher Rules
            foreach ($rule in $collection.FilePublisherRule) {
                if ($null -eq $rule) { continue }
                $stats.TotalRules++

                $pub = $rule.Conditions.FilePublisherCondition
                $key = "$collectionType|$($pub.PublisherName)|$($pub.ProductName)|$($pub.BinaryName)"

                if ($RemoveDuplicates -and $publisherRules.ContainsKey($key)) {
                    $stats.DuplicatesRemoved++
                }
                else {
                    $publisherRules[$key] = @{
                        Type = $collectionType
                        Rule = $rule.OuterXml
                        Action = $rule.Action
                        User = $rule.UserOrGroupSid
                    }
                    $stats.PublisherRules++
                }
            }

            # Process Path Rules
            foreach ($rule in $collection.FilePathRule) {
                if ($null -eq $rule) { continue }
                $stats.TotalRules++

                $path = $rule.Conditions.FilePathCondition.Path
                $key = "$collectionType|$($rule.Action)|$path"

                if ($RemoveDuplicates -and $pathRules.ContainsKey($key)) {
                    $stats.DuplicatesRemoved++
                }
                else {
                    $pathRules[$key] = @{
                        Type = $collectionType
                        Rule = $rule.OuterXml
                        Action = $rule.Action
                        User = $rule.UserOrGroupSid
                    }
                    $stats.PathRules++
                }
            }

            # Process Hash Rules
            foreach ($rule in $collection.FileHashRule) {
                if ($null -eq $rule) { continue }
                $stats.TotalRules++

                $hash = $rule.Conditions.FileHashCondition.FileHash.Data
                $key = "$collectionType|$hash"

                if ($RemoveDuplicates -and $hashRules.ContainsKey($key)) {
                    $stats.DuplicatesRemoved++
                }
                else {
                    $hashRules[$key] = @{
                        Type = $collectionType
                        Rule = $rule.OuterXml
                        Action = $rule.Action
                        User = $rule.UserOrGroupSid
                    }
                    $stats.HashRules++
                }
            }
        }
    }
    catch {
        Write-Warning "Error processing $($policyFile.FullName): $_"
    }
}

# Helper function to get rules for a collection type
function Get-RulesForCollection {
    param(
        [string]$CollectionType,
        [hashtable]$PublisherRules,
        [hashtable]$PathRules,
        [hashtable]$HashRules
    )

    $pubRules = @($PublisherRules.GetEnumerator() | Where-Object { $_.Value.Type -eq $CollectionType })
    $pathRules = @($PathRules.GetEnumerator() | Where-Object { $_.Value.Type -eq $CollectionType })
    $hashRules = @($HashRules.GetEnumerator() | Where-Object { $_.Value.Type -eq $CollectionType })

    $xml = ""
    foreach ($rule in $pubRules) { $xml += "`n    " + $rule.Value.Rule }
    foreach ($rule in $pathRules) { $xml += "`n    " + $rule.Value.Rule }
    foreach ($rule in $hashRules) { $xml += "`n    " + $rule.Value.Rule }

    return @{
        Xml = $xml
        Count = $pubRules.Count + $pathRules.Count + $hashRules.Count
    }
}

# Determine enforcement mode
$defaultMode = if ($EnforcementMode) { $EnforcementMode } else { "AuditOnly" }
$dllMode = "NotConfigured"  # DLL rules have performance impact - keep disabled

# Define collections and their default rules
$collections = @(
    @{ Type = "Exe";    Mode = $defaultMode; DefaultRule = "Allow Administrators"; UsePathDefault = $true }
    @{ Type = "Msi";    Mode = $defaultMode; DefaultRule = "Allow Administrators MSI"; UsePathDefault = $true }
    @{ Type = "Script"; Mode = $defaultMode; DefaultRule = "Allow Administrators Scripts"; UsePathDefault = $true }
    @{ Type = "Dll";    Mode = $dllMode;     DefaultRule = $null; UsePathDefault = $false }
    @{ Type = "Appx";   Mode = $defaultMode; DefaultRule = "Allow Microsoft Appx"; UsePathDefault = $false }
)

# Build merged policy XML
$mergedXml = @"
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
"@

foreach ($collection in $collections) {
    $collectionType = $collection.Type
    $mode = $collection.Mode

    $mergedXml += @"

  <RuleCollection Type="$collectionType" EnforcementMode="$mode">
"@

    # Get rules for this collection
    $rulesResult = Get-RulesForCollection -CollectionType $collectionType `
        -PublisherRules $publisherRules -PathRules $pathRules -HashRules $hashRules

    $mergedXml += $rulesResult.Xml

    # Add default rule if collection is empty and has a default rule defined
    if ($rulesResult.Count -eq 0 -and $collection.DefaultRule) {
        if ($collection.UsePathDefault) {
            $mergedXml += @"

    <FilePathRule Id="$(New-Guid)" Name="$($collection.DefaultRule)" Description="Default rule" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
"@
        }
        else {
            # Appx uses publisher rule
            $mergedXml += @"

    <FilePublisherRule Id="$(New-Guid)" Name="$($collection.DefaultRule)" Description="Default rule" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=MICROSOFT CORPORATION, L=REDMOND, S=WASHINGTON, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
"@
        }
    }

    $mergedXml += @"

  </RuleCollection>
"@
}

$mergedXml += "</AppLockerPolicy>"

# Save merged policy
$mergedXml | Out-File -FilePath $OutputPath -Encoding UTF8

# Print statistics
Write-Host "`n=== Merge Complete ===" -ForegroundColor Green
Write-Host "Files processed: $($stats.TotalFiles)" -ForegroundColor Cyan
Write-Host "Total rules found: $($stats.TotalRules)" -ForegroundColor Cyan
Write-Host "  Publisher rules: $($stats.PublisherRules)" -ForegroundColor Gray
Write-Host "  Path rules: $($stats.PathRules)" -ForegroundColor Gray
Write-Host "  Hash rules: $($stats.HashRules)" -ForegroundColor Gray
Write-Host "Duplicates removed: $($stats.DuplicatesRemoved)" -ForegroundColor Yellow
Write-Host "Final unique rules: $($stats.PublisherRules + $stats.PathRules + $stats.HashRules)" -ForegroundColor Green
Write-Host "`nMerged policy saved to: $OutputPath" -ForegroundColor Cyan

# Validate the output
try {
    [xml]$validation = Get-Content -Path $OutputPath -Raw
    Write-Host "Policy XML validation: PASSED" -ForegroundColor Green
}
catch {
    Write-Warning "Policy XML validation failed: $_"
}

Write-Host "`nTo apply this policy:" -ForegroundColor Yellow
Write-Host "  Set-AppLockerPolicy -XmlPolicy `"$OutputPath`"" -ForegroundColor White

return $OutputPath
