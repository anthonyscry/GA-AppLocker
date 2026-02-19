#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the lean must-pass GA-AppLocker test gate.

.DESCRIPTION
    Executes a curated set of high-signal behavioral/E2E tests only.
    This gate is designed for fast confidence without noisy pattern-only checks.
#>

[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$mustPassTests = @(
    (Join-Path $PSScriptRoot 'Behavioral\Workflows\CoreFlows.E2E.Tests.ps1'),
    (Join-Path $PSScriptRoot 'Behavioral\Workflows\Workflow.Mock.Tests.ps1'),
    (Join-Path $PSScriptRoot 'Behavioral\GUI\Scanner.PanelWorkflow.Tests.ps1'),
    (Join-Path $PSScriptRoot 'Behavioral\GUI\Rules.PanelWorkflow.Tests.ps1'),
    (Join-Path $PSScriptRoot 'Behavioral\GUI\Policy.PanelWorkflow.Tests.ps1'),
    (Join-Path $PSScriptRoot 'Behavioral\GUI\Deploy.PanelWorkflow.Tests.ps1')
)

$missing = @($mustPassTests | Where-Object { -not (Test-Path $_) })
if ($missing.Count -gt 0) {
    throw "Must-pass test files missing:`n$($missing -join "`n")"
}

$phase13EvidencePath = Join-Path $PSScriptRoot '..\docs\plans\2026-02-18-phase-13-verification-evidence.md'
if (-not (Test-Path $phase13EvidencePath)) {
    throw "Phase 13 verification evidence file missing: $phase13EvidencePath"
}

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host '  GA-AppLocker Must-Pass Test Gate' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "Test files: $($mustPassTests.Count)"
Write-Host ''
$invokeParams = @{
    Path     = $mustPassTests
    PassThru = $true
}

if ($OutputPath) {
    $invokeParams.OutputFile = $OutputPath
}

$result = Invoke-Pester @invokeParams

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host '  MUST-PASS SUMMARY' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "Passed: $($result.PassedCount)"
Write-Host "Failed: $($result.FailedCount)"
Write-Host "Skipped: $($result.SkippedCount)"

if ($result.FailedCount -gt 0) {
    exit 1
}

exit 0
