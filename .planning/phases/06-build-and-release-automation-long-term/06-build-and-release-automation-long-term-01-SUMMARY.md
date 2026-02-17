---
phase: 06-build-and-release-automation-long-term
plan: 01
subsystem: infra
tags: [release, semver, git, powershell]
requires:
  - phase: 03-ux-and-workflow-friction
    provides: Stable baseline workflows and current release version state
provides:
  - Deterministic release context extraction with commit-range classification
  - Standardized operator-facing release notes generation from git history
  - Stable markdown template with required release note sections
affects: [release automation, packaging, versioning]
tech-stack:
  added: []
  patterns: [conventional-commit bump precedence, template-driven notes rendering]
key-files:
  created:
    - tools/Release/Get-ReleaseContext.ps1
    - tools/Release/Get-ReleaseNotes.ps1
    - tools/templates/release-notes.md.tmpl
  modified: []
key-decisions:
  - "Use deterministic bump precedence breaking > feat > fix > patch from git history."
  - "Render release notes from a fixed template and always include empty sections as '- None.'."
patterns-established:
  - "Release context object contract: CurrentVersion, NormalizedVersion, LastTag, CommitRange, CommitRecords, BumpType, Warnings"
  - "Operator notes layout locked to Version, Highlights, Fixes, Known Issues, Upgrade Notes"
requirements-completed: [REL-01]
duration: 3 min
completed: 2026-02-17
---

# Phase 6 Plan 1: Build release context and standardized git-based release notes Summary

**Deterministic SemVer bump classification and operator-ready release notes generation now run directly from git history with fixed, complete markdown sections.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-17T06:17:06Z
- **Completed:** 2026-02-17T06:20:55Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added `Get-ReleaseContext.ps1` to read strict SemVer, discover commit range, parse commit records, and classify bump type deterministically.
- Added `Get-ReleaseNotes.ps1` to map commit records into operator-facing bullets and render required sections in fixed order.
- Added `release-notes.md.tmpl` so release notes always include Version, Highlights, Fixes, Known Issues, and Upgrade Notes.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement release context and SemVer bump classification helpers** - `a4cd53b` (feat)
2. **Task 2: Generate standardized operator-facing release notes from git history** - `e6936fe` (feat)

## Files Created/Modified
- `tools/Release/Get-ReleaseContext.ps1` - Produces deterministic release context and bump classification from manifest + git history.
- `tools/Release/Get-ReleaseNotes.ps1` - Renders operator-facing release notes and metadata from release context.
- `tools/templates/release-notes.md.tmpl` - Defines stable, required markdown section layout.

## Decisions Made
- Use strict SemVer validation (`major.minor.patch`) from the module manifest as release context source.
- Use conventional-commit precedence (`breaking > feat > fix > patch`) to keep bump classification deterministic.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] PowerShell command availability mismatch in WSL environment**
- **Found during:** Task 1 verification
- **Issue:** `powershell` command was unavailable in this Linux host, so the exact verification command could not run as written.
- **Fix:** Executed equivalent verification with `pwsh` while keeping scripts PowerShell 5.1-compatible and non-interactive.
- **Files modified:** none
- **Verification:** `pwsh -NoProfile -File tools/Release/Get-ReleaseContext.ps1 -AsJson` returned required `BumpType` and `CommitRange` fields.
- **Committed in:** N/A (execution-environment adjustment)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No scope creep; verification completed with equivalent PowerShell command path.

## Issues Encountered
- None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 01 deliverables are complete and verified.
- Ready for `06-build-and-release-automation-long-term-02-PLAN.md`.

---
*Phase: 06-build-and-release-automation-long-term*
*Completed: 2026-02-17*

## Self-Check: PASSED
