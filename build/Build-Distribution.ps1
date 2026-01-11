<#
.SYNOPSIS
    Creates a distributable GA-AppLocker package
.DESCRIPTION
    Builds the GUI executable and packages it with all required scripts
    into a single zip file ready for distribution.
.EXAMPLE
    .\build\Build-Distribution.ps1
    Creates GA-AppLocker-v1.2.4.zip in the dist folder
.EXAMPLE
    .\build\Build-Distribution.ps1 -SkipBuild
    Packages existing files without rebuilding the EXE
.NOTES
    The output zip contains everything needed to run GA-AppLocker
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ".\dist",
    [switch]$SkipBuild,
    [switch]$IncludeTests
)

$ErrorActionPreference = 'Stop'
$Version = "1.2.4"

Write-Host ""
Write-Host "GA-AppLocker Distribution Builder" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Version: $Version" -ForegroundColor Gray
Write-Host ""

# Determine project root
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
$projectRoot = Split-Path -Parent $scriptRoot

# Create output directory
$distPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path $projectRoot $OutputPath
}

if (-not (Test-Path $distPath)) {
    New-Item -ItemType Directory -Path $distPath -Force | Out-Null
}

# Step 1: Build the EXE (unless skipped)
if (-not $SkipBuild) {
    Write-Host "[1/4] Building executable..." -ForegroundColor Yellow
    $buildScript = Join-Path $scriptRoot "Build-GUI.ps1"
    if (Test-Path $buildScript) {
        & $buildScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "      Build failed!" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "      Build script not found: $buildScript" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[1/4] Skipping build (using existing EXE)..." -ForegroundColor Yellow
}

# Step 2: Create staging directory
Write-Host "[2/4] Preparing package contents..." -ForegroundColor Yellow

$stagingPath = Join-Path $distPath "GA-AppLocker-v$Version"
if (Test-Path $stagingPath) {
    Remove-Item $stagingPath -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

# Define what to include
$includeItems = @(
    # Main executable
    @{ Source = "GA-AppLocker.exe"; Dest = "" },
    @{ Source = "GA-AppLocker.exe.config"; Dest = "" },

    # Module files
    @{ Source = "GA-AppLocker.psd1"; Dest = "" },
    @{ Source = "GA-AppLocker.psm1"; Dest = "" },

    # Documentation
    @{ Source = "README.md"; Dest = "" },
    @{ Source = "CHANGELOG.md"; Dest = "" },
    @{ Source = "LICENSE"; Dest = "" },

    # Core scripts (required for GUI operations)
    @{ Source = "src\Core"; Dest = "src\Core"; IsDir = $true },

    # Utility scripts
    @{ Source = "src\Utilities"; Dest = "src\Utilities"; IsDir = $true },

    # GUI support files
    @{ Source = "src\GUI\AsyncHelpers.psm1"; Dest = "src\GUI" },

    # Assets
    @{ Source = "assets"; Dest = "assets"; IsDir = $true },

    # Documentation
    @{ Source = "docs"; Dest = "docs"; IsDir = $true },

    # Example files
    @{ Source = "ADManagement"; Dest = "ADManagement"; IsDir = $true }
)

# Optionally include tests
if ($IncludeTests) {
    $includeItems += @{ Source = "Tests"; Dest = "Tests"; IsDir = $true }
}

$copiedCount = 0
foreach ($item in $includeItems) {
    $sourcePath = Join-Path $projectRoot $item.Source
    $destPath = if ($item.Dest) {
        Join-Path $stagingPath $item.Dest
    } else {
        $stagingPath
    }

    if (Test-Path $sourcePath) {
        if ($item.IsDir) {
            # Create destination directory
            if (-not (Test-Path $destPath)) {
                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
            }
            # Copy directory contents
            Copy-Item -Path "$sourcePath\*" -Destination $destPath -Recurse -Force
            $copiedCount++
            Write-Host "      Copied: $($item.Source)\" -ForegroundColor Gray
        } else {
            # Copy file
            if ($item.Dest) {
                # Ensure destination directory exists
                $destDir = Join-Path $stagingPath $item.Dest
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                $finalDest = Join-Path $destDir (Split-Path $item.Source -Leaf)
                Copy-Item -Path $sourcePath -Destination $finalDest -Force
            } else {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
            }
            $copiedCount++
            Write-Host "      Copied: $($item.Source)" -ForegroundColor Gray
        }
    } else {
        Write-Host "      Skipped (not found): $($item.Source)" -ForegroundColor DarkGray
    }
}

Write-Host "      $copiedCount items copied" -ForegroundColor Green

# Step 3: Create zip archive
Write-Host "[3/4] Creating zip archive..." -ForegroundColor Yellow

$zipPath = Join-Path $distPath "GA-AppLocker-v$Version.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path "$stagingPath\*" -DestinationPath $zipPath -Force

$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "      Created: $zipPath ($zipSize MB)" -ForegroundColor Green

# Step 4: Cleanup staging
Write-Host "[4/4] Cleaning up..." -ForegroundColor Yellow
Remove-Item $stagingPath -Recurse -Force
Write-Host "      Staging directory removed" -ForegroundColor Gray

# Summary
Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Distribution package created!" -ForegroundColor Green
Write-Host ""
Write-Host "Output: $zipPath" -ForegroundColor White
Write-Host "Size:   $zipSize MB" -ForegroundColor White
Write-Host ""
Write-Host "Package contents:" -ForegroundColor Gray
Write-Host "  - GA-AppLocker.exe (main executable)" -ForegroundColor Gray
Write-Host "  - src/Core/ (workflow scripts)" -ForegroundColor Gray
Write-Host "  - src/Utilities/ (utility scripts)" -ForegroundColor Gray
Write-Host "  - docs/ (documentation)" -ForegroundColor Gray
Write-Host "  - assets/ (icons)" -ForegroundColor Gray
if ($IncludeTests) {
    Write-Host "  - Tests/ (test files)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Usage: Extract zip, then run GA-AppLocker.exe" -ForegroundColor Yellow
