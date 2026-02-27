function script:Get-PolicyRuleActionValue {
    param([PSCustomObject]$Rule)

    $action = if ($Rule.Action) { $Rule.Action } else { 'Allow' }
    return $action.ToString().Trim().ToUpperInvariant()
}

function script:Get-PolicyRuleSemanticKey {
    param([PSCustomObject]$Rule)

    if (-not $Rule) { return $null }

    $ruleType = if ($Rule.RuleType) { $Rule.RuleType.ToString().Trim().ToUpperInvariant() } else { '' }
    $collectionType = if ($Rule.CollectionType) { $Rule.CollectionType.ToString().Trim().ToUpperInvariant() } else { '' }
    $principal = if ($Rule.UserOrGroupSid) { $Rule.UserOrGroupSid.ToString().Trim().ToUpperInvariant() } else { 'S-1-1-0' }

    $conditionParts = @()

    switch ($ruleType) {
        'HASH' { $conditionParts += if ($Rule.Hash) { $Rule.Hash.ToString().Trim().ToUpperInvariant() } else { '' } }
        'PATH' { $conditionParts += if ($Rule.Path) { $Rule.Path.ToString().Trim().ToUpperInvariant() } else { '' } }
        'PUBLISHER' {
            $conditionParts += @(
                $(if ($Rule.PublisherName) { $Rule.PublisherName.ToString().Trim().ToUpperInvariant() } else { '' }),
                $(if ($Rule.ProductName) { $Rule.ProductName.ToString().Trim().ToUpperInvariant() } else { '' }),
                $(if ($Rule.BinaryName) { $Rule.BinaryName.ToString().Trim().ToUpperInvariant() } else { '' })
            )
        }
        default { $conditionParts += if ($Rule.Id) { $Rule.Id.ToString().Trim().ToUpperInvariant() } else { '' } }
    }

    $semiKeyParts = @($ruleType, $collectionType, $principal) + $conditionParts
    $normalized = $semiKeyParts | ForEach-Object {
        if ($_ -and $_ -ne '') { $_ } else { '' }
    }

    return ($normalized -join '|')
}

function script:Get-PolicyRulesById {
    param(
        [string[]]$Ids,
        [switch]$ErrorOnMissing
    )

    $rules = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($id in @($Ids | Where-Object { $_ })) {
        $ruleResult = Get-Rule -Id $id
        if (-not $ruleResult.Success) {
            if ($ErrorOnMissing) { throw $ruleResult.Error }
            continue
        }

        if ($ruleResult.Data) { [void]$rules.Add($ruleResult.Data) }
    }

    return $rules.ToArray()
}

function Test-RuleMergeConflicts {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId,

        [Parameter(Mandatory)]
        [string[]]$RuleIds
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data = @{
            HasConflicts = $false
            ConflictCount = 0
            Conflicts = @()
        }
        Error = $null
    }

    try {
        if (-not $RuleIds -or $RuleIds.Count -eq 0) {
            $result.Success = $true
            return $result
        }

        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'
        $policyFile = Join-Path $policiesPath "$PolicyId.json"

        if (-not (Test-Path $policyFile)) {
            throw "Policy not found: $PolicyId"
        }

        $policy = Get-Content -Path $policyFile -Raw | ConvertFrom-Json
        $existingIds = @($policy.RuleIds)

        $existingRules = script:Get-PolicyRulesById -Ids $existingIds
        $incomingRules = script:Get-PolicyRulesById -Ids $RuleIds -ErrorOnMissing

        $existingMap = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[PSCustomObject]]]::new()
        foreach ($rule in $existingRules) {
            $key = script:Get-PolicyRuleSemanticKey -Rule $rule
            if (-not $key) { continue }

            if (-not $existingMap.ContainsKey($key)) {
                $existingMap[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
            }

            [void]$existingMap[$key].Add([PSCustomObject]@{
                Id = $rule.Id
                Action = script:Get-PolicyRuleActionValue -Rule $rule
            })
        }

        $incomingMap = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[PSCustomObject]]]::new()
        foreach ($rule in $incomingRules) {
            $key = script:Get-PolicyRuleSemanticKey -Rule $rule
            if (-not $key) { continue }

            if (-not $incomingMap.ContainsKey($key)) {
                $incomingMap[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
            }

            [void]$incomingMap[$key].Add([PSCustomObject]@{
                Id = $rule.Id
                Action = script:Get-PolicyRuleActionValue -Rule $rule
            })
        }

        $conflicts = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($key in $incomingMap.Keys) {
            if (-not $existingMap.ContainsKey($key)) { continue }

            foreach ($existingEntry in $existingMap[$key]) {
                foreach ($incomingEntry in $incomingMap[$key]) {
                    if ($existingEntry.Action -ne $incomingEntry.Action) {
                        [void]$conflicts.Add([PSCustomObject]@{
                            SemanticKey    = $key
                            PolicyRuleId   = $existingEntry.Id
                            PolicyAction   = $existingEntry.Action
                            IncomingRuleId = $incomingEntry.Id
                            IncomingAction = $incomingEntry.Action
                        })
                    }
                }
            }
        }

        $conflictArray = $conflicts.ToArray()
        if ($conflictArray.Count -gt 0) {
            $result.Data.HasConflicts = $true
            $result.Data.ConflictCount = $conflictArray.Count
            $result.Data.Conflicts = $conflictArray
        }

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}
