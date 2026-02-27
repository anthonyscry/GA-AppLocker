# Proposal: Bundle A Preflight + Merge Conflict Guard

## Purpose

Reduce unsafe setup and policy edit operations by adding:

1. A unified preflight diagnostics command before full environment initialization.
2. Contradictory rule merge detection before policy rule attachment.

## Scope

- Add `Invoke-PreflightDiagnostics` in Setup module.
- Gate `Invoke-InitializeAll` on failed preflight checks.
- Add `Test-RuleMergeConflicts` in Policy module.
- Enforce conflict blocking in `Add-RuleToPolicy` before writing policy files.
- Export new commands in module and root manifests.
- Add/adjust targeted Setup unit tests and Policy behavioral tests.

## Acceptance Criteria

- `Invoke-PreflightDiagnostics` returns standard object: `Success`, `Data`, `Error`.
- Diagnostics output includes normalized `Pass|Warn|Fail` checks and summary counts.
- `Invoke-InitializeAll` blocks when any `Fail` checks are present; proceeds on warnings.
- `Add-RuleToPolicy` rejects contradictory Allow/Deny merges for the same semantic key.
- New commands resolve from root module import.
- Targeted Pester suites for Setup and Policy behavior pass.

## Risks

- False-positive conflict detection could block valid policy edits.
- Overly strict preflight fail conditions may reduce operator usability.
- Cross-module export mismatches can silently hide new functions.
