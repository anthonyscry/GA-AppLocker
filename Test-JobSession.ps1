<#
.SYNOPSIS
    Minimal test to isolate Start-Job issue with remote sessions
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [PSCredential]$Credential
)

Write-Host "=== Start-Job Remote Session Test ===" -ForegroundColor Cyan

if ($null -eq $Credential) {
    $Credential = Get-Credential -Message "Enter credentials"
}

# Extract credential components (same as main script)
$credUsername = $Credential.UserName
$credPassword = $Credential.Password

Write-Host "Username: $credUsername" -ForegroundColor Gray
Write-Host "Password type: $($credPassword.GetType().Name)" -ForegroundColor Gray

# Clear PSDefaultParameterValues before starting job (same as main script)
$savedDefaults = @{}
foreach ($key in $PSDefaultParameterValues.Keys) {
    $savedDefaults[$key] = $PSDefaultParameterValues[$key]
    Write-Host "Found default: $key = $($savedDefaults[$key])" -ForegroundColor Yellow
}
$PSDefaultParameterValues.Clear()
Write-Host "Cleared PSDefaultParameterValues" -ForegroundColor Gray

Write-Host ""
Write-Host "Starting job..." -ForegroundColor Yellow

# MINIMAL job - just try to create a session
$job = Start-Job -Name "Test-Job" -ArgumentList $ComputerName, $credUsername, $credPassword -ScriptBlock {
    param($Computer, $CredUsername, $CredPassword)

    # Clear defaults inside job too
    $PSDefaultParameterValues.Clear()

    $result = @{
        Step = "Init"
        Success = $false
        Error = ""
    }

    try {
        $result.Step = "Creating credential"
        $cred = New-Object System.Management.Automation.PSCredential($CredUsername, $CredPassword)

        $result.Step = "Creating session"
        $session = New-PSSession -ComputerName $Computer -Credential $cred -Authentication Default -ErrorAction Stop

        $result.Step = "Testing command"
        $hostname = Invoke-Command -Session $session -ScriptBlock { $env:COMPUTERNAME }

        $result.Step = "Cleanup"
        Remove-PSSession -Session $session

        $result.Step = "Done"
        $result.Success = $true
        $result.Hostname = $hostname
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

Write-Host "Job started, waiting..." -ForegroundColor Gray

# Wait for job
$job | Wait-Job | Out-Null

Write-Host ""
Write-Host "Job state: $($job.State)" -ForegroundColor $(if ($job.State -eq 'Completed') { 'Green' } else { 'Red' })

if ($job.State -eq 'Failed') {
    Write-Host "Job FAILED to execute" -ForegroundColor Red
    if ($job.ChildJobs -and $job.ChildJobs[0].JobStateInfo.Reason) {
        Write-Host "Reason: $($job.ChildJobs[0].JobStateInfo.Reason.Message)" -ForegroundColor Red
    }
}
else {
    $result = Receive-Job -Job $job
    Write-Host "Last step: $($result.Step)" -ForegroundColor Gray

    if ($result.Success) {
        Write-Host "SUCCESS! Connected to: $($result.Hostname)" -ForegroundColor Green
    }
    else {
        Write-Host "FAILED at step: $($result.Step)" -ForegroundColor Red
        Write-Host "Error: $($result.Error)" -ForegroundColor Red
    }
}

Remove-Job -Job $job -Force

# Restore defaults
foreach ($key in $savedDefaults.Keys) {
    $PSDefaultParameterValues[$key] = $savedDefaults[$key]
}

Write-Host ""
Write-Host "Test complete." -ForegroundColor Cyan
