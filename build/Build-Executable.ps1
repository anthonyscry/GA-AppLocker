<#
.SYNOPSIS
    Build portable executable from GA-AppLocker PowerShell scripts.

.DESCRIPTION
    Uses PS2EXE to convert Start-AppLockerWorkflow.ps1 into a standalone .exe file.
    Bundles all required modules and scripts into the executable.
    Includes code review with PSScriptAnalyzer before building.

.PARAMETER OutputName
    Name of the output executable (default: GA-AppLocker.exe)

.PARAMETER NoConsole
    Build as Windows GUI app (no console window). Default is console app.

.PARAMETER RequireAdmin
    Require administrator privileges to run.

.PARAMETER SkipCodeReview
    Skip the PSScriptAnalyzer code review step.

.PARAMETER FixIssues
    Attempt to auto-fix issues found by PSScriptAnalyzer.

.EXAMPLE
    .\Build-Executable.ps1

.EXAMPLE
    .\Build-Executable.ps1 -OutputName "AppLockerTool.exe" -RequireAdmin

.EXAMPLE
    .\Build-Executable.ps1 -SkipCodeReview
#>

param(
    [string]$OutputName = "GA-AppLocker.exe",
    [switch]$NoConsole,
    [switch]$RequireAdmin,
    [switch]$SkipCodeReview,
    [switch]$FixIssues
)

$ErrorActionPreference = "Stop"
$BuildScriptRoot = $PSScriptRoot
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$SrcRoot = Join-Path $ProjectRoot "src"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  GA-AppLocker Executable Builder" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================
# CODE REVIEW WITH PSSCRIPTANALYZER
# ============================================

if (-not $SkipCodeReview) {
    Write-Host "[*] Running code review with PSScriptAnalyzer..." -ForegroundColor Yellow

    # Check if PSScriptAnalyzer is installed
    $psaModule = Get-Module -ListAvailable -Name PSScriptAnalyzer
    if (-not $psaModule) {
        Write-Host "    Installing PSScriptAnalyzer..." -ForegroundColor Gray
        try {
            Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber
        }
        catch {
            Write-Host "[!] Could not install PSScriptAnalyzer. Skipping code review." -ForegroundColor Yellow
            $SkipCodeReview = $true
        }
    }

    if (-not $SkipCodeReview) {
        Import-Module PSScriptAnalyzer -Force

        # Define scripts to analyze (relative to SrcRoot)
        $ScriptsToAnalyze = @(
            "Core\Start-AppLockerWorkflow.ps1",
            "Core\Invoke-RemoteScan.ps1",
            "Core\Invoke-RemoteEventCollection.ps1",
            "Core\New-AppLockerPolicyFromGuide.ps1",
            "Core\Merge-AppLockerPolicies.ps1",
            "Utilities\Common.psm1",
            "Utilities\Manage-SoftwareLists.ps1",
            "Utilities\Test-AppLockerDiagnostic.ps1",
            "Utilities\Compare-SoftwareInventory.ps1"
        )

        $TotalIssues = 0
        $ErrorCount = 0
        $WarningCount = 0
        $InfoCount = 0
        $AllIssues = @()

        Write-Host ""
        foreach ($script in $ScriptsToAnalyze) {
            $scriptPath = Join-Path $SrcRoot $script
            if (Test-Path $scriptPath) {
                $issues = Invoke-ScriptAnalyzer -Path $scriptPath -Severity @('Error', 'Warning', 'Information')

                if ($issues) {
                    $scriptErrors = ($issues | Where-Object { $_.Severity -eq 'Error' }).Count
                    $scriptWarnings = ($issues | Where-Object { $_.Severity -eq 'Warning' }).Count
                    $scriptInfo = ($issues | Where-Object { $_.Severity -eq 'Information' }).Count

                    $ErrorCount += $scriptErrors
                    $WarningCount += $scriptWarnings
                    $InfoCount += $scriptInfo
                    $TotalIssues += $issues.Count

                    foreach ($issue in $issues) {
                        $AllIssues += [PSCustomObject]@{
                            Script = $script
                            Line = $issue.Line
                            Severity = $issue.Severity
                            Rule = $issue.RuleName
                            Message = $issue.Message
                        }
                    }

                    $statusIcon = if ($scriptErrors -gt 0) { "X" } elseif ($scriptWarnings -gt 0) { "!" } else { "i" }
                    $statusColor = if ($scriptErrors -gt 0) { "Red" } elseif ($scriptWarnings -gt 0) { "Yellow" } else { "Cyan" }
                    Write-Host "    [$statusIcon] $script - $($issues.Count) issue(s)" -ForegroundColor $statusColor
                }
                else {
                    Write-Host "    [+] $script - No issues" -ForegroundColor Green
                }
            }
        }

        Write-Host ""

        # Summary
        if ($TotalIssues -gt 0) {
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "  Code Review Summary" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "  Errors:      $ErrorCount" -ForegroundColor $(if ($ErrorCount -gt 0) { "Red" } else { "Green" })
            Write-Host "  Warnings:    $WarningCount" -ForegroundColor $(if ($WarningCount -gt 0) { "Yellow" } else { "Green" })
            Write-Host "  Information: $InfoCount" -ForegroundColor Cyan
            Write-Host "  Total:       $TotalIssues" -ForegroundColor White
            Write-Host ""

            # Show detailed issues
            if ($ErrorCount -gt 0) {
                Write-Host "ERRORS (must fix):" -ForegroundColor Red
                $AllIssues | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object {
                    Write-Host "  $($_.Script):$($_.Line) - $($_.Rule)" -ForegroundColor Red
                    Write-Host "    $($_.Message)" -ForegroundColor Gray
                }
                Write-Host ""
            }

            if ($WarningCount -gt 0 -and $ErrorCount -eq 0) {
                Write-Host "WARNINGS (recommended to fix):" -ForegroundColor Yellow
                $AllIssues | Where-Object { $_.Severity -eq 'Warning' } | Select-Object -First 10 | ForEach-Object {
                    Write-Host "  $($_.Script):$($_.Line) - $($_.Rule)" -ForegroundColor Yellow
                    Write-Host "    $($_.Message)" -ForegroundColor Gray
                }
                if ($WarningCount -gt 10) {
                    Write-Host "  ... and $($WarningCount - 10) more warnings" -ForegroundColor Yellow
                }
                Write-Host ""
            }

            # Block build on errors
            if ($ErrorCount -gt 0) {
                Write-Host "[!] Build blocked: $ErrorCount error(s) found. Fix errors before building." -ForegroundColor Red
                Write-Host "    Run with -SkipCodeReview to bypass (not recommended)" -ForegroundColor Gray
                exit 1
            }

            # Warn but continue on warnings
            if ($WarningCount -gt 0) {
                Write-Host "[*] Proceeding with build despite $WarningCount warning(s)..." -ForegroundColor Yellow
            }

            # Export full report
            $ReportPath = Join-Path $BuildScriptRoot "code-review-report.json"
            $AllIssues | ConvertTo-Json -Depth 3 | Set-Content -Path $ReportPath
            Write-Host "[*] Full report saved to: $ReportPath" -ForegroundColor Gray
            Write-Host ""
        }
        else {
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "  Code Review: All Clear!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "  No issues found in any scripts." -ForegroundColor Green
            Write-Host ""
        }
    }
}
else {
    Write-Host "[*] Skipping code review (--SkipCodeReview specified)" -ForegroundColor Gray
}

# ============================================
# BUILD PROCESS
# ============================================

# Check if PS2EXE is installed
$ps2exeModule = Get-Module -ListAvailable -Name ps2exe
if (-not $ps2exeModule) {
    Write-Host "[*] Installing PS2EXE module..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
        Write-Host "[+] PS2EXE installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Failed to install PS2EXE. Try running:" -ForegroundColor Red
        Write-Host "    Install-Module -Name ps2exe -Scope CurrentUser -Force" -ForegroundColor White
        exit 1
    }
}

Import-Module ps2exe -Force

# Create build directory
$BuildDir = Join-Path $BuildScriptRoot "build"
$DistDir = Join-Path $BuildScriptRoot "dist"

if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force }
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir -Force | Out-Null }

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

Write-Host "[*] Preparing build..." -ForegroundColor Yellow

# Create a consolidated script that embeds all dependencies
$ConsolidatedScript = Join-Path $BuildDir "GA-AppLocker-Consolidated.ps1"

# Read the Common module
$CommonModule = Get-Content (Join-Path $SrcRoot "Utilities\Common.psm1") -Raw
$ConfigData = Get-Content (Join-Path $SrcRoot "Utilities\Config.psd1") -Raw

# Read all the main scripts
$MainWorkflow = Get-Content (Join-Path $SrcRoot "Core\Start-AppLockerWorkflow.ps1") -Raw
$RemoteScan = Get-Content (Join-Path $SrcRoot "Core\Invoke-RemoteScan.ps1") -Raw
$EventCollection = Get-Content (Join-Path $SrcRoot "Core\Invoke-RemoteEventCollection.ps1") -Raw
$PolicyGenerator = Get-Content (Join-Path $SrcRoot "Core\New-AppLockerPolicyFromGuide.ps1") -Raw
$PolicyMerger = Get-Content (Join-Path $SrcRoot "Core\Merge-AppLockerPolicies.ps1") -Raw

# Read utility scripts
$SoftwareListMgr = Get-Content (Join-Path $SrcRoot "Utilities\Manage-SoftwareLists.ps1") -Raw
$DiagnosticTool = Get-Content (Join-Path $SrcRoot "Utilities\Test-AppLockerDiagnostic.ps1") -Raw
$CompareInventory = Get-Content (Join-Path $SrcRoot "Utilities\Compare-SoftwareInventory.ps1") -Raw

Write-Host "[*] Building consolidated script..." -ForegroundColor Yellow

# Build the consolidated script
$ConsolidatedContent = @"
<#
.SYNOPSIS
    GA-AppLocker - Portable Edition

.DESCRIPTION
    Standalone executable for GA-AppLocker toolkit.
    All modules and scripts are embedded.

.AUTHOR
    Tony Tran, ISSO, GA-ASI

.NOTES
    Built: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Version: 1.0.0
#>

`$ErrorActionPreference = "Continue"
`$Script:AppVersion = "1.0.0"
`$Script:BuildDate = "$(Get-Date -Format "yyyy-MM-dd")"

# ============================================
# EMBEDDED: Config.psd1
# ============================================
`$Script:EmbeddedConfig = @'
$ConfigData
'@

# ============================================
# EMBEDDED: Common.psm1
# ============================================
`$Script:EmbeddedCommonModule = @'
$CommonModule
'@

# ============================================
# EMBEDDED: Invoke-RemoteScan.ps1
# ============================================
`$Script:EmbeddedRemoteScan = @'
$RemoteScan
'@

# ============================================
# EMBEDDED: Invoke-RemoteEventCollection.ps1
# ============================================
`$Script:EmbeddedEventCollection = @'
$EventCollection
'@

# ============================================
# EMBEDDED: New-AppLockerPolicyFromGuide.ps1
# ============================================
`$Script:EmbeddedPolicyGenerator = @'
$PolicyGenerator
'@

# ============================================
# EMBEDDED: Merge-AppLockerPolicies.ps1
# ============================================
`$Script:EmbeddedPolicyMerger = @'
$PolicyMerger
'@

# ============================================
# EMBEDDED: Manage-SoftwareLists.ps1
# ============================================
`$Script:EmbeddedSoftwareListMgr = @'
$SoftwareListMgr
'@

# ============================================
# EMBEDDED: Test-AppLockerDiagnostic.ps1
# ============================================
`$Script:EmbeddedDiagnosticTool = @'
$DiagnosticTool
'@

# ============================================
# EMBEDDED: Compare-SoftwareInventory.ps1
# ============================================
`$Script:EmbeddedCompareInventory = @'
$CompareInventory
'@

# ============================================
# INITIALIZATION
# ============================================

# Create temp directory for extracted files
`$Script:TempDir = Join-Path `$env:TEMP "GA-AppLocker-`$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path `$Script:TempDir -Force | Out-Null

# Extract embedded files to temp
`$Script:ConfigPath = Join-Path `$Script:TempDir "Config.psd1"
`$Script:CommonPath = Join-Path `$Script:TempDir "Common.psm1"
`$Script:UtilitiesDir = Join-Path `$Script:TempDir "utilities"

New-Item -ItemType Directory -Path `$Script:UtilitiesDir -Force | Out-Null

# Write extracted files
`$Script:EmbeddedConfig | Set-Content -Path `$Script:ConfigPath -Force
`$Script:EmbeddedCommonModule | Set-Content -Path (Join-Path `$Script:UtilitiesDir "Common.psm1") -Force
`$Script:EmbeddedConfig | Set-Content -Path (Join-Path `$Script:UtilitiesDir "Config.psd1") -Force

# Extract scripts
`$Script:EmbeddedRemoteScan | Set-Content -Path (Join-Path `$Script:TempDir "Invoke-RemoteScan.ps1") -Force
`$Script:EmbeddedEventCollection | Set-Content -Path (Join-Path `$Script:TempDir "Invoke-RemoteEventCollection.ps1") -Force
`$Script:EmbeddedPolicyGenerator | Set-Content -Path (Join-Path `$Script:TempDir "New-AppLockerPolicyFromGuide.ps1") -Force
`$Script:EmbeddedPolicyMerger | Set-Content -Path (Join-Path `$Script:TempDir "Merge-AppLockerPolicies.ps1") -Force
`$Script:EmbeddedSoftwareListMgr | Set-Content -Path (Join-Path `$Script:UtilitiesDir "Manage-SoftwareLists.ps1") -Force
`$Script:EmbeddedDiagnosticTool | Set-Content -Path (Join-Path `$Script:UtilitiesDir "Test-AppLockerDiagnostic.ps1") -Force
`$Script:EmbeddedCompareInventory | Set-Content -Path (Join-Path `$Script:UtilitiesDir "Compare-SoftwareInventory.ps1") -Force

# Import common module
Import-Module (Join-Path `$Script:UtilitiesDir "Common.psm1") -Force -DisableNameChecking

# Change to temp directory context but remember original
`$Script:OriginalLocation = Get-Location
`$Script:WorkingDir = Get-Location

# Set PSScriptRoot equivalent for the embedded scripts
`$PSScriptRoot = `$Script:TempDir

# Cleanup function
function script:Cleanup-TempFiles {
    if (Test-Path `$Script:TempDir) {
        Remove-Item `$Script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Register cleanup on exit
`$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Cleanup-TempFiles
}

# ============================================
# MAIN WORKFLOW (from Start-AppLockerWorkflow.ps1)
# ============================================

$MainWorkflow

# Cleanup on normal exit
Cleanup-TempFiles
"@

# Write the consolidated script
$ConsolidatedContent | Set-Content -Path $ConsolidatedScript -Force -Encoding UTF8

Write-Host "[+] Consolidated script created: $ConsolidatedScript" -ForegroundColor Green

# Build parameters
$OutputPath = Join-Path $DistDir $OutputName
$IconFile = Join-Path $ProjectRoot "assets\general-atomics-large.ico"

$Ps2ExeParams = @{
    InputFile = $ConsolidatedScript
    OutputFile = $OutputPath
    Title = "GA-AppLocker"
    Description = "AppLocker Policy Deployment Toolkit"
    Company = "GA-ASI"
    Product = "GA-AppLocker"
    Version = "1.0.0.0"
    Copyright = "Tony Tran, ISSO"
}

# Add icon if it exists
if (Test-Path $IconFile) {
    $Ps2ExeParams.Add("IconFile", $IconFile)
    Write-Host "[+] Using icon: $IconFile" -ForegroundColor Green
}

if ($NoConsole) {
    $Ps2ExeParams.Add("NoConsole", $true)
}

if ($RequireAdmin) {
    $Ps2ExeParams.Add("RequireAdmin", $true)
}

Write-Host "[*] Converting to executable..." -ForegroundColor Yellow
Write-Host "    Output: $OutputPath" -ForegroundColor Gray

try {
    Invoke-ps2exe @Ps2ExeParams

    if (Test-Path $OutputPath) {
        $FileInfo = Get-Item $OutputPath
        Write-Host "`n[+] Build successful!" -ForegroundColor Green
        Write-Host "    File: $OutputPath" -ForegroundColor White
        Write-Host "    Size: $([math]::Round($FileInfo.Length / 1MB, 2)) MB" -ForegroundColor White

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Build Complete!" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`nUsage:" -ForegroundColor Yellow
        Write-Host "  .\$OutputName                    # Interactive mode" -ForegroundColor White
        Write-Host "  .\$OutputName -Mode Scan         # Direct mode" -ForegroundColor White
        Write-Host "`nThe executable is fully portable - copy it anywhere!" -ForegroundColor Gray
    }
    else {
        Write-Host "[!] Build may have failed - output file not found" -ForegroundColor Red
    }
}
catch {
    Write-Host "[!] Build failed: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup build directory
    if (Test-Path $BuildDir) {
        Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
