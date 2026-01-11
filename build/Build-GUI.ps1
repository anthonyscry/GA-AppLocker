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
    [switch]$IncludeDebug
)

$ErrorActionPreference = 'Stop'

Write-Host "GA-AppLocker Portable Build Script" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Check for PS2EXE module
Write-Host "[1/4] Checking for PS2EXE module..." -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name PS2EXE)) {
    Write-Host "      PS2EXE not found. Installing..." -ForegroundColor Gray
    try {
        Install-Module -Name PS2EXE -Scope CurrentUser -Force -AllowClobber
        Write-Host "      PS2EXE installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "      Failed to install PS2EXE: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "      Please install manually:" -ForegroundColor Yellow
        Write-Host "      Install-Module -Name PS2EXE -Scope CurrentUser" -ForegroundColor White
        exit 1
    }
}
else {
    Write-Host "      PS2EXE module found." -ForegroundColor Green
}

Import-Module PS2EXE -Force

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

$iconPath = Join-Path $projectRoot "assets\ga-applocker.ico"
if (-not (Test-Path $iconPath)) {
    # Fallback to general-atomics icon
    $iconPath = Join-Path $projectRoot "assets\general-atomics-large.ico"
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
    Version        = "1.2.1.0"
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
        Write-Host ""
        Write-Host "[4/4] Build complete!" -ForegroundColor Green
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
