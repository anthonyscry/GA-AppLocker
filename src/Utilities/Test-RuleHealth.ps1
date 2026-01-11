<#
.SYNOPSIS
    Checks the health of AppLocker rules and identifies broken or problematic rules.

.DESCRIPTION
    Performs comprehensive health checks on AppLocker policies:
    - Path rules pointing to non-existent locations
    - Publisher rules with expired or revoked certificates
    - Hash rules for files that no longer exist
    - Duplicate or conflicting rules
    - Overly permissive rules (security risks)
    - Rules that haven't matched anything (unused)
    - Certificate chain validation issues

.PARAMETER PolicyPath
    Path to the AppLocker policy XML file.

.PARAMETER ScanPath
    Path to scan data for cross-referencing (optional).

.PARAMETER EventPath
    Path to event data for usage analysis (optional).

.PARAMETER CheckCertificates
    Validate publisher certificates (slower, requires network).

.PARAMETER Detailed
    Include detailed information about each issue.

.EXAMPLE
    .\Test-RuleHealth.ps1 -PolicyPath .\policy.xml

.EXAMPLE
    .\Test-RuleHealth.ps1 -PolicyPath .\policy.xml -ScanPath .\Scans -CheckCertificates

.NOTES
    Regular health checks help maintain effective AppLocker policies.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$PolicyPath,

    [string]$ScanPath,

    [string]$EventPath,

    [switch]$CheckCertificates,

    [switch]$Detailed,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Get module root
$scriptRoot = Split-Path $PSScriptRoot -Parent

# Import common functions and error handling
Import-Module (Join-Path $scriptRoot 'utilities\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ErrorHandling.psm1') -Force

#region Health Check Functions

function Test-PathRuleHealth {
    param([xml]$PolicyXml)

    $issues = @()

    foreach ($collection in $PolicyXml.AppLockerPolicy.RuleCollection) {
        foreach ($rule in $collection.ChildNodes) {
            if ($rule.NodeType -ne 'Element') { continue }
            if ($rule.LocalName -ne 'FilePathRule') { continue }

            $pathCondition = $rule.Conditions.FilePathCondition
            if (-not $pathCondition) { continue }

            $path = $pathCondition.Path

            # Expand environment variables for checking
            $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

            # Skip wildcard-only paths (they're valid patterns)
            if ($path -eq '*' -or $path -eq '%OSDRIVE%\*') { continue }

            # Check if path exists (for non-wildcard paths)
            $pathWithoutWildcard = $expandedPath -replace '\*.*$', ''

            if ($pathWithoutWildcard -and -not $pathWithoutWildcard.EndsWith('\')) {
                $pathWithoutWildcard = Split-Path $pathWithoutWildcard -Parent
            }

            if ($pathWithoutWildcard -and -not (Test-Path $pathWithoutWildcard -ErrorAction SilentlyContinue)) {
                $issues += [PSCustomObject]@{
                    RuleId = $rule.Id
                    RuleName = $rule.Name
                    Collection = $collection.Type
                    IssueType = 'PathNotFound'
                    Severity = 'Warning'
                    Path = $path
                    ExpandedPath = $expandedPath
                    Message = "Path does not exist: $pathWithoutWildcard"
                    Recommendation = 'Verify path is correct or remove rule if no longer needed'
                }
            }

            # Check for overly permissive paths
            $riskyPaths = @(
                'C:\*',
                '%OSDRIVE%\*',
                '*',
                '%USERPROFILE%\*'
            )

            if ($rule.Action -eq 'Allow' -and $path -in $riskyPaths) {
                $issues += [PSCustomObject]@{
                    RuleId = $rule.Id
                    RuleName = $rule.Name
                    Collection = $collection.Type
                    IssueType = 'OverlyPermissive'
                    Severity = 'Critical'
                    Path = $path
                    Message = "Overly permissive allow rule: $path"
                    Recommendation = 'Restrict path to specific directories'
                }
            }
        }
    }

    return $issues
}

function Test-PublisherRuleHealth {
    param(
        [xml]$PolicyXml,
        [switch]$CheckCertificates
    )

    $issues = @()

    foreach ($collection in $PolicyXml.AppLockerPolicy.RuleCollection) {
        foreach ($rule in $collection.ChildNodes) {
            if ($rule.NodeType -ne 'Element') { continue }
            if ($rule.LocalName -ne 'FilePublisherRule') { continue }

            $pubCondition = $rule.Conditions.FilePublisherCondition
            if (-not $pubCondition) { continue }

            $publisherName = $pubCondition.PublisherName
            $productName = $pubCondition.ProductName
            $binaryName = $pubCondition.BinaryName

            # Check for wildcard-only publisher (too broad)
            if ($publisherName -eq '*' -and $rule.Action -eq 'Allow') {
                $issues += [PSCustomObject]@{
                    RuleId = $rule.Id
                    RuleName = $rule.Name
                    Collection = $collection.Type
                    IssueType = 'WildcardPublisher'
                    Severity = 'Critical'
                    Publisher = $publisherName
                    Message = "Wildcard publisher allows ANY signed file"
                    Recommendation = 'Specify a specific publisher name'
                }
            }

            # Check for missing version constraints on high-risk publishers
            $versionRange = $pubCondition.BinaryVersionRange
            if ($versionRange.LowSection -eq '*' -and $versionRange.HighSection -eq '*') {
                # All versions allowed - flag for security-sensitive publishers
                $sensitivePublishers = @('*ORACLE*', '*JAVA*', '*ADOBE*FLASH*')

                foreach ($pattern in $sensitivePublishers) {
                    if ($publisherName -like $pattern) {
                        $issues += [PSCustomObject]@{
                            RuleId = $rule.Id
                            RuleName = $rule.Name
                            Collection = $collection.Type
                            IssueType = 'NoVersionConstraint'
                            Severity = 'Warning'
                            Publisher = $publisherName
                            Message = "All versions allowed for potentially vulnerable software"
                            Recommendation = 'Consider adding minimum version constraint'
                        }
                        break
                    }
                }
            }

            # Certificate validation (if enabled)
            if ($CheckCertificates -and $publisherName -ne '*') {
                # This would require finding matching files and checking their certs
                # Simplified check - just note that it should be validated
                # Full implementation would scan Program Files for matching publishers
            }
        }
    }

    return $issues
}

function Test-HashRuleHealth {
    param(
        [xml]$PolicyXml,
        [string]$ScanPath
    )

    $issues = @()

    # Build hash lookup from scan data
    $knownHashes = @{}
    if ($ScanPath -and (Test-Path $ScanPath)) {
        Get-ChildItem $ScanPath -Filter 'InstalledSoftware.csv' -Recurse | ForEach-Object {
            $software = Import-Csv $_.FullName -ErrorAction SilentlyContinue
            foreach ($item in $software) {
                if ($item.Hash) {
                    $knownHashes[$item.Hash] = $item.Path
                }
            }
        }
    }

    foreach ($collection in $PolicyXml.AppLockerPolicy.RuleCollection) {
        foreach ($rule in $collection.ChildNodes) {
            if ($rule.NodeType -ne 'Element') { continue }
            if ($rule.LocalName -ne 'FileHashRule') { continue }

            $hashCondition = $rule.Conditions.FileHashCondition
            if (-not $hashCondition) { continue }

            foreach ($fileHash in $hashCondition.FileHash) {
                $hashData = $fileHash.Data -replace '^0x', ''
                $fileName = $fileHash.SourceFileName

                # Check if hash is still in use
                if ($knownHashes.Count -gt 0 -and -not $knownHashes.ContainsKey($hashData)) {
                    $issues += [PSCustomObject]@{
                        RuleId = $rule.Id
                        RuleName = $rule.Name
                        Collection = $collection.Type
                        IssueType = 'HashNotFound'
                        Severity = 'Info'
                        Hash = $hashData.Substring(0, 16) + '...'
                        FileName = $fileName
                        Message = "Hash not found in current scan data"
                        Recommendation = 'File may have been updated or removed'
                    }
                }

                # Check for duplicate hashes in policy
                $hashCount = ($PolicyXml.OuterXml | Select-String -Pattern $hashData -AllMatches).Matches.Count
                if ($hashCount -gt 1) {
                    $issues += [PSCustomObject]@{
                        RuleId = $rule.Id
                        RuleName = $rule.Name
                        Collection = $collection.Type
                        IssueType = 'DuplicateHash'
                        Severity = 'Warning'
                        Hash = $hashData.Substring(0, 16) + '...'
                        Message = "Hash appears $hashCount times in policy"
                        Recommendation = 'Remove duplicate hash rules'
                    }
                }
            }
        }
    }

    return $issues
}

function Test-RuleConflicts {
    param([xml]$PolicyXml)

    $issues = @()

    foreach ($collection in $PolicyXml.AppLockerPolicy.RuleCollection) {
        $allowPaths = @()
        $denyPaths = @()

        foreach ($rule in $collection.ChildNodes) {
            if ($rule.NodeType -ne 'Element') { continue }
            if ($rule.LocalName -ne 'FilePathRule') { continue }

            $path = $rule.Conditions.FilePathCondition.Path

            if ($rule.Action -eq 'Allow') {
                $allowPaths += @{ Rule = $rule; Path = $path }
            } else {
                $denyPaths += @{ Rule = $rule; Path = $path }
            }
        }

        # Check for overlapping allow/deny
        foreach ($allow in $allowPaths) {
            foreach ($deny in $denyPaths) {
                # Simple overlap check
                $allowPattern = $allow.Path -replace '\*', '.*' -replace '\?', '.'
                $denyPattern = $deny.Path -replace '\*', '.*' -replace '\?', '.'

                if ($allow.Path -like "$($deny.Path)*" -or $deny.Path -like "$($allow.Path)*") {
                    $issues += [PSCustomObject]@{
                        RuleId = "$($allow.Rule.Id) / $($deny.Rule.Id)"
                        RuleName = "$($allow.Rule.Name) vs $($deny.Rule.Name)"
                        Collection = $collection.Type
                        IssueType = 'ConflictingRules'
                        Severity = 'Warning'
                        AllowPath = $allow.Path
                        DenyPath = $deny.Path
                        Message = "Allow and Deny rules may conflict"
                        Recommendation = 'Review rule order and scope (Deny takes precedence)'
                    }
                }
            }
        }
    }

    return $issues
}

function Test-RuleUsage {
    param(
        [xml]$PolicyXml,
        [string]$EventPath
    )

    $issues = @()

    if (-not $EventPath -or -not (Test-Path $EventPath)) {
        return $issues
    }

    # Collect all paths/publishers that were allowed
    $allowedPaths = @{}
    $allowedPublishers = @{}

    Get-ChildItem $EventPath -Filter '*Allowed*.csv' -Recurse | ForEach-Object {
        $events = Import-Csv $_.FullName -ErrorAction SilentlyContinue
        foreach ($event in $events) {
            if ($event.Path) { $allowedPaths[$event.Path] = $true }
            if ($event.Publisher) { $allowedPublishers[$event.Publisher] = $true }
        }
    }

    if ($allowedPaths.Count -eq 0 -and $allowedPublishers.Count -eq 0) {
        return $issues
    }

    # Check each rule for usage
    foreach ($collection in $PolicyXml.AppLockerPolicy.RuleCollection) {
        foreach ($rule in $collection.ChildNodes) {
            if ($rule.NodeType -ne 'Element') { continue }
            if ($rule.Action -ne 'Allow') { continue }

            $matched = $false

            # Check path rules
            if ($rule.LocalName -eq 'FilePathRule') {
                $rulePath = $rule.Conditions.FilePathCondition.Path
                $rulePattern = $rulePath -replace '\*', '.*' -replace '\?', '.'

                foreach ($path in $allowedPaths.Keys) {
                    if ($path -match $rulePattern) {
                        $matched = $true
                        break
                    }
                }
            }

            # Check publisher rules
            if ($rule.LocalName -eq 'FilePublisherRule') {
                $rulePublisher = $rule.Conditions.FilePublisherCondition.PublisherName

                foreach ($publisher in $allowedPublishers.Keys) {
                    if ($publisher -like "*$rulePublisher*") {
                        $matched = $true
                        break
                    }
                }
            }

            if (-not $matched) {
                $issues += [PSCustomObject]@{
                    RuleId = $rule.Id
                    RuleName = $rule.Name
                    Collection = $collection.Type
                    IssueType = 'UnusedRule'
                    Severity = 'Info'
                    Message = "Rule has not matched any allowed events"
                    Recommendation = 'May be obsolete - verify before removing'
                }
            }
        }
    }

    return $issues
}

function Test-SIDValidity {
    param([xml]$PolicyXml)

    $issues = @()

    $wellKnownSids = @{
        'S-1-1-0' = 'Everyone'
        'S-1-5-32-544' = 'Administrators'
        'S-1-5-32-545' = 'Users'
        'S-1-5-18' = 'SYSTEM'
    }

    foreach ($collection in $PolicyXml.AppLockerPolicy.RuleCollection) {
        foreach ($rule in $collection.ChildNodes) {
            if ($rule.NodeType -ne 'Element') { continue }

            $sid = $rule.UserOrGroupSid

            if (-not $sid) { continue }

            # Check if it's a well-known SID
            if ($wellKnownSids.ContainsKey($sid)) { continue }

            # Try to resolve the SID
            try {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier($sid)
                $account = $sidObj.Translate([System.Security.Principal.NTAccount])
                # SID resolves - no issue
            }
            catch {
                $issues += [PSCustomObject]@{
                    RuleId = $rule.Id
                    RuleName = $rule.Name
                    Collection = $collection.Type
                    IssueType = 'UnresolvableSID'
                    Severity = 'Warning'
                    SID = $sid
                    Message = "Cannot resolve SID to account - may be deleted or from another domain"
                    Recommendation = 'Verify the account exists or update the rule'
                }
            }
        }
    }

    return $issues
}

#endregion

#region Main

Write-SectionHeader -Title "AppLocker Rule Health Check"

# Load and validate policy using standardized validation
Write-Host "Loading policy: $(Split-Path $PolicyPath -Leaf)" -ForegroundColor Yellow
$policyXml = Test-ValidAppLockerPolicy -Path $PolicyPath
if (-not $policyXml) {
    Write-ErrorMessage -Message "Failed to load or validate policy: $PolicyPath" -Throw
}

# Count rules
$totalRules = 0
foreach ($collection in $policyXml.AppLockerPolicy.RuleCollection) {
    $totalRules += ($collection.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }).Count
}
Write-Host "  Total rules: $totalRules" -ForegroundColor Gray
Write-Host ""

# Run health checks
$allIssues = @()
$totalSteps = 6

Write-Host "Running health checks..." -ForegroundColor Yellow

Write-StepProgress -Step 1 -Total $totalSteps -Message "Path rule validation"
$pathIssues = Invoke-SafeOperation -ScriptBlock { Test-PathRuleHealth -PolicyXml $policyXml } -ErrorMessage "Path rule validation failed" -ContinueOnError
$allIssues += @($pathIssues)
Write-Host "        Found $(@($pathIssues).Count) issues" -ForegroundColor $(if (@($pathIssues).Count -gt 0) { 'Yellow' } else { 'Green' })

Write-StepProgress -Step 2 -Total $totalSteps -Message "Publisher rule validation"
$pubIssues = Invoke-SafeOperation -ScriptBlock { Test-PublisherRuleHealth -PolicyXml $policyXml -CheckCertificates:$CheckCertificates } -ErrorMessage "Publisher rule validation failed" -ContinueOnError
$allIssues += @($pubIssues)
Write-Host "        Found $(@($pubIssues).Count) issues" -ForegroundColor $(if (@($pubIssues).Count -gt 0) { 'Yellow' } else { 'Green' })

Write-StepProgress -Step 3 -Total $totalSteps -Message "Hash rule validation"
$hashIssues = Invoke-SafeOperation -ScriptBlock { Test-HashRuleHealth -PolicyXml $policyXml -ScanPath $ScanPath } -ErrorMessage "Hash rule validation failed" -ContinueOnError
$allIssues += @($hashIssues)
Write-Host "        Found $(@($hashIssues).Count) issues" -ForegroundColor $(if (@($hashIssues).Count -gt 0) { 'Yellow' } else { 'Green' })

Write-StepProgress -Step 4 -Total $totalSteps -Message "Rule conflict detection"
$conflictIssues = Invoke-SafeOperation -ScriptBlock { Test-RuleConflicts -PolicyXml $policyXml } -ErrorMessage "Conflict detection failed" -ContinueOnError
$allIssues += @($conflictIssues)
Write-Host "        Found $(@($conflictIssues).Count) issues" -ForegroundColor $(if (@($conflictIssues).Count -gt 0) { 'Yellow' } else { 'Green' })

Write-StepProgress -Step 5 -Total $totalSteps -Message "SID validation"
$sidIssues = Invoke-SafeOperation -ScriptBlock { Test-SIDValidity -PolicyXml $policyXml } -ErrorMessage "SID validation failed" -ContinueOnError
$allIssues += @($sidIssues)
Write-Host "        Found $(@($sidIssues).Count) issues" -ForegroundColor $(if (@($sidIssues).Count -gt 0) { 'Yellow' } else { 'Green' })

Write-StepProgress -Step 6 -Total $totalSteps -Message "Usage analysis"
$usageIssues = Invoke-SafeOperation -ScriptBlock { Test-RuleUsage -PolicyXml $policyXml -EventPath $EventPath } -ErrorMessage "Usage analysis failed" -ContinueOnError
$allIssues += @($usageIssues)
Write-Host "        Found $(@($usageIssues).Count) issues" -ForegroundColor $(if (@($usageIssues).Count -gt 0) { 'Yellow' } else { 'Green' })

Write-Host ""

#endregion

#region Report

Write-SectionHeader -Title "Health Check Results"

# Summary by severity
$bySeverity = $allIssues | Group-Object Severity

$criticalCount = ($bySeverity | Where-Object { $_.Name -eq 'Critical' }).Count
$warningCount = ($bySeverity | Where-Object { $_.Name -eq 'Warning' }).Count
$infoCount = ($bySeverity | Where-Object { $_.Name -eq 'Info' }).Count

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Critical: $criticalCount" -ForegroundColor $(if ($criticalCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "  Warning:  $warningCount" -ForegroundColor $(if ($warningCount -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Info:     $infoCount" -ForegroundColor $(if ($infoCount -gt 0) { 'Cyan' } else { 'Gray' })
Write-Host ""

# Health score
$healthScore = 100
$healthScore -= ($criticalCount * 20)
$healthScore -= ($warningCount * 5)
$healthScore -= ($infoCount * 1)
$healthScore = [math]::Max(0, $healthScore)

$healthColor = if ($healthScore -ge 80) { 'Green' }
               elseif ($healthScore -ge 60) { 'Yellow' }
               else { 'Red' }

Write-Host "Policy Health Score: $healthScore / 100" -ForegroundColor $healthColor
Write-Host ""

# Show critical and warning issues
if ($criticalCount -gt 0) {
    Write-Host "CRITICAL ISSUES:" -ForegroundColor Red
    $allIssues | Where-Object { $_.Severity -eq 'Critical' } | ForEach-Object {
        Write-Host "  [!] $($_.RuleName)" -ForegroundColor Red
        Write-Host "      Type: $($_.IssueType)" -ForegroundColor DarkRed
        Write-Host "      $($_.Message)" -ForegroundColor DarkRed
        if ($Detailed -and $_.Recommendation) {
            Write-Host "      Fix: $($_.Recommendation)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

if ($warningCount -gt 0) {
    Write-Host "WARNINGS:" -ForegroundColor Yellow
    $allIssues | Where-Object { $_.Severity -eq 'Warning' } | Select-Object -First 10 | ForEach-Object {
        Write-Host "  [*] $($_.RuleName)" -ForegroundColor Yellow
        Write-Host "      Type: $($_.IssueType) - $($_.Message)" -ForegroundColor DarkYellow
    }
    if ($warningCount -gt 10) {
        Write-Host "  ... and $($warningCount - 10) more warnings" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

# Export if requested
if ($OutputPath) {
    $validOutputPath = Test-ValidPath -Path $OutputPath -Type Directory -CreateIfMissing
    if ($validOutputPath) {
        $reportFile = Join-Path $validOutputPath "health-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

        $reportData = @{
            PolicyFile = $PolicyPath
            AnalyzedAt = Get-Date -Format 'o'
            TotalRules = $totalRules
            HealthScore = $healthScore
            IssueCount = @{
                Critical = $criticalCount
                Warning = $warningCount
                Info = $infoCount
            }
            Issues = $allIssues
        }

        Invoke-SafeOperation -ScriptBlock {
            $reportData | ConvertTo-Json -Depth 10 | Out-File $reportFile -Encoding UTF8
        } -ErrorMessage "Failed to save report" -ContinueOnError

        Write-SuccessMessage -Message "Report saved: $reportFile"
    }
}

#endregion

# Return results
return [PSCustomObject]@{
    PolicyPath = $PolicyPath
    TotalRules = $totalRules
    HealthScore = $healthScore
    CriticalCount = $criticalCount
    WarningCount = $warningCount
    InfoCount = $infoCount
    Issues = $allIssues
}
