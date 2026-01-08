<#
.SYNOPSIS
    Validation functions for AppLocker policies and scan data.

.DESCRIPTION
    Provides functions to validate:
    - AppLocker policy XML structure and content
    - Scan data integrity
    - Rule conflicts and security issues

.NOTES
    Dot-source this file or import as needed:
    . "$PSScriptRoot\utilities\Validators.ps1"
#>

#region Policy Validation

<#
.SYNOPSIS
    Validates an AppLocker policy XML file.

.PARAMETER PolicyPath
    Path to the policy XML file.

.OUTPUTS
    PSCustomObject with validation results.
#>
function Test-AppLockerPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyPath
    )

    $result = [PSCustomObject]@{
        Path          = $PolicyPath
        IsValid       = $false
        XmlValid      = $false
        HasRules      = $false
        RuleCount     = 0
        Collections   = @()
        Warnings      = [System.Collections.Generic.List[string]]::new()
        Errors        = [System.Collections.Generic.List[string]]::new()
    }

    # Check file exists
    if (-not (Test-Path $PolicyPath)) {
        $result.Errors.Add("File not found: $PolicyPath")
        return $result
    }

    # Validate XML structure
    try {
        [xml]$policy = Get-Content -Path $PolicyPath -Raw -ErrorAction Stop
        $result.XmlValid = $true
    }
    catch {
        $result.Errors.Add("Invalid XML: $($_.Exception.Message)")
        return $result
    }

    # Check for AppLockerPolicy root element
    if ($null -eq $policy.AppLockerPolicy) {
        $result.Errors.Add("Missing <AppLockerPolicy> root element")
        return $result
    }

    # Analyze rule collections
    $totalRules = 0
    foreach ($collection in $policy.AppLockerPolicy.RuleCollection) {
        $collectionType = $collection.Type
        $enforcementMode = $collection.EnforcementMode

        $ruleCount = 0
        $ruleCount += ($collection.FilePublisherRule | Measure-Object).Count
        $ruleCount += ($collection.FilePathRule | Measure-Object).Count
        $ruleCount += ($collection.FileHashRule | Measure-Object).Count

        $result.Collections += [PSCustomObject]@{
            Type            = $collectionType
            EnforcementMode = $enforcementMode
            RuleCount       = $ruleCount
        }

        $totalRules += $ruleCount

        # Check for empty enforced collections (warning)
        if ($enforcementMode -eq "Enabled" -and $ruleCount -eq 0) {
            $result.Warnings.Add("$collectionType collection is enforced but has no rules - will block everything!")
        }

        # Check for DLL rules in enforce mode (warning)
        if ($collectionType -eq "Dll" -and $enforcementMode -eq "Enabled") {
            $result.Warnings.Add("DLL rules are in Enforce mode - ensure thorough testing was done")
        }
    }

    $result.RuleCount = $totalRules
    $result.HasRules = $totalRules -gt 0

    # Additional security checks
    $securityIssues = Test-PolicySecurity -Policy $policy
    foreach ($issue in $securityIssues) {
        $result.Warnings.Add($issue)
    }

    # Determine overall validity
    $result.IsValid = $result.XmlValid -and $result.HasRules -and ($result.Errors.Count -eq 0)

    return $result
}

<#
.SYNOPSIS
    Checks a policy for common security issues.

.PARAMETER Policy
    The XML policy object.

.OUTPUTS
    Array of warning messages.
#>
function Test-PolicySecurity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Policy
    )

    $warnings = @()

    foreach ($collection in $Policy.AppLockerPolicy.RuleCollection) {
        # Check for overly permissive path rules
        foreach ($rule in $collection.FilePathRule) {
            $path = $rule.Conditions.FilePathCondition.Path
            $action = $rule.Action
            $sid = $rule.UserOrGroupSid

            # Warning: Allow * for Everyone
            if ($path -eq "*" -and $action -eq "Allow" -and $sid -eq "S-1-1-0") {
                $warnings += "[$($collection.Type)] Rule '$($rule.Name)' allows EVERYTHING for Everyone"
            }

            # Warning: Allow from user-writable paths
            $userWritablePaths = @("%TEMP%", "%TMP%", "%APPDATA%", "%LOCALAPPDATA%", "Downloads")
            foreach ($uwp in $userWritablePaths) {
                if ($path -like "*$uwp*" -and $action -eq "Allow") {
                    $warnings += "[$($collection.Type)] Rule '$($rule.Name)' allows execution from user-writable path: $path"
                }
            }
        }

        # Check for wildcard publisher rules to Everyone
        foreach ($rule in $collection.FilePublisherRule) {
            $publisher = $rule.Conditions.FilePublisherCondition.PublisherName
            $product = $rule.Conditions.FilePublisherCondition.ProductName
            $binary = $rule.Conditions.FilePublisherCondition.BinaryName
            $sid = $rule.UserOrGroupSid

            # Warning: Overly broad publisher to Everyone
            if ($publisher -eq "*" -and $sid -eq "S-1-1-0") {
                $warnings += "[$($collection.Type)] Rule '$($rule.Name)' allows ANY publisher for Everyone"
            }
        }
    }

    return $warnings
}

<#
.SYNOPSIS
    Compares two AppLocker policies and reports differences.

.PARAMETER ReferencePath
    Path to the reference (baseline) policy.

.PARAMETER DifferencePath
    Path to the policy to compare.

.OUTPUTS
    PSCustomObject with comparison results.
#>
function Compare-AppLockerPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReferencePath,

        [Parameter(Mandatory = $true)]
        [string]$DifferencePath
    )

    $result = [PSCustomObject]@{
        ReferencePath  = $ReferencePath
        DifferencePath = $DifferencePath
        AreIdentical   = $false
        RulesOnlyInRef = @()
        RulesOnlyInDiff = @()
        ModeDifferences = @()
    }

    # Load both policies
    try {
        [xml]$refPolicy = Get-Content -Path $ReferencePath -Raw
        [xml]$diffPolicy = Get-Content -Path $DifferencePath -Raw
    }
    catch {
        Write-Error "Failed to load policies: $_"
        return $result
    }

    # Compare enforcement modes
    foreach ($refColl in $refPolicy.AppLockerPolicy.RuleCollection) {
        $diffColl = $diffPolicy.AppLockerPolicy.RuleCollection | Where-Object { $_.Type -eq $refColl.Type }

        if ($refColl.EnforcementMode -ne $diffColl.EnforcementMode) {
            $result.ModeDifferences += [PSCustomObject]@{
                Collection    = $refColl.Type
                ReferenceMode = $refColl.EnforcementMode
                DifferenceMode = $diffColl.EnforcementMode
            }
        }
    }

    # Extract rule identifiers for comparison
    $refRules = Get-PolicyRuleIdentifiers -Policy $refPolicy
    $diffRules = Get-PolicyRuleIdentifiers -Policy $diffPolicy

    $result.RulesOnlyInRef = $refRules | Where-Object { $_ -notin $diffRules }
    $result.RulesOnlyInDiff = $diffRules | Where-Object { $_ -notin $refRules }

    $result.AreIdentical = ($result.RulesOnlyInRef.Count -eq 0) -and
                           ($result.RulesOnlyInDiff.Count -eq 0) -and
                           ($result.ModeDifferences.Count -eq 0)

    return $result
}

<#
.SYNOPSIS
    Extracts unique rule identifiers from a policy for comparison.
#>
function Get-PolicyRuleIdentifiers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Policy
    )

    $identifiers = @()

    foreach ($collection in $Policy.AppLockerPolicy.RuleCollection) {
        $type = $collection.Type

        foreach ($rule in $collection.FilePublisherRule) {
            $pub = $rule.Conditions.FilePublisherCondition
            $identifiers += "$type|Publisher|$($pub.PublisherName)|$($pub.ProductName)|$($pub.BinaryName)"
        }

        foreach ($rule in $collection.FilePathRule) {
            $path = $rule.Conditions.FilePathCondition.Path
            $identifiers += "$type|Path|$($rule.Action)|$path"
        }

        foreach ($rule in $collection.FileHashRule) {
            $hash = $rule.Conditions.FileHashCondition.FileHash.Data
            $identifiers += "$type|Hash|$hash"
        }
    }

    return $identifiers
}

#endregion

#region Scan Data Validation

<#
.SYNOPSIS
    Validates scan data directory structure and content.

.PARAMETER ScanPath
    Path to the scan results directory.

.OUTPUTS
    PSCustomObject with validation results.
#>
function Test-ScanData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanPath
    )

    $result = [PSCustomObject]@{
        Path           = $ScanPath
        IsValid        = $false
        ComputerCount  = 0
        HasExecutables = $false
        HasPublishers  = $false
        HasWritable    = $false
        Computers      = @()
        Warnings       = [System.Collections.Generic.List[string]]::new()
        Errors         = [System.Collections.Generic.List[string]]::new()
    }

    # Check path exists
    if (-not (Test-Path $ScanPath)) {
        $result.Errors.Add("Scan path not found: $ScanPath")
        return $result
    }

    # Find computer folders (folders containing CSV files)
    $computerFolders = Get-ChildItem -Path $ScanPath -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "*.csv") }

    if ($computerFolders.Count -eq 0) {
        $result.Errors.Add("No computer scan data found in $ScanPath")
        return $result
    }

    $result.ComputerCount = $computerFolders.Count

    foreach ($folder in $computerFolders) {
        $computerData = [PSCustomObject]@{
            Name           = $folder.Name
            ExecutableCount = 0
            SignedCount    = 0
            PublisherCount = 0
            WritableCount  = 0
        }

        # Check for Executables.csv
        $exePath = Join-Path $folder.FullName "Executables.csv"
        if (Test-Path $exePath) {
            $exes = Import-Csv -Path $exePath
            $computerData.ExecutableCount = $exes.Count
            $computerData.SignedCount = ($exes | Where-Object { $_.IsSigned -eq "True" }).Count
            $result.HasExecutables = $true
        }

        # Check for Publishers.csv
        $pubPath = Join-Path $folder.FullName "Publishers.csv"
        if (Test-Path $pubPath) {
            $pubs = Import-Csv -Path $pubPath
            $computerData.PublisherCount = $pubs.Count
            $result.HasPublishers = $true
        }

        # Check for WritableDirectories.csv
        $writablePath = Join-Path $folder.FullName "WritableDirectories.csv"
        if (Test-Path $writablePath) {
            $writable = Import-Csv -Path $writablePath
            $computerData.WritableCount = $writable.Count
            $result.HasWritable = $true
        }

        $result.Computers += $computerData
    }

    # Add warnings for missing data
    if (-not $result.HasExecutables) {
        $result.Warnings.Add("No executable data found - publisher rules cannot be generated")
    }

    if (-not $result.HasWritable) {
        $result.Warnings.Add("No writable directory data - security analysis incomplete")
    }

    $result.IsValid = $result.HasExecutables -and ($result.Errors.Count -eq 0)

    return $result
}

#endregion

#region Output Formatting

<#
.SYNOPSIS
    Displays validation results in a formatted manner.

.PARAMETER ValidationResult
    The result object from Test-AppLockerPolicy or Test-ScanData.
#>
function Show-ValidationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ValidationResult
    )

    $statusColor = if ($ValidationResult.IsValid) { "Green" } else { "Red" }
    $statusText = if ($ValidationResult.IsValid) { "VALID" } else { "INVALID" }

    Write-Host "`n=== Validation Result: $statusText ===" -ForegroundColor $statusColor
    Write-Host "Path: $($ValidationResult.Path)" -ForegroundColor Cyan

    if ($ValidationResult.RuleCount) {
        Write-Host "Total Rules: $($ValidationResult.RuleCount)" -ForegroundColor Gray
    }

    if ($ValidationResult.Collections) {
        Write-Host "`nRule Collections:" -ForegroundColor Yellow
        foreach ($coll in $ValidationResult.Collections) {
            Write-Host "  $($coll.Type): $($coll.RuleCount) rules ($($coll.EnforcementMode))" -ForegroundColor Gray
        }
    }

    if ($ValidationResult.ComputerCount) {
        Write-Host "Computers: $($ValidationResult.ComputerCount)" -ForegroundColor Gray
    }

    if ($ValidationResult.Warnings.Count -gt 0) {
        Write-Host "`nWarnings:" -ForegroundColor Yellow
        foreach ($warning in $ValidationResult.Warnings) {
            Write-Host "  [!] $warning" -ForegroundColor Yellow
        }
    }

    if ($ValidationResult.Errors.Count -gt 0) {
        Write-Host "`nErrors:" -ForegroundColor Red
        foreach ($error in $ValidationResult.Errors) {
            Write-Host "  [-] $error" -ForegroundColor Red
        }
    }

    Write-Host ""
}

#endregion

# Export functions if loaded as module
if ($MyInvocation.MyCommand.Name -ne $MyInvocation.MyCommand.Path) {
    Export-ModuleMember -Function @(
        'Test-AppLockerPolicy',
        'Test-PolicySecurity',
        'Compare-AppLockerPolicies',
        'Get-PolicyRuleIdentifiers',
        'Test-ScanData',
        'Show-ValidationResult'
    )
}
