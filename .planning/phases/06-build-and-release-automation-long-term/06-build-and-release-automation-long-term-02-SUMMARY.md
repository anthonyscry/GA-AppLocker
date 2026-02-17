---
phase: 06-build-and-release-automation-long-term
plan: 02
subsystem: infra
tags: [powershell, release, git-archive, sha256]

requires:
  - phase: 06-build-and-release-automation-long-term-01
    provides: release context and commit metadata helpers
provides:
  - Deterministic versioned ZIP packaging from tracked repository content
  - SHA256 sidecar and machine-readable package manifest generation
  - Backward-compatible packaging entrypoint routed through shared helpers
affects: [build, release, operators]

tech-stack:
  added: []
  patterns: [git archive with fixed prefix root, structured result objects for release helpers]

key-files:
  created:
    - tools/Release/New-ReleasePackage.ps1
    - tools/Release/New-IntegrityArtifacts.ps1
  modified:
    - tools/Package-Release.ps1

key-decisions:
  - "Use git archive with --prefix to guarantee single-root deterministic package layout."
  - "Keep tools/Package-Release.ps1 as a compatibility wrapper to avoid operator workflow breakage."

patterns-established:
  - "Release helpers return structured Success/Error objects for orchestration."
  - "Integrity sidecars are emitted adjacent to package artifacts for offline verification."

requirements-completed: [REL-02]

duration: 2 min
completed: 2026-02-17
---

# Phase 6 Plan 2: Deterministic Packaging and Integrity Artifacts Summary

**Deterministic git-archive packaging now produces `GA-AppLocker-vX.Y.Z.zip` with a single root folder and adjacent checksum/manifest sidecars from release helpers.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-17T06:19:15Z
- **Completed:** 2026-02-17T06:21:45Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Added `New-ReleasePackage.ps1` with SemVer validation, dry-run support, and deterministic tracked-content ZIP generation.
- Added `New-IntegrityArtifacts.ps1` to emit ASCII `.sha256` sidecar and package manifest JSON (`version`, `tag`, `commit`, `generatedAtUtc`, `files`).
- Replaced legacy `Compress-Archive` path in `tools/Package-Release.ps1` with helper delegation while preserving existing operator entrypoint.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement reproducible ZIP packaging helper with single root folder** - `a023dc2` (feat)
2. **Task 2: Emit integrity artifacts and package manifest sidecar** - `d933079` (feat)
3. **Task 3: Preserve existing package entrypoint by delegating to new helper** - `53135f0` (fix)

## Files Created/Modified
- `tools/Release/New-ReleasePackage.ps1` - Creates deterministic versioned ZIP from tracked sources.
- `tools/Release/New-IntegrityArtifacts.ps1` - Generates SHA256 sidecar and manifest metadata.
- `tools/Package-Release.ps1` - Compatibility wrapper that delegates packaging + integrity generation.

## Decisions Made
- Used `git archive --prefix` for deterministic tracked-content packaging instead of direct working-tree compression.
- Kept legacy packaging command path stable by routing through new helper scripts rather than replacing operator-facing entrypoint.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added resilient git invocation for mixed environments**
- **Found during:** Task 1 (Implement reproducible ZIP packaging helper with single root folder)
- **Issue:** Verification environment lacked Windows `git` in PATH and hit safe-directory checks for repository ownership.
- **Fix:** Added git command resolution plus `safe.directory` invocation and WSL `git` fallback path conversion for `git archive`.
- **Files modified:** tools/Release/New-ReleasePackage.ps1
- **Verification:** `powershell -NoProfile -File tools/Release/New-ReleasePackage.ps1 -Version 1.2.82 -OutputPath .\BuildOutput` succeeded and produced correct root folder.
- **Committed in:** 53135f0 (part of task completion)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Blocking fix preserved plan intent and enabled deterministic packaging verification in this environment.

## Authentication Gates

None.

## Issues Encountered

- Windows PowerShell environment did not have native `git` available, requiring a non-interactive WSL git fallback in the packaging helper.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Packaging and integrity helper layer is complete and ready for phase 06 plan 03 orchestration wiring.
- Legacy operator command remains stable and now emits deterministic package outputs with sidecars.

## Self-Check: PASSED

- Found summary file at expected path.
- Verified task commits `a023dc2`, `d933079`, and `53135f0` exist in git history.
