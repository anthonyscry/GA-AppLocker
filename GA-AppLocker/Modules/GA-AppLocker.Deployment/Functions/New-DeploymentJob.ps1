function New-DeploymentJob {
    <#
    .SYNOPSIS
        Creates a new deployment job for a policy.

    .DESCRIPTION
        Creates a deployment job that tracks the deployment of
        an AppLocker policy to a GPO.

    .PARAMETER PolicyId
        The ID of the policy to deploy.

    .PARAMETER GPOName
        The name of the target GPO.

    .PARAMETER TargetOUs
        Optional array of OU distinguished names to link the GPO to.

    .PARAMETER Schedule
        When to execute: 'Immediate', 'Scheduled', or 'Manual'.

    .EXAMPLE
        New-DeploymentJob -PolicyId "abc123" -GPOName "AppLocker-Workstations"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $false)]
        [string[]]$TargetOUs = @(),

        [Parameter(Mandatory = $false)]
        [ValidateSet('Immediate', 'Scheduled', 'Manual')]
        [string]$Schedule = 'Manual'
    )

    try {
        # Verify policy exists
        $policyResult = Get-Policy -PolicyId $PolicyId
        if (-not $policyResult.Success) {
            return @{
                Success = $false
                Error   = "Policy not found: $PolicyId"
            }
        }

        $dataPath = Get-AppLockerDataPath
        $deploymentsPath = Join-Path $dataPath 'Deployments'

        if (-not (Test-Path $deploymentsPath)) {
            New-Item -Path $deploymentsPath -ItemType Directory -Force | Out-Null
        }

        $jobId = [guid]::NewGuid().ToString()

        $job = [PSCustomObject]@{
            JobId        = $jobId
            PolicyId     = $PolicyId
            PolicyName   = $policyResult.Data.Name
            GPOName      = $GPOName
            TargetOUs    = @($TargetOUs)
            Schedule     = $Schedule
            Status       = 'Pending'
            Progress     = 0
            Message      = 'Job created, awaiting deployment'
            CreatedAt    = (Get-Date).ToString('o')
            StartedAt    = $null
            CompletedAt  = $null
            CreatedBy    = $env:USERNAME
            ErrorDetails = $null
        }

        $jobFile = Join-Path $deploymentsPath "$jobId.json"
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

        return @{
            Success = $true
            Data    = $job
            Message = "Deployment job created for policy '$($policyResult.Data.Name)'"
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Get-DeploymentJob {
    <#
    .SYNOPSIS
        Retrieves a deployment job by ID.

    .PARAMETER JobId
        The unique identifier of the deployment job.

    .EXAMPLE
        Get-DeploymentJob -JobId "abc123"
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

        return @{
            Success = $true
            Data    = $job
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Get-AllDeploymentJobs {
    <#
    .SYNOPSIS
        Retrieves all deployment jobs.

    .PARAMETER Status
        Optional filter by status.

    .EXAMPLE
        Get-AllDeploymentJobs
        Get-AllDeploymentJobs -Status "Running"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Pending', 'Running', 'Completed', 'Failed', 'Cancelled', '')]
        [string]$Status = ''
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $deploymentsPath = Join-Path $dataPath 'Deployments'

        if (-not (Test-Path $deploymentsPath)) {
            return @{
                Success = $true
                Data    = @()
            }
        }

        $jobFiles = Get-ChildItem -Path $deploymentsPath -Filter '*.json' -File
        $jobs = @()

        foreach ($file in $jobFiles) {
            $job = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            
            if ([string]::IsNullOrEmpty($Status) -or $job.Status -eq $Status) {
                $jobs += $job
            }
        }

        # Sort by created date descending
        $jobs = $jobs | Sort-Object -Property CreatedAt -Descending

        return @{
            Success = $true
            Data    = $jobs
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
