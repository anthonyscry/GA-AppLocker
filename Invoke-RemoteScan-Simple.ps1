<#
.SYNOPSIS
    Simplified remote scan - NO parallel jobs, direct execution.
    Use this version to debug what's failing.

.DESCRIPTION
    This is a stripped-down version of Invoke-RemoteScan.ps1 that:
    - Processes ONE computer at a time (no parallelization)
    - Uses direct Invoke-Command (no Start-Job)
    - Shows detailed progress and errors
    - Still collects the same data

    Once this works, you know the job-based version has the issue.

.EXAMPLE
    .\Invoke-RemoteScan-Simple.ps1 -ComputerListPath .\computers.txt -SharePath .\Scans
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerListPath,

    [Parameter(Mandatory=$true)]
    [string]$SharePath,

    [PSCredential]$Credential,

    [switch]$SkipWritableDirectoryScan
)

$ErrorActionPreference = 'Continue'

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
    $Credential = Get-Credential -Message "Enter credentials for remote connections"
}

if ($null -eq $Credential) {
    throw "Credentials required"
}

# Load computer list
$computers = @(Get-Content -Path $ComputerListPath | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })

if ($computers.Count -eq 0) {
    throw "No computers found in $ComputerListPath"
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
        Computer = $computer
        Status = "Failed"
        Message = ""
        ExeCount = 0
        SignedCount = 0
    }

    $session = $null

    try {
        # Create session
        Write-Host "  Creating session..." -ForegroundColor Gray
        $session = New-PSSession -ComputerName $computer -Credential $Credential -Authentication Default -ErrorAction Stop
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
            } else {
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
                                Path = $file.FullName
                                Name = $file.Name
                                IsSigned = ($sig.Status -eq "Valid")
                                Publisher = if ($sig.SignerCertificate -and $sig.SignerCertificate.Subject -match "O=([^,]+)") {
                                    $matches[1].Trim('"')
                                } else { "" }
                            }
                        }
                        catch { }
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
                    Group-Object Publisher | Select-Object @{N="Publisher";E={$_.Name}}, Count |
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
                    OSName = if ($os) { $os.Caption } else { "Unknown" }
                    OSVersion = if ($os) { $os.Version } else { "Unknown" }
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
