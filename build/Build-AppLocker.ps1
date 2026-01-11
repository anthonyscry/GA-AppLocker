<#
.SYNOPSIS
    Build script for GA-AppLocker toolkit.

.DESCRIPTION
    Validates code quality, runs tests, and packages the GA-AppLocker toolkit
    for distribution. Supports multiple build targets and output formats.

.PARAMETER Target
    Build target to execute. Valid values:
    - All: Run all build steps (default)
    - Validate: Run code validation only (lint, XAML)
    - Test: Run Pester tests only
    - Package: Create distribution package only
    - Clean: Remove build artifacts

.PARAMETER OutputPath
    Output directory for build artifacts. Defaults to .\Build

.PARAMETER Version
    Version string for the package. Defaults to date-based version (YYYY.MM.DD)

.PARAMETER SkipTests
    Skip running Pester tests during build.

.PARAMETER SkipValidation
    Skip code validation during build.

.PARAMETER CI
    Run in CI mode with stricter error handling and no interactive prompts.

.EXAMPLE
    .\Build-AppLocker.ps1
    Run full build with all validation and packaging.

.EXAMPLE
    .\Build-AppLocker.ps1 -Target Validate
    Run code validation only.

.EXAMPLE
    .\Build-AppLocker.ps1 -Target Package -Version "2.0.0"
    Create distribution package with specific version.

.EXAMPLE
    .\Build-AppLocker.ps1 -CI
    Run in CI mode for automated pipelines.
#>

[CmdletBinding()]
# Suppress PSReviewUnusedParameter - these parameters are used in nested functions
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Target', Justification = 'Used in Invoke-Build function')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Version', Justification = 'Used in Get-ProjectVersion function')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SkipTests', Justification = 'Used in Test-Prerequisite and Invoke-Build functions')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SkipValidation', Justification = 'Used in Test-Prerequisite and Invoke-Build functions')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CI', Justification = 'Used in Invoke-Build, Invoke-Test, and Invoke-Validate functions')]
param(
    [ValidateSet('All', 'Validate', 'Test', 'Package', 'Clean')]
    [string]$Target = 'All',

    [string]$OutputPath = '.\Build',

    [string]$Version,

    [switch]$SkipTests,

    [switch]$SkipValidation,

    [switch]$CI
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script root and project paths
$Script:ProjectRoot = $PSScriptRoot
$Script:BuildPath = Join-Path $ProjectRoot $OutputPath
$Script:DistPath = Join-Path $BuildPath 'dist'
$Script:ReportsPath = Join-Path $BuildPath 'reports'

# Build state tracking
$Script:BuildErrors = @()
$Script:BuildWarnings = @()
$Script:StartTime = Get-Date

#region Helper Functions

function Write-BuildHeader {
    param([string]$Message)

    $separator = '=' * 60
    Write-Host ''
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ''
}

function Write-BuildStep {
    param([string]$Message)
    Write-Host ">> $Message" -ForegroundColor Yellow
}

function Write-BuildSuccess {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-BuildWarning {
    param([string]$Message)
    $Script:BuildWarnings += $Message
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-BuildError {
    param([string]$Message)
    $Script:BuildErrors += $Message
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Get-ProjectVersion {
    # Generate version based on date if not specified
    if ($Version) {
        return $Version
    }

    # Check for existing version in changelog
    $changelogPath = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelogPath) {
        $changelog = Get-Content $changelogPath -Raw
        if ($changelog -match 'Version\s+(\d{4}-\d{2}-\d{2})') {
            return $Matches[1]
        }
    }

    # Default to today's date
    return (Get-Date -Format 'yyyy.MM.dd')
}

function Test-Prerequisite {
    Write-BuildStep 'Checking prerequisites...'

    $prereqMet = $true

    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-BuildError 'PowerShell 5.1 or higher is required'
        $prereqMet = $false
    } else {
        Write-BuildSuccess "PowerShell $($PSVersionTable.PSVersion)"
    }

    # Check for PSScriptAnalyzer
    $pssa = Get-Module -ListAvailable -Name PSScriptAnalyzer |
            Sort-Object Version -Descending |
            Select-Object -First 1

    if (-not $pssa) {
        Write-BuildWarning 'PSScriptAnalyzer not installed. Install with: Install-Module PSScriptAnalyzer'
        if (-not $SkipValidation) {
            $prereqMet = $false
        }
    } else {
        Write-BuildSuccess "PSScriptAnalyzer $($pssa.Version)"
    }

    # Check for Pester
    $pester = Get-Module -ListAvailable -Name Pester |
              Where-Object { $_.Version.Major -ge 5 } |
              Sort-Object Version -Descending |
              Select-Object -First 1

    if (-not $pester) {
        Write-BuildWarning 'Pester 5.0+ not installed. Install with: Install-Module Pester -MinimumVersion 5.0'
        if (-not $SkipTests) {
            $prereqMet = $false
        }
    } else {
        Write-BuildSuccess "Pester $($pester.Version)"
    }

    return $prereqMet
}

#endregion

#region Build Targets

function Invoke-Clean {
    Write-BuildHeader 'Cleaning Build Artifacts'

    if (Test-Path $BuildPath) {
        Write-BuildStep "Removing $BuildPath..."
        Remove-Item -Path $BuildPath -Recurse -Force
        Write-BuildSuccess 'Build directory cleaned'
    } else {
        Write-BuildSuccess 'Build directory already clean'
    }
}

function Invoke-Validate {
    Write-BuildHeader 'Validating Code Quality'

    # Ensure reports directory exists
    if (-not (Test-Path $ReportsPath)) {
        New-Item -Path $ReportsPath -ItemType Directory -Force | Out-Null
    }

    $validationPassed = $true

    # Run PSScriptAnalyzer
    Write-BuildStep 'Running PSScriptAnalyzer...'

    $analyzerParams = @{
        Path        = $ProjectRoot
        Recurse     = $true
        ExcludeRule = @('PSAvoidUsingWriteHost')
    }

    # Use GUI-specific settings if available
    $guiSettingsPath = Join-Path $ProjectRoot 'GUI\PSScriptAnalyzerSettings.psd1'
    if (Test-Path $guiSettingsPath) {
        $analyzerParams['Settings'] = $guiSettingsPath
    }

    try {
        $analysisResults = Invoke-ScriptAnalyzer @analyzerParams

        # Separate errors and warnings
        $errors = $analysisResults | Where-Object { $_.Severity -eq 'Error' }
        $warnings = $analysisResults | Where-Object { $_.Severity -eq 'Warning' }
        $info = $analysisResults | Where-Object { $_.Severity -eq 'Information' }

        # Export results
        $reportFile = Join-Path $ReportsPath 'ScriptAnalyzer.json'
        $analysisResults | ConvertTo-Json -Depth 5 | Out-File $reportFile -Encoding UTF8

        if ($errors.Count -gt 0) {
            Write-BuildError "PSScriptAnalyzer found $($errors.Count) error(s)"
            foreach ($err in $errors) {
                Write-Host "  - $($err.ScriptName):$($err.Line) - $($err.Message)" -ForegroundColor Red
            }
            $validationPassed = $false
        }

        if ($warnings.Count -gt 0) {
            Write-BuildWarning "PSScriptAnalyzer found $($warnings.Count) warning(s)"
            if (-not $CI) {
                foreach ($warn in $warnings | Select-Object -First 5) {
                    Write-Host "  - $($warn.ScriptName):$($warn.Line) - $($warn.Message)" -ForegroundColor Yellow
                }
                if ($warnings.Count -gt 5) {
                    Write-Host "  ... and $($warnings.Count - 5) more (see $reportFile)" -ForegroundColor Yellow
                }
            }
        }

        if ($errors.Count -eq 0) {
            Write-BuildSuccess "PSScriptAnalyzer passed ($($warnings.Count) warnings, $($info.Count) info)"
        }
    }
    catch {
        Write-BuildError "PSScriptAnalyzer failed: $_"
        $validationPassed = $false
    }

    # Run XAML Validation
    Write-BuildStep 'Validating XAML...'

    $xamlValidatorPath = Join-Path $ProjectRoot 'src\GUI\Scripts\Test-XamlValidation.ps1'
    if (Test-Path $xamlValidatorPath) {
        try {
            $xamlResults = & $xamlValidatorPath -Path (Join-Path $ProjectRoot 'src\GUI') 2>&1

            # Check for errors in output
            $xamlErrors = $xamlResults | Where-Object { $_ -match 'ERROR|FAILED' }
            if ($xamlErrors) {
                Write-BuildError 'XAML validation failed'
                $xamlErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
                $validationPassed = $false
            } else {
                Write-BuildSuccess 'XAML validation passed'
            }
        }
        catch {
            Write-BuildError "XAML validation failed: $_"
            $validationPassed = $false
        }
    } else {
        Write-BuildWarning 'XAML validator not found, skipping XAML validation'
    }

    # Validate module imports
    Write-BuildStep 'Validating module imports...'

    $modulePath = Join-Path $ProjectRoot 'src\Utilities\Common.psm1'
    if (Test-Path $modulePath) {
        try {
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $modulePath,
                [ref]$null,
                [ref]$null
            )
            Write-BuildSuccess 'Common.psm1 syntax valid'
        }
        catch {
            Write-BuildError "Common.psm1 has syntax errors: $_"
            $validationPassed = $false
        }
    }

    $errorHandlingPath = Join-Path $ProjectRoot 'src\Utilities\ErrorHandling.psm1'
    if (Test-Path $errorHandlingPath) {
        try {
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $errorHandlingPath,
                [ref]$null,
                [ref]$null
            )
            Write-BuildSuccess 'ErrorHandling.psm1 syntax valid'
        }
        catch {
            Write-BuildError "ErrorHandling.psm1 has syntax errors: $_"
            $validationPassed = $false
        }
    }

    $asyncHelpersPath = Join-Path $ProjectRoot 'src\GUI\AsyncHelpers.psm1'
    if (Test-Path $asyncHelpersPath) {
        try {
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $asyncHelpersPath,
                [ref]$null,
                [ref]$null
            )
            Write-BuildSuccess 'AsyncHelpers.psm1 syntax valid'
        }
        catch {
            Write-BuildError "AsyncHelpers.psm1 has syntax errors: $_"
            $validationPassed = $false
        }
    }

    return $validationPassed
}

function Invoke-Test {
    Write-BuildHeader 'Running Tests'

    # Ensure reports directory exists
    if (-not (Test-Path $ReportsPath)) {
        New-Item -Path $ReportsPath -ItemType Directory -Force | Out-Null
    }

    $testsPassed = $true

    # Find all test files
    $testFiles = Get-ChildItem -Path $ProjectRoot -Filter '*.Tests.ps1' -Recurse

    if ($testFiles.Count -eq 0) {
        Write-BuildWarning 'No test files found'
        return $true
    }

    Write-BuildStep "Found $($testFiles.Count) test file(s)"

    # Configure Pester
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $testFiles.FullName
    $pesterConfig.Run.Exit = $false
    $pesterConfig.Output.Verbosity = 'Detailed'
    $pesterConfig.TestResult.Enabled = $true
    $pesterConfig.TestResult.OutputPath = Join-Path $ReportsPath 'TestResults.xml'
    $pesterConfig.TestResult.OutputFormat = 'NUnitXml'

    # Enable code coverage if not in CI mode (slower)
    if (-not $CI) {
        $pesterConfig.CodeCoverage.Enabled = $true
        $pesterConfig.CodeCoverage.Path = @(
            (Join-Path $ProjectRoot 'src\GUI\AsyncHelpers.psm1'),
            (Join-Path $ProjectRoot 'src\Utilities\Common.psm1'),
            (Join-Path $ProjectRoot 'src\Utilities\ErrorHandling.psm1')
        ) | Where-Object { Test-Path $_ }
        $pesterConfig.CodeCoverage.OutputPath = Join-Path $ReportsPath 'Coverage.xml'
    }

    try {
        $testResults = Invoke-Pester -Configuration $pesterConfig

        if ($testResults.FailedCount -gt 0) {
            Write-BuildError "$($testResults.FailedCount) test(s) failed"
            $testsPassed = $false
        } else {
            Write-BuildSuccess "All $($testResults.PassedCount) test(s) passed"
        }

        # Report code coverage if available
        if ($testResults.CodeCoverage) {
            $coverage = [math]::Round($testResults.CodeCoverage.CoveragePercent, 2)
            if ($coverage -lt 50) {
                Write-BuildWarning "Code coverage: $coverage%"
            } else {
                Write-BuildSuccess "Code coverage: $coverage%"
            }
        }
    }
    catch {
        Write-BuildError "Test execution failed: $_"
        $testsPassed = $false
    }

    return $testsPassed
}

function Invoke-Package {
    Write-BuildHeader 'Creating Distribution Package'

    $projectVersion = Get-ProjectVersion
    Write-BuildStep "Package version: $projectVersion"

    # Create distribution directory
    $packageName = "GA-AppLocker-$projectVersion"
    $packagePath = Join-Path $DistPath $packageName

    if (Test-Path $packagePath) {
        Remove-Item -Path $packagePath -Recurse -Force
    }
    New-Item -Path $packagePath -ItemType Directory -Force | Out-Null

    # Define files to include
    $includePatterns = @(
        # Root scripts
        'Start-AppLockerWorkflow.ps1',
        'Start-GUI.ps1',
        'Invoke-RemoteScan.ps1',
        'Invoke-RemoteEventCollection.ps1',
        'New-AppLockerPolicyFromGuide.ps1',
        'Merge-AppLockerPolicies.ps1',

        # Documentation
        'README.md',
        'CHANGELOG.md',
        'LICENSE'
    )

    # Copy root files
    Write-BuildStep 'Copying root files...'
    foreach ($pattern in $includePatterns) {
        $sourcePath = Join-Path $ProjectRoot $pattern
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $packagePath
        }
    }

    # Copy directories
    $includeDirs = @(
        @{ Source = 'src\Utilities'; Dest = 'src\Utilities'; Exclude = @('*.Tests.ps1') },
        @{ Source = 'src\Core'; Dest = 'src\Core'; Exclude = @('*.Tests.ps1') },
        @{ Source = 'src\GUI'; Dest = 'src\GUI'; Exclude = @('*.Tests.ps1', 'Scripts', 'Tests') },
        @{ Source = 'ADManagement'; Dest = 'ADManagement'; Exclude = @() },
        @{ Source = 'Tests'; Dest = 'Tests'; Exclude = @() }
    )

    foreach ($dir in $includeDirs) {
        $sourceDir = Join-Path $ProjectRoot $dir.Source
        if (Test-Path $sourceDir) {
            Write-BuildStep "Copying $($dir.Source)..."
            $destDir = Join-Path $packagePath $dir.Dest
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null

            Get-ChildItem -Path $sourceDir -File |
                Where-Object {
                    $file = $_
                    -not ($dir.Exclude | Where-Object { $file.Name -like $_ })
                } |
                ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $destDir
                }
        }
    }

    # Create version file
    $versionInfo = @{
        Version      = $projectVersion
        BuildDate    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        BuildHost    = $env:COMPUTERNAME
        PowerShell   = $PSVersionTable.PSVersion.ToString()
    }
    $versionInfo | ConvertTo-Json | Out-File (Join-Path $packagePath 'version.json') -Encoding UTF8

    # Create ZIP archive
    Write-BuildStep 'Creating ZIP archive...'
    $zipPath = Join-Path $DistPath "$packageName.zip"

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    Compress-Archive -Path $packagePath -DestinationPath $zipPath -CompressionLevel Optimal

    $zipSize = [math]::Round((Get-Item $zipPath).Length / 1KB, 2)
    Write-BuildSuccess "Package created: $zipPath ($zipSize KB)"

    # Generate file manifest
    Write-BuildStep 'Generating file manifest...'
    $manifest = Get-ChildItem -Path $packagePath -Recurse -File | ForEach-Object {
        [PSCustomObject]@{
            RelativePath = $_.FullName.Substring($packagePath.Length + 1)
            Size         = $_.Length
            Hash         = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        }
    }
    $manifest | Export-Csv -Path (Join-Path $DistPath "$packageName-manifest.csv") -NoTypeInformation
    Write-BuildSuccess "Manifest created with $($manifest.Count) files"

    return $true
}

#endregion

#region Main Build Logic

function Invoke-Build {
    Write-BuildHeader "GA-AppLocker Build System"
    Write-Host "Target: $Target"
    Write-Host "Output: $OutputPath"
    Write-Host "CI Mode: $CI"
    Write-Host ''

    # Check prerequisites
    if (-not (Test-Prerequisite)) {
        if ($CI) {
            Write-BuildError 'Prerequisites not met, aborting in CI mode'
            exit 1
        }
        Write-BuildWarning 'Some prerequisites not met, continuing with available tools'
    }

    # Create build directory
    if (-not (Test-Path $BuildPath)) {
        New-Item -Path $BuildPath -ItemType Directory -Force | Out-Null
    }

    $success = $true

    switch ($Target) {
        'Clean' {
            Invoke-Clean
        }

        'Validate' {
            $success = Invoke-Validate
        }

        'Test' {
            $success = Invoke-Test
        }

        'Package' {
            $success = Invoke-Package
        }

        'All' {
            # Run validation unless skipped
            if (-not $SkipValidation) {
                if (-not (Invoke-Validate)) {
                    $success = $false
                    if ($CI) {
                        Write-BuildError 'Validation failed, aborting build'
                        exit 1
                    }
                }
            }

            # Run tests unless skipped
            if (-not $SkipTests) {
                if (-not (Invoke-Test)) {
                    $success = $false
                    if ($CI) {
                        Write-BuildError 'Tests failed, aborting build'
                        exit 1
                    }
                }
            }

            # Create package
            if (-not (Invoke-Package)) {
                $success = $false
            }
        }
    }

    # Build summary
    $duration = (Get-Date) - $StartTime
    Write-BuildHeader 'Build Summary'

    Write-Host "Duration: $([math]::Round($duration.TotalSeconds, 2)) seconds"
    Write-Host "Errors: $($Script:BuildErrors.Count)"
    Write-Host "Warnings: $($Script:BuildWarnings.Count)"
    Write-Host ''

    if ($success -and $Script:BuildErrors.Count -eq 0) {
        Write-Host 'BUILD SUCCEEDED' -ForegroundColor Green
        if ($Target -eq 'All' -or $Target -eq 'Package') {
            Write-Host ''
            Write-Host "Distribution package available at: $DistPath" -ForegroundColor Cyan
        }
        exit 0
    } else {
        Write-Host 'BUILD FAILED' -ForegroundColor Red
        if ($Script:BuildErrors.Count -gt 0) {
            Write-Host ''
            Write-Host 'Errors:' -ForegroundColor Red
            $Script:BuildErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        exit 1
    }
}

# Execute build
Invoke-Build

#endregion
