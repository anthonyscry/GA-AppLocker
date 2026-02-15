# Scanner/Rules Publisher Fidelity Design

Date: 2026-02-15
Status: Approved for planning (validated)
Owner: GA-AppLocker

## Summary

- Goal: maximize publisher-rule fidelity in the Scanner to Rules flow by preventing metadata drift across scan, export, import, and generation.
- Primary outcome: signed artifacts that include signer identity should continue producing publisher rules after any supported roundtrip.
- Acceptance signal: behavioral regression proof in curated must-pass tests.

## Validated Constraints

- Priority: behavioral safety first; prefer deterministic compatibility-preserving changes over strict breakage.
- Scope boundary: Scanner and Rules artifact paths only (normalization/projection/import/export and rule-generation inputs).
- Verification bar: curated must-pass gate with targeted behavioral coverage for roundtrip publisher fidelity and tier normalization.

## Problem Statement

Recent regressions showed two reliability gaps:

1. Artifact metadata loss during CSV export/import could strip signer identity fields required for publisher rule generation.
2. Credential tier resolution could drift when `MachineTypeTiers` config shape varied (hashtable vs object; numeric vs `T0/T1/T2` values).

Both issues create silent behavior changes that degrade operator trust and produce weaker rule output.

## Goals

- Preserve publisher-signing metadata end-to-end in Scanner and Scan export/import paths.
- Normalize tier mapping keys and values deterministically before credential selection.
- Keep backward compatibility with legacy artifact files and legacy tier config formats.
- Enforce the behavior with high-signal behavioral tests in the must-pass gate.

## Non-Goals

- No scheduler or deployment workflow changes.
- No redesign of rule generation semantics beyond metadata fidelity.
- No broad UI redesign outside Scanner import/export behavior and status reporting.

## Approaches Considered

### A) Canonical artifact contract (selected)

- Define and enforce one normalized artifact schema at all Scanner/Rules boundaries.
- Route every artifact ingress/egress path through shared normalization.
- Pros: strongest long-term consistency, easiest regression detection, least drift.
- Cons: moderate implementation scope.

### B) Targeted patch set

- Patch only known breakpoints (specific export/import fields and tier parsing).
- Pros: fastest delivery.
- Cons: higher future drift risk as new paths are added.

### C) Preflight validator gate

- Keep current paths but add a strict validation gate before rule generation.
- Pros: catches missing data early.
- Cons: detects but does not prevent metadata loss; weaker operator experience.

## Selected Design

### 1) Canonical artifact contract

Use a single logical schema (types and semantics) for artifacts consumed by rule generation:

- Identity: `FileName`, `FilePath`, `Extension`, `ArtifactType`, `CollectionType`
- Signing: `IsSigned` (strict boolean), `SignerCertificate`, `PublisherName`, `SignatureStatus`
- Product metadata: `ProductName`, `ProductVersion`, `FileVersion`
- Rule identity inputs: `SHA256Hash`, `SizeBytes`, `ComputerName`
- Compatibility field: `FileSize` retained for legacy consumers but normalized to `SizeBytes` when needed

### 2) Normalization boundaries

Normalize at every boundary where shape changes can occur:

- Scan output before persistence/export
- Per-host CSV export
- Scanner panel export
- Scanner panel import (CSV/JSON)
- Drag/drop artifact import paths

Normalization rules:

- `IsSigned`: convert string/legacy values to strict boolean (`True/False`, case-insensitive, with explicit numeric fallback where applicable)
- `SizeBytes`: if missing and `FileSize` present, attempt typed coercion and log on failure
- Publisher identity: preserve both `SignerCertificate` and `PublisherName` when present
- Never drop publisher-related fields from export projections

### 3) Tier mapping normalization

Normalize machine-type keys and tier values before lookup:

- Key normalization examples: `Domain Controller`, `domaincontroller`, `dc` -> `DomainController`; `srv` -> `Server`
- Tier value normalization examples: `0/1/2`, `T0/T1/T2`, `Tier 0/1/2`
- Deterministic fallback order:
  1. normalized configured tier
  2. default tier from normalized machine type
  3. final fallback tier `2`

## Data Flow

1. Collect artifacts (`Get-LocalArtifacts`, `Get-RemoteArtifacts`, Appx enumeration)
2. Normalize to canonical contract
3. Persist/export with full fidelity fields
4. Import and re-normalize (legacy-safe)
5. Generate rules (`Invoke-BatchRuleGeneration` / `ConvertFrom-Artifact`)

Publisher rule readiness is determined by:

- `IsSigned = $true`, and
- non-empty signer identity field (`SignerCertificate` for classic binaries, `PublisherName` for Appx paths)

## Error Handling and Observability

- Replace silent coercion catches with debug-level logs that include file context and bad values.
- Treat normalization anomalies as non-fatal warnings when safe fallback exists.
- Continue batch processing; avoid UI-blocking behavior for recoverable issues.
- Reserve hard failures for unrecoverable contract violations.

## Testing Strategy

- Add behavioral roundtrip tests proving signed artifacts remain publisher-rule candidates after export/import.
- Add tier normalization tests for:
  - hashtable and object config shapes
  - numeric and `T0/T1/T2` tier values
  - machine-type key variants and casing
- Keep these checks in curated must-pass coverage to enforce regression detection.

## Definition of Done

- Signed artifact roundtrip retains signer identity and generates publisher rules.
- Tier credential selection is deterministic under mixed legacy/current config shapes.
- No silent coercion failures in import normalization paths.
- Curated must-pass gate includes and passes behavioral evidence for these scenarios.

## Risks and Mitigations

- Risk: future export paths omit newly required fields.
  - Mitigation: canonical field list and shared projection helper.
- Risk: legacy data with malformed numeric strings.
  - Mitigation: strict coercion with logged fallback behavior.
- Risk: config drift in machine type names.
  - Mitigation: centralized key normalization with deterministic defaults.

## Rollout

1. Implement normalization and projection updates in Scanner/Scanning paths.
2. Add/update behavioral tests for publisher fidelity and tier mapping.
3. Run must-pass gate.
4. Promote to broader test runs as needed.
