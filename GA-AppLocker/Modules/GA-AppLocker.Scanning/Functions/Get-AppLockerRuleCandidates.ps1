function Get-AppLockerRuleCandidates {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [object[]]
        $Events,

        [Parameter()]
        [int]
        $MinimumRecurrenceCount = 2,

        [Parameter()]
        [int]
        $MinimumConfidenceScore = 40,

        [Parameter()]
        [int]
        $MaximumCandidates = 100,

        [Parameter()]
        [switch]
        $SkipCoveredCandidates
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $eventsToProcess = @($Events)
        $totalEventsProcessed = 0
        $groups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
        $coverageOnlyKeys = [System.Collections.Generic.HashSet[string]]::new()
        $uncoveredKeys = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($event in $eventsToProcess) {
            if ($null -eq $event) {
                continue
            }

            $totalEventsProcessed++

            $filePathCandidate = $null
            if ($event.PSObject.Properties.Name -contains 'FilePath') {
                $filePathCandidate = $event.FilePath
            }

            if ([string]::IsNullOrWhiteSpace($filePathCandidate) -and ($event.PSObject.Properties.Name -contains 'FileName')) {
                $filePathCandidate = $event.FileName
            }

            if ([string]::IsNullOrWhiteSpace($filePathCandidate) -and ($event.PSObject.Properties.Name -contains 'BinaryName')) {
                $filePathCandidate = $event.BinaryName
            }

            if ([string]::IsNullOrWhiteSpace($filePathCandidate)) {
                $filePathCandidate = 'UnknownPath'
            }

            $normalizedPath = $filePathCandidate.Trim().ToLowerInvariant()
            $hashCandidate = $null
            if ($event.PSObject.Properties.Name -contains 'SHA256Hash') {
                $hashCandidate = $event.SHA256Hash
            }

            if ($hashCandidate) {
                $hashCandidate = $hashCandidate.Trim().ToUpperInvariant()
            }

            $correlationKey = if ($hashCandidate) { "hash:$hashCandidate" } else { "path:$normalizedPath" }
            $isCoveredEvent = $false
            if ($event.PSObject.Properties.Name -contains 'CoverageStatus') {
                $isCoveredEvent = ([string]$event.CoverageStatus).Equals('Covered', 'InvariantCultureIgnoreCase')
            }

            if ($SkipCoveredCandidates -and $isCoveredEvent) {
                [void]$coverageOnlyKeys.Add($correlationKey)
                continue
            }

            [void]$uncoveredKeys.Add($correlationKey)

            if (-not $groups.ContainsKey($correlationKey)) {
                [void]$groups.Add($correlationKey, [System.Collections.Generic.List[object]]::new())
            }

            [void]$groups[$correlationKey].Add($event)
        }

        $coverageFilteredCandidateKeys = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $coverageOnlyKeys) {
            if (-not $uncoveredKeys.Contains($key)) {
                [void]$coverageFilteredCandidateKeys.Add($key)
            }
        }

        $candidateList = [System.Collections.Generic.List[PSCustomObject]]::new()
        $thresholdFilteredCount = 0

        foreach ($groupEntry in $groups.GetEnumerator()) {
            $candidateEvents = $groupEntry.Value
            if ($candidateEvents.Count -eq 0) {
                continue
            }

            $machineSet = [System.Collections.Generic.HashSet[string]]::new()
            $blockedCount = 0
            $auditCount = 0
            $allowedCount = 0
            $latestSeen = $null

            foreach ($entry in $candidateEvents) {
                $machineName = $null
                if ($entry.PSObject.Properties.Name -contains 'ComputerName') {
                    $machineName = $entry.ComputerName
                }

                if ([string]::IsNullOrWhiteSpace($machineName)) {
                    $machineName = 'UnknownMachine'
                }

                [void]$machineSet.Add($machineName.ToUpperInvariant())

                if ($entry.PSObject.Properties.Name -contains 'IsBlocked' -and $entry.IsBlocked) {
                    $blockedCount++
                }

                if ($entry.PSObject.Properties.Name -contains 'IsAudit' -and $entry.IsAudit) {
                    $auditCount++
                }

                if ($entry.PSObject.Properties.Name -contains 'Action' -and ($entry.Action -eq 'Allow')) {
                    $allowedCount++
                }

                if ($entry.PSObject.Properties.Name -contains 'TimeCreated') {
                    $candidateTime = $entry.TimeCreated
                    if ($candidateTime -and ($candidateTime -gt $latestSeen)) {
                        $latestSeen = $candidateTime
                    }
                }
            }

            if (-not $latestSeen) {
                $latestSeen = Get-Date
            }

            $recurrenceCount = $candidateEvents.Count
            $machineCount = $machineSet.Count
            $sampleEvent = $candidateEvents[0]

            $candidateFilePath = $null
            if ($sampleEvent.PSObject.Properties.Name -contains 'FilePath') {
                $candidateFilePath = $sampleEvent.FilePath
            }

            if (-not $candidateFilePath -and $sampleEvent.PSObject.Properties.Name -contains 'FileName') {
                $candidateFilePath = $sampleEvent.FileName
            }

            if (-not $candidateFilePath -and $sampleEvent.PSObject.Properties.Name -contains 'BinaryName') {
                $candidateFilePath = $sampleEvent.BinaryName
            }

            if (-not $candidateFilePath) {
                $candidateFilePath = 'UnknownPath'
            }

            $candidateHash = $null
            if ($sampleEvent.PSObject.Properties.Name -contains 'SHA256Hash') {
                $candidateHash = $sampleEvent.SHA256Hash
            }

            $candidateHash = if ($candidateHash) { $candidateHash.Trim().ToUpperInvariant() } else { $null }

            $candidatePublisher = $null
            if ($sampleEvent.PSObject.Properties.Name -contains 'PublisherName') {
                $candidatePublisher = $sampleEvent.PublisherName
            }

            if (-not $candidatePublisher -and $sampleEvent.PSObject.Properties.Name -contains 'Publisher') {
                $candidatePublisher = $sampleEvent.Publisher
            }

            $candidateProduct = $null
            if ($sampleEvent.PSObject.Properties.Name -contains 'ProductName') {
                $candidateProduct = $sampleEvent.ProductName
            }

            $isSignedCandidate = $false
            if ($sampleEvent.PSObject.Properties.Name -contains 'IsSigned') {
                $isSignedCandidate = [bool]$sampleEvent.IsSigned
            }

            $recurrenceRatio = [math]::Min(1, $recurrenceCount / [math]::Max($MinimumRecurrenceCount, 1))
            $machineSpreadRatio = [math]::Min(1, $machineCount / [math]::Max($recurrenceCount, 1))
            $blockedRatio = [math]::Min(1, ($blockedCount + $auditCount) / [math]::Max($recurrenceCount, 1))

            $recurrenceContribution = [math]::Min(35, $recurrenceRatio * 35)
            $machineContribution = [math]::Min(20, $machineSpreadRatio * 20)
            $blockedContribution = [math]::Min(25, $blockedRatio * 25)

            $publisherBonus = if ($candidatePublisher) { 8 } else { 0 }
            $signedBonus = if ($isSignedCandidate) { 5 } else { 0 }

            $normalizedCandidatePath = ($candidateFilePath -as [string])
            if (-not [string]::IsNullOrWhiteSpace($normalizedCandidatePath)) {
                $normalizedCandidatePath = $normalizedCandidatePath.Trim().ToLowerInvariant()
            }

            $riskyPenalty = 0
            if ($normalizedCandidatePath) {
                if ($normalizedCandidatePath -match '\\temp\\' -or $normalizedCandidatePath -match '\\downloads\\' -or $normalizedCandidatePath -match '\\appdata\\local\\temp\\') {
                    $riskyPenalty = 10
                }
            }

            $confidenceScore = $recurrenceContribution + $machineContribution + $blockedContribution + $publisherBonus + $signedBonus - $riskyPenalty
            $confidenceScore = [math]::Round([math]::Max(0, [math]::Min(100, $confidenceScore)))

            $confidenceLevel = if ($confidenceScore -ge 75) {
                'High'
            }
            elseif ($confidenceScore -ge 45) {
                'Medium'
            }
            else {
                'Low'
            }

            $recommendedRuleType = 'Path'
            if ($candidatePublisher) {
                $recommendedRuleType = 'Publisher'
            }
            elseif ($candidateHash) {
                $recommendedRuleType = 'Hash'
            }

            if ($recurrenceCount -lt $MinimumRecurrenceCount -or $confidenceScore -lt $MinimumConfidenceScore) {
                $thresholdFilteredCount++
                continue
            }

            $candidate = [PSCustomObject]@{
                CorrelationKey     = $groupEntry.Key
                FilePath           = $candidateFilePath
                FileHash           = $candidateHash
                PublisherName      = $candidatePublisher
                ProductName        = $candidateProduct
                RecurrenceCount    = $recurrenceCount
                MachineCount       = $machineCount
                BlockedCount       = $blockedCount
                AuditCount         = $auditCount
                AllowedCount       = $allowedCount
                ConfidenceScore    = $confidenceScore
                ConfidenceLevel    = $confidenceLevel
                RecommendedRuleType = $recommendedRuleType
                LastSeen           = $latestSeen
            }

            [void]$candidateList.Add($candidate)
        }

        $sortedCandidates = $candidateList | Sort-Object @{Expression = { $_.ConfidenceScore }; Descending = $true }, @{Expression = { $_.RecurrenceCount }; Descending = $true }
        $limitedCandidates = [System.Collections.Generic.List[PSCustomObject]]::new()
        $cappedMaximum = [math]::Max(0, $MaximumCandidates)
        foreach ($candidate in $sortedCandidates | Select-Object -First $cappedMaximum) {
            [void]$limitedCandidates.Add($candidate)
        }

        $summary = [PSCustomObject]@{
            TotalEventsProcessed          = $totalEventsProcessed
            GroupsEvaluated               = $groups.Count
            CandidatesGenerated           = $limitedCandidates.Count
            CandidatesFilteredByThreshold = $thresholdFilteredCount
            CandidatesFilteredByCoverage  = $coverageFilteredCandidateKeys.Count
        }

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            Candidates = $limitedCandidates
            Summary    = $summary
        }
    }
    catch {
        $result.Error = "Rule candidate evaluation failed: $($_.Exception.Message)"
    }

    return $result
}
