<#
.SYNOPSIS
    Remotely collects AppLocker data from target computers for policy creation.

.DESCRIPTION
    Part of GA-AppLocker toolkit. Use Start-AppLockerWorkflow.ps1 for guided experience.

    This script connects to remote computers via WinRM (Windows Remote Management) and
    collects comprehensive data needed for AppLocker policy creation:

    Data Collected:
    - Current AppLocker policy (if any) - exported as XML
    - Installed software from registry (both 32-bit and 64-bit)
    - Signed executables with publisher information (for publisher rules)
    - User-writable directories (critical for security - deny rules)
    - Running processes and their paths (shows what's actively executing)
    - System information (OS version, architecture, domain)

    This data is consumed by New-AppLockerPolicy.ps1 to create comprehensive policies.

    Key Features:
    - Modernized for Windows 11/Server 2019+ (no AccessChk.exe dependency)
    - Uses native PowerShell ACL inspection for writable directory detection
    - Parallel processing with configurable throttle limit
    - Extracts publisher info from Authenticode signatures
    - Calculates SHA256 hashes for hash-based rules

    Authentication Note:
    - Uses '-Authentication Default' to work around environments with
      $PSDefaultParameterValues["*:Authentication"] = "None" set in profiles
    - Jobs explicitly remove this default at start of script block

.PARAMETER ComputerListPath
    Path to a text file containing one computer name per line.
    Empty lines and whitespace are ignored.

.PARAMETER SharePath
    UNC path (or local path) to save collected results.
    A timestamped subfolder will be created automatically.

.PARAMETER Credential
    Credential for remote connections (DOMAIN\username format).
    If not provided, prompts interactively.

.PARAMETER ThrottleLimit
    Maximum concurrent connections (default: 10).
    Increase for faster scans, decrease if overwhelming the network.

.PARAMETER ScanPaths
    Additional paths to scan for executables beyond the defaults.
    Default paths: Program Files, Windows\System32, Windows\SysWOW64

.PARAMETER ScanUserProfiles
    Also scan user profile directories (AppData, Desktop, Downloads).
    Important for finding user-installed applications.

.PARAMETER SkipWritableDirectoryScan
    Skip the scan for user-writable directories.
    Faster but misses critical security information.

.EXAMPLE
    # Basic scan of computers listed in text file
    .\Invoke-RemoteScan.ps1 -ComputerListPath .\computers.txt -SharePath \\server\share\Scans

.EXAMPLE
    # Include user profile scanning for more thorough results
    .\Invoke-RemoteScan.ps1 -ComputerListPath .\computers.txt -SharePath \\server\share\Scans -ScanUserProfiles

.EXAMPLE
    # Fast scan skipping writable directory detection
    .\Invoke-RemoteScan.ps1 -ComputerListPath .\computers.txt -SharePath .\LocalScans -SkipWritableDirectoryScan

.NOTES
    Requires: PowerShell 5.1+
    Requires: WinRM enabled on target computers (Enable-PSRemoting)
    Requires: Admin credentials with remote access to targets
    Requires: Firewall allowing WinRM (TCP 5985/5986)

    Output Structure:
    ├── Scan-{timestamp}/
    │   ├── ScanResults.csv          (summary log)
    │   ├── COMPUTER1/
    │   │   ├── AppLockerPolicy.xml  (current policy if any)
    │   │   ├── InstalledSoftware.csv
    │   │   ├── Executables.csv      (with signature info)
    │   │   ├── Publishers.csv       (unique publishers found)
    │   │   ├── WritableDirectories.csv
    │   │   ├── RunningProcesses.csv
    │   │   └── SystemInfo.csv
    │   └── COMPUTER2/
    │       └── ...

    Author: AaronLocker Simplified Scripts
    Version: 2.0 (Windows 11/Server 2019+ compatible)

.LINK
    New-AppLockerPolicy.ps1 - Creates policies from this scan data
    Merge-AppLockerPolicies.ps1 - Merges multiple policies together
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerListPath,

    [Parameter(Mandatory=$true)]
    [string]$SharePath,

    [PSCredential]$Credential,

    [int]$ThrottleLimit = 10,

    [string[]]$ScanPaths = @(),

    [switch]$ScanUserProfiles,

    [switch]$SkipWritableDirectoryScan
)

#Requires -Version 5.1

# Import utilities module and config
$scriptRoot = $PSScriptRoot
$modulePath = Join-Path $scriptRoot "utilities\Common.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    $config = Get-AppLockerConfig
}
else {
    $config = $null
}

# Validate inputs
if (!(Test-Path -Path $ComputerListPath)) {
    throw "Computer list not found: $ComputerListPath"
}

# Create output directory
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputRoot = Join-Path $SharePath "Scan-$timestamp"
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

# Get credentials if not provided
if ($null -eq $Credential) {
    $Credential = Get-Credential -Message "Enter credentials for remote connections (DOMAIN\username)"
}

# Load computer list
$computers = Get-Content -Path $ComputerListPath |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_.Trim() }

if ($computers.Count -eq 0) {
    throw "No computers found in $ComputerListPath"
}

Write-Host "=== AaronLocker Remote Scanner ===" -ForegroundColor Cyan
Write-Host "Scanning $($computers.Count) computers..." -ForegroundColor Cyan
Write-Host "Results will be saved to: $outputRoot" -ForegroundColor Cyan
Write-Host ""

# Results collection
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Process each computer
$jobCount = 0

foreach ($computer in $computers) {
    $jobCount++
    Write-Host "[$jobCount/$($computers.Count)] Starting: $computer" -ForegroundColor Gray

    # Start job for this computer
    Start-Job -Name "Scan-$computer" -ArgumentList $computer, $Credential, $outputRoot, $ScanPaths, $ScanUserProfiles.IsPresent, $SkipWritableDirectoryScan.IsPresent -ScriptBlock {
        param($Computer, $Credential, $OutputRoot, $ExtraScanPaths, $ScanUserProfiles, $SkipWritableScan)

        # Clear any problematic defaults
        $PSDefaultParameterValues.Remove("*:Authentication")

        $start = Get-Date
        $result = [PSCustomObject]@{
            Computer = $Computer
            Status = "Failed"
            Message = ""
            StartTime = $start
            EndTime = $null
            ExeCount = 0
            SignedCount = 0
            WritableDirCount = 0
        }

        try {
            # Test connectivity and create session
            $session = New-PSSession -ComputerName $Computer -Credential $Credential -Authentication Default -ErrorAction Stop

            # Create output folder for this computer
            $computerFolder = Join-Path $OutputRoot $Computer
            New-Item -ItemType Directory -Path $computerFolder -Force | Out-Null

            #region 1. Export current AppLocker policy
            $policyXml = Invoke-Command -Session $session -ScriptBlock {
                try {
                    Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
                }
                catch { $null }
            }

            if ($null -ne $policyXml -and $policyXml.Length -gt 0) {
                $policyXml | Out-File -FilePath (Join-Path $computerFolder "AppLockerPolicy.xml") -Encoding UTF8
            }
            #endregion

            #region 2. Collect installed software from registry
            $software = Invoke-Command -Session $session -ScriptBlock {
                $paths = @(
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName } |
                    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation |
                    Sort-Object DisplayName
            }

            if ($null -ne $software -and $software.Count -gt 0) {
                $software | Export-Csv -Path (Join-Path $computerFolder "InstalledSoftware.csv") -NoTypeInformation
            }
            #endregion

            #region 3. Scan for executables and extract publisher info
            $exeData = Invoke-Command -Session $session -ArgumentList $ExtraScanPaths, $ScanUserProfiles -ScriptBlock {
                param($ExtraPaths, $IncludeUserProfiles)

                $scanPaths = @(
                    $env:ProgramFiles,
                    ${env:ProgramFiles(x86)},
                    "$env:SystemRoot\System32",
                    "$env:SystemRoot\SysWOW64"
                )

                # Add user profiles if requested
                if ($IncludeUserProfiles) {
                    $scanPaths += "$env:SystemDrive\Users\*\AppData\Local\Programs"
                    $scanPaths += "$env:SystemDrive\Users\*\AppData\Local\Microsoft"
                    $scanPaths += "$env:SystemDrive\Users\*\Desktop"
                    $scanPaths += "$env:SystemDrive\Users\*\Downloads"
                }

                # Add any extra paths
                if ($ExtraPaths) {
                    $scanPaths += $ExtraPaths
                }

                $executables = @()
                $extensions = @("*.exe", "*.dll", "*.msi", "*.ps1", "*.bat", "*.cmd", "*.vbs", "*.js")

                foreach ($basePath in $scanPaths) {
                    if (!(Test-Path $basePath -ErrorAction SilentlyContinue)) { continue }

                    foreach ($ext in $extensions) {
                        try {
                            $files = Get-ChildItem -Path $basePath -Filter $ext -Recurse -ErrorAction SilentlyContinue -Force |
                                Select-Object -First 5000  # Limit per path to avoid timeout

                            foreach ($file in $files) {
                                try {
                                    $sig = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue

                                    $executables += [PSCustomObject]@{
                                        Path = $file.FullName
                                        Name = $file.Name
                                        Extension = $file.Extension
                                        Size = $file.Length
                                        LastWriteTime = $file.LastWriteTime
                                        IsSigned = ($sig.Status -eq "Valid")
                                        SignerCertificate = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "" }
                                        Publisher = if ($sig.SignerCertificate) {
                                            # Extract O= from certificate subject
                                            if ($sig.SignerCertificate.Subject -match "O=([^,]+)") {
                                                $matches[1].Trim('"')
                                            } else { "" }
                                        } else { "" }
                                        Hash = try {
                                            (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                                        } catch { "" }
                                    }
                                }
                                catch { }
                            }
                        }
                        catch { }
                    }
                }

                return $executables
            }

            if ($null -ne $exeData -and $exeData.Count -gt 0) {
                $exeData | Export-Csv -Path (Join-Path $computerFolder "Executables.csv") -NoTypeInformation
                $result.ExeCount = $exeData.Count
                $result.SignedCount = ($exeData | Where-Object { $_.IsSigned }).Count

                # Also create a summary of unique publishers
                $publishers = $exeData |
                    Where-Object { $_.Publisher -and $_.IsSigned } |
                    Group-Object Publisher |
                    Select-Object @{N="Publisher";E={$_.Name}}, Count |
                    Sort-Object Count -Descending

                if ($publishers.Count -gt 0) {
                    $publishers | Export-Csv -Path (Join-Path $computerFolder "Publishers.csv") -NoTypeInformation
                }
            }
            #endregion

            #region 4. Scan for user-writable directories (core AaronLocker functionality)
            if (-not $SkipWritableScan) {
                $writableDirs = Invoke-Command -Session $session -ScriptBlock {
                    $writable = @()
                    $checkPaths = @(
                        "$env:SystemRoot",
                        $env:ProgramFiles,
                        ${env:ProgramFiles(x86)}
                    )

                    # Get current user's SID for comparison
                    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                    $userSid = $currentUser.User.Value

                    # Well-known SIDs for non-admin groups
                    $nonAdminSids = @(
                        "S-1-1-0",        # Everyone
                        "S-1-5-11",       # Authenticated Users
                        "S-1-5-32-545",   # Users
                        $userSid
                    )

                    foreach ($basePath in $checkPaths) {
                        if (!(Test-Path $basePath)) { continue }

                        try {
                            $dirs = Get-ChildItem -Path $basePath -Directory -Recurse -ErrorAction SilentlyContinue -Force |
                                Select-Object -First 2000  # Limit to avoid timeout

                            foreach ($dir in $dirs) {
                                try {
                                    $acl = Get-Acl -Path $dir.FullName -ErrorAction SilentlyContinue
                                    if ($null -eq $acl) { continue }

                                    foreach ($ace in $acl.Access) {
                                        # Check if non-admin has write access
                                        $sid = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value

                                        if ($nonAdminSids -contains $sid) {
                                            $rights = $ace.FileSystemRights.ToString()
                                            if ($rights -match "Write|Modify|FullControl|CreateFiles") {
                                                $writable += [PSCustomObject]@{
                                                    Path = $dir.FullName
                                                    Identity = $ace.IdentityReference.Value
                                                    Rights = $rights
                                                    AccessType = $ace.AccessControlType.ToString()
                                                }
                                                break  # Found writable, move to next dir
                                            }
                                        }
                                    }
                                }
                                catch { }
                            }
                        }
                        catch { }
                    }

                    return $writable
                }

                if ($null -ne $writableDirs -and $writableDirs.Count -gt 0) {
                    $writableDirs | Export-Csv -Path (Join-Path $computerFolder "WritableDirectories.csv") -NoTypeInformation
                    $result.WritableDirCount = $writableDirs.Count
                }
            }
            #endregion

            #region 5. Get OS and system info
            $osInfo = Invoke-Command -Session $session -ScriptBlock {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem
                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    OSName = $os.Caption
                    OSVersion = $os.Version
                    OSBuild = $os.BuildNumber
                    Architecture = $os.OSArchitecture
                    Domain = $cs.Domain
                    Manufacturer = $cs.Manufacturer
                    Model = $cs.Model
                    TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
                }
            }

            $osInfo | Export-Csv -Path (Join-Path $computerFolder "SystemInfo.csv") -NoTypeInformation
            #endregion

            #region 6. Get running processes (to see what's actually executing)
            $processes = Invoke-Command -Session $session -ScriptBlock {
                Get-Process | Where-Object { $_.Path } |
                    Select-Object Name, Path, Company, ProductVersion, Description |
                    Sort-Object Path -Unique
            }

            if ($null -ne $processes -and $processes.Count -gt 0) {
                $processes | Export-Csv -Path (Join-Path $computerFolder "RunningProcesses.csv") -NoTypeInformation
            }
            #endregion

            Remove-PSSession $session
            $result.Status = "Success"
        }
        catch {
            $result.Message = $_.Exception.Message
        }
        finally {
            $result.EndTime = Get-Date
        }

        return $result
    } | Out-Null

    # Throttle: wait if we have too many jobs
    while ((Get-Job -State Running).Count -ge $ThrottleLimit) {
        Start-Sleep -Seconds 2
    }
}

# Wait for all jobs to complete
Write-Host "`nWaiting for scans to complete..." -ForegroundColor Yellow

$allJobs = Get-Job -Name "Scan-*"
$completedCount = 0

while ((Get-Job -Name "Scan-*" -State Running).Count -gt 0) {
    $newCompleted = (Get-Job -Name "Scan-*" -State Completed).Count
    if ($newCompleted -gt $completedCount) {
        $completedCount = $newCompleted
        Write-Host "  Completed: $completedCount / $($computers.Count)" -ForegroundColor Gray
    }
    Start-Sleep -Seconds 3
}

# Collect results
foreach ($job in $allJobs) {
    $jobResult = Receive-Job -Job $job
    if ($null -ne $jobResult) {
        $results.Add($jobResult)
    }
    Remove-Job -Job $job
}

# Export results log
$logPath = Join-Path $outputRoot "ScanResults.csv"
$results | Export-Csv -Path $logPath -NoTypeInformation

# Summary
$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
$failCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count
$totalExes = ($results | Measure-Object -Property ExeCount -Sum).Sum
$totalSigned = ($results | Measure-Object -Property SignedCount -Sum).Sum
$totalWritable = ($results | Measure-Object -Property WritableDirCount -Sum).Sum

Write-Host "`n=== Scan Complete ===" -ForegroundColor Green
Write-Host "Computers scanned: $($results.Count)" -ForegroundColor Cyan
Write-Host "  Success: $successCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host "Data collected:" -ForegroundColor Cyan
Write-Host "  Executables found: $totalExes" -ForegroundColor Gray
Write-Host "  Signed executables: $totalSigned" -ForegroundColor Gray
Write-Host "  Writable directories: $totalWritable" -ForegroundColor Gray
Write-Host ""
Write-Host "Results saved to: $outputRoot" -ForegroundColor Cyan
Write-Host "Log file: $logPath" -ForegroundColor Cyan

# Show failures
$failures = $results | Where-Object { $_.Status -eq "Failed" }
if ($failures.Count -gt 0) {
    Write-Host "`nFailed computers:" -ForegroundColor Yellow
    foreach ($f in $failures) {
        Write-Host "  $($f.Computer): $($f.Message)" -ForegroundColor Red
    }
}

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Review Publishers.csv files to see what software is signed" -ForegroundColor White
Write-Host "  2. Review WritableDirectories.csv for security concerns" -ForegroundColor White
Write-Host "  3. Run: .\Merge-AppLockerPolicies.ps1 -InputPath '$outputRoot'" -ForegroundColor White
