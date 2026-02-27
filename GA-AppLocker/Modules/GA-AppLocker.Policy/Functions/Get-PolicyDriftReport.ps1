function Get-PolicyDriftReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [object[]]$Events,
        [object[]]$Rules,
        [string]$PolicyId,
        [int]$StaleAfterHours = 24,
        [switch]$RecordTelemetry
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $eventList = if ($Events) { @($Events) } else { @() }

        $ruleCollection = [System.Collections.Generic.List[object]]::new()

        if ($PSBoundParameters.ContainsKey('Rules') -and $Rules) {
            foreach ($rule in @($Rules)) {
                if ($rule) { [void]$ruleCollection.Add($rule) }
            }
        }
        elseif ($PolicyId) {
            $policyResult = $null
            if (Get-Command -Name 'Get-Policy' -ErrorAction SilentlyContinue) {
                try {
                    $policyResult = Get-Policy -PolicyId $PolicyId -ErrorAction Stop
                }
                catch {
                    if (Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue) {
                        $msg = 'Failed to retrieve policy {0}: {1}' -f $PolicyId, $_.Exception.Message
                        Write-PolicyLog -Level 'Warning' -Message $msg
                    }
                }
            }
            if ($policyResult -and $policyResult.Success -and $policyResult.Data -and $policyResult.Data.RuleIds) {
                foreach ($ruleId in @($policyResult.Data.RuleIds)) {
                    if (-not $ruleId) { continue }
                    try {
                        $ruleResult = Get-Rule -Id $ruleId -ErrorAction Stop
                        if ($ruleResult -and $ruleResult.Success -and $ruleResult.Data) {
                            [void]$ruleCollection.Add($ruleResult.Data)
                        }
                    }
                    catch {
                        if (Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue) {
                            $msg = 'Failed to load rule {0} for policy {1}: {2}' -f $ruleId, $PolicyId, $_.Exception.Message
                            Write-PolicyLog -Level 'Warning' -Message $msg
                        }
                    }
                }
            }
        }
        else {
            try {
                if (Get-Command -Name 'Get-Rule' -ErrorAction SilentlyContinue) {
                    $approvedRuleResult = Get-Rule -Status Approved -ErrorAction Stop
                    if ($approvedRuleResult -and $approvedRuleResult.Success -and $approvedRuleResult.Data) {
                        foreach ($rule in @($approvedRuleResult.Data)) {
                            if ($rule) { [void]$ruleCollection.Add($rule) }
                        }
                    }
                }
            }
            catch {
                if (Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue) {
                    $msg = 'Fallback approved rule load failed: {0}' -f $_.Exception.Message
                    Write-PolicyLog -Level 'Warning' -Message $msg
                }
            }
        }

        $categorizationResult = Invoke-AppLockerEventCategorization -Events $eventList -Rules $ruleCollection -WorkingPolicyId $PolicyId -ErrorAction Stop
        if (-not $categorizationResult -or -not $categorizationResult.Success -or -not $categorizationResult.Data) {
            throw 'Event categorization did not return usable data.'
        }

        $categorizedEvents = if ($categorizationResult.Data.Events) { @($categorizationResult.Data.Events) } else { @() }
        $gaps = [System.Collections.Generic.List[object]]::new()
        foreach ($evt in $categorizedEvents) {
            if ($evt -and $evt.CoverageStatus -and ($evt.CoverageStatus -eq 'Uncovered')) {
                [void]$gaps.Add($evt)
            }
        }

        $summarySource = $categorizationResult.Data.Summary
        $totalEvents = if ($summarySource -and $summarySource.PSObject.Properties.Name -contains 'TotalEvents') { $summarySource.TotalEvents } else { $categorizedEvents.Count }
        $coveredCount = if ($summarySource -and $summarySource.PSObject.Properties.Name -contains 'CoveredCount') { $summarySource.CoveredCount } else { 0 }
        $partialCount = if ($summarySource -and $summarySource.PSObject.Properties.Name -contains 'PartialCount') { $summarySource.PartialCount } else { 0 }
        $uncoveredCount = if ($summarySource -and $summarySource.PSObject.Properties.Name -contains 'UncoveredCount') { $summarySource.UncoveredCount } else { 0 }
        $coveragePercentage = if ($summarySource -and $summarySource.PSObject.Properties.Name -contains 'CoveragePercentage') { $summarySource.CoveragePercentage } else { 0 }

        $lastEventTime = $null
        foreach ($evt in $categorizedEvents) {
            if (-not $evt) { continue }

            $timestamp = $null
            if ($evt.PSObject.Properties.Name -contains 'TimeCreated') {
                $timestamp = $evt.TimeCreated
            }
            elseif ($evt.PSObject.Properties.Name -contains 'Timestamp') {
                $timestamp = $evt.Timestamp
            }

            if ($timestamp) {
                try {
                    $candidate = [datetime]$timestamp
                    if (-not $lastEventTime -or $candidate -gt $lastEventTime) {
                        $lastEventTime = $candidate
                    }
                }
                catch {
                    # ignore parse failures
                }
            }
        }

        $stalenessStatus = 'Unknown'
        if ($lastEventTime) {
            $age = (Get-Date) - $lastEventTime
            if ($age.TotalHours -le $StaleAfterHours) {
                $stalenessStatus = 'Fresh'
            }
            else {
                $stalenessStatus = 'Stale'
            }
        }

        $finalSummary = [PSCustomObject]@{
            TotalEvents         = $totalEvents
            CoveredCount        = $coveredCount
            PartialCount        = $partialCount
            UncoveredCount      = $uncoveredCount
            CoveragePercentage  = $coveragePercentage
            GapCount            = $gaps.Count
            StalenessStatus     = $stalenessStatus
            LastEventTime       = $lastEventTime
        }

        $policyRuleCount = $ruleCollection.Count
        $dataObject = [PSCustomObject]@{
            PolicyId         = $PolicyId
            PolicyRuleCount  = $policyRuleCount
            Rules            = @($ruleCollection.ToArray())
            Events           = $categorizedEvents
            Gaps             = @()
            Summary          = $finalSummary
        }

        $dataObject.Gaps = @($gaps.ToArray())

        if (Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue) {
            $targetLabel = if ($PolicyId) { $PolicyId } else { 'unspecified policy' }
            Write-PolicyLog -Message "Policy drift calculated for $targetLabel" -Level 'Debug'
        }

        if ($RecordTelemetry) {
            $telemetryDetails = @{
                PolicyId           = $PolicyId
                GapCount           = $gaps.Count
                CoveragePercentage = $coveragePercentage
            }
            $detailsJson = $telemetryDetails | ConvertTo-Json -Compress

            try {
                Write-AuditLog -Action 'PolicyDriftCalculated' -Category 'Policy' -TargetId $PolicyId -Details $detailsJson | Out-Null
            }
            catch {
                if (Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue) {
                    $msg = 'Telemetry logging skipped: {0}' -f $_.Exception.Message
                    Write-PolicyLog -Level 'Warning' -Message $msg
                }
            }
        }

        $result.Success = $true
        $result.Data = $dataObject
    }
    catch {
        $result.Error = "Policy drift report failed: $($_.Exception.Message)"
        if (Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue) {
            Write-PolicyLog -Level 'Error' -Message $result.Error
        }
    }

    return $result
}
