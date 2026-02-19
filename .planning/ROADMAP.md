# Roadmap: GA-AppLocker

## Milestones

- ✅ **v1.2.86 Release Automation** — Phases 2-6 (shipped 2026-02-17)
- ✅ **v1.2.88 Event Viewer Rule Workbench** — Phases 7-9 (shipped 2026-02-19)
- 🚧 **v1.2.90 Production Hardening** — Phases 10-13 (in progress)

## Phases

<details>
<summary>v1.2.86 Release Automation (Phases 2-6) — SHIPPED 2026-02-17</summary>

- [x] Phase 2: Data Access Indexing (3/3 plans)
- [x] Phase 3: UX and Workflow Friction (3/3 plans)
- [x] Phase 4: Reliability Diagnostics (1/1 plan)
- [x] Phase 5: Test Infrastructure (1/1 plan)
- [x] Phase 6: Build and Release Automation (4/4 plans)

See `.planning/milestones/v1.2.86-ROADMAP.md` for full details.

</details>

<details>
<summary>v1.2.88 Event Viewer Rule Workbench (Phases 7-9) — SHIPPED 2026-02-19</summary>

- [x] Phase 7: Event Ingestion and Bounded Retrieval (3/3 plans) — completed 2026-02-18
- [x] Phase 8: Event Triage and Inspection Workbench (2/2 plans) — completed 2026-02-18
- [x] Phase 9: Rule Generation from Event Selections (2/2 plans) — completed 2026-02-19

See `.planning/milestones/v1.2.88-ROADMAP.md` for full details.

</details>

### v1.2.90 Production Hardening (In Progress)

**Milestone Goal:** Eliminate silent failures, close test coverage gaps, and fix performance bottlenecks to reach production confidence.

- [x] **Phase 10: Error Handling Hardening** - Replace silent catch blocks and standardize return patterns across the codebase (completed 2026-02-19)
- [x] **Phase 11: Performance Fixes** - Replace O(n²) string patterns, reduce serialization depth, and use .NET APIs for health reporting (completed 2026-02-19)
- [ ] **Phase 12: Module Test Coverage** - Add unit tests for Credentials, Deployment, and Setup modules
- [ ] **Phase 13: GUI and E2E Test Coverage** - Add behavioral tests for major GUI panels and a full scan-to-deploy E2E workflow test

## Phase Details

### Phase 10: Error Handling Hardening
**Goal**: Every failure in the codebase surfaces with context — no silent swallowing
**Depends on**: Phase 9 (previous milestone complete)
**Requirements**: ERR-01, ERR-02, ERR-03, ERR-04, ERR-05
**Success Criteria** (what must be TRUE):
  1. Opening any GUI panel and triggering an error produces a log entry with function name and context — no blank catches remain in GUI/Panels
  2. GUI helper operations (async, drag-drop, search, theme) that fail produce a log entry — no blank catches remain in GUI/Helpers
  3. Backend module functions that catch exceptions log the error context before continuing — no blank catches remain in any module
  4. Functions that return results use the `@{ Success; Data; Error }` shape consistently — callers can check `.Success` without defensive null guards
  5. Operator-visible errors (scan failure, rule save failure, policy export failure) appear as toast notifications in the GUI, not only in the log file
**Plans:** 4/4 plans complete
Plans:
- [x] 10-01-PLAN.md -- Replace 105 empty catch blocks in 10 GUI Panel files with contextual logging (ERR-01)
- [x] 10-02-PLAN.md -- Replace 49 empty catch blocks in GUI Helpers, MainWindow, and Wizard files (ERR-02)
- [x] 10-03-PLAN.md -- Replace 25 empty catch blocks in 9 backend Module files with contextual logging (ERR-03)
- [ ] 10-04-PLAN.md -- Standardize return patterns for 3 key functions and add toast notifications for operator errors (ERR-04, ERR-05)

### Phase 11: Performance Fixes
**Goal**: The codebase eliminates known O(n²) patterns and uses efficient APIs for bulk operations
**Depends on**: Phase 10
**Requirements**: PERF-01, PERF-02, PERF-03, PERF-04
**Success Criteria** (what must be TRUE):
  1. Exporting a policy with 1,000+ rules completes without measurable O(n²) string growth — Export-PolicyToXml uses StringBuilder throughout the rule assembly loop
  2. All ConvertTo-Json calls in the codebase use -Depth 3 or lower — no -Depth 10 calls remain
  3. DragDropHelpers file-drop processing uses List<T> for artifact accumulation — no array += patterns remain in that file
  4. Export-AppLockerHealthReport returns without calling Get-CimInstance or Measure-Object — .NET IPGlobalProperties and direct .Count are used instead
**Plans:** 2/2 plans complete
Plans:
- [ ] 11-01-PLAN.md -- StringBuilder for Export-PolicyToXml + .NET APIs for HealthReport (PERF-01, PERF-04)
- [ ] 11-02-PLAN.md -- ConvertTo-Json depth reduction + DragDropHelpers List<T> (PERF-02, PERF-03)

### Phase 12: Module Test Coverage
**Goal**: Credentials, Deployment, and Setup modules have unit tests verifying their core contracts
**Depends on**: Phase 11
**Requirements**: TEST-01, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. Running `Invoke-Pester Tests\Unit\` includes Credentials tests covering credential creation, retrieval, and tier-based fallback — test file exists and passes
  2. Running `Invoke-Pester Tests\Unit\` includes Deployment tests covering job creation, status tracking, and GPO import paths — test file exists and passes
  3. Running `Invoke-Pester Tests\Unit\` includes Setup tests covering environment initialization and WinRM GPO configuration — test file exists and passes
**Plans:** 1/3 plans executed
Plans:
- [ ] 12-01-PLAN.md -- Credentials module unit tests: creation, retrieval, tier-based fallback, removal (TEST-01)
- [ ] 12-02-PLAN.md -- Deployment module unit tests: job CRUD, status tracking, GPO import paths (TEST-02)
- [ ] 12-03-PLAN.md -- Setup module unit tests: environment initialization, WinRM GPO configuration (TEST-03)

### Phase 13: GUI and E2E Test Coverage
**Goal**: Core GUI panel workflows and the end-to-end scan-to-deploy pipeline have automated test coverage
**Depends on**: Phase 12
**Requirements**: TEST-04, TEST-05
**Success Criteria** (what must be TRUE):
  1. Behavioral tests for Scanner, Rules, Policy, and Deploy panels exist and pass — covering load, filter, and action workflows for each panel
  2. An E2E workflow test executes the full scan-to-rule-to-policy-to-deploy pipeline using mock data without errors
  3. The full test suite passes at 100% after all new tests are added — no regressions introduced by error handling or performance changes
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 2. Data Access Indexing | v1.2.86 | 3/3 | Complete | 2026-02-16 |
| 3. UX and Workflow Friction | v1.2.86 | 3/3 | Complete | 2026-02-16 |
| 4. Reliability Diagnostics | v1.2.86 | 1/1 | Complete | 2026-02-16 |
| 5. Test Infrastructure | v1.2.86 | 1/1 | Complete | 2026-02-16 |
| 6. Build and Release Automation | v1.2.86 | 4/4 | Complete | 2026-02-17 |
| 7. Event Ingestion and Bounded Retrieval | v1.2.88 | 3/3 | Complete | 2026-02-18 |
| 8. Event Triage and Inspection Workbench | v1.2.88 | 2/2 | Complete | 2026-02-18 |
| 9. Rule Generation from Event Selections | v1.2.88 | 2/2 | Complete | 2026-02-19 |
| 10. Error Handling Hardening | 4/4 | Complete    | 2026-02-19 | - |
| 11. Performance Fixes | 2/2 | Complete    | 2026-02-19 | - |
| 12. Module Test Coverage | 1/3 | In Progress|  | - |
| 13. GUI and E2E Test Coverage | v1.2.90 | 0/TBD | Not started | - |

---
*Last updated: 2026-02-18 after Phase 12 planning (3 plans: Credentials, Deployment, Setup tests)*
