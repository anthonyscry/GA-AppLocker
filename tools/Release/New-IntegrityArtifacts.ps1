#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath
)

$ErrorActionPreference = 'Stop'

function Get-GitMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $result = [pscustomobject]@{
        Commit = 'unknown'
        Tag = 'unknown'
        Warning = $null
    }

    try {
        $commit = & git -c "safe.directory=$RepoRoot" rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $commit) {
            $result.Commit = ([string]$commit).Trim()
        }

        $tag = & git -c "safe.directory=$RepoRoot" describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -eq 0 -and $tag) {
            $result.Tag = ([string]$tag).Trim()
        }
    }
    catch {
        $result.Warning = 'Git metadata unavailable. Commit and tag set to unknown.'
    }

    return $result
}

function New-IntegrityArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath
    )

    if (-not (Test-Path -Path $PackagePath)) {
        return [pscustomobject]@{
            Success = $false
            PackagePath = $PackagePath
            Sha256Path = $null
            ManifestPath = $null
            Warning = $null
            Error = 'PackagePath does not exist.'
        }
    }

    $packageFile = Get-Item -Path $PackagePath
    $directory = Split-Path -Path $packageFile.FullName -Parent
    $shaPath = "$($packageFile.FullName).sha256"
    $manifestPath = "$($packageFile.FullName).manifest.json"

    $versionMatch = [regex]::Match($packageFile.BaseName, 'v(\d+\.\d+\.\d+)$')
    $version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { 'unknown' }

    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $meta = Get-GitMetadata -RepoRoot $repoRoot

    try {
        $zipHash = Get-FileHash -Path $packageFile.FullName -Algorithm SHA256
        "$($zipHash.Hash) *$($packageFile.Name)" | Set-Content -Path $shaPath -Encoding ASCII

        $files = [System.Collections.Generic.List[object]]::new()
        [void]$files.Add([pscustomobject]@{
            path = $packageFile.Name
            sha256 = $zipHash.Hash
            size = [int64]$packageFile.Length
        })

        $shaFile = Get-Item -Path $shaPath
        $shaFileHash = Get-FileHash -Path $shaPath -Algorithm SHA256
        [void]$files.Add([pscustomobject]@{
            path = $shaFile.Name
            sha256 = $shaFileHash.Hash
            size = [int64]$shaFile.Length
        })

        $manifestObject = [pscustomobject]@{
            version = $version
            tag = $meta.Tag
            commit = $meta.Commit
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            files = @($files)
        }

        $manifestObject | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding ASCII

        return [pscustomobject]@{
            Success = $true
            PackagePath = $packageFile.FullName
            Sha256Path = $shaPath
            ManifestPath = $manifestPath
            Warning = $meta.Warning
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            PackagePath = $packageFile.FullName
            Sha256Path = $shaPath
            ManifestPath = $manifestPath
            Warning = $meta.Warning
            Error = $_.Exception.Message
        }
    }
}

New-IntegrityArtifacts -PackagePath $PackagePath
