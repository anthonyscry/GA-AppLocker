---
phase: 06-build-and-release-automation-long-term
verified: 2026-02-17T06:48:00Z
status: verified
score: 9/9 must-haves verified
gaps: []
---

# Phase 6: Build and Release Automation (long term) Verification Report

**Phase Goal:** Reproducible releases and single-command packaging for operators.
**Verified:** 2026-02-17T06:48:00Z
**Status:** verified
**Re-verification:** Yes - requirements traceability gap closed

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Operator can generate release notes from git history without manual curation. | ✓ VERIFIED | `tools/Release/Get-ReleaseNotes.ps1:77`, `tools/Release/Get-ReleaseNotes.ps1:89`; dry-run output includes full notes sections (`pwsh -File tools/Release/Get-ReleaseNotes.ps1 -Version 1.2.82`). |
| 2 | Release notes always include Version, Highlights, Fixes, Known Issues, and Upgrade Notes sections. | ✓ VERIFIED | Template hard-codes all sections in order (`tools/templates/release-notes.md.tmpl:1`); renderer fills each placeholder (`tools/Release/Get-ReleaseNotes.ps1:122`). |
| 3 | Version bump classification is deterministic for the same commit range. | ✓ VERIFIED | Deterministic precedence logic breaking > feat > fix > patch (`tools/Release/Get-ReleaseContext.ps1:128`, `tools/Release/Get-ReleaseContext.ps1:149`). |
| 4 | Release packaging produces a versioned ZIP with one root folder. | ✓ VERIFIED | `git archive --prefix` zip generation (`tools/Release/New-ReleasePackage.ps1:146`); package name and root folder set from version (`tools/Release/New-ReleasePackage.ps1:89`). |
| 5 | Integrity sidecars include SHA256 checksums and a package manifest. | ✓ VERIFIED | SHA256 sidecar generation and manifest emission (`tools/Release/New-IntegrityArtifacts.ps1:71`, `tools/Release/New-IntegrityArtifacts.ps1:97`). |
| 6 | Packaging inputs are reproducible from tracked source content. | ✓ VERIFIED | Uses `git archive ... HEAD -- @includePaths` from tracked files only (`tools/Release/New-ReleasePackage.ps1:149`, `tools/Release/New-ReleasePackage.ps1:93`). |
| 7 | A single non-interactive command can run release flow end-to-end. | ✓ VERIFIED | Orchestrator runs Preflight/Version/Notes/Package/Integrity and returns summary (`tools/Invoke-Release.ps1:41`, `tools/Invoke-Release.ps1:221`); command output shows all steps PASS (`pwsh -File tools/Invoke-Release.ps1 --dry-run`). |
| 8 | Version references are normalized and manifests are updated with strict SemVer. | ✓ VERIFIED | Strict SemVer parser + Update-ModuleManifest + Test-ModuleManifest (`tools/Release/Update-ManifestVersions.ps1:16`, `tools/Release/Update-ManifestVersions.ps1:133`, `tools/Release/Update-ManifestVersions.ps1:142`). |
| 9 | Release run continues after step failures and prints per-step summary with next actions. | ✓ VERIFIED | Each step in isolated try/catch with ledger record (`tools/Invoke-Release.ps1:83`, `tools/Invoke-Release.ps1:124`, `tools/Invoke-Release.ps1:156`, `tools/Invoke-Release.ps1:176`, `tools/Invoke-Release.ps1:214`); next actions always printed (`tools/Invoke-Release.ps1:255`). |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `tools/Release/Get-ReleaseContext.ps1` | Commit range, last tag, bump classification | ✓ VERIFIED | Exists; substantive (180 lines); wired from notes/orchestrator (`tools/Release/Get-ReleaseNotes.ps1:66`, `tools/Invoke-Release.ps1:53`). |
| `tools/Release/Get-ReleaseNotes.ps1` | Render operator-facing sectioned release notes | ✓ VERIFIED | Exists; substantive (145 lines); wired from orchestrator (`tools/Invoke-Release.ps1:54`). |
| `tools/templates/release-notes.md.tmpl` | Stable section template | ✓ VERIFIED | Exists; all required placeholders/sections present (`tools/templates/release-notes.md.tmpl:1`). |
| `tools/Release/New-ReleasePackage.ps1` | Versioned ZIP creation | ✓ VERIFIED | Exists; substantive (189 lines); wired from wrapper+orchestrator (`tools/Package-Release.ps1:22`, `tools/Invoke-Release.ps1:56`). |
| `tools/Release/New-IntegrityArtifacts.ps1` | SHA256 + manifest sidecars | ✓ VERIFIED | Exists; substantive (121 lines); wired from wrapper+orchestrator (`tools/Package-Release.ps1:23`, `tools/Invoke-Release.ps1:57`). |
| `tools/Package-Release.ps1` | Compatibility wrapper to new packaging path | ✓ VERIFIED | Exists; delegates to new helpers (`tools/Package-Release.ps1:32`, `tools/Package-Release.ps1:50`); dry-run verified successful. |
| `tools/Release/Update-ManifestVersions.ps1` | Manifest-only version normalization/bump | ✓ VERIFIED | Exists; substantive (175 lines); wired from orchestrator (`tools/Invoke-Release.ps1:55`, `tools/Invoke-Release.ps1:97`). |
| `tools/Invoke-Release.ps1` | Best-effort dry-run release orchestrator | ✓ VERIFIED | Exists; substantive (277 lines); wired from `build.ps1` and `Release-Version.ps1` (`build.ps1:368`, `Release-Version.ps1:36`). |
| `build.ps1` | Package task wired to standardized release command | ✓ VERIFIED | Package task calls orchestrator and checks returned status (`build.ps1:377`). |
| `Release-Version.ps1` | Legacy compatibility wrapper | ✓ VERIFIED | Wrapper forwards to orchestrator and remains non-interactive (`Release-Version.ps1:52`, no `Read-Host` usage). |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `tools/Release/Get-ReleaseContext.ps1` | `git log` | commit range extraction | ✓ WIRED | Commit range and `git log` invocation present (`tools/Release/Get-ReleaseContext.ps1:74`, `tools/Release/Get-ReleaseContext.ps1:77`). |
| `tools/Release/Get-ReleaseNotes.ps1` | `tools/templates/release-notes.md.tmpl` | section rendering | ✓ WIRED | Template path + load + placeholder replacements (`tools/Release/Get-ReleaseNotes.ps1:67`, `tools/Release/Get-ReleaseNotes.ps1:120`). |
| `tools/Release/New-ReleasePackage.ps1` | `git archive` | tracked-source archive generation | ✓ WIRED | Native and WSL `git archive --format=zip --prefix=...` calls (`tools/Release/New-ReleasePackage.ps1:146`, `tools/Release/New-ReleasePackage.ps1:149`). |
| `tools/Release/New-IntegrityArtifacts.ps1` | `GA-AppLocker-v*.zip` | SHA256 hash + manifest sidecar generation | ✓ WIRED | Uses package path, emits `.sha256` and `.manifest.json` with `Get-FileHash` (`tools/Release/New-IntegrityArtifacts.ps1:61`, `tools/Release/New-IntegrityArtifacts.ps1:71`). |
| `tools/Invoke-Release.ps1` | `tools/Release/Update-ManifestVersions.ps1` | version normalization and bump | ✓ WIRED | Script dependency path and invocation present (`tools/Invoke-Release.ps1:55`, `tools/Invoke-Release.ps1:97`). |
| `tools/Invoke-Release.ps1` | `tools/Release/Get-ReleaseNotes.ps1` | notes generation step | ✓ WIRED | Script dependency path and invocation present (`tools/Invoke-Release.ps1:54`, `tools/Invoke-Release.ps1:136`). |
| `tools/Invoke-Release.ps1` | `tools/Release/New-ReleasePackage.ps1` | package/integrity steps | ✓ WIRED | Script dependency path and invocation present (`tools/Invoke-Release.ps1:56`, `tools/Invoke-Release.ps1:165`). |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| REL-01 | Plan 01 | Deterministic release context and release-note generation from git history. | ✓ SATISFIED | `tools/Release/Get-ReleaseContext.ps1`, `tools/Release/Get-ReleaseNotes.ps1`, template + command output evidence above. |
| REL-02 | Plan 02 | Deterministic packaging + integrity sidecars. | ✓ SATISFIED | `tools/Release/New-ReleasePackage.ps1`, `tools/Release/New-IntegrityArtifacts.ps1`, `tools/Package-Release.ps1` dry-run output. |
| REL-03 | Plan 03 | Single-command non-interactive orchestrator with best-effort step reporting. | ✓ SATISFIED | `tools/Invoke-Release.ps1` ledger + step summary output from dry-run. |
| REL-04 | Plan 03 | Standardized entrypoint wiring + manifest version normalization flow. | ✓ SATISFIED | `tools/Release/Update-ManifestVersions.ps1`, `build.ps1:368`, `Release-Version.ps1:36`. |
| REL-01..REL-04 cross-reference | Required by verifier process | Canonical mapping against `.planning/REQUIREMENTS.md`. | ✓ SATISFIED | `.planning/REQUIREMENTS.md` defines REL-01..REL-04 with explicit mapping to `06-build-and-release-automation-long-term`. |

### Plan Summary Alignment

| Summary | Exists | Alignment to code | Evidence |
| --- | --- | --- | --- |
| `06-build-and-release-automation-long-term-01-SUMMARY.md` | ✓ | ✓ aligned | Key files exist and commit hashes `a4cd53b`, `e6936fe` exist with matching changed files. |
| `06-build-and-release-automation-long-term-02-SUMMARY.md` | ✓ | ✓ aligned | Key files exist and commit hashes `a023dc2`, `d933079`, `53135f0` exist with matching changed files. |
| `06-build-and-release-automation-long-term-03-SUMMARY.md` | ✓ | ✓ aligned | Key files exist and commit hashes `41819b3`, `0810189`, `fb1a72c` exist with matching changed files. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| N/A | N/A | No TODO/FIXME/placeholders, empty stubs, or console-log-only implementations detected in phase files. | ℹ️ Info | No blocker anti-patterns found in release automation artifacts. |

### Human Verification Required

### 1. Reproducibility Hash Check

**Test:** Run `pwsh -NoProfile -File tools/Release/New-ReleasePackage.ps1 -Version <same-version> -OutputPath <same-dir>` twice on the same commit, then compare SHA256 of the zip.
**Expected:** SHA256 is identical across both runs.
**Why human:** Determinism claim requires repeated-run comparison in operator environment.

### 2. End-to-End Runtime Check

**Test:** Run `pwsh -NoProfile -File tools/Invoke-Release.ps1` in a clean operator environment and measure elapsed time.
**Expected:** End-to-end flow completes in under 5 minutes and outputs package + sidecars.
**Why human:** Runtime envelope depends on host performance/tooling and cannot be guaranteed from static inspection.

### Gaps Summary

Implementation for phase goal remains present, substantive, and wired: release context/notes, deterministic packaging, integrity artifacts, manifest version normalization, and single-command orchestration are verified in code and dry-run execution. Requirement traceability is now complete because `.planning/REQUIREMENTS.md` provides canonical REL-01..REL-04 definitions mapped to this phase.

---

_Verified: 2026-02-17T06:48:00Z_
_Verifier: Claude (gsd-verifier)_
