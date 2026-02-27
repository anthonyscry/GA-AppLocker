# Proposal: Bundle B Event Categorization and Candidate Scoring Foundation

## Purpose
Add backend foundations for AppLocker event categorization and rule candidate scoring so operators can prioritize high-signal rule work from event telemetry.

## Scope
- Add event categorization function that labels events as KnownGood, KnownBad, NeedsReview, or Uncategorized.
- Add candidate generation/scoring function that groups repeated events and computes confidence/priority scores.
- Keep this iteration backend-only (no new XAML views).
- Export new functions from Scanning module and root module.

Out of scope:
- New candidate queue UI panel.
- Automatic approval workflows.
- Persistent candidate database beyond existing data sources.

## Acceptance Criteria
- New categorization command returns standardized result object with summary counts and coverage percentage.
- New candidate command returns deterministic, sorted candidate list with confidence score/level and recommended rule type.
- Behavioral tests cover blocked/audit/covered categorization and candidate grouping/scoring behavior.
- Functions are exported and discoverable from root module import.

## Risks
- Misclassification if event fields are incomplete or inconsistent.
- Overly aggressive scoring could over-prioritize low-quality candidates.
- Performance regressions if aggregation logic uses non-scalable collection patterns.
