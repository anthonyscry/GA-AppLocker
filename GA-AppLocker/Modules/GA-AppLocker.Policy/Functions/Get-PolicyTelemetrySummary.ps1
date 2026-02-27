function Get-PolicyTelemetrySummary {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [string]$PolicyId,
        [int]$Days = 30,
        [int]$Last = 200,
        [switch]$IncludeRawEvents
    )

    $writeLog = Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue

    try {
        if ($writeLog) {
            $targetPolicyLabel = if ($PolicyId) { $PolicyId } else { 'all policies' }
            Write-PolicyLog -Message "Generating policy telemetry summary for $targetPolicyLabel" -Level 'Verbose'
        }

        $startDate = (Get-Date).AddDays(-$Days)
        $auditResponse = Get-AuditLog -Category 'Policy' -StartDate $startDate -Last $Last

        if ($null -eq $auditResponse) {
            throw 'Get-AuditLog returned no data.'
        }

        $events = @()

        if ($auditResponse.PSObject.Properties.Match('Success')) {
            if (-not $auditResponse.Success) {
                $failure = if ($auditResponse.Error) { $auditResponse.Error } else { 'Get-AuditLog reported failure.' }
                throw $failure
            }

            $payload = $auditResponse.Data
            if ($null -ne $payload) {
                if ($payload -is [System.Collections.IEnumerable] -and -not ($payload -is [string])) {
                    $events = @($payload)
                }
                else {
                    $events = @($payload)
                }
            }
        }
        else {
            $events = @($auditResponse)
        }

        $filteredEventList = [System.Collections.Generic.List[object]]::new()

        foreach ($event in $events) {
            if ($null -eq $event) {
                continue
            }

            if ($event.Category -ne 'Policy') {
                continue
            }

            if ($PolicyId -and $event.TargetId -ne $PolicyId) {
                continue
            }

            [void]$filteredEventList.Add($event)
        }

        $filteredEvents = @($filteredEventList.ToArray())

        $totalPolicyEvents = $filteredEvents.Count
        $driftEventList = [System.Collections.Generic.List[object]]::new()

        foreach ($event in $filteredEvents) {
            if ($event.Action -eq 'PolicyDriftCalculated') {
                [void]$driftEventList.Add($event)
            }
        }

        $driftEvents = @($driftEventList.ToArray())

        $driftChecksCount = $driftEvents.Count

        $byAction = [ordered]@{}
        foreach ($group in $filteredEvents | Group-Object -Property Action) {
            $byAction[$group.Name] = $group.Count
        }

        $lastDriftCheck = $null

        if ($driftEvents.Count) {
            $sorted = $driftEvents | Sort-Object {[datetime]$_.Timestamp} -Descending
            $latest = $sorted | Select-Object -First 1
            $gapCount = $null

            if ($latest.Details) {
                try {
                    $parsedDetails = $latest.Details | ConvertFrom-Json
                    if ($parsedDetails -and $parsedDetails.PSObject.Properties.Match('GapCount')) {
                        $gapCount = $parsedDetails.GapCount
                    }
                }
                catch {
                    # ignore parsing errors
                }
            }

            $lastDriftCheck = [PSCustomObject]@{
                Timestamp = if ($latest.Timestamp) { [datetime]$latest.Timestamp } else { $null }
                TargetId  = $latest.TargetId
                Action    = $latest.Action
                GapCount  = $gapCount
            }
        }

        $summary = [ordered]@{
            PeriodDays        = $Days
            PolicyId          = $PolicyId
            TotalPolicyEvents = $totalPolicyEvents
            DriftChecksCount  = $driftChecksCount
            ByAction          = [PSCustomObject]$byAction
            LastDriftCheck    = $lastDriftCheck
        }

        if ($IncludeRawEvents) {
            $summary.RawEvents = $filteredEvents
        }

        if ($writeLog) {
            Write-PolicyLog -Message 'Policy telemetry summary generated.' -Level 'Verbose'
        }

        return [PSCustomObject]@{ Success = $true; Data = [PSCustomObject]$summary; Error = $null }
    }
    catch {
        $message = $_.Exception.Message
        if ($writeLog) {
            Write-PolicyLog -Message "Failed to build telemetry summary: $message" -Level 'Error'
        }

        return [PSCustomObject]@{ Success = $false; Data = $null; Error = $message }
    }
}
