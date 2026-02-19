function Start-Deployment {
    <#
    .SYNOPSIS
        Starts a deployment job.

    .DESCRIPTION
        Executes the deployment process:
        1. Export policy to XML
        2. Check/create GPO
        3. Import policy to GPO
        4. Link GPO to OUs if specified

    .PARAMETER JobId
        The ID of the deployment job to start.

    .PARAMETER WhatIf
        Show what would happen without making changes.

    .EXAMPLE
        Start-Deployment -JobId "abc123"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )

    try {
        # Get job
        $jobResult = Get-DeploymentJob -JobId $JobId
        if (-not $jobResult.Success) {
            return $jobResult
        }

        $job = $jobResult.Data
        $dataPath = Get-AppLockerDataPath
        $deploymentsPath = Join-Path $dataPath 'Deployments'
        $jobFile = Join-Path $deploymentsPath "$JobId.json"

        # Update status to running
        $job.Status = 'Running'
        $job.StartedAt = (Get-Date).ToString('o')
        $job.Progress = 10
        $job.Message = 'Starting deployment...'

        # Read existing job if exists for version checking
        $existingVersion = $null
        if (Test-Path $jobFile) {
            try {
                $existingJob = Get-Content -Path $jobFile -Raw | ConvertFrom-Json
                $existingVersion = $existingJob.Version
            }
            catch {
                Write-AppLockerLog -Message "Failed to read existing job file for version check: $($_.Exception.Message)" -Level 'DEBUG'
            }
        }

        Write-DeploymentJobFile -Path $jobFile -Job $job

        # Verify version didn't change during write (race condition detection)
        if ($null -ne $existingVersion) {
            try {
                $verifyJob = Get-Content -Path $jobFile -Raw | ConvertFrom-Json
                $expectedVersion = $existingVersion + 1
                if ($verifyJob.Version -ne $expectedVersion) {
                    Write-AppLockerLog -Message "Race condition detected: Job version inconsistent. Expected $expectedVersion, got $($verifyJob.Version). Retrying..." -Level 'WARNING'
                    # Version mismatch - another process modified the job
                    $result = @{
                        Success = $false
                        Error = "Concurrent deployment detected. Job file modified during operation."
                    }
                    $job.Status = 'Failed'
                    $job.Message = $result.Error
                    $job.CompletedAt = (Get-Date).ToString('o')
                    Write-DeploymentJobFile -Path $jobFile -Job $job
                    return $result
                }
            }
            catch {
                Write-AppLockerLog -Message "Failed to verify job version after write: $($_.Exception.Message)" -Level 'DEBUG'
            }
        }

        # Step 1: Export policy to temp XML
        $job.Progress = 20
        $job.Message = 'Exporting policy to XML...'
        Write-DeploymentJobFile -Path $jobFile -Job $job

        $tempPath = Join-Path $env:TEMP "AppLocker_$($job.PolicyId).xml"
        $exportResult = Export-PolicyToXml -PolicyId $job.PolicyId -OutputPath $tempPath

        if (-not $exportResult.Success) {
            $job.Status = 'Failed'
            $job.Message = "Export failed: $($exportResult.Error)"
            $job.ErrorDetails = $exportResult.Error
            Write-DeploymentJobFile -Path $jobFile -Job $job
            return @{
                Success = $false
                Error   = $exportResult.Error
            }
        }

        # Step 2: Check if GPO exists
        $job.Progress = 40
        $job.Message = 'Checking GPO...'
        Write-DeploymentJobFile -Path $jobFile -Job $job

        $gpoExists = Test-GPOExists -GPOName $job.GPOName

        # Check if GPO verification failed due to missing modules
        if (-not $gpoExists.Success) {
            if ($gpoExists.ManualRequired) {
                $job.Status = 'ManualRequired'
                $job.Progress = 40
                $job.Message = "Manual deployment required: $($gpoExists.Error)"
                $job.ErrorDetails = $gpoExists.Error
                if ($job.PSObject.Properties['XmlExportPath']) {
                    $job.XmlExportPath = $tempPath
                } else {
                    $job | Add-Member -MemberType NoteProperty -Name 'XmlExportPath' -Value $tempPath -Force
                }
                Write-DeploymentJobFile -Path $jobFile -Job $job
                return @{
                    Success        = $false
                    Error          = $gpoExists.Error
                    ManualRequired = $true
                    XmlPath        = $tempPath
                }
            }
            $job.Status = 'Failed'
            $job.Message = "GPO check failed: $($gpoExists.Error)"
            $job.ErrorDetails = $gpoExists.Error
            Write-DeploymentJobFile -Path $jobFile -Job $job
            return @{
                Success = $false
                Error   = $gpoExists.Error
            }
        }

        # SupportsShouldProcess provides -WhatIf automatically via [CmdletBinding]
        if ($WhatIfPreference) {
            $job.Status = 'Completed'
            $job.Progress = 100
            $job.Message = "WhatIf: Would deploy to GPO '$($job.GPOName)'"
            $job.CompletedAt = (Get-Date).ToString('o')
            Write-DeploymentJobFile -Path $jobFile -Job $job
            
            return @{
                Success = $true
                Data    = $job
                Message = "WhatIf: Would deploy policy to '$($job.GPOName)'"
            }
        }

        # Step 3: Create GPO if needed
        if (-not $gpoExists.Data) {
            $job.Progress = 50
            $job.Message = 'Creating GPO...'
            Write-DeploymentJobFile -Path $jobFile -Job $job

            $createResult = New-AppLockerGPO -GPOName $job.GPOName
            if (-not $createResult.Success) {
                $job.Status = 'Failed'
                $job.Message = "GPO creation failed: $($createResult.Error)"
                $job.ErrorDetails = $createResult.Error
                Write-DeploymentJobFile -Path $jobFile -Job $job
                return @{
                    Success = $false
                    Error   = $createResult.Error
                }
            }
        }

        # Step 4: Import policy to GPO
        $job.Progress = 70
        $job.Message = 'Importing policy to GPO...'
        Write-DeploymentJobFile -Path $jobFile -Job $job

        $importResult = Import-PolicyToGPO -GPOName $job.GPOName -XmlPath $tempPath

        if (-not $importResult.Success) {
            if ($importResult.ManualRequired) {
                # Policy exported but manual import needed
                $job.Status = 'ManualRequired'
                $job.Progress = 70
                $job.Message = "Policy exported. Manual import required via GPMC."
                $job.ErrorDetails = $importResult.Error
                if ($job.PSObject.Properties['XmlExportPath']) {
                    $job.XmlExportPath = $tempPath
                } else {
                    $job | Add-Member -MemberType NoteProperty -Name 'XmlExportPath' -Value $tempPath -Force
                }
                Write-DeploymentJobFile -Path $jobFile -Job $job
                
                # Don't delete temp file since user needs it
                Add-DeploymentHistory -JobId $JobId -Action 'ManualRequired' -Details "Policy exported to: $tempPath"
                
                return @{
                    Success        = $false
                    Error          = $importResult.Error
                    ManualRequired = $true
                    XmlPath        = $tempPath
                    Message        = "Policy exported to '$tempPath'. Manual import required via GPMC."
                }
            }
            
            $job.Status = 'Failed'
            $job.Message = "Import failed: $($importResult.Error)"
            $job.ErrorDetails = $importResult.Error
            Write-DeploymentJobFile -Path $jobFile -Job $job
            return @{
                Success = $false
                Error   = $importResult.Error
            }
        }

        # Step 5: Link GPO to OUs if specified
        if ($job.TargetOUs -and $job.TargetOUs.Count -gt 0) {
            $job.Progress = 85
            $job.Message = 'Linking GPO to OUs...'
            Write-DeploymentJobFile -Path $jobFile -Job $job

            # Check if ActiveDirectory module is available for linking
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                try {
                    Import-Module ActiveDirectory -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-AppLockerLog -Level Warning -Message "GPO linking skipped - ActiveDirectory module could not be imported. Manual linking required for $($job.TargetOUs.Count) OUs."
                }
                foreach ($ouDN in $job.TargetOUs) {
                    try {
                        New-GPLink -Name $job.GPOName -Target $ouDN -ErrorAction Stop | Out-Null
                        Write-AppLockerLog -Message "Linked GPO '$($job.GPOName)' to OU: $ouDN"
                    }
                    catch {
                        Write-AppLockerLog -Level Warning -Message "Failed to link GPO to $ouDN`: $($_.Exception.Message)"
                    }
                }
            }
            else {
                Write-AppLockerLog -Level Warning -Message "GPO linking skipped - ActiveDirectory module not available. Manual linking required for $($job.TargetOUs.Count) OUs."
            }
        }

        # Cleanup temp file
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }

        # Mark as completed
        $job.Status = 'Completed'
        $job.Progress = 100
        $job.Message = "Successfully deployed to GPO '$($job.GPOName)'"
        $job.CompletedAt = (Get-Date).ToString('o')
        Write-DeploymentJobFile -Path $jobFile -Job $job

        # Update policy status
        $statusResult = Set-PolicyStatus -PolicyId $job.PolicyId -Status 'Deployed'
        if (-not $statusResult.Success) {
            Write-AppLockerLog -Level Warning -Message "Failed to set policy status: $($statusResult.Error)"
        }

        # Log to history
        Add-DeploymentHistory -JobId $JobId -Action 'Deployed' -Details "Deployed to GPO '$($job.GPOName)'"

        return @{
            Success = $true
            Data    = $job
            Message = "Policy deployed successfully to '$($job.GPOName)'"
        }
    }
    catch {
        # Update job with error
        try {
            $dataPath = Get-AppLockerDataPath
            $deploymentsPath = Join-Path $dataPath 'Deployments'
            $jobFile = Join-Path $deploymentsPath "$JobId.json"
            
            if (Test-Path $jobFile) {
                $job = Get-Content -Path $jobFile -Raw | ConvertFrom-Json
                $job.Status = 'Failed'
                $job.Message = "Deployment failed: $($_.Exception.Message)"
                $job.ErrorDetails = $_.Exception.Message
                Write-DeploymentJobFile -Path $jobFile -Job $job
            }
        }
        catch { 
            # Unable to update job file - log the secondary error
            Write-AppLockerLog -Level Warning -Message "Failed to update job file after error: $($_.Exception.Message)"
        }

        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Stop-Deployment {
    <#
    .SYNOPSIS
        Cancels a pending or running deployment.


.DESCRIPTION
    Cancels a pending or running deployment. Gracefully stops the running operation.

    .PARAMETER JobId
        The ID of the deployment job to cancel.

    .EXAMPLE
        Stop-Deployment -JobId "abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )

    try {
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

        if ($job.Status -in @('Completed', 'Failed', 'Cancelled')) {
            return @{
                Success = $false
                Error   = "Cannot cancel job with status '$($job.Status)'"
            }
        }

        $job.Status = 'Cancelled'
        if ($job.PSObject.Properties['Message']) {
            $job.Message = 'Deployment cancelled by user'
        } else {
            $job | Add-Member -MemberType NoteProperty -Name 'Message' -Value 'Deployment cancelled by user' -Force
        }
        $job.CompletedAt = (Get-Date).ToString('o')
        Write-DeploymentJobFile -Path $jobFile -Job $job

        return @{
            Success = $true
            Data    = $job
            Message = 'Deployment cancelled'
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Get-DeploymentStatus {
    <#
    .SYNOPSIS
        Gets the current status of a deployment job.


.DESCRIPTION
    Gets the current status of a deployment job.

    .PARAMETER JobId
        The ID of the deployment job.

    .EXAMPLE
        Get-DeploymentStatus -JobId "abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )

    $jobResult = Get-DeploymentJob -JobId $JobId
    if (-not $jobResult.Success) {
        return $jobResult
    }

    $job = $jobResult.Data

    return @{
        Success = $true
        Data    = @{
            JobId    = $job.JobId
            Status   = $job.Status
            Progress = $job.Progress
            Message  = $job.Message
        }
    }
}

function Add-DeploymentHistory {
    param(
        [string]$JobId,
        [string]$Action,
        [string]$Details
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $historyPath = Join-Path $dataPath 'DeploymentHistory'

        if (-not (Test-Path $historyPath)) {
            New-Item -Path $historyPath -ItemType Directory -Force | Out-Null
        }

        $entry = [PSCustomObject]@{
            Id        = [guid]::NewGuid().ToString()
            JobId     = $JobId
            Action    = $Action
            Details   = $Details
            Timestamp = (Get-Date).ToString('o')
            User      = $env:USERNAME
            Computer  = $env:COMPUTERNAME
        }

        $entryFile = Join-Path $historyPath "$($entry.Id).json"
        $entry | ConvertTo-Json | Set-Content -Path $entryFile -Encoding UTF8
    }
    catch {
        Write-AppLockerLog -Level Warning -Message "Failed to log deployment history: $($_.Exception.Message)"
    }
}

