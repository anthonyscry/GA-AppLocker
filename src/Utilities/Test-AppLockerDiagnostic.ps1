<#
.SYNOPSIS
    Consolidated diagnostic and testing tool for AppLocker remote scanning.

.DESCRIPTION
    This script provides multiple diagnostic tests for troubleshooting remote scanning issues:

    - Connectivity: Step-by-step connectivity diagnostic (ping, WinRM, session, commands)
    - JobSession: Minimal test to isolate Start-Job issues with remote sessions
    - JobFull: Full job scriptblock test with detailed section tracing
    - SimpleScan: Simplified scan without parallel jobs (direct Invoke-Command)

    Use these diagnostics when the full Invoke-RemoteScan.ps1 fails to help identify
    whether the issue is with connectivity, job execution, or the scan logic itself.

.PARAMETER TestType
    Type of diagnostic test to run:
    - Connectivity: Test network, WinRM, session creation, and basic commands
    - JobSession: Minimal job test to isolate Start-Job credential issues
    - JobFull: Full job execution with section-by-section tracing
    - SimpleScan: Run simplified scan (no parallel jobs) for debugging

.PARAMETER ComputerName
    Target computer name for single-computer tests (Connectivity, JobSession, JobFull).

.PARAMETER ComputerListPath
    Path to text file with computer names (for SimpleScan mode).

.PARAMETER OutputPath
    Output path for scan results (SimpleScan and JobFull modes).

.PARAMETER Credential
    Credentials for remote connections. Will prompt if not provided.

.PARAMETER SkipWritableDirectoryScan
    Skip writable directory scanning in SimpleScan mode.

.EXAMPLE
    # Test connectivity to a single computer
    .\utilities\Test-AppLockerDiagnostic.ps1 -TestType Connectivity -ComputerName "WORKSTATION01"

.EXAMPLE
    # Test job execution with full tracing
    .\utilities\Test-AppLockerDiagnostic.ps1 -TestType JobFull -ComputerName "WORKSTATION01"

.EXAMPLE
    # Run simplified scan for debugging
    .\utilities\Test-AppLockerDiagnostic.ps1 -TestType SimpleScan -ComputerListPath .\ADManagement\computers.csv -OutputPath .\Scans

.NOTES
    Part of GA-AppLocker toolkit.
    Use this script to diagnose issues before running the full Invoke-RemoteScan.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Connectivity", "JobSession", "JobFull", "SimpleScan")]
    [string]$TestType,

    [string]$ComputerName,

    [string]$ComputerListPath,

    [string]$OutputPath = ".\DiagnosticOutput",

    [PSCredential]$Credential,

    [switch]$SkipWritableDirectoryScan
)

$ErrorActionPreference = 'Continue'

#region Connectivity Test
function Invoke-ConnectivityTest {
    param(
        [string]$Computer,
        [PSCredential]$Cred
    )

    Write-Host "=== Remote Scan Diagnostic ===" -ForegroundColor Cyan
    Write-Host "Target: $Computer" -ForegroundColor Cyan
    Write-Host ""

    # Step 1: Get credentials if not provided
    Write-Host "[Step 1] Credentials" -ForegroundColor Yellow
    if ($null -eq $Cred) {
        Write-Host "  Prompting for credentials..." -ForegroundColor Gray
        $Cred = Get-Credential -Message "Enter credentials for $Computer"
    }

    if ($null -eq $Cred) {
        Write-Host "  FAILED: No credentials provided" -ForegroundColor Red
        return $false
    }
    Write-Host "  OK: Got credentials for $($Cred.UserName)" -ForegroundColor Green

    # Step 2: Test basic connectivity
    Write-Host "[Step 2] Testing network connectivity" -ForegroundColor Yellow
    try {
        $ping = Test-Connection -ComputerName $Computer -Count 1 -ErrorAction Stop
        Write-Host "  OK: Ping succeeded (IP: $($ping.IPV4Address))" -ForegroundColor Green
    }
    catch {
        Write-Host "  FAILED: Cannot ping $Computer" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    # Step 3: Test WinRM port
    Write-Host "[Step 3] Testing WinRM port (5985)" -ForegroundColor Yellow
    try {
        $tcpTest = Test-NetConnection -ComputerName $Computer -Port 5985 -WarningAction SilentlyContinue
        if ($tcpTest.TcpTestSucceeded) {
            Write-Host "  OK: Port 5985 is open" -ForegroundColor Green
        }
        else {
            Write-Host "  FAILED: Port 5985 is not reachable" -ForegroundColor Red
            Write-Host "  Hint: Run 'Enable-PSRemoting' on target machine" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "  WARNING: Could not test port (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Step 4: Create PS Session
    Write-Host "[Step 4] Creating PowerShell session" -ForegroundColor Yellow
    $session = $null
    try {
        Write-Host "  Attempting: New-PSSession -ComputerName $Computer -Credential ... -Authentication Default" -ForegroundColor Gray
        $session = New-PSSession -ComputerName $Computer -Credential $Cred -Authentication Default -ErrorAction Stop
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
        Write-Host "    - TrustedHosts: Run 'Set-Item WSMan:\localhost\Client\TrustedHosts -Value $Computer'" -ForegroundColor Gray
        return $false
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
        return $false
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
                    Path   = $notepad
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
    Write-Host '  .\utilities\Test-AppLockerDiagnostic.ps1 -TestType JobSession -ComputerName "COMPUTER"' -ForegroundColor White

    return $true
}
#endregion

#region JobSession Test
function Invoke-JobSessionTest {
    param(
        [string]$Computer,
        [PSCredential]$Cred
    )

    Write-Host "=== Start-Job Remote Session Test ===" -ForegroundColor Cyan

    if ($null -eq $Cred) {
        $Cred = Get-Credential -Message "Enter credentials"
    }

    # Extract credential components (same as main script)
    $credUsername = $Cred.UserName
    $credPassword = $Cred.Password

    Write-Host "Username: $credUsername" -ForegroundColor Gray
    Write-Host "Password type: $($credPassword.GetType().Name)" -ForegroundColor Gray

    # Clear PSDefaultParameterValues before starting job
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
    $job = Start-Job -Name "Test-Job" -ArgumentList $Computer, $credUsername, $credPassword -ScriptBlock {
        param($Comp, $UserName, $SecurePass)

        # Clear defaults inside job too
        $PSDefaultParameterValues.Clear()

        $result = @{
            Step     = "Init"
            Success  = $false
            Error    = ""
            Hostname = ""
        }

        try {
            $result.Step = "Creating credential"
            $cred = New-Object System.Management.Automation.PSCredential($UserName, $SecurePass)

            $result.Step = "Creating session"
            $session = New-PSSession -ComputerName $Comp -Credential $cred -Authentication Default -ErrorAction Stop

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
}
#endregion

#region JobFull Test
function Invoke-JobFullTest {
    param(
        [string]$Computer,
        [PSCredential]$Cred,
        [string]$OutPath
    )

    Write-Host "=== Full Job Test with Section Tracing ===" -ForegroundColor Cyan

    if ($null -eq $Cred) {
        $Cred = Get-Credential -Message "Enter credentials"
    }

    # Setup
    $credUsername = $Cred.UserName
    $credPassword = $Cred.Password
    New-Item -ItemType Directory -Path $OutPath -Force | Out-Null

    $PSDefaultParameterValues.Clear()

    Write-Host "Starting job with full scriptblock..." -ForegroundColor Yellow

    $job = Start-Job -Name "FullTest" -ArgumentList $Computer, $credUsername, $credPassword, $OutPath -ScriptBlock {
        param($Comp, $UserName, $SecurePass, $OutputRoot)

        $PSDefaultParameterValues.Clear()

        $log = @()
        $log += "=== Job Started ==="

        try {
            # Section 1: Credential
            $log += "Section 1: Creating credential..."
            $Cred = New-Object System.Management.Automation.PSCredential($UserName, $SecurePass)
            $log += "  OK"

            # Section 2: Session
            $log += "Section 2: Creating session..."
            $session = New-PSSession -ComputerName $Comp -Credential $Cred -Authentication Default -ErrorAction Stop
            $log += "  OK: Session ID $($session.Id)"

            # Section 3: Create folder
            $log += "Section 3: Creating output folder..."
            $computerFolder = Join-Path $OutputRoot $Comp
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
                }
                else {
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
                            Path     = $file.FullName
                            Name     = $file.Name
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
                        OSName       = if ($os) { $os.Caption } else { "Unknown" }
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
    Write-Host "Output saved to: $OutPath\$Computer" -ForegroundColor Cyan
}
#endregion

#region SimpleScan
function Invoke-SimpleScan {
    param(
        [string]$ComputerList,
        [string]$OutPath,
        [PSCredential]$Cred,
        [switch]$SkipWritable
    )

    # Validate inputs
    if (!(Test-Path -Path $ComputerList)) {
        throw "Computer list not found: $ComputerList"
    }

    # Create output directory
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputRoot = Join-Path $OutPath "Scan-$timestamp"
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

    # Get credentials if not provided
    if ($null -eq $Cred) {
        $Cred = Get-Credential -Message "Enter credentials for remote connections"
    }

    if ($null -eq $Cred) {
        throw "Credentials required"
    }

    # Load computer list
    $computers = @(Get-Content -Path $ComputerList | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })

    if ($computers.Count -eq 0) {
        throw "No computers found in $ComputerList"
    }

    Write-Host "=== Simple Remote Scanner (Debug Mode) ===" -ForegroundColor Cyan
    Write-Host "Computers to scan: $($computers.Count)" -ForegroundColor Cyan
    Write-Host "Output: $outputRoot" -ForegroundColor Cyan
    Write-Host "Processing sequentially (no parallel jobs)" -ForegroundColor Yellow
    Write-Host ""

    $results = @()
    $computerNum = 0

    foreach ($computer in $computers) {
        $computerNum++
        Write-Host "[$computerNum/$($computers.Count)] Scanning: $computer" -ForegroundColor Cyan

        $result = [PSCustomObject]@{
            Computer    = $computer
            Status      = "Failed"
            Message     = ""
            ExeCount    = 0
            SignedCount = 0
        }

        $session = $null

        try {
            # Create session
            Write-Host "  Creating session..." -ForegroundColor Gray
            $session = New-PSSession -ComputerName $computer -Credential $Cred -Authentication Default -ErrorAction Stop
            Write-Host "  Session created" -ForegroundColor Green

            # Create output folder
            $computerFolder = Join-Path $outputRoot $computer
            New-Item -ItemType Directory -Path $computerFolder -Force | Out-Null

            # 1. AppLocker Policy
            Write-Host "  Getting AppLocker policy..." -ForegroundColor Gray
            try {
                $policyXml = Invoke-Command -Session $session -ScriptBlock {
                    Get-AppLockerPolicy -Effective -Xml -ErrorAction SilentlyContinue
                }
                if ($policyXml) {
                    $policyXml | Out-File -FilePath (Join-Path $computerFolder "AppLockerPolicy.xml") -Encoding UTF8
                    Write-Host "    Saved AppLockerPolicy.xml" -ForegroundColor Green
                }
                else {
                    Write-Host "    No policy configured" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # 2. Installed Software
            Write-Host "  Getting installed software..." -ForegroundColor Gray
            try {
                $software = Invoke-Command -Session $session -ScriptBlock {
                    $paths = @(
                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                    )
                    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName } |
                        Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation |
                        Sort-Object DisplayName
                }
                if ($software) {
                    $software | Export-Csv -Path (Join-Path $computerFolder "InstalledSoftware.csv") -NoTypeInformation
                    Write-Host "    Saved InstalledSoftware.csv ($($software.Count) items)" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # 3. Executables (simplified - just Program Files)
            Write-Host "  Scanning executables (this may take a while)..." -ForegroundColor Gray
            try {
                $exeData = Invoke-Command -Session $session -ScriptBlock {
                    $executables = @()
                    $scanPaths = @($env:ProgramFiles)

                    foreach ($basePath in $scanPaths) {
                        if (!(Test-Path $basePath)) { continue }

                        $files = Get-ChildItem -Path $basePath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue |
                            Select-Object -First 500

                        foreach ($file in $files) {
                            try {
                                $sig = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue
                                $executables += [PSCustomObject]@{
                                    Path      = $file.FullName
                                    Name      = $file.Name
                                    IsSigned  = ($sig.Status -eq "Valid")
                                    Publisher = if ($sig.SignerCertificate -and $sig.SignerCertificate.Subject -match "O=([^,]+)") {
                                        $matches[1].Trim('"')
                                    }
                                    else { "" }
                                }
                            }
                            catch { continue }
                        }
                    }
                    return $executables
                }

                if ($exeData) {
                    $exeData | Export-Csv -Path (Join-Path $computerFolder "Executables.csv") -NoTypeInformation
                    $result.ExeCount = $exeData.Count
                    $result.SignedCount = ($exeData | Where-Object { $_.IsSigned }).Count
                    Write-Host "    Saved Executables.csv ($($exeData.Count) files, $($result.SignedCount) signed)" -ForegroundColor Green

                    # Publishers summary
                    $publishers = $exeData | Where-Object { $_.Publisher -and $_.IsSigned } |
                        Group-Object Publisher | Select-Object @{N = "Publisher"; E = { $_.Name } }, Count |
                        Sort-Object Count -Descending
                    if ($publishers) {
                        $publishers | Export-Csv -Path (Join-Path $computerFolder "Publishers.csv") -NoTypeInformation
                        Write-Host "    Saved Publishers.csv ($($publishers.Count) unique)" -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # 4. System Info
            Write-Host "  Getting system info..." -ForegroundColor Gray
            try {
                $osInfo = Invoke-Command -Session $session -ScriptBlock {
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                    [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        OSName       = if ($os) { $os.Caption } else { "Unknown" }
                        OSVersion    = if ($os) { $os.Version } else { "Unknown" }
                    }
                }
                if ($osInfo) {
                    $osInfo | Export-Csv -Path (Join-Path $computerFolder "SystemInfo.csv") -NoTypeInformation
                    Write-Host "    Saved SystemInfo.csv" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            $result.Status = "Success"
            Write-Host "  DONE: $computer" -ForegroundColor Green
        }
        catch {
            $result.Message = $_.Exception.Message
            Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            if ($session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }

        $results += $result
        Write-Host ""
    }

    # Save results
    $results | Export-Csv -Path (Join-Path $outputRoot "ScanResults.csv") -NoTypeInformation

    # Summary
    $successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
    $failCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count

    Write-Host "=== Scan Complete ===" -ForegroundColor Green
    Write-Host "Success: $successCount / $($computers.Count)" -ForegroundColor $(if ($successCount -eq $computers.Count) { "Green" } else { "Yellow" })
    Write-Host "Output: $outputRoot" -ForegroundColor Cyan

    if ($failCount -gt 0) {
        Write-Host "`nFailed:" -ForegroundColor Red
        $results | Where-Object { $_.Status -eq "Failed" } | ForEach-Object {
            Write-Host "  $($_.Computer): $($_.Message)" -ForegroundColor Red
        }
    }

    return $outputRoot
}
#endregion

#region Main Execution

# Validate parameters based on test type
switch ($TestType) {
    "Connectivity" {
        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            $ComputerName = Read-Host "Enter computer name to test"
        }
        Invoke-ConnectivityTest -Computer $ComputerName -Cred $Credential
    }
    "JobSession" {
        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            $ComputerName = Read-Host "Enter computer name to test"
        }
        Invoke-JobSessionTest -Computer $ComputerName -Cred $Credential
    }
    "JobFull" {
        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            $ComputerName = Read-Host "Enter computer name to test"
        }
        Invoke-JobFullTest -Computer $ComputerName -Cred $Credential -OutPath $OutputPath
    }
    "SimpleScan" {
        if ([string]::IsNullOrWhiteSpace($ComputerListPath)) {
            $ComputerListPath = Read-Host "Enter path to computer list file"
        }
        Invoke-SimpleScan -ComputerList $ComputerListPath -OutPath $OutputPath -Cred $Credential -SkipWritable:$SkipWritableDirectoryScan
    }
}

#endregion
