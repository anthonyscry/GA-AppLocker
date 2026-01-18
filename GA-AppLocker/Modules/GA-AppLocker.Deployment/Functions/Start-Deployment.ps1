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
        [string]$JobId,

        [Parameter(Mandatory = $false)]
        [switch]$WhatIf
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
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

        # Step 1: Export policy to temp XML
        $job.Progress = 20
        $job.Message = 'Exporting policy to XML...'
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

        $tempPath = Join-Path $env:TEMP "AppLocker_$($job.PolicyId).xml"
        $exportResult = Export-PolicyToXml -PolicyId $job.PolicyId -OutputPath $tempPath

        if (-not $exportResult.Success) {
            $job.Status = 'Failed'
            $job.Message = "Export failed: $($exportResult.Error)"
            $job.ErrorDetails = $exportResult.Error
            $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8
            return @{
                Success = $false
                Error   = $exportResult.Error
            }
        }

        # Step 2: Check if GPO exists
        $job.Progress = 40
        $job.Message = 'Checking GPO...'
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

        $gpoExists = Test-GPOExists -GPOName $job.GPOName

        if ($WhatIf) {
            $job.Status = 'Completed'
            $job.Progress = 100
            $job.Message = "WhatIf: Would deploy to GPO '$($job.GPOName)'"
            $job.CompletedAt = (Get-Date).ToString('o')
            $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8
            
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
            $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

            $createResult = New-AppLockerGPO -GPOName $job.GPOName
            if (-not $createResult.Success) {
                $job.Status = 'Failed'
                $job.Message = "GPO creation failed: $($createResult.Error)"
                $job.ErrorDetails = $createResult.Error
                $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8
                return @{
                    Success = $false
                    Error   = $createResult.Error
                }
            }
        }

        # Step 4: Import policy to GPO
        $job.Progress = 70
        $job.Message = 'Importing policy to GPO...'
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

        $importResult = Import-PolicyToGPO -GPOName $job.GPOName -XmlPath $tempPath

        if (-not $importResult.Success) {
            $job.Status = 'Failed'
            $job.Message = "Import failed: $($importResult.Error)"
            $job.ErrorDetails = $importResult.Error
            $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8
            return @{
                Success = $false
                Error   = $importResult.Error
            }
        }

        # Step 5: Link GPO to OUs if specified
        if ($job.TargetOUs -and $job.TargetOUs.Count -gt 0) {
            $job.Progress = 85
            $job.Message = 'Linking GPO to OUs...'
            $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

            # Note: In real environment, would use New-GPLink
            # For now, just log the action
            Write-AppLockerLog -Message "Would link GPO '$($job.GPOName)' to $($job.TargetOUs.Count) OUs"
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
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

        # Update policy status
        Set-PolicyStatus -PolicyId $job.PolicyId -Status 'Deployed' | Out-Null

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
                $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8
            }
        }
        catch { }

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
        $job.Message = 'Deployment cancelled by user'
        $job.CompletedAt = (Get-Date).ToString('o')
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

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
