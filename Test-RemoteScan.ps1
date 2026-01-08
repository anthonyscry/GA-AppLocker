<#
.SYNOPSIS
    Simplified diagnostic script to test remote scanning connectivity.
    Use this to debug what's failing before running the full Invoke-RemoteScan.ps1

.DESCRIPTION
    This is a stripped-down version that:
    - Tests ONE computer at a time (no parallel jobs)
    - Uses direct Invoke-Command (no Start-Job complexity)
    - Shows verbose errors at each step
    - Only collects minimal data to verify connectivity

.EXAMPLE
    .\Test-RemoteScan.ps1 -ComputerName "WORKSTATION01"

.EXAMPLE
    .\Test-RemoteScan.ps1 -ComputerName "WORKSTATION01" -Credential (Get-Credential)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Remote Scan Diagnostic ===" -ForegroundColor Cyan
Write-Host "Target: $ComputerName" -ForegroundColor Cyan
Write-Host ""

# Step 1: Get credentials if not provided
Write-Host "[Step 1] Credentials" -ForegroundColor Yellow
if ($null -eq $Credential) {
    Write-Host "  Prompting for credentials..." -ForegroundColor Gray
    $Credential = Get-Credential -Message "Enter credentials for $ComputerName"
}

if ($null -eq $Credential) {
    Write-Host "  FAILED: No credentials provided" -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Got credentials for $($Credential.UserName)" -ForegroundColor Green

# Step 2: Test basic connectivity
Write-Host "[Step 2] Testing network connectivity" -ForegroundColor Yellow
try {
    $ping = Test-Connection -ComputerName $ComputerName -Count 1 -ErrorAction Stop
    Write-Host "  OK: Ping succeeded (IP: $($ping.IPV4Address))" -ForegroundColor Green
}
catch {
    Write-Host "  FAILED: Cannot ping $ComputerName" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 3: Test WinRM port
Write-Host "[Step 3] Testing WinRM port (5985)" -ForegroundColor Yellow
try {
    $tcpTest = Test-NetConnection -ComputerName $ComputerName -Port 5985 -WarningAction SilentlyContinue
    if ($tcpTest.TcpTestSucceeded) {
        Write-Host "  OK: Port 5985 is open" -ForegroundColor Green
    }
    else {
        Write-Host "  FAILED: Port 5985 is not reachable" -ForegroundColor Red
        Write-Host "  Hint: Run 'Enable-PSRemoting' on target machine" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Host "  WARNING: Could not test port (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 4: Create PS Session
Write-Host "[Step 4] Creating PowerShell session" -ForegroundColor Yellow
try {
    Write-Host "  Attempting: New-PSSession -ComputerName $ComputerName -Credential ... -Authentication Default" -ForegroundColor Gray
    $session = New-PSSession -ComputerName $ComputerName -Credential $Credential -Authentication Default -ErrorAction Stop
    Write-Host "  OK: Session created (ID: $($session.Id), State: $($session.State))" -ForegroundColor Green
}
catch {
    Write-Host "  FAILED: Could not create session" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Common causes:" -ForegroundColor Yellow
    Write-Host "    - WinRM not enabled: Run 'Enable-PSRemoting -Force' on target" -ForegroundColor Gray
    Write-Host "    - Firewall blocking: Check Windows Firewall for WinRM rule" -ForegroundColor Gray
    Write-Host "    - Credential issue: Verify username format (DOMAIN\user or user@domain)" -ForegroundColor Gray
    Write-Host "    - TrustedHosts: Run 'Set-Item WSMan:\localhost\Client\TrustedHosts -Value $ComputerName'" -ForegroundColor Gray
    exit 1
}

# Step 5: Test basic command
Write-Host "[Step 5] Testing basic remote command" -ForegroundColor Yellow
try {
    $hostname = Invoke-Command -Session $session -ScriptBlock { $env:COMPUTERNAME }
    Write-Host "  OK: Remote hostname is '$hostname'" -ForegroundColor Green
}
catch {
    Write-Host "  FAILED: Could not run remote command" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    exit 1
}

# Step 6: Test AppLocker cmdlet
Write-Host "[Step 6] Testing Get-AppLockerPolicy cmdlet" -ForegroundColor Yellow
try {
    $policy = Invoke-Command -Session $session -ScriptBlock {
        Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
    }
    if ($policy) {
        Write-Host "  OK: Got AppLocker policy ($($policy.Length) chars)" -ForegroundColor Green
    }
    else {
        Write-Host "  OK: No AppLocker policy configured (this is normal)" -ForegroundColor Green
    }
}
catch {
    Write-Host "  WARNING: Could not get AppLocker policy (non-fatal)" -ForegroundColor Yellow
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
}

# Step 7: Test registry read
Write-Host "[Step 7] Testing registry access (installed software)" -ForegroundColor Yellow
try {
    $softwareCount = Invoke-Command -Session $session -ScriptBlock {
        (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName }).Count
    }
    Write-Host "  OK: Found $softwareCount installed programs" -ForegroundColor Green
}
catch {
    Write-Host "  FAILED: Could not read registry" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 8: Test file system access
Write-Host "[Step 8] Testing file system access" -ForegroundColor Yellow
try {
    $exeCount = Invoke-Command -Session $session -ScriptBlock {
        (Get-ChildItem -Path "$env:SystemRoot\System32" -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 10).Count
    }
    Write-Host "  OK: Can access file system (found $exeCount .exe files in System32 sample)" -ForegroundColor Green
}
catch {
    Write-Host "  FAILED: Could not access file system" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 9: Test signature check
Write-Host "[Step 9] Testing Authenticode signature check" -ForegroundColor Yellow
try {
    $sigResult = Invoke-Command -Session $session -ScriptBlock {
        $notepad = "$env:SystemRoot\System32\notepad.exe"
        if (Test-Path $notepad) {
            $sig = Get-AuthenticodeSignature -FilePath $notepad -ErrorAction Stop
            return @{
                Path = $notepad
                Status = $sig.Status.ToString()
                Signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "None" }
            }
        }
        return $null
    }
    if ($sigResult) {
        Write-Host "  OK: Signature check works" -ForegroundColor Green
        Write-Host "      File: $($sigResult.Path)" -ForegroundColor Gray
        Write-Host "      Status: $($sigResult.Status)" -ForegroundColor Gray
        Write-Host "      Signer: $($sigResult.Signer.Substring(0, [Math]::Min(60, $sigResult.Signer.Length)))..." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  FAILED: Could not check signature" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Cleanup
Write-Host "[Cleanup] Removing session" -ForegroundColor Yellow
Remove-PSSession -Session $session -ErrorAction SilentlyContinue
Write-Host "  OK: Session closed" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "=== Diagnostic Complete ===" -ForegroundColor Green
Write-Host "All basic connectivity tests passed!" -ForegroundColor Green
Write-Host ""
Write-Host "If the full Invoke-RemoteScan.ps1 still fails, the issue is likely:" -ForegroundColor Yellow
Write-Host "  - PowerShell job execution (Start-Job)" -ForegroundColor Gray
Write-Host "  - Credential serialization through jobs" -ForegroundColor Gray
Write-Host "  - PSDefaultParameterValues interference" -ForegroundColor Gray
Write-Host ""
Write-Host "Try running:" -ForegroundColor Cyan
Write-Host '  $PSDefaultParameterValues' -ForegroundColor White
Write-Host "to see if any defaults are set that could interfere." -ForegroundColor Cyan
