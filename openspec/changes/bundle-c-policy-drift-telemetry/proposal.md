# Proposal: Bundle C Policy Drift Reporting and Telemetry Foundation

## Purpose
Add policy drift reporting and telemetry foundations so operators can quickly identify policy-to-runtime coverage gaps and monitor drift health over time.

## Scope
- Add a backend command to compute policy drift from event telemetry and policy rule coverage.
- Add a backend command to summarize policy telemetry from audit logs.
- Keep this iteration backend-only (no new WPF panel or visual redesign).

Out of scope:
- New dashboard tiles or drift UI tabs.
- Continuous background polling/runspace scheduler for drift.
- Changes to `Export-PolicyToXml` or Validation module internals.

## Acceptance Criteria
- Drift command returns standardized result object with coverage, gap list, and staleness summary.
- Telemetry summary command returns policy action counts and last drift-check metadata.
- Behavioral tests validate drift summary math, gap extraction, telemetry aggregation, and policy filtering.
- New commands are exported from Policy module and root module.

## Risks
- Incomplete event fields can reduce classification fidelity.
- Large event lists may affect latency if aggregation patterns are not O(n).
- Telemetry quality depends on audit log consistency and parsing robustness.
