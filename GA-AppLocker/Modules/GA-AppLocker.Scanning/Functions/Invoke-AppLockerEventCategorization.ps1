function Invoke-AppLockerEventCategorization {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Events,

        [Parameter()]
        [object[]]$Rules,

        [Parameter()]
        [string]$WorkingPolicyId
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $eventCollection = if ($Events) { @($Events) } else { @() }

        if ($PSBoundParameters.ContainsKey('Rules')) {
            $ruleSet = @($Rules | Where-Object { $_ -and $_.Status -eq 'Approved' })
        }
        else {
            try {
                $ruleSet = @()
                if (Get-Command -Name 'Get-Rule' -ErrorAction SilentlyContinue) {
                    $approvedRuleResult = Get-Rule -Status Approved -ErrorAction Stop
                    if ($approvedRuleResult -and $approvedRuleResult.Success -and $approvedRuleResult.Data) {
                        $ruleSet = @($approvedRuleResult.Data)
                    }
                }
            }
            catch {
                $ruleSet = @()
            }
        }

        $ruleSet = if ($ruleSet) { @($ruleSet) } else { @() }

        $totalEvents = $eventCollection.Count
        [int]$knownGoodCount   = 0
        [int]$knownBadCount    = 0
        [int]$needsReviewCount = 0
        [int]$uncategorizedCount = 0
        [int]$coveredCount     = 0
        [int]$partialCount     = 0
        [int]$uncoveredCount   = 0

        $enrichedEvents = [System.Collections.Generic.List[object]]::new()

        foreach ($event in $eventCollection) {
            $allowMatches = [System.Collections.Generic.List[object]]::new()
            $denyMatches  = [System.Collections.Generic.List[object]]::new()

            if ($null -eq $event -or -not $event.PSObject) {
                continue
            }

            $eventPath = if ($event.PSObject.Properties.Name -contains 'FilePath' -and $event.FilePath) { $event.FilePath } else { $null }
            $hashValue = if ($event.SHA256Hash) { $event.SHA256Hash } elseif ($event.Hash) { $event.Hash } elseif ($event.HashValue) { $event.HashValue } else { $null }
            $hasPath = -not [string]::IsNullOrWhiteSpace($eventPath)

            foreach ($rule in $ruleSet) {
                if (-not $rule) { continue }

                $matched = $false

                $ruleType = if ($rule.RuleType) { [string]$rule.RuleType } else { '' }
                switch ($ruleType) {
                    'Hash' {
                        $ruleHash = if ($rule.Hash) { $rule.Hash } elseif ($rule.HashValue) { $rule.HashValue } else { $null }
                        if ($ruleHash -and $hashValue) {
                            if ([string]::Compare($ruleHash, $hashValue, [System.StringComparison]::InvariantCultureIgnoreCase) -eq 0) {
                                $matched = $true
                            }
                        }
                    }
                    'Path' {
                        if ($hasPath -and $rule.Path) {
                            $pattern = $rule.Path
                            $tokenMap = @{ '%OSDRIVE%' = $env:SystemDrive; '%WINDIR%' = $env:windir; '%SYSTEM32%' = "$env:windir\System32"; '%PROGRAMFILES%' = $env:ProgramFiles; '%REMOVABLE%' = '*'; '%HOT%' = '*' }
                            foreach ($token in $tokenMap.Keys) {
                                $replacement = $tokenMap[$token]
                                if (-not $replacement) {
                                    $replacement = '*'
                                }

                                $pattern = [regex]::Replace(
                                    $pattern,
                                    "(?i)" + [regex]::Escape($token),
                                    { param($match) return $replacement }
                                )
                            }

                            $matched = $eventPath -like $pattern
                        }
                    }
                    'Publisher' {
                        $eventPublisher = if ($event.PublisherName) { $event.PublisherName } elseif ($event.Publisher) { $event.Publisher } else { $null }
                        if ($eventPublisher -and $rule.PublisherName) {
                            if ([string]::Compare($eventPublisher, $rule.PublisherName, [System.StringComparison]::InvariantCultureIgnoreCase) -eq 0) {
                                $ruleProduct = if ($rule.ProductName) { $rule.ProductName } else { '*' }
                                $eventProduct = if ($event.ProductName) { $event.ProductName } else { $null }
                                $productMatches = ($ruleProduct -eq '*') -or ($eventProduct -and ([string]::Compare($eventProduct, $ruleProduct, [System.StringComparison]::InvariantCultureIgnoreCase) -eq 0))

                                $ruleBinary = if ($rule.BinaryName) { $rule.BinaryName } else { '*' }
                                $eventBinary = if ($event.BinaryName) { $event.BinaryName } elseif ($event.FileName) { $event.FileName } else { $null }
                                $binaryMatches = ($ruleBinary -eq '*') -or ($eventBinary -and ([string]::Compare($eventBinary, $ruleBinary, [System.StringComparison]::InvariantCultureIgnoreCase) -eq 0))

                                if ($productMatches -and $binaryMatches) {
                                    $matched = $true
                                }
                            }
                        }
                    }
                }

                if ($matched) {
                    $action = if ($rule.Action) { $rule.Action } else { 'Allow' }
                    if ($action -ieq 'Allow') {
                        [void]$allowMatches.Add($rule)
                    }
                    elseif ($action -ieq 'Deny') {
                        [void]$denyMatches.Add($rule)
                    }
                }
            }

            $coverageStatus = 'Uncovered'
            $category = 'NeedsReview'
            $reason = 'No matching rules'

            if (-not $hasPath) {
                $category = 'Uncategorized'
                $reason = 'Missing FilePath'
            }
            elseif ($allowMatches.Count -gt 0) {
                $coverageStatus = 'Covered'
                $category = 'KnownGood'
                $reason = "Matched allow rule $(Format-AppLockerEventRuleReference -Rule $allowMatches[0])"
            }
            elseif ($denyMatches.Count -gt 0) {
                $coverageStatus = 'Partial'
                $category = 'NeedsReview'
                $reason = "Matched deny rule $(Format-AppLockerEventRuleReference -Rule $denyMatches[0])"
            }
            else {
                $coverageStatus = 'Uncovered'
                if ($event.IsBlocked) {
                    $category = 'KnownBad'
                    $reason = 'Blocked event without matching rules'
                }
                elseif ($event.IsAudit) {
                    $category = 'NeedsReview'
                    $reason = 'Audit event without matching rules'
                }
                else {
                    $category = 'NeedsReview'
                    $reason = 'No matching rules'
                }
            }

            switch ($coverageStatus) {
                'Covered' { $coveredCount++ }
                'Partial' { $partialCount++ }
                'Uncovered' { $uncoveredCount++ }
            }

            switch ($category) {
                'KnownGood' { $knownGoodCount++ }
                'KnownBad' { $knownBadCount++ }
                'NeedsReview' { $needsReviewCount++ }
                'Uncategorized' { $uncategorizedCount++ }
            }

            $eventProps = @{}
            foreach ($property in $event.PSObject.Properties) {
                $eventProps[$property.Name] = $property.Value
            }

            $eventProps['CoverageStatus']   = $coverageStatus
            $eventProps['Category']         = $category
            $eventProps['CategorizationReason'] = $reason

            $enrichedEvent = [PSCustomObject]$eventProps
            [void]$enrichedEvents.Add($enrichedEvent)
        }

        $coveragePercentage = if ($totalEvents -gt 0) {
            [math]::Round(($coveredCount / $totalEvents) * 100, 2)
        }
        else {
            0
        }

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            Events          = @($enrichedEvents)
            Summary         = [PSCustomObject]@{
                TotalEvents       = $totalEvents
                KnownGoodCount    = $knownGoodCount
                KnownBadCount     = $knownBadCount
                NeedsReviewCount  = $needsReviewCount
                UncategorizedCount = $uncategorizedCount
                CoveredCount      = $coveredCount
                PartialCount      = $partialCount
                UncoveredCount    = $uncoveredCount
                CoveragePercentage = $coveragePercentage
            }
            WorkingPolicyId = $WorkingPolicyId
        }
    }
    catch {
        $result.Error = "Event categorization failed: $($_.Exception.Message)"
    }

    return $result
}

function script:Format-AppLockerEventRuleReference {
    param([object]$Rule)

    if (-not $Rule) { return 'unknown' }
    $idOrName = if ($Rule.Id) { $Rule.Id } elseif ($Rule.Name) { $Rule.Name } else { $Rule.RuleType }
    $ruleTypeLabel = if ($Rule.RuleType) { $Rule.RuleType } else { 'Rule' }
    return "$ruleTypeLabel $idOrName"
}
