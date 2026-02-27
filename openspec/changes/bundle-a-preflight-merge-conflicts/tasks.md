# Tasks: Bundle A Preflight + Merge Conflict Guard

## Plan

1. Add failing tests for preflight diagnostics result contract.
2. Implement `Invoke-PreflightDiagnostics` and export from Setup module.
3. Gate Setup full initialization on preflight fail checks.
4. Add failing behavioral test for contradictory policy rule merge.
5. Implement `Test-RuleMergeConflicts` and enforce it in `Add-RuleToPolicy`.
6. Export policy command from Policy module and root module.
7. Run targeted verification and command discovery checks.

## Checkpoints

- Checkpoint A: RED state captured for Setup and Policy tests before implementation.
- Checkpoint B: New commands return standardized result objects.
- Checkpoint C: Contradictory merges are blocked while non-conflicting adds still succeed.
- Checkpoint D: Targeted Pester suites and root command discovery pass.
