function Add-RuleToPolicy {
    <#
    .SYNOPSIS
        Adds one or more rules to a policy.

    .DESCRIPTION
        Adds one or more rules to a policy.

    .PARAMETER PolicyId
        The unique identifier of policy.

    .PARAMETER RuleId
        The rule ID(s) to add.

    .EXAMPLE
        Add-RuleToPolicy -PolicyId "abc123" -RuleId "rule1", "rule2"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [string[]]$RuleId
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'
        $policyFile = Join-Path $policiesPath "$PolicyId.json"

        if (-not (Test-Path $policyFile)) {
            return @{
                Success = $false
                Error   = "Policy not found: $PolicyId"
            }
        }

        $policy = Get-Content -Path $policyFile -Raw | ConvertFrom-Json

        # Ensure RuleIds is an array
        if (-not $policy.RuleIds) {
            $policy | Add-Member -NotePropertyName 'RuleIds' -NotePropertyValue @() -Force
        }

        $currentRules = [System.Collections.Generic.List[string]]::new()
        foreach ($existingId in @($policy.RuleIds)) {
            if ($existingId) { [void]$currentRules.Add([string]$existingId) }
        }
        $addedCount = 0

        foreach ($id in $RuleId) {
            if (-not $currentRules.Contains($id)) {
                [void]$currentRules.Add($id)
                $addedCount++
            }
        }

        $policy.RuleIds = @($currentRules)
        $policy.ModifiedAt = (Get-Date).ToString('o')
        $currentVersion = if ($policy.Version) { [int]$policy.Version } else { 0 }
        $policy.Version = $currentVersion + 1

        $policy | ConvertTo-Json -Depth 5 | Set-Content -Path $policyFile -Encoding UTF8

        # Update policy index
        try {
            Initialize-PolicyIndex
            $indexEntry = [PSCustomObject]@{
                PolicyId        = $policy.PolicyId
                Name            = $policy.Name
                Description     = $policy.Description
                EnforcementMode = $policy.EnforcementMode
                Phase           = $policy.Phase
                Status          = $policy.Status
                RuleIds         = @($policy.RuleIds)
                TargetOUs       = if ($policy.TargetOUs) { @($policy.TargetOUs) } else { @() }
                TargetGPO       = $policy.TargetGPO
                CreatedAt       = $policy.CreatedAt
                ModifiedAt      = $policy.ModifiedAt
                Version         = $policy.Version
                FilePath        = $policyFile
            }
            $null = Add-PolicyIndexEntry -Entry $indexEntry -SkipSave
            Save-PolicyIndex
        }
        catch {
            # Index update failure should not block rule addition
            Write-PolicyLog -Message "Failed to update policy index for rule addition: $($_.Exception.Message)" -Level 'WARNING'
        }

        # Invalidate GlobalSearch cache
        if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
            Clear-AppLockerCache -Pattern "GlobalSearch_*" | Out-Null
        }

        return @{
            Success = $true
            Data    = $policy
            Message = "Added $addedCount rule(s) to policy"
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Remove-RuleFromPolicy {
    <#
    .SYNOPSIS
        Removes one or more rules from a policy.

    .DESCRIPTION
        Removes one or more rules from a policy.

    .PARAMETER PolicyId
        The unique identifier of policy.

    .PARAMETER RuleId
        The rule ID(s) to remove.

    .EXAMPLE
        Remove-RuleFromPolicy -PolicyId "abc123" -RuleId "rule1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [string[]]$RuleId
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'
        $policyFile = Join-Path $policiesPath "$PolicyId.json"

        if (-not (Test-Path $policyFile)) {
            return @{
                Success = $false
                Error   = "Policy not found: $PolicyId"
            }
        }

        $policy = Get-Content -Path $policyFile -Raw | ConvertFrom-Json

        $currentRules = @($policy.RuleIds)
        $removedCount = 0

        foreach ($id in $RuleId) {
            if ($id -in $currentRules) {
                $currentRules = $currentRules | Where-Object { $_ -ne $id }
                $removedCount++
            }
        }

        $policy.RuleIds = @($currentRules)
        $policy.ModifiedAt = (Get-Date).ToString('o')
        $currentVersion = if ($policy.Version) { [int]$policy.Version } else { 0 }
        $policy.Version = $currentVersion + 1

        $policy | ConvertTo-Json -Depth 5 | Set-Content -Path $policyFile -Encoding UTF8

        # Update policy index
        try {
            Initialize-PolicyIndex
            $indexEntry = [PSCustomObject]@{
                PolicyId        = $policy.PolicyId
                Name            = $policy.Name
                Description     = $policy.Description
                EnforcementMode = $policy.EnforcementMode
                Phase           = $policy.Phase
                Status          = $policy.Status
                RuleIds         = @($policy.RuleIds)
                TargetOUs       = if ($policy.TargetOUs) { @($policy.TargetOUs) } else { @() }
                TargetGPO       = $policy.TargetGPO
                CreatedAt       = $policy.CreatedAt
                ModifiedAt      = $policy.ModifiedAt
                Version         = $policy.Version
                FilePath        = $policyFile
            }
            $null = Add-PolicyIndexEntry -Entry $indexEntry -SkipSave
            Save-PolicyIndex
        }
        catch {
            # Index update failure should not block rule removal
            Write-PolicyLog -Message "Failed to update policy index for rule removal: $($_.Exception.Message)" -Level 'WARNING'
        }

        # Invalidate GlobalSearch cache
        if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
            Clear-AppLockerCache -Pattern "GlobalSearch_*" | Out-Null
        }

        return @{
            Success = $true
            Data    = $policy
            Message = "Removed $removedCount rule(s) from policy"
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
