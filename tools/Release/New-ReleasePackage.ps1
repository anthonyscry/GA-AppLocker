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

function Convert-ToWslPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path -match '^/mnt/[a-z]/') {
        return $Path
    }

    if ($Path -match '^([A-Za-z]):\\') {
        $drive = $Matches[1].ToLowerInvariant()
        $suffix = $Path.Substring(2).Replace('\', '/')
        return "/mnt/$drive$suffix"
    }

    return $Path
}

function Resolve-GitCommandInfo {
    [CmdletBinding()]
    param()

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $gitCommand) {
        return [pscustomobject]@{ Type = 'native'; Command = $gitCommand.Source }
    }

    $whereResult = & cmd.exe /d /c "where git 2>nul"
    if ($LASTEXITCODE -eq 0 -and $whereResult) {
        foreach ($candidate in @($whereResult)) {
            if (Test-Path -Path $candidate) {
                return [pscustomobject]@{ Type = 'native'; Command = $candidate }
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
            return [pscustomobject]@{ Type = 'native'; Command = $candidate }
        }
    }

    $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -ne $wslCommand) {
        & $wslCommand.Source git --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Type = 'wsl'; Command = $wslCommand.Source }
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

    $gitInfo = Resolve-GitCommandInfo
    if ($null -eq $gitInfo -or [string]::IsNullOrWhiteSpace($gitInfo.Command)) {
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
            Error              = 'git command was not found in PATH, common install locations, or WSL.'
        }
    }

    if (-not (Test-Path -Path $OutputPath)) {
        [void](New-Item -Path $OutputPath -ItemType Directory -Force)
    }

    if (Test-Path -Path $packagePath) {
        Remove-Item -Path $packagePath -Force
    }

    try {
        if ($gitInfo.Type -eq 'wsl') {
            $repoRootForGit = Convert-ToWslPath -Path $repoRoot
            $packagePathForGit = Convert-ToWslPath -Path $packagePath
            & $gitInfo.Command git -C $repoRootForGit -c "safe.directory=$repoRootForGit" archive --format=zip "--prefix=$rootFolder/" -o $packagePathForGit HEAD -- @includePaths
        }
        else {
            & $gitInfo.Command -C $repoRoot -c "safe.directory=$repoRoot" archive --format=zip "--prefix=$rootFolder/" -o $packagePath HEAD -- @includePaths
        }

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
}

New-ReleasePackage -Version $Version -OutputPath $OutputPath -DryRun:$DryRun
