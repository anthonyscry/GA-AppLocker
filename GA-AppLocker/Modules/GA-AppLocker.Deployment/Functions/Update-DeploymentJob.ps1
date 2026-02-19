function Update-DeploymentJob {
    <#
    .SYNOPSIS
        Updates an existing deployment job.

    .DESCRIPTION
        Updates the fields of a pending deployment job. This includes the target GPO name and schedule.
        Jobs that are in 'Running' or completed status cannot be updated and will fail.

    .PARAMETER JobId
        The unique identifier of the deployment job to update.

    .PARAMETER GPOName
        The name of the target GPO. If provided, updates the job's GPO assignment.

    .PARAMETER Schedule
        When to execute: 'Immediate', 'Scheduled', or 'Manual'. If provided, updates the job's schedule.
        Only valid if the job is still in 'Pending' status.

    .PARAMETER TargetOUs
        Optional array of OU distinguished names to link the GPO to. If provided, updates the job's target OUs.

    .EXAMPLE
        Update-DeploymentJob -JobId "abc123" -GPOName "AppLocker-Servers" -Schedule "Immediate"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $false)]
        [string]$GPOName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Immediate', 'Scheduled', 'Manual')]
        [string]$Schedule,

        [Parameter(Mandatory = $false)]
        [string[]]$TargetOUs = $null
    )

    try {
        # Load existing job
        $dataPath = Get-AppLockerDataPath
        $deploymentsPath = Join-Path $dataPath 'Deployments'
        $jobFile = Join-Path $deploymentsPath "$JobId.json"

        if (-not (Test-Path $jobFile)) {
            return @{
                Success = $false
                Error   = "Deployment job not found: $JobId"
            }
        }

        $job = Get-Content -Path $jobFile -Raw | ConvertFrom-Json

        # Validate that the job exists and is in 'Pending' status
        if (-not $job) {
            return @{
                Success = $false
                Error   = "Invalid job file: $JobId"
            }
        }

        if ($job.Status -ne 'Pending') {
            return @{
                Success = $false
                Error   = "Cannot update job '$JobId' with status '$($job.Status)'. Only 'Pending' jobs can be modified."
            }
        }

        # Update fields if provided
        $wasUpdated = $false

        if ($PSBoundParameters.ContainsKey('GPOName') -and $null -ne $GPOName) {
            $job.GPOName = $GPOName
            $wasUpdated = $true
        }

        if ($PSBoundParameters.ContainsKey('Schedule') -and $null -ne $Schedule) {
            $job.Schedule = $Schedule
            $wasUpdated = $true
        }

        if ($null -ne $TargetOUs) {
            $job.TargetOUs = @($TargetOUs)
            $wasUpdated = $true
        }

        if (-not $wasUpdated) {
            return @{
                Success = $true
                Data    = $job
                Message = "Job '$JobId' already in desired state. No changes made."
            }
        }

        # Save updated job back to disk
        # Version checking before write: capture current version, then increment before write
        $existingVersion = $job.Version
        if ($null -ne $existingVersion) {
            # Increment version in the job object so the post-write verification can confirm no race
            if ($job.PSObject.Properties['Version']) {
                $job.Version = $existingVersion + 1
            } else {
                $job | Add-Member -MemberType NoteProperty -Name 'Version' -Value ($existingVersion + 1) -Force
            }
        }
        Write-DeploymentJobFile -Path $jobFile -Job $job

        # Verify version didn't change during write (race condition detection)
        try {
            $verifyJob = Get-Content -Path $jobFile -Raw | ConvertFrom-Json
            $expectedVersion = $existingVersion + 1
            if ($verifyJob.Version -ne $expectedVersion) {
                Write-AppLockerLog -Message "Race condition detected in Update-DeploymentJob: Job version inconsistent. Expected $expectedVersion, got $($verifyJob.Version)." -Level 'WARNING'
                return @{
                    Success = $false
                    Error = "Concurrent deployment modification detected. Job file modified during update."
                }
            }
        }
        catch {
            Write-AppLockerLog -Message "Failed to verify job version after update: $($_.Exception.Message)" -Level 'DEBUG'
        }

        # Log the change
        $changedFields = @()
        if ($PSBoundParameters.ContainsKey('GPOName')) { $changedFields += 'GPOName' }
        if ($PSBoundParameters.ContainsKey('Schedule')) { $changedFields += 'Schedule' }
        if ($null -ne $TargetOUs) { $changedFields += 'TargetOUs' }

        Write-AppLockerLog -Message "Updated deployment job '$JobId' with changes: $($changedFields -join ', ')" -Level 'INFO'

        return @{
            Success = $true
            Data    = $job
            Message = "Job '$JobId' updated successfully."
        }
    }
    catch {
        Write-AppLockerLog -Message "Failed to update deployment job '$JobId': $($_.Exception.Message)" -Level 'ERROR'
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

