---
updated: 2026-02-17
source: phase-requirements-catalog
---

# GA-AppLocker Canonical Requirements Catalog

This file defines canonical requirement IDs used by planning and verification artifacts.

## REL-01

- **Requirement:** Release context and release notes generation MUST derive from repository history with deterministic version bump classification precedence `breaking > feat > fix > patch`.
- **Phase Mapping:** `06-build-and-release-automation-long-term`

## REL-02

- **Requirement:** Release packaging MUST use tracked-source archiving via `git archive --prefix` and produce a versioned ZIP with a single root folder plus integrity sidecars.
- **Phase Mapping:** `06-build-and-release-automation-long-term`

## REL-03

- **Requirement:** Release execution MUST provide a single non-interactive orchestration path that runs release steps end-to-end and reports per-step pass/fail outcomes.
- **Phase Mapping:** `06-build-and-release-automation-long-term`

## REL-04

- **Requirement:** Release-note output and entrypoint compatibility MUST remain stable for operators, including fixed section templates with empty-section fallback `- None.`, compatibility wrappers, and manifest version normalization.
- **Phase Mapping:** `06-build-and-release-automation-long-term`
