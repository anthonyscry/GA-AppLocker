#Requires -Version 5.1
<#
.SYNOPSIS
    Legacy compatibility wrapper for GA-AppLocker release automation.

.DESCRIPTION
    Forwards execution to tools/Invoke-Release.ps1 to keep release behavior
    non-interactive and standardized across entrypoints.

.PARAMETER Version
    Legacy parameter retained for compatibility. Informational only.

.PARAMETER SkipZip
    Legacy parameter retained for compatibility. The orchestrator controls
    package creation and integrity artifacts.

.PARAMETER DryRun
    Runs release orchestration in dry-run mode.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version,

    [Parameter()]
    [switch]$SkipZip,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$invokeReleasePath = Join-Path $scriptRoot 'tools\Invoke-Release.ps1'

if (-not (Test-Path -Path $invokeReleasePath)) {
    Write-Error "Release orchestrator not found: $invokeReleasePath"
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($Version)) {
    Write-Warning "-Version is retained for compatibility and ignored. Invoke-Release determines version from release context."
}

if ($SkipZip) {
    Write-Warning "-SkipZip is retained for compatibility and ignored. Invoke-Release controls packaging steps."
}

try {
    $result = & $invokeReleasePath -DryRun:$DryRun
    if ($result -is [array]) {
        $result = $result[-1]
    }

    if ($null -eq $result -or -not $result.Success) {
        Write-Error 'Release workflow completed with one or more failed steps. Review summary output above.'
        exit 1
    }

    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
