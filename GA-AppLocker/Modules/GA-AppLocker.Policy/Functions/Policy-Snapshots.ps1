<#
.SYNOPSIS
    Functions for creating and managing policy snapshots (versioned backups).

.DESCRIPTION
    Provides snapshot functionality for AppLocker policies allowing:
    - Point-in-time backups before changes
    - Version history with metadata
    - Easy rollback to previous states
    - Audit trail of policy changes


    .EXAMPLE
    New-PolicySnapshot
    # New PolicySnapshot
    #>

function New-PolicySnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot (backup) of a policy's current state.

    .DESCRIPTION
        Saves a complete copy of the policy including all rules at the current moment.
        Snapshots are stored with timestamps and optional descriptions for auditing.

    .PARAMETER PolicyId
        The ID of the policy to snapshot.

    .PARAMETER Description
        Optional description explaining why this snapshot was created.

    .PARAMETER CreatedBy
        Optional username/identifier of who created the snapshot.

    .EXAMPLE
        New-PolicySnapshot -PolicyId "abc123"
        Creates a snapshot of the policy.

    .EXAMPLE
        New-PolicySnapshot -PolicyId "abc123" -Description "Before adding Chrome rules" -CreatedBy "admin"

    .OUTPUTS
        [PSCustomObject] Snapshot result with Success, Data (snapshot ID), and Error.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId,

        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [string]$CreatedBy = ''
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # Get the policy
        $policyResult = Get-Policy -PolicyId $PolicyId
        if (-not $policyResult.Success) {
            throw "Policy not found: $PolicyId"
        }
        $policy = $policyResult.Data

        # Get all rules for this policy
        $rules = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($policy.RuleIds) {
            foreach ($ruleId in $policy.RuleIds) {
                $ruleResult = Get-Rule -Id $ruleId
                if ($ruleResult.Success) {
                    [void]$rules.Add($ruleResult.Data)
                }
            }
        }
        $snapshot.Rules = @($rules)

        # Create snapshot directory
        $dataPath = Get-AppLockerDataPath
        $snapshotPath = Join-Path $dataPath 'Snapshots'
        if (-not (Test-Path $snapshotPath)) {
            New-Item -Path $snapshotPath -ItemType Directory -Force | Out-Null
        }

        # Create policy-specific snapshot folder
        $policySnapshotPath = Join-Path $snapshotPath $PolicyId
        if (-not (Test-Path $policySnapshotPath)) {
            New-Item -Path $policySnapshotPath -ItemType Directory -Force | Out-Null
        }

        # Generate snapshot ID and timestamp
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $snapshotId = "$($PolicyId)_$timestamp"

        # Create snapshot object
        $snapshot = [PSCustomObject]@{
            SnapshotId   = $snapshotId
            PolicyId     = $PolicyId
            PolicyName   = $policy.Name
            CreatedAt    = (Get-Date).ToString('o')
            CreatedBy    = if ($CreatedBy) { $CreatedBy } else { $env:USERNAME }
            Description  = $Description
            PolicyState  = $policy
            Rules        = $rules
            RuleCount    = $rules.Count
            Version      = (Get-PolicySnapshotCount -PolicyId $PolicyId) + 1
        }

        # Save snapshot
        $snapshotFile = Join-Path $policySnapshotPath "$snapshotId.json"
        $snapshot | ConvertTo-Json -Depth 20 | Set-Content -Path $snapshotFile -Encoding UTF8

        # Publish event if available
        if (Get-Command -Name 'Publish-AppLockerEvent' -ErrorAction SilentlyContinue) {
            Publish-AppLockerEvent -EventName 'SnapshotCreated' -EventData @{
                SnapshotId  = $snapshotId
                PolicyId    = $PolicyId
                Description = $Description
            } | Out-Null
        }

        $result.Data = [PSCustomObject]@{
            SnapshotId  = $snapshotId
            PolicyId    = $PolicyId
            PolicyName  = $policy.Name
            CreatedAt   = $snapshot.CreatedAt
            RuleCount   = $rules.Count
            Version     = $snapshot.Version
        }
        $result.Success = $true

        Write-PolicyLog -Message "Created snapshot $snapshotId for policy '$($policy.Name)' with $($rules.Count) rules"
    }
    catch {
        $result.Error = "Failed to create snapshot: $($_.Exception.Message)"
        Write-PolicyLog -Level Error -Message $result.Error
    }

    return $result
}

function Get-PolicySnapshots {
    <#
    .SYNOPSIS
        Retrieves all snapshots for a policy.

    .DESCRIPTION
        Lists all available snapshots for the specified policy, sorted by creation date.

    .PARAMETER PolicyId
        The ID of the policy to get snapshots for.

    .PARAMETER Limit
        Maximum number of snapshots to return. Default is 50.

    .EXAMPLE
        Get-PolicySnapshots -PolicyId "abc123"

    .EXAMPLE
        Get-PolicySnapshots -PolicyId "abc123" -Limit 10

    .OUTPUTS
        [PSCustomObject] List of snapshots with Success, Data, and Error.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId,

        [Parameter()]
        [int]$Limit = 50
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $dataPath = Get-AppLockerDataPath
        $policySnapshotPath = Join-Path $dataPath "Snapshots\$PolicyId"

        if (-not (Test-Path $policySnapshotPath)) {
            $result.Data = @()
            $result.Success = $true
            return $result
        }

        $snapshotFiles = Get-ChildItem -Path $policySnapshotPath -Filter '*.json' -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Limit

        $snapshots = @()
        foreach ($file in $snapshotFiles) {
            $snapshot = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            
            # Return summary without full rule data for list view
            $snapshots += [PSCustomObject]@{
                SnapshotId   = $snapshot.SnapshotId
                PolicyId     = $snapshot.PolicyId
                PolicyName   = $snapshot.PolicyName
                CreatedAt    = $snapshot.CreatedAt
                CreatedBy    = $snapshot.CreatedBy
                Description  = $snapshot.Description
                RuleCount    = $snapshot.RuleCount
                Version      = $snapshot.Version
            }
        }

        $result.Data = $snapshots
        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to get snapshots: $($_.Exception.Message)"
        Write-PolicyLog -Level Error -Message $result.Error
    }

    return $result
}

function Get-PolicySnapshot {
    <#
    .SYNOPSIS
        Retrieves a specific snapshot with full details.

    .DESCRIPTION
        Gets the complete snapshot including the full policy state and all rules.

    .PARAMETER SnapshotId
        The ID of the snapshot to retrieve.

    .EXAMPLE
        Get-PolicySnapshot -SnapshotId "abc123_20260122_143000"

    .OUTPUTS
        [PSCustomObject] Full snapshot with Success, Data, and Error.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$SnapshotId
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # Extract policy ID from snapshot ID (format: policyId_timestamp)
        $policyId = ($SnapshotId -split '_')[0..($SnapshotId.Split('_').Count - 3)] -join '_'
        if ([string]::IsNullOrEmpty($policyId)) {
            # Fallback: search all snapshot folders
            $dataPath = Get-AppLockerDataPath
            $snapshotPath = Join-Path $dataPath 'Snapshots'
            
            $found = Get-ChildItem -Path $snapshotPath -Recurse -Filter "$SnapshotId.json" -File | Select-Object -First 1
            if ($found) {
                $snapshot = Get-Content -Path $found.FullName -Raw | ConvertFrom-Json
                $result.Data = $snapshot
                $result.Success = $true
                return $result
            }
            throw "Snapshot not found: $SnapshotId"
        }

        $dataPath = Get-AppLockerDataPath
        $snapshotFile = Join-Path $dataPath "Snapshots\$policyId\$SnapshotId.json"

        if (-not (Test-Path $snapshotFile)) {
            throw "Snapshot not found: $SnapshotId"
        }

        $snapshot = Get-Content -Path $snapshotFile -Raw | ConvertFrom-Json
        $result.Data = $snapshot
        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to get snapshot: $($_.Exception.Message)"
        Write-PolicyLog -Level Error -Message $result.Error
    }

    return $result
}

function Restore-PolicySnapshot {
    <#
    .SYNOPSIS
        Restores a policy to a previous snapshot state.

    .DESCRIPTION
        Reverts a policy and its rules to the state captured in a snapshot.
        Automatically creates a new snapshot before restoring for safety.

    .PARAMETER SnapshotId
        The ID of the snapshot to restore.

    .PARAMETER CreateBackup
        If true (default), creates a backup snapshot before restoring.

    .PARAMETER Force
        If specified, skips confirmation for destructive operation.

    .EXAMPLE
        Restore-PolicySnapshot -SnapshotId "abc123_20260122_143000"

    .EXAMPLE
        Restore-PolicySnapshot -SnapshotId "abc123_20260122_143000" -CreateBackup:$false -Force

    .OUTPUTS
        [PSCustomObject] Restore result with Success, Data, and Error.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$SnapshotId,

        [Parameter()]
        [bool]$CreateBackup = $true,

        [Parameter()]
        [switch]$Force
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # Get the snapshot
        $snapshotResult = Get-PolicySnapshot -SnapshotId $SnapshotId
        if (-not $snapshotResult.Success) {
            throw $snapshotResult.Error
        }
        $snapshot = $snapshotResult.Data

        $policyId = $snapshot.PolicyId

        # Create backup before restore
        $backupSnapshotId = $null
        if ($CreateBackup) {
            $backupResult = New-PolicySnapshot -PolicyId $policyId -Description "Auto-backup before restore from $SnapshotId"
            if ($backupResult.Success) {
                $backupSnapshotId = $backupResult.Data.SnapshotId
                Write-PolicyLog -Message "Created backup snapshot: $backupSnapshotId"
            }
        }

        if (-not $Force -and -not $PSCmdlet.ShouldProcess($policyId, "Restore policy to snapshot $SnapshotId")) {
            $result.Error = "Operation cancelled by user"
            return $result
        }

        # Restore policy state
        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'
        $policyFile = Join-Path $policiesPath "$policyId.json"

        # Restore policy with updated metadata
        $restoredPolicy = $snapshot.PolicyState
        $restoredPolicy.ModifiedAt = (Get-Date).ToString('o')
        $restoredPolicy.RestoredFrom = $SnapshotId
        $restoredPolicy.RestoredAt = (Get-Date).ToString('o')

        $restoredPolicy | ConvertTo-Json -Depth 3 | Set-Content -Path $policyFile -Encoding UTF8

        # Restore rules
        $rulesPath = Join-Path $dataPath 'Rules'
        $restoredRuleCount = 0

        foreach ($rule in $snapshot.Rules) {
            $ruleFile = Join-Path $rulesPath "$($rule.Id).json"
            $rule | ConvertTo-Json -Depth 3 | Set-Content -Path $ruleFile -Encoding UTF8
            $restoredRuleCount++
        }

        # Publish event if available
        if (Get-Command -Name 'Publish-AppLockerEvent' -ErrorAction SilentlyContinue) {
            Publish-AppLockerEvent -EventName 'PolicyRestored' -EventData @{
                PolicyId        = $policyId
                SnapshotId      = $SnapshotId
                BackupId        = $backupSnapshotId
                RulesRestored   = $restoredRuleCount
            } | Out-Null
        }

        # Clear cache if available
        if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
            Clear-AppLockerCache -Pattern "Policy:$policyId*" | Out-Null
            Clear-AppLockerCache -Pattern "Rule:*" | Out-Null
        }

        $result.Data = [PSCustomObject]@{
            PolicyId        = $policyId
            PolicyName      = $snapshot.PolicyName
            RestoredFrom    = $SnapshotId
            SnapshotDate    = $snapshot.CreatedAt
            RulesRestored   = $restoredRuleCount
            BackupSnapshotId = $backupSnapshotId
        }
        $result.Success = $true

        Write-PolicyLog -Message "Restored policy '$($snapshot.PolicyName)' from snapshot $SnapshotId ($restoredRuleCount rules)"
    }
    catch {
        $result.Error = "Failed to restore snapshot: $($_.Exception.Message)"
        Write-PolicyLog -Level Error -Message $result.Error
    }

    return $result
}

function Remove-PolicySnapshot {
    <#
    .SYNOPSIS
        Removes a policy snapshot.

    .DESCRIPTION
        Permanently deletes a snapshot. Cannot be undone.

    .PARAMETER SnapshotId
        The ID of the snapshot to remove.

    .PARAMETER Force
        If specified, skips confirmation.

    .EXAMPLE
        Remove-PolicySnapshot -SnapshotId "abc123_20260122_143000"

    .OUTPUTS
        [PSCustomObject] Remove result with Success and Error.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$SnapshotId,

        [Parameter()]
        [switch]$Force
    )

    $result = [PSCustomObject]@{
        Success = $false
        Error   = $null
    }

    try {
        # Get snapshot to find its location
        $snapshotResult = Get-PolicySnapshot -SnapshotId $SnapshotId
        if (-not $snapshotResult.Success) {
            throw $snapshotResult.Error
        }

        $policyId = $snapshotResult.Data.PolicyId
        $dataPath = Get-AppLockerDataPath
        $snapshotFile = Join-Path $dataPath "Snapshots\$policyId\$SnapshotId.json"

        if (-not $Force -and -not $PSCmdlet.ShouldProcess($SnapshotId, "Remove snapshot")) {
            $result.Error = "Operation cancelled by user"
            return $result
        }

        if (Test-Path $snapshotFile) {
            Remove-Item -Path $snapshotFile -Force
            $result.Success = $true
            Write-PolicyLog -Message "Removed snapshot: $SnapshotId"
        }
        else {
            throw "Snapshot file not found"
        }
    }
    catch {
        $result.Error = "Failed to remove snapshot: $($_.Exception.Message)"
        Write-PolicyLog -Level Error -Message $result.Error
    }

    return $result
}

function Get-PolicySnapshotCount {
    <#
    .SYNOPSIS
        Gets the number of snapshots for a policy.

    .DESCRIPTION
        Helper function to count existing snapshots.

    .PARAMETER PolicyId
        The ID of the policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId
    )

    $dataPath = Get-AppLockerDataPath
    $policySnapshotPath = Join-Path $dataPath "Snapshots\$PolicyId"

    if (-not (Test-Path $policySnapshotPath)) {
        return 0
    }

    return (Get-ChildItem -Path $policySnapshotPath -Filter '*.json' -File).Count
}

function Invoke-PolicySnapshotCleanup {
    <#
    .SYNOPSIS
        Removes old snapshots based on retention policy.

    .DESCRIPTION
        Cleans up old snapshots keeping only the specified number of recent ones
        or those within a time window.

    .PARAMETER PolicyId
        The ID of the policy to clean up snapshots for. If not specified, cleans all.

    .PARAMETER KeepCount
        Number of most recent snapshots to keep. Default is 10.

    .PARAMETER KeepDays
        Keep all snapshots from the last N days. Default is 30.

    .PARAMETER WhatIf
        Shows what would be deleted without actually deleting.

    .EXAMPLE
        Invoke-PolicySnapshotCleanup -PolicyId "abc123" -KeepCount 5

    .EXAMPLE
        Invoke-PolicySnapshotCleanup -KeepDays 7

    .OUTPUTS
        [PSCustomObject] Cleanup result with Success, Data (removed count), and Error.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$PolicyId,

        [Parameter()]
        [int]$KeepCount = 10,

        [Parameter()]
        [int]$KeepDays = 30
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $dataPath = Get-AppLockerDataPath
        $snapshotBasePath = Join-Path $dataPath 'Snapshots'

        if (-not (Test-Path $snapshotBasePath)) {
            $result.Data = @{ RemovedCount = 0 }
            $result.Success = $true
            return $result
        }

        $cutoffDate = (Get-Date).AddDays(-$KeepDays)
        $removedCount = 0
        $folders = @()

        if ($PolicyId) {
            $policyPath = Join-Path $snapshotBasePath $PolicyId
            if (Test-Path $policyPath) {
                $folders += Get-Item $policyPath
            }
        }
        else {
            $folders = Get-ChildItem -Path $snapshotBasePath -Directory
        }

        foreach ($folder in $folders) {
            $snapshots = Get-ChildItem -Path $folder.FullName -Filter '*.json' -File |
                Sort-Object LastWriteTime -Descending

            # Keep the most recent $KeepCount
            $toKeep = $snapshots | Select-Object -First $KeepCount
            $candidates = $snapshots | Select-Object -Skip $KeepCount

            foreach ($file in $candidates) {
                # Also check age
                if ($file.LastWriteTime -lt $cutoffDate) {
                    if ($PSCmdlet.ShouldProcess($file.Name, "Remove old snapshot")) {
                        Remove-Item -Path $file.FullName -Force
                        $removedCount++
                    }
                }
            }
        }

        $result.Data = @{
            RemovedCount = $removedCount
            CutoffDate   = $cutoffDate.ToString('o')
            KeepCount    = $KeepCount
        }
        $result.Success = $true

        if ($removedCount -gt 0) {
            Write-PolicyLog -Message "Cleaned up $removedCount old snapshots"
        }
    }
    catch {
        $result.Error = "Failed to cleanup snapshots: $($_.Exception.Message)"
        Write-PolicyLog -Level Error -Message $result.Error
    }

    return $result
}
