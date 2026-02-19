# Phase 13 P0/P1 Triage

Date: 2026-02-18
Scope: Phase 13 targeted release-readiness areas only

## Findings

1. Title: WSL `pwsh` test execution fails before suite starts
   - Severity: P1 (environmental for Linux test host only)
   - Status: Closed
   - Root cause: `$env:LOCALAPPDATA` is null in WSL `pwsh`, and Windows/WPF module assumptions fail in non-Windows host context.
   - Resolution: Run release-readiness suites through Windows host PowerShell (`powershell.exe`) from WSL.

2. Title: Non-Windows host missing WPF assembly load path
   - Severity: P1 (environmental for Linux test host only)
   - Status: Closed
   - Root cause: project depends on Windows PowerShell + WPF assemblies not available in Linux runtime.
   - Resolution: validated targeted suites with Windows PowerShell host; documented operator guidance.

## Open P0/P1 in Scope

- None.
