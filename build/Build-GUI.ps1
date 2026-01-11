<#
.SYNOPSIS
    Builds GA-AppLocker GUI executable
.DESCRIPTION
    Compiles the GA-AppLocker-Portable.ps1 script into a standalone .exe file
    using PS2EXE module. The resulting executable can be distributed without
    requiring PowerShell script execution.
.EXAMPLE
    .\build\Build-GUI.ps1
    Builds GA-AppLocker.exe in the dist directory
.EXAMPLE
    .\build\Build-GUI.ps1 -OutputPath "C:\Tools\GA-AppLocker.exe"
    Builds to a specific path
.NOTES
    Requires: PS2EXE module (automatically installed if missing)
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ".\GA-AppLocker.exe",
    [switch]$IncludeDebug,
    [switch]$SkipZip
)

$ErrorActionPreference = 'Stop'

Write-Host "GA-AppLocker Portable Build Script" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Check for PS2EXE module
Write-Host "[1/4] Checking for PS2EXE module..." -ForegroundColor Yellow

# ps2exe module name is lowercase
$ps2exeModule = Get-InstalledModule -Name ps2exe -ErrorAction SilentlyContinue
if (-not $ps2exeModule) {
    Write-Host "      ps2exe not found. Installing..." -ForegroundColor Gray
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
        $ps2exeModule = Get-InstalledModule -Name ps2exe -ErrorAction SilentlyContinue
        Write-Host "      ps2exe installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "      Failed to install ps2exe: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "      Please install manually:" -ForegroundColor Yellow
        Write-Host "      Install-Module -Name ps2exe -Scope CurrentUser" -ForegroundColor White
        exit 1
    }
}
else {
    Write-Host "      ps2exe module found at: $($ps2exeModule.InstalledLocation)" -ForegroundColor Green
}

# Import module - try by path first (handles OneDrive sync issues)
try {
    $modulePath = Join-Path $ps2exeModule.InstalledLocation "ps2exe.psd1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    } else {
        Import-Module ps2exe -Force
    }
} catch {
    Write-Host "      Failed to import ps2exe: $_" -ForegroundColor Red
    exit 1
}

# Locate source file
Write-Host "[2/4] Locating source file..." -ForegroundColor Yellow

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
$projectRoot = Split-Path -Parent $scriptRoot

$sourcePath = Join-Path $projectRoot "src\GUI\GA-AppLocker-Portable.ps1"
if (-not (Test-Path $sourcePath)) {
    Write-Host "      Source file not found: $sourcePath" -ForegroundColor Red
    exit 1
}
Write-Host "      Source: $sourcePath" -ForegroundColor Green

# Resolve output path (default to root folder for easy access)
if ($OutputPath -eq ".\GA-AppLocker.exe") {
    $OutputPath = Join-Path $projectRoot "GA-AppLocker.exe"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}
Write-Host "      Output: $OutputPath" -ForegroundColor Green

# Build parameters
Write-Host "[3/4] Compiling to executable..." -ForegroundColor Yellow

$iconPath = Join-Path $projectRoot "assets\general-atomics-logo.ico"
if (-not (Test-Path $iconPath)) {
    # Fallback to wsus icon
    $iconPath = Join-Path $projectRoot "assets\wsus-icon.ico"
}

$buildParams = @{
    InputFile      = $sourcePath
    OutputFile     = $OutputPath
    NoConsole      = $true
    Title          = "GA-AppLocker Toolkit"
    Description    = "Windows AppLocker Policy Management Tool"
    Company        = "GA-AppLocker Project"
    Product        = "GA-AppLocker Toolkit"
    Copyright      = "GA-AppLocker Project"
    Version        = "1.2.4.0"
    RequireAdmin   = $false
    SupportOS      = $true
    Longpaths      = $true
    x64            = $true
}

if (Test-Path $iconPath) {
    $buildParams['IconFile'] = $iconPath
    Write-Host "      Icon: $iconPath" -ForegroundColor Green
}

if ($IncludeDebug) {
    $buildParams['NoConsole'] = $false
    Write-Host "      Debug mode: Console window enabled" -ForegroundColor Gray
}

try {
    Invoke-PS2EXE @buildParams

    if (Test-Path $OutputPath) {
        $fileInfo = Get-Item $OutputPath
        Write-Host "      Compilation successful!" -ForegroundColor Green

        # Step 4: Create distribution zip (unless skipped)
        if (-not $SkipZip) {
            Write-Host ""
            Write-Host "[4/5] Creating distribution package..." -ForegroundColor Yellow

            $distScript = Join-Path $scriptRoot "Build-Distribution.ps1"
            if (Test-Path $distScript) {
                & $distScript -SkipBuild
            } else {
                Write-Host "      Distribution script not found, skipping zip" -ForegroundColor DarkGray
            }

            Write-Host ""
            Write-Host "[5/5] Build complete!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "[4/4] Build complete!" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "Output file: $OutputPath" -ForegroundColor Cyan
        Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  - Run GA-AppLocker.exe from any location" -ForegroundColor White
        Write-Host "  - For full functionality, place in GA-AppLocker folder" -ForegroundColor White
        Write-Host "  - Or configure Scripts Location in Settings" -ForegroundColor White
    }
    else {
        Write-Host "      Build failed - output file not created." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "      Compilation failed: $_" -ForegroundColor Red
    exit 1
}
