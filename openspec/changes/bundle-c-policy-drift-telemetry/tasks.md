# Tasks: Bundle C Policy Drift Reporting and Telemetry Foundation

## Plan

1. Define Bundle C backend MVP and document design assumptions.
2. Add failing behavioral tests for drift report and telemetry summary commands.
3. Implement policy drift report command in Policy module.
4. Implement policy telemetry summary command in Policy module.
5. Wire module/root exports for both commands.
6. Run targeted tests, parse checks, and command discovery verification.

## Checkpoints

- Checkpoint A: RED state confirmed (tests fail before implementation).
- Checkpoint B: Drift and telemetry functions return standardized success/data/error objects.
- Checkpoint C: Targeted Pester suites pass and new commands resolve via root module import.
