#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')]
    [string]$Version,

    [string]$OutputPath = (Join-Path (Get-Location) 'BuildOutput'),

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-GitCommandPath {
    [CmdletBinding()]
    param()

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $gitCommand) {
        return $gitCommand.Source
    }

    $whereResult = & cmd.exe /d /c "where git 2>nul"
    if ($LASTEXITCODE -eq 0 -and $whereResult) {
        foreach ($candidate in @($whereResult)) {
            if (Test-Path -Path $candidate) {
                return $candidate
            }
        }
    }

    $candidatePaths = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramW6432 'Git\cmd\git.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidatePaths) {
        if (Test-Path -Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function New-ReleasePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [switch]$DryRun
    )

    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $packageName = "GA-AppLocker-v$Version.zip"
    $rootFolder = "GA-AppLocker-v$Version"
    $packagePath = Join-Path $OutputPath $packageName

    $includePaths = @(
        'GA-AppLocker',
        'Run-Dashboard.ps1',
        'Run-Dashboard-ForceFresh.ps1',
        'README.md',
        'CHANGELOG.md'
    )

    if ($DryRun) {
        return [pscustomobject]@{
            Success            = $true
            DryRun             = $true
            Version            = $Version
            PackagePath        = $packagePath
            PackageSizeBytes   = 0
            RootFolder         = $rootFolder
            IncludedPathCount  = $includePaths.Count
            IncludedPaths      = $includePaths
            IncludedSummary    = ($includePaths -join ', ')
            Warning            = $null
            Error              = $null
        }
    }

    $gitPath = Resolve-GitCommandPath
    if ([string]::IsNullOrWhiteSpace($gitPath)) {
        return [pscustomobject]@{
            Success            = $false
            DryRun             = $false
            Version            = $Version
            PackagePath        = $packagePath
            PackageSizeBytes   = 0
            RootFolder         = $rootFolder
            IncludedPathCount  = $includePaths.Count
            IncludedPaths      = $includePaths
            IncludedSummary    = ($includePaths -join ', ')
            Warning            = $null
            Error              = 'git command was not found in PATH or common install locations.'
        }
    }

    if (-not (Test-Path -Path $OutputPath)) {
        [void](New-Item -Path $OutputPath -ItemType Directory -Force)
    }

    if (Test-Path -Path $packagePath) {
        Remove-Item -Path $packagePath -Force
    }

    Push-Location $repoRoot
    try {
        & $gitPath -c "safe.directory=$repoRoot" archive --format=zip "--prefix=$rootFolder/" -o $packagePath HEAD -- @includePaths
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -Path $packagePath)) {
            throw 'git archive did not create the expected package.'
        }

        $zipItem = Get-Item -Path $packagePath
        return [pscustomobject]@{
            Success            = $true
            DryRun             = $false
            Version            = $Version
            PackagePath        = $packagePath
            PackageSizeBytes   = [int64]$zipItem.Length
            RootFolder         = $rootFolder
            IncludedPathCount  = $includePaths.Count
            IncludedPaths      = $includePaths
            IncludedSummary    = ($includePaths -join ', ')
            Warning            = $null
            Error              = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success            = $false
            DryRun             = $false
            Version            = $Version
            PackagePath        = $packagePath
            PackageSizeBytes   = 0
            RootFolder         = $rootFolder
            IncludedPathCount  = $includePaths.Count
            IncludedPaths      = $includePaths
            IncludedSummary    = ($includePaths -join ', ')
            Warning            = $null
            Error              = $_.Exception.Message
        }
    }
    finally {
        Pop-Location
    }
}

New-ReleasePackage -Version $Version -OutputPath $OutputPath -DryRun:$DryRun
