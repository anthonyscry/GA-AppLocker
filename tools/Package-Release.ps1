#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Version,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'BuildOutput'
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $manifestPath = Join-Path $projectRoot 'GA-AppLocker\GA-AppLocker.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $Version = [string]$manifest.ModuleVersion
}

$releaseHelperPath = Join-Path $projectRoot 'tools\Release\New-ReleasePackage.ps1'
$integrityHelperPath = Join-Path $projectRoot 'tools\Release\New-IntegrityArtifacts.ps1'

if (-not (Test-Path -Path $releaseHelperPath)) {
    throw "Required helper not found: $releaseHelperPath"
}
if (-not (Test-Path -Path $integrityHelperPath)) {
    throw "Required helper not found: $integrityHelperPath"
}

$packageResult = & $releaseHelperPath -Version $Version -OutputPath $OutputPath -DryRun:$DryRun
if (-not $packageResult.Success) {
    throw "Release packaging failed: $($packageResult.Error)"
}

if ($DryRun) {
    Write-Host "[DRY-RUN] Package planned: $($packageResult.PackagePath)"
    return [pscustomobject]@{
        Success = $true
        DryRun = $true
        PackagePath = $packageResult.PackagePath
        Sha256Path = $null
        ManifestPath = $null
        Warning = $packageResult.Warning
        Error = $null
    }
}

$integrityResult = & $integrityHelperPath -PackagePath $packageResult.PackagePath
if (-not $integrityResult.Success) {
    throw "Integrity artifact generation failed: $($integrityResult.Error)"
}

Write-Host "Package:  $($packageResult.PackagePath)"
Write-Host "SHA256:   $($integrityResult.Sha256Path)"
Write-Host "Manifest: $($integrityResult.ManifestPath)"

[pscustomobject]@{
    Success = $true
    DryRun = $false
    PackagePath = $packageResult.PackagePath
    Sha256Path = $integrityResult.Sha256Path
    ManifestPath = $integrityResult.ManifestPath
    Warning = $integrityResult.Warning
    Error = $null
}
