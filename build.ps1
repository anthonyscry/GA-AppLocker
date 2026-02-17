#Requires -Version 5.1
<#
.SYNOPSIS
    GA-AppLocker build pipeline - local CI/CD equivalent for air-gapped environments.

.DESCRIPTION
    Runs build tasks in sequence: Analyze, Test, Build, Validate, Package.
    Designed for air-gapped environments where no external CI/CD is available.

.PARAMETER Task
    Which task(s) to run. Default: All.

.PARAMETER Quick
    Run only Analyze + Unit Tests (fast feedback loop).

.PARAMETER OutputPath
    Directory for build artifacts (test results, packages). Default: .\BuildOutput

.EXAMPLE
    .\build.ps1
    Runs all tasks.

.EXAMPLE
    .\build.ps1 -Task Analyze
    Runs only PSScriptAnalyzer.

.EXAMPLE
    .\build.ps1 -Task Test
    Runs only Pester tests.

.EXAMPLE
    .\build.ps1 -Quick
    Fast feedback: Analyze + Unit tests only.

.EXAMPLE
    .\build.ps1 -Task Validate
    Validates all exported policy XML files.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
    Exit codes: 0 = success, 1 = failure
#>
[CmdletBinding()]
param(
    [ValidateSet('Analyze', 'Test', 'Build', 'Validate', 'Package', 'All')]
    [string[]]$Task = @('All'),

    [switch]$Quick,

    [switch]$Coverage,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'BuildOutput')
)

$ErrorActionPreference = 'Stop'
$script:ExitCode = 0
$script:ProjectRoot = $PSScriptRoot
$script:ModulePath = Join-Path $PSScriptRoot 'GA-AppLocker'
$script:TestsPath = Join-Path $PSScriptRoot 'Tests'
$script:StartTime = Get-Date

# ============================================================
# Banner
# ============================================================
Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  GA-AppLocker Build Pipeline" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

if ($Quick) {
    $Task = @('Analyze', 'Test')
    Write-Host "  Mode: QUICK (Analyze + Unit Tests only)" -ForegroundColor Yellow
}
else {
    Write-Host "  Tasks: $($Task -join ', ')" -ForegroundColor White
}
if ($Coverage) {
    Write-Host "  Coverage: ENABLED (JaCoCo format)" -ForegroundColor Yellow
}
Write-Host ""

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# ============================================================
# TASK: Analyze (PSScriptAnalyzer)
# ============================================================
function Invoke-AnalyzeTask {
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  ANALYZE: PSScriptAnalyzer" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    $analyzer = Get-Module -Name PSScriptAnalyzer -ListAvailable
    if (-not $analyzer) {
        Write-Host "  [SKIP] PSScriptAnalyzer not installed" -ForegroundColor Yellow
        Write-Host "  Install with: Install-Module PSScriptAnalyzer -Scope CurrentUser" -ForegroundColor Gray
        return
    }

    Import-Module PSScriptAnalyzer -Force

    $settingsPath = Join-Path $script:ProjectRoot 'PSScriptAnalyzerSettings.psd1'
    $params = @{
        Path      = $script:ModulePath
        Recurse   = $true
        Severity  = @('Error', 'Warning')
    }
    if (Test-Path $settingsPath) {
        $params['Settings'] = $settingsPath
    }

    $results = Invoke-ScriptAnalyzer @params

    $errors = @($results | Where-Object Severity -eq 'Error')
    $warnings = @($results | Where-Object Severity -eq 'Warning')

    if ($errors.Count -gt 0) {
        Write-Host "  [FAIL] $($errors.Count) error(s)" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "    ERROR: $($err.ScriptName):$($err.Line) - $($err.RuleName): $($err.Message)" -ForegroundColor Red
        }
        $script:ExitCode = 1
    }
    else {
        Write-Host "  [PASS] No errors" -ForegroundColor Green
    }

    if ($warnings.Count -gt 0) {
        Write-Host "  [WARN] $($warnings.Count) warning(s)" -ForegroundColor Yellow
        $warnings | Select-Object -First 10 | ForEach-Object {
            Write-Host "    WARN: $($_.ScriptName):$($_.Line) - $($_.RuleName)" -ForegroundColor Yellow
        }
        if ($warnings.Count -gt 10) {
            Write-Host "    ... and $($warnings.Count - 10) more" -ForegroundColor Yellow
        }
    }

    # Export results
    if ($results.Count -gt 0) {
        $reportPath = Join-Path $OutputPath 'analyzer-results.csv'
        $results | Export-Csv $reportPath -NoTypeInformation
        Write-Host "  Report: $reportPath" -ForegroundColor Gray
    }

    Write-Host ""
}

# ============================================================
# TASK: Test (Pester)
# ============================================================
function Invoke-TestTask {
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  TEST: Pester" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    # Check for Pester 5+
    $pester = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester -or $pester.Version -lt [version]'5.0.0') {
        Write-Host "  [WARN] Pester 5+ not found. Installing..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
    }
    Import-Module Pester -Force

    $config = New-PesterConfiguration
    $config.Run.Path = $script:TestsPath
    $config.Run.Exit = $false
    $config.Output.Verbosity = 'Detailed'

    if ($Quick) {
        $config.Filter.Tag = @('Unit')
        Write-Host "  Filter: Unit tests only" -ForegroundColor Yellow
    }

    # Test results output
    $resultsPath = Join-Path $OutputPath 'test-results.xml'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $resultsPath
    $config.TestResult.OutputFormat = 'NUnitXml'

    # Code coverage (all module Functions/ directories)
    if ($Coverage) {
        Write-Host "  Code Coverage: ENABLED" -ForegroundColor Yellow
        $config.CodeCoverage.Enabled = $true
        $coveragePaths = @()
        $modulesDir = Join-Path $script:ModulePath 'Modules'
        $subModules = Get-ChildItem -Path $modulesDir -Directory -ErrorAction SilentlyContinue
        foreach ($mod in $subModules) {
            $funcDir = Join-Path $mod.FullName 'Functions'
            if (Test-Path $funcDir) {
                $coveragePaths += Join-Path $funcDir '*.ps1'
            }
        }
        $config.CodeCoverage.Path = $coveragePaths
        $coverageOutputPath = Join-Path $OutputPath 'coverage.xml'
        $config.CodeCoverage.OutputPath = $coverageOutputPath
        $config.CodeCoverage.OutputFormat = 'JaCoCo'
    }

    $pesterResult = Invoke-Pester -Configuration $config

    if ($pesterResult.FailedCount -gt 0) {
        Write-Host "  [FAIL] $($pesterResult.FailedCount) test(s) failed" -ForegroundColor Red
        $script:ExitCode = 1
    }
    else {
        Write-Host "  [PASS] All $($pesterResult.PassedCount) tests passed" -ForegroundColor Green
    }

    Write-Host "  Results: $resultsPath" -ForegroundColor Gray

    # Coverage summary
    if ($Coverage -and $pesterResult.CodeCoverage) {
        $cc = $pesterResult.CodeCoverage
        $pct = [math]::Round($cc.CoveragePercent, 2)
        $color = if ($pct -ge 80) { 'Green' } elseif ($pct -ge 50) { 'Yellow' } else { 'Red' }
        Write-Host ""
        Write-Host "  ============================================" -ForegroundColor Cyan
        Write-Host "  CODE COVERAGE REPORT" -ForegroundColor Cyan
        Write-Host "  ============================================" -ForegroundColor Cyan
        Write-Host "  Overall:      $pct%" -ForegroundColor $color
        Write-Host "  Commands Hit: $($cc.CommandsExecutedCount) / $($cc.CommandsAnalyzedCount)"
        Write-Host "  Files:        $($cc.FilesAnalyzedCount)"
        Write-Host "  Output:       $coverageOutputPath" -ForegroundColor Gray

        # Show uncovered files summary (files with 0% coverage)
        if ($cc.CommandsMissed -and $cc.CommandsMissed.Count -gt 0) {
            $missedByFile = $cc.CommandsMissed | Group-Object File | Sort-Object Count -Descending | Select-Object -First 10
            Write-Host ""
            Write-Host "  Top 10 files needing coverage:" -ForegroundColor Yellow
            foreach ($f in $missedByFile) {
                $shortName = Split-Path $f.Name -Leaf
                Write-Host "    $shortName - $($f.Count) uncovered commands" -ForegroundColor Yellow
            }
        }
        Write-Host "  ============================================" -ForegroundColor Cyan
    }

    Write-Host ""
}

# ============================================================
# TASK: Build (Module Manifest Validation)
# ============================================================
function Invoke-BuildTask {
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  BUILD: Module Validation" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    $manifestPath = Join-Path $script:ModulePath 'GA-AppLocker.psd1'

    # Validate main manifest
    try {
        $manifest = Test-ModuleManifest $manifestPath -ErrorAction Stop
        Write-Host "  [PASS] Main manifest valid: v$($manifest.Version)" -ForegroundColor Green
        Write-Host "    Exported functions: $($manifest.ExportedFunctions.Count)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  [FAIL] Main manifest invalid: $($_.Exception.Message)" -ForegroundColor Red
        $script:ExitCode = 1
    }

    # Validate each nested module manifest
    $nestedModules = Get-ChildItem -Path (Join-Path $script:ModulePath 'Modules') -Directory
    foreach ($mod in $nestedModules) {
        $psd1 = Join-Path $mod.FullName "$($mod.Name).psd1"
        if (Test-Path $psd1) {
            try {
                $nested = Test-ModuleManifest $psd1 -ErrorAction Stop
                Write-Host "  [PASS] $($mod.Name): v$($nested.Version)" -ForegroundColor Green
            }
            catch {
                Write-Host "  [FAIL] $($mod.Name): $($_.Exception.Message)" -ForegroundColor Red
                $script:ExitCode = 1
            }
        }
    }

    Write-Host ""
}

# ============================================================
# TASK: Validate (Policy XML Validation)
# ============================================================
function Invoke-ValidateTask {
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  VALIDATE: Policy XML Files" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    # Import the module to get validation functions
    try {
        Import-Module (Join-Path $script:ModulePath 'GA-AppLocker.psd1') -Force -ErrorAction Stop
    }
    catch {
        Write-Host "  [FAIL] Could not import module: $($_.Exception.Message)" -ForegroundColor Red
        $script:ExitCode = 1
        return
    }

    # Find policy XML files in data directory and project
    $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
        Get-AppLockerDataPath
    } else {
        Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
    }

    $policyDir = Join-Path $dataPath 'Policies'
    $xmlFiles = @()

    if (Test-Path $policyDir) {
        $xmlFiles += Get-ChildItem -Path $policyDir -Filter '*.xml' -ErrorAction SilentlyContinue
    }

    # Also check for test XML files
    $testXml = Join-Path $script:ProjectRoot 'test-import.xml'
    if (Test-Path $testXml) {
        $xmlFiles += Get-Item $testXml
    }

    if ($xmlFiles.Count -eq 0) {
        Write-Host "  [SKIP] No policy XML files found to validate" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $failed = @()
    foreach ($xml in $xmlFiles) {
        Write-Host "  Validating: $($xml.Name)..." -ForegroundColor White -NoNewline
        try {
            $result = Invoke-AppLockerPolicyValidation -XmlPath $xml.FullName
            if ($result.OverallSuccess) {
                Write-Host " PASSED" -ForegroundColor Green
            }
            else {
                Write-Host " FAILED ($($result.TotalErrors) errors)" -ForegroundColor Red
                $failed += $xml.Name
            }
        }
        catch {
            Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
            $failed += $xml.Name
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host "  [FAIL] $($failed.Count) policy file(s) failed validation: $($failed -join ', ')" -ForegroundColor Red
        $script:ExitCode = 1
    }
    else {
        Write-Host "  [PASS] All $($xmlFiles.Count) policy file(s) valid" -ForegroundColor Green
    }

    Write-Host ""
}

# ============================================================
# TASK: Package (Create Release Archive)
# ============================================================
function Invoke-PackageTask {
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  PACKAGE: Create Release" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    $releaseScript = Join-Path $script:ProjectRoot 'tools\Invoke-Release.ps1'
    if (-not (Test-Path -Path $releaseScript)) {
        Write-Host "  [FAIL] Release orchestrator not found: $releaseScript" -ForegroundColor Red
        $script:ExitCode = 1
        Write-Host ""
        return
    }

    try {
        $releaseResult = & $releaseScript -OutputPath $OutputPath
        if ($releaseResult -is [array]) {
            $releaseResult = $releaseResult[-1]
        }

        if ($null -eq $releaseResult -or -not $releaseResult.Success) {
            Write-Host "  [FAIL] Release orchestrator reported one or more failed steps" -ForegroundColor Red
            $script:ExitCode = 1
        }
        else {
            Write-Host "  [PASS] Release orchestrator completed successfully" -ForegroundColor Green
            if ($releaseResult.Artifacts -and $releaseResult.Artifacts.PackagePath) {
                Write-Host "  Package: $($releaseResult.Artifacts.PackagePath)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  [FAIL] Packaging failed: $($_.Exception.Message)" -ForegroundColor Red
        $script:ExitCode = 1
    }

    Write-Host ""
}

# ============================================================
# Execute Tasks
# ============================================================
$taskMap = @{
    'Analyze'  = { Invoke-AnalyzeTask }
    'Test'     = { Invoke-TestTask }
    'Build'    = { Invoke-BuildTask }
    'Validate' = { Invoke-ValidateTask }
    'Package'  = { Invoke-PackageTask }
}

if ($Task -contains 'All') {
    $Task = @('Analyze', 'Test', 'Build', 'Validate', 'Package')
}

foreach ($t in $Task) {
    try {
        & $taskMap[$t]
    }
    catch {
        Write-Host "  [FAIL] Task '$t' threw an exception: $($_.Exception.Message)" -ForegroundColor Red
        $script:ExitCode = 1
    }
}

# ============================================================
# Summary
# ============================================================
$duration = (Get-Date) - $script:StartTime

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  BUILD SUMMARY" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Duration: $([math]::Round($duration.TotalSeconds, 1))s"
Write-Host "  Tasks:    $($Task -join ', ')"

if ($script:ExitCode -eq 0) {
    Write-Host "  Result:   SUCCESS" -ForegroundColor Green
}
else {
    Write-Host "  Result:   FAILURE" -ForegroundColor Red
}

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

exit $script:ExitCode
