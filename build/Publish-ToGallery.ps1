<#
.SYNOPSIS
    Publishes GA-AppLocker module to the PowerShell Gallery.

.DESCRIPTION
    This script prepares and publishes the GA-AppLocker module to the PowerShell Gallery.
    It performs pre-publication validation, creates a clean staging area, and publishes
    the module using the provided API key.

.PARAMETER ApiKey
    Your PowerShell Gallery API key. Get one at https://www.powershellgallery.com/account/apikeys

.PARAMETER WhatIf
    Shows what would be published without actually publishing.

.PARAMETER SkipValidation
    Skip pre-publication validation checks.

.EXAMPLE
    .\Publish-ToGallery.ps1 -ApiKey "your-api-key-here"

.EXAMPLE
    .\Publish-ToGallery.ps1 -WhatIf
    # Shows what would be published without publishing

.NOTES
    Prerequisites:
    1. PowerShellGet module installed (Install-Module PowerShellGet -Force)
    2. Valid PowerShell Gallery API key
    3. Module passes Test-ModuleManifest validation
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'

# Get paths
$ModuleRoot = Split-Path $PSScriptRoot -Parent
$ManifestPath = Join-Path $ModuleRoot 'GA-AppLocker.psd1'
$StagingPath = Join-Path $env:TEMP 'GA-AppLocker-Publish'

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  GA-AppLocker Gallery Publisher" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

#region Validation
if (-not $SkipValidation) {
    Write-Host "[1/5] Validating module manifest..." -ForegroundColor Yellow

    try {
        $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        Write-Host "      Module: $($manifest.Name)" -ForegroundColor Gray
        Write-Host "      Version: $($manifest.Version)" -ForegroundColor Gray
        Write-Host "      Author: $($manifest.Author)" -ForegroundColor Gray
        Write-Host "      Manifest valid" -ForegroundColor Green
    }
    catch {
        Write-Host "      FAILED: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    # Check for required files
    Write-Host "`n[2/5] Checking required files..." -ForegroundColor Yellow

    $requiredFiles = @(
        'GA-AppLocker.psd1',
        'GA-AppLocker.psm1',
        'LICENSE',
        'README.md'
    )

    $missingFiles = @()
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $ModuleRoot $file
        if (Test-Path $filePath) {
            Write-Host "      [OK] $file" -ForegroundColor Green
        } else {
            Write-Host "      [MISSING] $file" -ForegroundColor Red
            $missingFiles += $file
        }
    }

    if ($missingFiles.Count -gt 0) {
        Write-Host "`n      ERROR: Missing required files. Cannot publish." -ForegroundColor Red
        exit 1
    }

    # Check for existing version
    Write-Host "`n[3/5] Checking PowerShell Gallery..." -ForegroundColor Yellow

    try {
        $existingModule = Find-Module -Name 'GA-AppLocker' -ErrorAction SilentlyContinue
        if ($existingModule) {
            Write-Host "      Existing version on Gallery: $($existingModule.Version)" -ForegroundColor Gray
            if ([version]$manifest.Version -le [version]$existingModule.Version) {
                Write-Host "      WARNING: Local version ($($manifest.Version)) is not newer than published version" -ForegroundColor Yellow
                $continue = Read-Host "      Continue anyway? (y/n)"
                if ($continue -ne 'y') {
                    Write-Host "      Aborted." -ForegroundColor Yellow
                    exit 0
                }
            } else {
                Write-Host "      New version $($manifest.Version) will replace $($existingModule.Version)" -ForegroundColor Green
            }
        } else {
            Write-Host "      Module not yet published - this will be the first release" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "      Could not check Gallery (may be offline or first publish)" -ForegroundColor Yellow
    }
}
#endregion

#region Staging
Write-Host "`n[4/5] Preparing staging area..." -ForegroundColor Yellow

# Clean staging area
if (Test-Path $StagingPath) {
    Remove-Item $StagingPath -Recurse -Force
}

$stagingModulePath = Join-Path $StagingPath 'GA-AppLocker'
New-Item -ItemType Directory -Path $stagingModulePath -Force | Out-Null

# Files to include in the published module
$filesToPublish = @(
    # Core module files
    'GA-AppLocker.psd1',
    'GA-AppLocker.psm1',
    'LICENSE',
    'README.md',

    # Main scripts
    'Start-AppLockerWorkflow.ps1',
    'Start-GUI.ps1',
    'Invoke-RemoteScan.ps1',
    'Invoke-RemoteEventCollection.ps1',
    'New-AppLockerPolicyFromGuide.ps1',
    'Merge-AppLockerPolicies.ps1'
)

$foldersToPublish = @(
    'utilities',
    'GUI',
    'ADManagement'
)

# Copy files
foreach ($file in $filesToPublish) {
    $sourcePath = Join-Path $ModuleRoot $file
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $stagingModulePath
        Write-Host "      Copied: $file" -ForegroundColor Gray
    }
}

# Copy folders
foreach ($folder in $foldersToPublish) {
    $sourcePath = Join-Path $ModuleRoot $folder
    if (Test-Path $sourcePath) {
        $destPath = Join-Path $stagingModulePath $folder
        Copy-Item $sourcePath -Destination $destPath -Recurse
        Write-Host "      Copied: $folder\" -ForegroundColor Gray
    }
}

Write-Host "      Staging complete: $stagingModulePath" -ForegroundColor Green
#endregion

#region Publish
Write-Host "`n[5/5] Publishing to PowerShell Gallery..." -ForegroundColor Yellow

if ($WhatIfPreference) {
    Write-Host "`n      WHATIF: Would publish module from:" -ForegroundColor Cyan
    Write-Host "      $stagingModulePath" -ForegroundColor Gray
    Write-Host "`n      Files that would be published:" -ForegroundColor Cyan
    Get-ChildItem $stagingModulePath -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Replace($stagingModulePath, '').TrimStart('\')
        Write-Host "        $relativePath" -ForegroundColor Gray
    }
    Write-Host "`n      Run without -WhatIf to publish." -ForegroundColor Yellow
} else {
    if (-not $ApiKey) {
        Write-Host "`n      ERROR: API Key required for publishing." -ForegroundColor Red
        Write-Host "      Get your API key at: https://www.powershellgallery.com/account/apikeys" -ForegroundColor Gray
        Write-Host "`n      Usage: .\Publish-ToGallery.ps1 -ApiKey 'your-key-here'" -ForegroundColor Yellow
        exit 1
    }

    try {
        Publish-Module -Path $stagingModulePath -NuGetApiKey $ApiKey -Verbose
        Write-Host "`n      SUCCESS: Module published to PowerShell Gallery!" -ForegroundColor Green
        Write-Host "      View at: https://www.powershellgallery.com/packages/GA-AppLocker" -ForegroundColor Cyan
    }
    catch {
        Write-Host "`n      FAILED: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
#endregion

#region Cleanup
if (-not $WhatIfPreference) {
    Write-Host "`nCleaning up staging area..." -ForegroundColor Gray
    Remove-Item $StagingPath -Recurse -Force -ErrorAction SilentlyContinue
}
#endregion

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  Publication Complete" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

Write-Host "Users can now install with:" -ForegroundColor Yellow
Write-Host "  Install-Module -Name GA-AppLocker" -ForegroundColor White
Write-Host ""
