#region ===== AUDIT TRAIL FUNCTIONS =====
<#
.SYNOPSIS
    Multi-user audit trail for tracking all actions in GA-AppLocker.

.DESCRIPTION
    Records user actions with timestamps, user identity, action type,
    target objects, and details. Supports querying, filtering, and
    export of audit logs.


    .EXAMPLE
    Write-AuditLog
    # Write AuditLog
    #>

function Write-AuditLog {
    <#
    .SYNOPSIS
        Writes an entry to the audit trail.

    .DESCRIPTION
        Writes an entry to the audit trail. Writes a timestamped entry to the log.

    .PARAMETER Action
        The action performed (e.g., 'RuleApproved', 'PolicyDeployed').

    .PARAMETER Category
        Category of action: Rule, Policy, Scan, Machine, Credential, System.

    .PARAMETER Target
        The target object (rule name, policy name, machine name, etc.).

    .PARAMETER TargetId
        The unique ID of the target object.

    .PARAMETER Details
        Additional details about the action.

    .PARAMETER OldValue
        Previous value (for changes).

    .PARAMETER NewValue
        New value (for changes).

    .EXAMPLE
        Write-AuditLog -Action 'RuleApproved' -Category 'Rule' -Target 'Microsoft Office' -TargetId 'rule-123'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [Parameter(Mandatory)]
        [ValidateSet('Rule', 'Policy', 'Scan', 'Machine', 'Credential', 'System', 'Config')]
        [string]$Category,

        [string]$Target,
        [string]$TargetId,
        [string]$Details,
        [string]$OldValue,
        [string]$NewValue
    )

    try {
        $auditPath = Get-AuditLogPath
        $auditDir = Split-Path $auditPath -Parent

        if (-not (Test-Path $auditDir)) {
            New-Item -Path $auditDir -ItemType Directory -Force | Out-Null
        }

        # Create audit entry
        $entry = [PSCustomObject]@{
            Id = [guid]::NewGuid().ToString()
            Timestamp = (Get-Date).ToString('o')
            User = "$env:USERDOMAIN\$env:USERNAME"
            Computer = $env:COMPUTERNAME
            Action = $Action
            Category = $Category
            Target = $Target
            TargetId = $TargetId
            Details = $Details
            OldValue = $OldValue
            NewValue = $NewValue
        }

        # JSONL format: one JSON object per line, append-only for O(1) writes
        $jsonLine = ($entry | ConvertTo-Json -Depth 5 -Compress) + "`r`n"
        [System.IO.File]::AppendAllText($auditPath, $jsonLine)

        # Periodic truncation: enforce 10K entry cap every 100 writes
        # Check line count only occasionally to avoid perf hit on every write
        $lineCount = 0
        try {
            $reader = [System.IO.File]::OpenText($auditPath)
            try {
                while ($null -ne $reader.ReadLine()) { $lineCount++ }
            }
            finally { $reader.Close() }
        }
        catch { $lineCount = 0 }

        if ($lineCount -gt 10000) {
            # Read all lines, keep last 10000, rewrite
            $allLines = [System.IO.File]::ReadAllLines($auditPath)
            $keepLines = $allLines[($allLines.Count - 10000)..($allLines.Count - 1)]
            [System.IO.File]::WriteAllLines($auditPath, $keepLines)
        }

        return @{
            Success = $true
            Data = $entry
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Get-AuditLog {
    <#
    .SYNOPSIS
        Retrieves audit log entries with optional filtering.

    .DESCRIPTION
        Retrieves audit log entries with optional filtering. Returns the requested data in a standard result object.

    .PARAMETER Category
        Filter by category.

    .PARAMETER Action
        Filter by action type.

    .PARAMETER User
        Filter by user.

    .PARAMETER Target
        Filter by target (partial match).

    .PARAMETER StartDate
        Filter entries from this date.

    .PARAMETER EndDate
        Filter entries until this date.

    .PARAMETER Last
        Return only the last N entries.

    .EXAMPLE
        Get-AuditLog -Category 'Rule' -Last 50
    #>
    [CmdletBinding()]
    param(
        [string]$Category,
        [string]$Action,
        [string]$User,
        [string]$Target,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [int]$Last = 100
    )

    try {
        $auditPath = Get-AuditLogPath

        if (-not (Test-Path $auditPath)) {
            return @{
                Success = $true
                Data = @()
                Error = $null
            }
        }

        # Read JSONL format (one JSON object per line) with fallback for legacy JSON array
        $auditLog = @()
        $content = Get-Content $auditPath -Raw -ErrorAction SilentlyContinue
        if (-not $content) {
            return @{
                Success = $true
                Data = @()
                Error = $null
            }
        }

        $trimmed = $content.TrimStart()
        if ($trimmed.StartsWith('[')) {
            # Legacy JSON array format -- read normally
            $auditLog = @($content | ConvertFrom-Json)
        }
        else {
            # JSONL format -- parse line by line
            $lines = [System.IO.File]::ReadAllLines($auditPath)
            $parsed = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($line in $lines) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    try { $parsed.Add(($line | ConvertFrom-Json)) } catch { Write-AppLockerLog -Message "Failed to parse audit log line: $($_.Exception.Message)" -Level 'DEBUG' }
                }
            }
            $auditLog = $parsed.ToArray()
        }

        # Apply filters
        if ($Category) {
            $auditLog = @($auditLog | Where-Object { $_.Category -eq $Category })
        }
        if ($Action) {
            $auditLog = @($auditLog | Where-Object { $_.Action -eq $Action })
        }
        if ($User) {
            $auditLog = @($auditLog | Where-Object { $_.User -like "*$User*" })
        }
        if ($Target) {
            $auditLog = @($auditLog | Where-Object { $_.Target -like "*$Target*" })
        }
        if ($StartDate) {
            $auditLog = @($auditLog | Where-Object { [datetime]$_.Timestamp -ge $StartDate })
        }
        if ($EndDate) {
            $auditLog = @($auditLog | Where-Object { [datetime]$_.Timestamp -le $EndDate })
        }

        # Sort by timestamp descending and take last N
        $auditLog = @($auditLog | Sort-Object { [datetime]$_.Timestamp } -Descending | Select-Object -First $Last)

        return @{
            Success = $true
            Data = $auditLog
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = @()
            Error = $_.Exception.Message
        }
    }
}

function Export-AuditLog {
    <#
    .SYNOPSIS
        Exports audit log to CSV or JSON file.

    .DESCRIPTION
        Exports audit log to CSV or JSON file. Writes output to the specified path.

    .PARAMETER OutputPath
        Path to save the export file.

    .PARAMETER Format
        Export format: CSV or JSON.

    .PARAMETER Category
        Filter by category before export.

    .PARAMETER StartDate
        Filter entries from this date.

    .PARAMETER EndDate
        Filter entries until this date.

    .EXAMPLE
        Export-AuditLog -OutputPath 'C:\AuditExport.csv' -Format CSV -StartDate (Get-Date).AddDays(-30)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [ValidateSet('CSV', 'JSON')]
        [string]$Format = 'CSV',

        [string]$Category,
        [datetime]$StartDate,
        [datetime]$EndDate
    )

    try {
        $params = @{ Last = 999999 }
        if ($Category) { $params.Category = $Category }
        if ($StartDate) { $params.StartDate = $StartDate }
        if ($EndDate) { $params.EndDate = $EndDate }

        $result = Get-AuditLog @params
        if (-not $result.Success) {
            return $result
        }

        $auditLog = $result.Data

        if ($Format -eq 'CSV') {
            $auditLog | Export-Csv -Path $OutputPath -NoTypeInformation -Force
        }
        else {
            $auditLog | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Force
        }

        return @{
            Success = $true
            Data = @{
                Path = $OutputPath
                Count = $auditLog.Count
                Format = $Format
            }
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Clear-AuditLog {
    <#
    .SYNOPSIS
        Clears audit log entries older than specified days.

    .DESCRIPTION
        Clears audit log entries older than specified days. Removes all matching items.

    .PARAMETER DaysToKeep
        Number of days of entries to keep.

    .EXAMPLE
        Clear-AuditLog -DaysToKeep 90
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$DaysToKeep
    )

    try {
        $auditPath = Get-AuditLogPath

        if (-not (Test-Path $auditPath)) {
            return @{
                Success = $true
                Data = @{ Removed = 0; Remaining = 0 }
                Error = $null
            }
        }

        # Read entries (supports both JSONL and legacy JSON array)
        $getResult = Get-AuditLog -Last 999999
        if (-not $getResult.Success) {
            return $getResult
        }
        $auditLog = @($getResult.Data)
        $originalCount = $auditLog.Count

        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $auditLog = @($auditLog | Where-Object { [datetime]$_.Timestamp -gt $cutoffDate })

        # Rewrite as JSONL
        $lines = $auditLog | ForEach-Object { ($_ | ConvertTo-Json -Depth 5 -Compress) }
        [System.IO.File]::WriteAllLines($auditPath, $lines)

        # Audit the cleanup itself
        Write-AuditLog -Action 'AuditLogCleanup' -Category 'System' `
            -Details "Removed $($originalCount - $auditLog.Count) entries older than $DaysToKeep days" | Out-Null

        return @{
            Success = $true
            Data = @{
                Removed = $originalCount - $auditLog.Count
                Remaining = $auditLog.Count
            }
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Get-AuditLogPath {
    <#
    .SYNOPSIS
        Gets the path to the audit log file.

    .DESCRIPTION
        Gets the path to the audit log file. Returns the requested data in a standard result object.
    #>
    $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
        Get-AppLockerDataPath
    } else {
        Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
    }
    return Join-Path $dataPath 'AuditTrail\audit-log.json'
}

function Get-AuditLogSummary {
    <#
    .SYNOPSIS
        Gets a summary of audit log activity.

    .DESCRIPTION
        Gets a summary of audit log activity. Returns the requested data in a standard result object.

    .PARAMETER Days
        Number of days to include in summary.

    .EXAMPLE
        Get-AuditLogSummary -Days 7
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 7
    )

    try {
        $result = Get-AuditLog -StartDate (Get-Date).AddDays(-$Days) -Last 999999

        if (-not $result.Success) {
            return $result
        }

        $entries = $result.Data

        $summary = [PSCustomObject]@{
            TotalEntries = $entries.Count
            Period = "$Days days"
            ByCategory = $entries | Group-Object Category | ForEach-Object {
                [PSCustomObject]@{
                    Category = $_.Name
                    Count = $_.Count
                }
            }
            ByUser = $entries | Group-Object User | ForEach-Object {
                [PSCustomObject]@{
                    User = $_.Name
                    Count = $_.Count
                }
            }
            ByAction = $entries | Group-Object Action | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
                [PSCustomObject]@{
                    Action = $_.Name
                    Count = $_.Count
                }
            }
            RecentActivity = $entries | Select-Object -First 5
        }

        return @{
            Success = $true
            Data = $summary
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion
