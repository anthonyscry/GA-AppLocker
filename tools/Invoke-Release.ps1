#Requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('dry-run')]
    [switch]$DryRun,

    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'BuildOutput')
)

$ErrorActionPreference = 'Stop'

function Add-StepRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Ledger,

        [Parameter(Mandatory = $true)]
        [string]$Step,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Message,

        [string[]]$Artifacts,

        [string]$Error
    )

    [void]$Ledger.Add([pscustomobject]@{
            Step = $Step
            Status = $Status
            Message = $Message
            Artifacts = @($Artifacts)
            Error = $Error
        })
}

function Invoke-Release {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [string]$OutputPath
    )

    $projectRoot = Split-Path $PSScriptRoot -Parent
    if (-not (Test-Path -Path $OutputPath)) {
        [void](New-Item -Path $OutputPath -ItemType Directory -Force)
    }

    $contextScript = Join-Path $projectRoot 'tools/Release/Get-ReleaseContext.ps1'
    $notesScript = Join-Path $projectRoot 'tools/Release/Get-ReleaseNotes.ps1'
    $versionScript = Join-Path $projectRoot 'tools/Release/Update-ManifestVersions.ps1'
    $packageScript = Join-Path $projectRoot 'tools/Release/New-ReleasePackage.ps1'
    $integrityScript = Join-Path $projectRoot 'tools/Release/New-IntegrityArtifacts.ps1'

    $ledger = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    $releaseContext = $null
    $versionResult = $null
    $notesResult = $null
    $packageResult = $null
    $integrityResult = $null
    $releaseVersion = $null

    try {
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($path in @($contextScript, $notesScript, $versionScript, $packageScript, $integrityScript)) {
            if (-not (Test-Path -Path $path)) {
                [void]$missing.Add($path)
            }
        }

        if ($missing.Count -gt 0) {
            throw ('Missing release helper(s): ' + ($missing -join ', '))
        }

        Add-StepRecord -Ledger $ledger -Step 'Preflight' -Status 'PASS' -Message 'Release helper scripts are available.' -Artifacts @() -Error $null
    }
    catch {
        Add-StepRecord -Ledger $ledger -Step 'Preflight' -Status 'FAIL' -Message 'Preflight checks failed.' -Artifacts @() -Error $_.Exception.Message
    }

    try {
        $releaseContext = & $contextScript
        if ($releaseContext -is [array]) {
            $releaseContext = $releaseContext[-1]
        }

        if ($null -eq $releaseContext -or [string]::IsNullOrWhiteSpace([string]$releaseContext.CurrentVersion)) {
            throw 'Release context did not return CurrentVersion.'
        }

        $versionResult = & $versionScript -CurrentVersion ([string]$releaseContext.CurrentVersion) -BumpType ([string]$releaseContext.BumpType) -DryRun:$DryRun
        if ($versionResult -is [array]) {
            $versionResult = $versionResult[-1]
        }

        if (-not $versionResult.Success) {
            throw $versionResult.Error
        }

        $releaseVersion = [string]$versionResult.TargetVersion
        if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
            throw 'Version step did not produce a target release version.'
        }

        foreach ($warning in @($releaseContext.Warnings)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$warning)) {
                [void]$warnings.Add([string]$warning)
            }
        }
        foreach ($warning in @($versionResult.Warnings)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$warning)) {
                [void]$warnings.Add([string]$warning)
            }
        }

        Add-StepRecord -Ledger $ledger -Step 'Version' -Status 'PASS' -Message ("Version planned: {0} -> {1} ({2})" -f $versionResult.CurrentVersion, $versionResult.TargetVersion, $versionResult.BumpType) -Artifacts @($versionResult.ChangedFiles) -Error $null
    }
    catch {
        Add-StepRecord -Ledger $ledger -Step 'Version' -Status 'FAIL' -Message 'Version update step failed.' -Artifacts @() -Error $_.Exception.Message
    }

    try {
        $notesVersion = if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
            if ($null -ne $releaseContext) { [string]$releaseContext.NormalizedVersion } else { $null }
        }
        else {
            $releaseVersion
        }

        $notesResult = & $notesScript -Version $notesVersion -AsObject
        if ($notesResult -is [array]) {
            $notesResult = $notesResult[-1]
        }

        if ($null -eq $notesResult -or [string]::IsNullOrWhiteSpace([string]$notesResult.ReleaseNotes)) {
            throw 'Release notes generation returned empty content.'
        }

        if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
            $releaseVersion = [string]$notesResult.Version
        }

        $notesPath = Join-Path $OutputPath ("GA-AppLocker-v{0}-release-notes.md" -f $releaseVersion)
        if (-not $DryRun) {
            Set-Content -Path $notesPath -Value ([string]$notesResult.ReleaseNotes) -Encoding ASCII
        }

        Add-StepRecord -Ledger $ledger -Step 'Notes' -Status 'PASS' -Message 'Release notes generated.' -Artifacts @($notesPath) -Error $null
    }
    catch {
        Add-StepRecord -Ledger $ledger -Step 'Notes' -Status 'FAIL' -Message 'Release notes step failed.' -Artifacts @() -Error $_.Exception.Message
    }

    try {
        if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
            throw 'Package step requires a resolved release version.'
        }

        $packageResult = & $packageScript -Version $releaseVersion -OutputPath $OutputPath -DryRun:$DryRun
        if ($packageResult -is [array]) {
            $packageResult = $packageResult[-1]
        }

        if (-not $packageResult.Success) {
            throw $packageResult.Error
        }

        Add-StepRecord -Ledger $ledger -Step 'Package' -Status 'PASS' -Message 'Release package step completed.' -Artifacts @([string]$packageResult.PackagePath) -Error $null
    }
    catch {
        Add-StepRecord -Ledger $ledger -Step 'Package' -Status 'FAIL' -Message 'Package step failed.' -Artifacts @() -Error $_.Exception.Message
    }

    try {
        if ($null -eq $packageResult -or [string]::IsNullOrWhiteSpace([string]$packageResult.PackagePath)) {
            throw 'Integrity step requires package output path.'
        }

        if ($DryRun) {
            $plannedSha = ([string]$packageResult.PackagePath) + '.sha256'
            $plannedManifest = ([string]$packageResult.PackagePath) + '.manifest.json'
            $integrityResult = [pscustomobject]@{
                Success = $true
                Sha256Path = $plannedSha
                ManifestPath = $plannedManifest
                Warning = $null
                Error = $null
            }
        }
        else {
            $integrityResult = & $integrityScript -PackagePath ([string]$packageResult.PackagePath)
            if ($integrityResult -is [array]) {
                $integrityResult = $integrityResult[-1]
            }
        }

        if (-not $integrityResult.Success) {
            throw $integrityResult.Error
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$integrityResult.Warning)) {
            [void]$warnings.Add([string]$integrityResult.Warning)
        }

        Add-StepRecord -Ledger $ledger -Step 'Integrity' -Status 'PASS' -Message 'Integrity artifacts ready.' -Artifacts @([string]$integrityResult.Sha256Path, [string]$integrityResult.ManifestPath) -Error $null
    }
    catch {
        Add-StepRecord -Ledger $ledger -Step 'Integrity' -Status 'FAIL' -Message 'Integrity step failed.' -Artifacts @() -Error $_.Exception.Message
    }

    $failed = @($ledger | Where-Object { $_.Status -eq 'FAIL' })
    $overallSuccess = ($failed.Count -eq 0)

    Write-Host ''
    Write-Host '=== Release Step Summary ===' -ForegroundColor Cyan
    foreach ($entry in @($ledger)) {
        $color = if ($entry.Status -eq 'PASS') { 'Green' } else { 'Red' }
        Write-Host ("[{0}] {1}: {2}" -f $entry.Status, $entry.Step, $entry.Message) -ForegroundColor $color
        foreach ($artifact in @($entry.Artifacts)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$artifact)) {
                Write-Host ("  artifact: {0}" -f $artifact) -ForegroundColor Gray
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.Error)) {
            Write-Host ("  error: {0}" -f $entry.Error) -ForegroundColor Yellow
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Host ''
        Write-Host 'Warnings:' -ForegroundColor Yellow
        foreach ($warning in @($warnings)) {
            Write-Host ("- {0}" -f $warning) -ForegroundColor Yellow
        }
    }

    $nextActions = [System.Collections.Generic.List[string]]::new()
    if ($overallSuccess -and $DryRun) {
        [void]$nextActions.Add('Run without --dry-run to apply manifest updates and produce package artifacts.')
    }
    elseif ($overallSuccess) {
        [void]$nextActions.Add('Review artifacts and proceed with release promotion checks.')
    }
    else {
        [void]$nextActions.Add('Review failed steps and rerun tools/Invoke-Release.ps1 after resolving reported errors.')
    }

    Write-Host ''
    Write-Host 'Next actions:' -ForegroundColor Cyan
    foreach ($line in @($nextActions)) {
        Write-Host ("- {0}" -f $line)
    }

    return [pscustomobject]@{
        Success = $overallSuccess
        DryRun = [bool]$DryRun
        Version = $releaseVersion
        Steps = @($ledger)
        Warnings = @($warnings)
        NextActions = @($nextActions)
        Artifacts = [pscustomobject]@{
            NotesPath = if ($null -ne $notesResult) { Join-Path $OutputPath ("GA-AppLocker-v{0}-release-notes.md" -f $releaseVersion) } else { $null }
            PackagePath = if ($null -ne $packageResult) { $packageResult.PackagePath } else { $null }
            Sha256Path = if ($null -ne $integrityResult) { $integrityResult.Sha256Path } else { $null }
            ManifestPath = if ($null -ne $integrityResult) { $integrityResult.ManifestPath } else { $null }
        }
    }
}

Invoke-Release -DryRun:$DryRun -OutputPath $OutputPath
