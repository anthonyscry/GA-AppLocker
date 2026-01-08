<#
.SYNOPSIS
    Test the full job scriptblock with detailed error reporting per section
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [PSCredential]$Credential,

    [string]$OutputPath = ".\TestOutput"
)

Write-Host "=== Full Job Test with Section Tracing ===" -ForegroundColor Cyan

if ($null -eq $Credential) {
    $Credential = Get-Credential -Message "Enter credentials"
}

# Setup
$credUsername = $Credential.UserName
$credPassword = $Credential.Password
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$PSDefaultParameterValues.Clear()

Write-Host "Starting job with full scriptblock..." -ForegroundColor Yellow

$job = Start-Job -Name "FullTest" -ArgumentList $ComputerName, $credUsername, $credPassword, $OutputPath -ScriptBlock {
    param($Computer, $CredUsername, $CredPassword, $OutputRoot)

    $PSDefaultParameterValues.Clear()

    $log = @()
    $log += "=== Job Started ==="

    try {
        # Section 1: Credential
        $log += "Section 1: Creating credential..."
        $Credential = New-Object System.Management.Automation.PSCredential($CredUsername, $CredPassword)
        $log += "  OK"

        # Section 2: Session
        $log += "Section 2: Creating session..."
        $session = New-PSSession -ComputerName $Computer -Credential $Credential -Authentication Default -ErrorAction Stop
        $log += "  OK: Session ID $($session.Id)"

        # Section 3: Create folder
        $log += "Section 3: Creating output folder..."
        $computerFolder = Join-Path $OutputRoot $Computer
        New-Item -ItemType Directory -Path $computerFolder -Force | Out-Null
        $log += "  OK: $computerFolder"

        # Section 4: AppLocker policy
        $log += "Section 4: Getting AppLocker policy..."
        try {
            $policyXml = Invoke-Command -Session $session -ScriptBlock {
                Get-AppLockerPolicy -Effective -Xml -ErrorAction SilentlyContinue
            }
            if ($policyXml) {
                $policyXml | Out-File -FilePath (Join-Path $computerFolder "AppLockerPolicy.xml") -Encoding UTF8
                $log += "  OK: Saved policy"
            } else {
                $log += "  OK: No policy configured"
            }
        }
        catch {
            $log += "  ERROR: $($_.Exception.Message)"
        }

        # Section 5: Installed software
        $log += "Section 5: Getting installed software..."
        try {
            $software = Invoke-Command -Session $session -ScriptBlock {
                $paths = @(
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName } |
                    Select-Object DisplayName, DisplayVersion, Publisher
            }
            if ($software) {
                $software | Export-Csv -Path (Join-Path $computerFolder "InstalledSoftware.csv") -NoTypeInformation
                $log += "  OK: $($software.Count) items"
            }
        }
        catch {
            $log += "  ERROR: $($_.Exception.Message)"
        }

        # Section 6: Executables (simplified)
        $log += "Section 6: Scanning executables..."
        try {
            $exeData = Invoke-Command -Session $session -ScriptBlock {
                $files = Get-ChildItem -Path $env:ProgramFiles -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 50
                $results = @()
                foreach ($file in $files) {
                    $sig = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue
                    $results += [PSCustomObject]@{
                        Path = $file.FullName
                        Name = $file.Name
                        IsSigned = ($sig.Status -eq "Valid")
                    }
                }
                return $results
            }
            if ($exeData) {
                $exeData | Export-Csv -Path (Join-Path $computerFolder "Executables.csv") -NoTypeInformation
                $log += "  OK: $($exeData.Count) files"
            }
        }
        catch {
            $log += "  ERROR: $($_.Exception.Message)"
        }

        # Section 7: System info
        $log += "Section 7: Getting system info..."
        try {
            $osInfo = Invoke-Command -Session $session -ScriptBlock {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    OSName = if ($os) { $os.Caption } else { "Unknown" }
                }
            }
            if ($osInfo) {
                $osInfo | Export-Csv -Path (Join-Path $computerFolder "SystemInfo.csv") -NoTypeInformation
                $log += "  OK"
            }
        }
        catch {
            $log += "  ERROR: $($_.Exception.Message)"
        }

        # Cleanup
        $log += "Section 8: Cleanup..."
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        $log += "  OK"

        $log += "=== SUCCESS ==="
    }
    catch {
        $log += "=== FAILED: $($_.Exception.Message) ==="
    }

    return $log
}

$job | Wait-Job | Out-Null

Write-Host ""
Write-Host "Job state: $($job.State)" -ForegroundColor $(if ($job.State -eq 'Completed') { 'Green' } else { 'Red' })
Write-Host ""

if ($job.State -eq 'Failed') {
    Write-Host "Job execution failed:" -ForegroundColor Red
    if ($job.ChildJobs -and $job.ChildJobs[0].JobStateInfo.Reason) {
        Write-Host $job.ChildJobs[0].JobStateInfo.Reason.Message -ForegroundColor Red
    }
}
else {
    $log = Receive-Job -Job $job
    Write-Host "=== Job Log ===" -ForegroundColor Cyan
    foreach ($line in $log) {
        $color = "White"
        if ($line -match "ERROR") { $color = "Red" }
        elseif ($line -match "OK") { $color = "Green" }
        elseif ($line -match "Section") { $color = "Yellow" }
        Write-Host $line -ForegroundColor $color
    }
}

Remove-Job -Job $job -Force
Write-Host ""
Write-Host "Output saved to: $OutputPath\$ComputerName" -ForegroundColor Cyan
