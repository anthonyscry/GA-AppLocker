[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version,

    [Parameter()]
    [switch]$AsObject,

    [Parameter()]
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Get-StrictSemVer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $match = [regex]::Match($Value, '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
    if (-not $match.Success) {
        throw "Version '$Value' is not strict SemVer major.minor.patch"
    }

    return '{0}.{1}.{2}' -f $match.Groups[1].Value, $match.Groups[2].Value, $match.Groups[3].Value
}

function ConvertTo-OperatorBullet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subject
    )

    $text = $Subject.Trim()
    $text = [regex]::Replace($text, '^[A-Za-z]+(\([^)]+\))?(!)?:\s*', '')

    if ([string]::IsNullOrWhiteSpace($text)) {
        return '- Operational update applied.'
    }

    $first = $text.Substring(0, 1).ToUpperInvariant()
    $rest = if ($text.Length -gt 1) { $text.Substring(1) } else { '' }
    $sentence = "$first$rest"
    if ($sentence[-1] -ne '.') {
        $sentence = "$sentence."
    }

    return "- $sentence"
}

function Join-OrNone {
    param(
        [System.Collections.Generic.List[string]]$Items
    )

    if (($null -eq $Items) -or ($Items.Count -eq 0)) {
        return '- None.'
    }

    return ($Items -join [Environment]::NewLine)
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path (Split-Path $scriptPath -Parent) -Parent
$contextScript = Join-Path $scriptPath 'Get-ReleaseContext.ps1'
$templatePath = Join-Path $repoRoot 'tools/templates/release-notes.md.tmpl'

if (-not (Test-Path $contextScript)) {
    throw "Missing dependency script: $contextScript"
}

if (-not (Test-Path $templatePath)) {
    throw "Missing template file: $templatePath"
}

$context = & $contextScript

$resolvedVersion = if ([string]::IsNullOrWhiteSpace($Version)) {
    [string]$context.NormalizedVersion
}
else {
    Get-StrictSemVer -Value $Version
}

$highlights = [System.Collections.Generic.List[string]]::new()
$fixes = [System.Collections.Generic.List[string]]::new()

foreach ($record in @($context.CommitRecords)) {
    if ($null -eq $record) {
        continue
    }

    $bullet = ConvertTo-OperatorBullet -Subject ([string]$record.Subject)

    if ($record.IsBreaking -or $record.ConventionalType -eq 'feat') {
        [void]$highlights.Add($bullet)
        continue
    }

    if ($record.ConventionalType -eq 'fix') {
        [void]$fixes.Add($bullet)
        continue
    }

    [void]$highlights.Add($bullet)
}

$knownIssues = '- None.'
$upgradeNotes = if ($context.BumpType -eq 'major') {
    '- Review policy compatibility and rollout sequencing before deployment.'
}
elseif ($context.BumpType -eq 'minor') {
    '- Validate new feature behavior in audit mode before enforcement.'
}
else {
    '- Apply update and run standard post-deployment validation checks.'
}

$template = Get-Content -Path $templatePath -Raw
$notesText = $template
$notesText = $notesText.Replace('{{VERSION}}', $resolvedVersion)
$notesText = $notesText.Replace('{{HIGHLIGHTS}}', (Join-OrNone -Items $highlights))
$notesText = $notesText.Replace('{{FIXES}}', (Join-OrNone -Items $fixes))
$notesText = $notesText.Replace('{{KNOWN_ISSUES}}', $knownIssues)
$notesText = $notesText.Replace('{{UPGRADE_NOTES}}', $upgradeNotes)

$metadata = [pscustomobject]@{
    EntryCount   = @($context.CommitRecords).Count
    SourceRange  = [string]$context.CommitRange
    Version      = $resolvedVersion
    BumpType     = [string]$context.BumpType
    ReleaseNotes = $notesText
}

if ($AsJson) {
    $metadata | ConvertTo-Json -Depth 6
}
elseif ($AsObject) {
    $metadata
}
else {
    $notesText
}
