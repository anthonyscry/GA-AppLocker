#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentVersion,

    [Parameter(Mandatory = $true)]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$BumpType,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Get-StrictSemVer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $match = [regex]::Match($Version, '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
    if (-not $match.Success) {
        throw "Version '$Version' is not strict SemVer major.minor.patch"
    }

    return [pscustomobject]@{
        Normalized = '{0}.{1}.{2}' -f $match.Groups[1].Value, $match.Groups[2].Value, $match.Groups[3].Value
        Major = [int]$match.Groups[1].Value
        Minor = [int]$match.Groups[2].Value
        Patch = [int]$match.Groups[3].Value
    }
}

function Get-BumpedVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateSet('major', 'minor', 'patch')]
        [string]$BumpType
    )

    $parts = Get-StrictSemVer -Version $Version

    if ($BumpType -eq 'major') {
        return '{0}.0.0' -f ($parts.Major + 1)
    }

    if ($BumpType -eq 'minor') {
        return '{0}.{1}.0' -f $parts.Major, ($parts.Minor + 1)
    }

    return '{0}.{1}.{2}' -f $parts.Major, $parts.Minor, ($parts.Patch + 1)
}

function Get-ManifestPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $moduleRoot = Join-Path $RepositoryRoot 'GA-AppLocker'
    $rootManifest = Join-Path $moduleRoot 'GA-AppLocker.psd1'
    if (-not (Test-Path -Path $rootManifest)) {
        throw "Root manifest not found: $rootManifest"
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    [void]$paths.Add($rootManifest)

    $nestedRoot = Join-Path $moduleRoot 'Modules'
    if (Test-Path -Path $nestedRoot) {
        $nested = Get-ChildItem -Path $nestedRoot -Filter '*.psd1' -File -Recurse -ErrorAction Stop
        foreach ($item in @($nested)) {
            [void]$paths.Add($item.FullName)
        }
    }

    return @($paths | Select-Object -Unique)
}

function Update-ManifestVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentVersion,

        [Parameter(Mandatory = $true)]
        [ValidateSet('major', 'minor', 'patch')]
        [string]$BumpType,

        [switch]$DryRun
    )

    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $normalizedCurrent = (Get-StrictSemVer -Version $CurrentVersion).Normalized
    $targetVersion = Get-BumpedVersion -Version $normalizedCurrent -BumpType $BumpType
    $manifestPaths = Get-ManifestPaths -RepositoryRoot $repoRoot

    $warnings = [System.Collections.Generic.List[string]]::new()
    $changedFiles = [System.Collections.Generic.List[string]]::new()
    $normalizedFiles = [System.Collections.Generic.List[string]]::new()

    foreach ($manifestPath in @($manifestPaths)) {
        $manifestData = Import-PowerShellDataFile -Path $manifestPath
        $existingVersionRaw = [string]$manifestData.ModuleVersion

        $existingIsStrict = $true
        try {
            $null = Get-StrictSemVer -Version $existingVersionRaw
        }
        catch {
            $existingIsStrict = $false
            [void]$warnings.Add("Manifest has non-strict version '$existingVersionRaw': $manifestPath")
        }

        $needsNormalization = (-not $existingIsStrict) -or ($existingVersionRaw -ne $normalizedCurrent)
        if ($needsNormalization) {
            [void]$normalizedFiles.Add($manifestPath)
        }

        if ($DryRun) {
            [void]$changedFiles.Add($manifestPath)
            continue
        }

        if ($needsNormalization) {
            Update-ModuleManifest -Path $manifestPath -ModuleVersion $normalizedCurrent
        }

        Update-ModuleManifest -Path $manifestPath -ModuleVersion $targetVersion
        [void]$changedFiles.Add($manifestPath)
    }

    if (-not $DryRun) {
        foreach ($manifestPath in @($changedFiles)) {
            $null = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        }
    }

    return [pscustomobject]@{
        Success = $true
        DryRun = [bool]$DryRun
        CurrentVersion = $normalizedCurrent
        TargetVersion = $targetVersion
        BumpType = $BumpType
        ChangedFiles = @($changedFiles)
        NormalizedFiles = @($normalizedFiles)
        Warnings = @($warnings)
        Error = $null
    }
}

try {
    Update-ManifestVersions -CurrentVersion $CurrentVersion -BumpType $BumpType -DryRun:$DryRun
}
catch {
    [pscustomobject]@{
        Success = $false
        DryRun = [bool]$DryRun
        CurrentVersion = $CurrentVersion
        TargetVersion = $null
        BumpType = $BumpType
        ChangedFiles = @()
        NormalizedFiles = @()
        Warnings = @()
        Error = $_.Exception.Message
    }
}
