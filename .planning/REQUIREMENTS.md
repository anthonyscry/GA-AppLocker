# Requirements: GA-AppLocker v1.2.90

**Defined:** 2026-02-19
**Core Value:** Reliable, operator-friendly policy management that stays responsive on large enterprise datasets

## v1 Requirements

Requirements for v1.2.90 Production Hardening. Each maps to roadmap phases.

### Error Handling

- [ ] **ERR-01**: All empty catch blocks in GUI/Panels replace silent swallowing with contextual Write-AppLockerLog calls
- [ ] **ERR-02**: All empty catch blocks in GUI/Helpers replace silent swallowing with contextual logging (excluding intentional cleanup catches)
- [x] **ERR-03**: All empty catch blocks in backend Modules replace silent swallowing with contextual logging
- [ ] **ERR-04**: Functions with inconsistent return patterns standardized to `@{ Success; Data; Error }` format
- [ ] **ERR-05**: Operator-facing errors in GUI panels surface via toast notifications instead of silent log-only handling

### Test Coverage

- [ ] **TEST-01**: Credentials module has unit tests covering credential creation, retrieval, and tier-based fallback
- [ ] **TEST-02**: Deployment module has unit tests covering job creation, status tracking, and GPO import paths
- [ ] **TEST-03**: Setup module has unit tests covering environment initialization and WinRM GPO configuration
- [ ] **TEST-04**: Major GUI panels (Scanner, Rules, Policy, Deploy) have behavioral tests for core workflows
- [ ] **TEST-05**: E2E workflow test covers scan-to-rule-to-policy-to-deploy pipeline with mock data

### Performance

- [ ] **PERF-01**: Export-PolicyToXml uses StringBuilder instead of string concatenation for rule XML assembly
- [ ] **PERF-02**: All ConvertTo-Json -Depth 10 calls reduced to -Depth 3 across the codebase
- [ ] **PERF-03**: DragDropHelpers array concatenation patterns replaced with List<T>
- [ ] **PERF-04**: Export-AppLockerHealthReport uses .NET APIs instead of Get-CimInstance and direct .Count instead of Measure-Object

## Future Requirements

Deferred beyond v1.2.90.

### Tech Debt Carryover

- **DEBT-01**: CollectionType field emission from event retrieval backend (functional fallback exists)
- **DEBT-02**: Promote script:-scoped functions called from global: context to proper global: scope
- **DEBT-03**: Remote transport fallback details (WinRM vs event log RPC)
- **DEBT-04**: Event query snapshot retention/pruning policy

## Out of Scope

| Feature | Reason |
|---------|--------|
| New operator workflows or panels | This is a hardening milestone, not a feature release |
| Validation module changes | Known-stable, locked area |
| Rule import core path changes | Known-stable, locked area |
| Full rewrite of GUI panel architecture | Disproportionate risk for hardening milestone |
| External dependency additions | Air-gap constraint; hardening uses existing stack only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ERR-01 | Phase 10 | Pending |
| ERR-02 | Phase 10 | Pending |
| ERR-03 | Phase 10 | Complete |
| ERR-04 | Phase 10 | Pending |
| ERR-05 | Phase 10 | Pending |
| TEST-01 | Phase 12 | Pending |
| TEST-02 | Phase 12 | Pending |
| TEST-03 | Phase 12 | Pending |
| TEST-04 | Phase 13 | Pending |
| TEST-05 | Phase 13 | Pending |
| PERF-01 | Phase 11 | Pending |
| PERF-02 | Phase 11 | Pending |
| PERF-03 | Phase 11 | Pending |
| PERF-04 | Phase 11 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-02-19*
*Last updated: 2026-02-19 after roadmap creation — all 14 requirements mapped*
