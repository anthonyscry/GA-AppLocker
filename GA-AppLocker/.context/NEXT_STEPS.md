# GA-AppLocker Next Steps

**Last Updated:** 2026-01-17

---

## Immediate Next Steps (Phase 4: Scanning)

### Priority 1: GA-AppLocker.Scanning Module
1. Create module manifest and loader
2. Implement `Get-LocalArtifacts` - Collect from local machine
3. Implement `Get-RemoteArtifacts` - Collect via WinRM
4. Implement `Get-AppLockerEventLogs` - Collect 8001-8025 events
5. Implement `Start-ArtifactScan` - Orchestrate multi-machine scanning

### Priority 2: Artifact Scanner Panel UI
1. Build scan configuration UI (machine selection, artifact types)
2. Add progress bar and status indicators
3. Create artifact results DataGrid
4. Implement artifact detail view
5. Add export functionality (CSV/JSON)

### Priority 3: Artifact Data Model
1. Define artifact object structure (path, hash, publisher, etc.)
2. Implement artifact storage (JSON files per scan)
3. Add artifact deduplication logic
4. Create artifact summary statistics

---

## Completed Phases

### Phase 1: Foundation - COMPLETE
- [x] Core module with logging, config, prerequisites
- [x] WPF shell with navigation

### Phase 2: Discovery - COMPLETE
- [x] Domain info retrieval
- [x] OU tree discovery
- [x] Machine enumeration
- [x] Connectivity testing

### Phase 3: Credentials - COMPLETE
- [x] Tiered credential model (T0/T1/T2)
- [x] DPAPI-encrypted storage
- [x] Credential testing
- [x] Settings panel UI

---

## Upcoming Phases

### Phase 5: Rules
- [ ] Create GA-AppLocker.Scanning module
- [ ] Implement local artifact collection
- [ ] Implement remote WinRM scanning
- [ ] Add event log collection (8001-8025)
- [ ] Build Artifact Scanner panel UI
- [ ] Add progress tracking

### Phase 5: Rules
- [ ] Create GA-AppLocker.Rules module
- [ ] Implement publisher rule generation
- [ ] Implement hash rule generation
- [ ] Implement path rule generation
- [ ] Add traffic light review system (Green/Yellow/Red)
- [ ] Build Rule Generator panel UI
- [ ] Implement bulk approve/reject operations

### Phase 6: Policy & Deployment
- [ ] Create GA-AppLocker.Policy module
- [ ] Implement policy creation by machine type
- [ ] Add policy merging
- [ ] Implement GPO deployment
- [ ] Build Policy Builder panel UI
- [ ] Build Deployment panel UI
- [ ] Add phase-based enforcement

### Phase 7: Polish & Testing
- [ ] Add keyboard shortcuts
- [ ] Implement context menus
- [ ] Add first-time setup wizard
- [ ] Write Pester unit tests
- [ ] Write integration tests
- [ ] Create user documentation
- [ ] Performance optimization

---

## Technical Debt

*None accumulated yet.*

---

## Ideas for Later

- Export/import of scan groups
- Scheduled scan support
- Email notifications
- PowerBI integration for reporting
- Custom rule templates library
