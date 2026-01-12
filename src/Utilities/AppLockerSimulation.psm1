<#
.SYNOPSIS
    AppLocker what-if simulation utilities.

.DESCRIPTION
    Provides lightweight simulation of AppLocker policy enforcement against
    audit event CSV data. Produces summary statistics and detailed per-app
    results suitable for UI display and export.

.NOTES
    Part of GA-AppLocker toolkit.
#>

#Requires -Version 5.1

function Get-NormalizedAppLockerEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Event path not found: $Path"
    }

    $eventFile = $Path
    if ((Get-Item $Path).PSIsContainer) {
        $candidateFiles = @(
            (Join-Path $Path "UniqueBlockedApps.csv"),
            (Join-Path $Path "BlockedEvents.csv")
        ) | Where-Object { Test-Path $_ }

        if ($candidateFiles.Count -eq 0) {
            $candidateFiles = Get-ChildItem -Path $Path -Filter "*.csv" -File | Sort-Object LastWriteTime -Descending
        }

        if ($candidateFiles.Count -gt 0) {
            $eventFile = $candidateFiles[0].FullName
        }
    }

    if (-not (Test-Path $eventFile)) {
        throw "No event CSV found in: $Path"
    }

    $rawEvents = Import-Csv -Path $eventFile
    if (-not $rawEvents -or $rawEvents.Count -eq 0) {
        return @()
    }

    $normalized = foreach ($row in $rawEvents) {
        $filePath = $row.FilePath
        if (-not $filePath) { $filePath = $row.Path }
        if (-not $filePath) { $filePath = $row.'File Path' }
        if (-not $filePath) { $filePath = $row.ExecutablePath }

        $publisher = $row.Publisher
        if (-not $publisher) { $publisher = $row.SignerName }
        if (-not $publisher) { $publisher = $row.PublisherName }

        $productName = $row.ProductName
        if (-not $productName) { $productName = $row.Product }

        $fileHash = $row.FileHash
        if (-not $fileHash) { $fileHash = $row.Hash }
        if (-not $fileHash) { $fileHash = $row.SHA256 }
        if (-not $fileHash) { $fileHash = $row.Sha256 }

        $eventId = $row.EventId
        if (-not $eventId) { $eventId = $row.Id }

        $eventType = $row.EventType
        if (-not $eventType) { $eventType = $row.Action }
        if (-not $eventType) { $eventType = $row.Result }

        $occurrence = $row.OccurrenceCount
        if (-not $occurrence) { $occurrence = $row.TimesSeen }
        if (-not $occurrence) { $occurrence = $row.Count }
        if (-not $occurrence) { $occurrence = 1 }

        [PSCustomObject]@{
            FilePath = $filePath
            FileName = if ($row.FileName) { $row.FileName } elseif ($filePath) { Split-Path $filePath -Leaf } else { "" }
            Publisher = $publisher
            ProductName = $productName
            FileHash = $fileHash
            EventId = $eventId
            EventType = $eventType
            TimesSeen = [int]$occurrence
            SourceFile = $eventFile
        }
    }

    return $normalized | Where-Object { $_.FilePath }
}

function Get-AppLockerRulesFromPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyPath
    )

    if (-not (Test-Path $PolicyPath)) {
        throw "Policy not found: $PolicyPath"
    }

    $policyXml = [xml](Get-Content -Path $PolicyPath -Raw)
    $rules = @()

    foreach ($collection in $policyXml.AppLockerPolicy.RuleCollection) {
        foreach ($rule in @($collection.FilePathRule)) {
            if ($rule) {
                $rules += [PSCustomObject]@{
                    Type = "Path"
                    Action = $rule.Action
                    Name = $rule.Name
                    RuleId = $rule.Id
                    UserOrGroupSid = $rule.UserOrGroupSid
                    Path = $rule.Conditions.FilePathCondition.Path
                }
            }
        }

        foreach ($rule in @($collection.FilePublisherRule)) {
            if ($rule) {
                $rules += [PSCustomObject]@{
                    Type = "Publisher"
                    Action = $rule.Action
                    Name = $rule.Name
                    RuleId = $rule.Id
                    UserOrGroupSid = $rule.UserOrGroupSid
                    PublisherName = $rule.Conditions.FilePublisherCondition.PublisherName
                    ProductName = $rule.Conditions.FilePublisherCondition.ProductName
                    BinaryName = $rule.Conditions.FilePublisherCondition.BinaryName
                }
            }
        }

        foreach ($rule in @($collection.FileHashRule)) {
            if ($rule) {
                $hashData = $rule.Conditions.FileHashCondition.FileHash.Data
                if (-not $hashData) { $hashData = $rule.Conditions.FileHashCondition.FileHash.Hash }
                $rules += [PSCustomObject]@{
                    Type = "Hash"
                    Action = $rule.Action
                    Name = $rule.Name
                    RuleId = $rule.Id
                    UserOrGroupSid = $rule.UserOrGroupSid
                    Hash = $hashData
                }
            }
        }
    }

    return $rules
}

function Test-AppLockerRuleMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Rule,
        [Parameter(Mandatory = $true)]
        $Event
    )

    switch ($Rule.Type) {
        "Path" {
            if (-not $Event.FilePath -or -not $Rule.Path) { return $false }
            $pattern = [Environment]::ExpandEnvironmentVariables($Rule.Path)
            return $Event.FilePath.ToLower() -like $pattern.ToLower()
        }
        "Publisher" {
            if (-not $Event.Publisher -or -not $Rule.PublisherName) { return $false }
            $publisherValue = $Event.Publisher
            if ($publisherValue -notmatch '^O=') {
                $publisherValue = "O=$publisherValue"
            }
            $publisherMatch = $publisherValue.ToLower() -like $Rule.PublisherName.ToLower()
            if (-not $publisherMatch) { return $false }

            $productRule = if ($Rule.ProductName) { $Rule.ProductName } else { "*" }
            $binaryRule = if ($Rule.BinaryName) { $Rule.BinaryName } else { "*" }

            $productMatch = $true
            if ($productRule -ne "*" ) {
                if (-not $Event.ProductName) { return $false }
                $productMatch = $Event.ProductName.ToLower() -like $productRule.ToLower()
            }

            $binaryMatch = $true
            if ($binaryRule -ne "*" ) {
                $binaryMatch = $Event.FileName.ToLower() -like $binaryRule.ToLower()
            }

            return ($publisherMatch -and $productMatch -and $binaryMatch)
        }
        "Hash" {
            if (-not $Event.FileHash -or -not $Rule.Hash) { return $false }
            $eventHash = $Event.FileHash.ToLower().Replace("0x", "")
            $ruleHash = $Rule.Hash.ToLower().Replace("0x", "")
            return $eventHash -eq $ruleHash
        }
    }

    return $false
}

function Invoke-AppLockerSimulation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyPath,

        [Parameter(Mandatory = $true)]
        [string]$EventPath
    )

    $events = Get-NormalizedAppLockerEvents -Path $EventPath
    if (-not $events -or $events.Count -eq 0) {
        throw "No events found to simulate."
    }

    $rules = Get-AppLockerRulesFromPolicy -PolicyPath $PolicyPath
    if (-not $rules -or $rules.Count -eq 0) {
        throw "No rules found in policy."
    }

    $denyRules = $rules | Where-Object { $_.Action -eq "Deny" }
    $allowRules = $rules | Where-Object { $_.Action -eq "Allow" }

    $groupedEvents = $events | Group-Object -Property FilePath
    $results = foreach ($group in $groupedEvents) {
        $sample = $group.Group[0]
        $timesSeen = ($group.Group | Measure-Object -Property TimesSeen -Sum).Sum
        if (-not $timesSeen) { $timesSeen = $group.Count }

        $matchedRule = $null
        $result = "NoMatch"

        foreach ($rule in $denyRules) {
            if (Test-AppLockerRuleMatch -Rule $rule -Event $sample) {
                $matchedRule = "$($rule.Type): $($rule.Name)"
                $result = "Blocked"
                break
            }
        }

        if ($result -eq "NoMatch") {
            foreach ($rule in $allowRules) {
                if (Test-AppLockerRuleMatch -Rule $rule -Event $sample) {
                    $matchedRule = "$($rule.Type): $($rule.Name)"
                    $result = "Allowed"
                    break
                }
            }
        }

        [PSCustomObject]@{
            FilePath = $sample.FilePath
            Publisher = $sample.Publisher
            FileHash = $sample.FileHash
            ProductName = $sample.ProductName
            TimesSeen = [int]$timesSeen
            Result = $result
            MatchedRule = if ($matchedRule) { $matchedRule } else { "None" }
        }
    }

    $summary = [PSCustomObject]@{
        TotalApps = $results.Count
        Allowed = ($results | Where-Object { $_.Result -eq "Allowed" }).Count
        Blocked = ($results | Where-Object { $_.Result -eq "Blocked" }).Count
        NoMatch = ($results | Where-Object { $_.Result -eq "NoMatch" }).Count
    }

    return [PSCustomObject]@{
        Results = $results | Sort-Object TimesSeen -Descending
        Summary = $summary
    }
}

function Export-AppLockerSimulationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results,

        [Parameter(Mandatory = $true)]
        [psobject]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [ValidateSet("Csv", "Text")]
        [string]$Format = "Csv"
    )

    if ($Format -eq "Csv") {
        $Results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        return
    }

    $topAllowed = $Results | Where-Object { $_.Result -eq "Allowed" } | Select-Object -First 20
    $topBlocked = $Results | Where-Object { $_.Result -eq "Blocked" } | Select-Object -First 20
    $topNoMatch = $Results | Where-Object { $_.Result -eq "NoMatch" } | Select-Object -First 20

    $lines = @()
    $lines += "GA-AppLocker Simulation Report"
    $lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += ""
    $lines += "Summary"
    $lines += "-------"
    $lines += "Total Apps: $($Summary.TotalApps)"
    $lines += "Allowed:    $($Summary.Allowed)"
    $lines += "Blocked:    $($Summary.Blocked)"
    $lines += "No Match:   $($Summary.NoMatch)"
    $lines += ""

    function Add-Section {
        param([string]$Title, [array]$Items)
        $lines += $Title
        $lines += ("-" * $Title.Length)
        if (-not $Items -or $Items.Count -eq 0) {
            $lines += "  (none)"
            $lines += ""
            return
        }
        foreach ($item in $Items) {
            $lines += "  $($item.Result) | $($item.TimesSeen) | $($item.FilePath)"
        }
        $lines += ""
    }

    Add-Section -Title "Top Allowed Applications" -Items $topAllowed
    Add-Section -Title "Top Blocked Applications" -Items $topBlocked
    Add-Section -Title "Top No-Match Applications" -Items $topNoMatch

    $lines += "Recommendations"
    $lines += "---------------"
    if ($Summary.NoMatch -gt 0) {
        $lines += "- Review no-match applications and add publisher/hash/path rules as needed."
    }
    if ($Summary.Blocked -gt 0) {
        $lines += "- Validate blocked applications are expected before enforcing policy."
    }
    if ($Summary.Allowed -eq 0) {
        $lines += "- No allow matches detected; verify policy scoping and rule conditions."
    }
    $lines += ""

    $lines | Out-File -FilePath $OutputPath -Encoding UTF8
}

Export-ModuleMember -Function Get-NormalizedAppLockerEvents, Get-AppLockerRulesFromPolicy, Invoke-AppLockerSimulation, Export-AppLockerSimulationReport
