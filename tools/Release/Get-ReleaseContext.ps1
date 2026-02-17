[CmdletBinding()]
param(
    [Parameter()]
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Invoke-RepoGit {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $allArgs = @('-c', "safe.directory=$RepositoryRoot", '-C', $RepositoryRoot) + $Arguments
    return (& $script:GitCommand @allArgs 2>$null)
}

function Resolve-GitCommand {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    $candidates = @(
        '/usr/bin/git',
        '/bin/git',
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files\Git\bin\git.exe',
        'C:\Program Files (x86)\Git\cmd\git.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw 'Git executable not found. Install Git or add git.exe to PATH.'
}

function Get-ReleaseContextData {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $manifestPath = Join-Path $repoRoot 'GA-AppLocker/GA-AppLocker.psd1'

    if (-not (Test-Path $manifestPath)) {
        throw "Manifest not found: $manifestPath"
    }

    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $currentVersion = [string]$manifest.ModuleVersion

    $versionMatch = [regex]::Match($currentVersion, '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
    if (-not $versionMatch.Success) {
        throw "Manifest version '$currentVersion' is not strict SemVer major.minor.patch"
    }

    $normalizedVersion = '{0}.{1}.{2}' -f $versionMatch.Groups[1].Value, $versionMatch.Groups[2].Value, $versionMatch.Groups[3].Value

    $warnings = [System.Collections.Generic.List[string]]::new()

    $tags = @(Invoke-RepoGit -RepositoryRoot $repoRoot -Arguments @('tag', '--merged', 'HEAD', '--list', 'v*', '--sort=-v:refname'))
    $lastTag = $null
    if ($tags.Count -gt 0) {
        $candidate = [string]$tags[0]
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $lastTag = $candidate.Trim()
        }
    }

    $commitRange = if ($lastTag) { "$lastTag..HEAD" } else { 'HEAD' }

    $format = '%H%x1f%s%x1f%b%x1e'
    $rawLog = [string](Invoke-RepoGit -RepositoryRoot $repoRoot -Arguments @('log', $commitRange, '--pretty=format:' + $format))

    $commitRecords = [System.Collections.Generic.List[object]]::new()

    if (-not [string]::IsNullOrWhiteSpace($rawLog)) {
        $entries = $rawLog -split [char]0x1e
        foreach ($entry in $entries) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }

            $fields = $entry -split [char]0x1f, 3
            if ($fields.Count -lt 2) {
                continue
            }

            $commitHash = [string]$fields[0]
            $subject = [string]$fields[1]
            $body = if ($fields.Count -ge 3) { [string]$fields[2] } else { '' }

            $type = $null
            $scope = $null
            $breakingFromBang = $false
            $subjectMatch = [regex]::Match($subject, '^([A-Za-z]+)(\(([^)]+)\))?(!)?:\s+(.+)$')
            if ($subjectMatch.Success) {
                $type = $subjectMatch.Groups[1].Value.ToLowerInvariant()
                if ($subjectMatch.Groups[3].Success) {
                    $scope = $subjectMatch.Groups[3].Value
                }
                if ($subjectMatch.Groups[4].Success) {
                    $breakingFromBang = $true
                }
            }
            else {
                [void]$warnings.Add("Non-conventional commit subject: $subject")
            }

            $breakingFromBody = [regex]::IsMatch($body, '(?im)^BREAKING CHANGE\s*:')
            $isBreaking = $breakingFromBang -or $breakingFromBody

            [void]$commitRecords.Add([pscustomobject]@{
                    CommitHash       = $commitHash
                    Subject          = $subject
                    Body             = $body
                    ConventionalType = $type
                    Scope            = $scope
                    IsBreaking       = $isBreaking
                })
        }
    }

    $bumpType = 'patch'
    if ($commitRecords.Count -gt 0) {
        $hasBreaking = $false
        $hasFeat = $false
        $hasFix = $false

        foreach ($record in $commitRecords) {
            if ($record.IsBreaking) {
                $hasBreaking = $true
                break
            }

            if ($record.ConventionalType -eq 'feat') {
                $hasFeat = $true
            }

            if ($record.ConventionalType -eq 'fix') {
                $hasFix = $true
            }
        }

        if ($hasBreaking) {
            $bumpType = 'major'
        }
        elseif ($hasFeat) {
            $bumpType = 'minor'
        }
        elseif ($hasFix) {
            $bumpType = 'patch'
        }
    }

    return [pscustomobject]@{
        CurrentVersion    = $currentVersion
        NormalizedVersion = $normalizedVersion
        LastTag           = $lastTag
        CommitRange       = $commitRange
        CommitRecords     = @($commitRecords)
        BumpType          = $bumpType
        Warnings          = @($warnings)
    }
}

$script:GitCommand = Resolve-GitCommand
$context = Get-ReleaseContextData

if ($AsJson) {
    $context | ConvertTo-Json -Depth 6
}
else {
    $context
}
