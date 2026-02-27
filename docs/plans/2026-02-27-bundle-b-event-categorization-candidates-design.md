# Bundle B Event Categorization and Candidate Scoring Design

## Goal
Implement backend foundations that convert AppLocker events into operator-prioritized rule candidates without introducing new UI risk.

## Why this scope
GA-AppLocker already collects event logs and supports rule generation, but lacks two decision layers:
1) Event categorization (KnownGood/KnownBad/NeedsReview)
2) Candidate scoring from repeated event patterns

This design adds those layers as exported commands first, then leaves UI integration for a later iteration.

## Proposed commands

### Invoke-AppLockerEventCategorization
- Module: `GA-AppLocker.Scanning`
- Inputs:
  - `-Events` event array (mandatory)
  - `-Rules` optional rule array (defaults to approved rules)
  - `-WorkingPolicyId` optional future-facing identifier (not used for storage mutation)
- Behavior:
  - Determines coverage status (`Covered`, `Uncovered`, `Partial`) per event.
  - Applies category mapping:
    - Covered -> `KnownGood`
    - Uncovered + IsBlocked -> `KnownBad`
    - Uncovered + IsAudit -> `NeedsReview`
    - Missing critical fields -> `Uncategorized`
  - Returns standardized result object with categorized events and summary counts.

### Get-AppLockerRuleCandidates
- Module: `GA-AppLocker.Scanning`
- Inputs:
  - `-Events` event array (mandatory)
  - `-MinimumRecurrenceCount` default `2`
  - `-MinimumConfidenceScore` default `40`
  - `-MaximumCandidates` default `100`
  - `-SkipCoveredCandidates` switch
- Behavior:
  - Groups events by correlation key (`FileHash` when present, otherwise normalized `FilePath`).
  - Computes recurrence and machine spread.
  - Computes deterministic confidence score and confidence level.
  - Recommends rule type (`Publisher`, `Hash`, `Path`) based on available signal quality.
  - Returns sorted candidates with generation summary.

## Scoring model (MVP)
- Base: recurrence and machine spread.
- Positive signals: signed/publisher-rich events, repeated blocked events.
- Negative signals: volatile paths (Temp/Downloads/AppData Local Temp), low recurrence.
- Output fields include `ConfidenceScore` (0-100), `ConfidenceLevel` (Low/Medium/High), and `RecommendedRuleType`.

## Safety and compatibility
- PowerShell 5.1 safe constructs only.
- Uses `List[T]` and dictionary/hashset patterns to avoid O(n^2) array concatenation.
- No UI thread work added.
- No changes to policy export/validation critical paths.

## Test strategy
- Add behavioral core tests with mocked event/rule objects:
  - Categorization for covered, blocked-uncovered, audit-uncovered.
  - Candidate grouping and confidence sorting determinism.
  - Skip-covered behavior and threshold filtering.
- Keep tests independent from WPF and network.
