# GA-AppLocker Next Steps

**Last Updated:** 2026-01-17

---

## Immediate Next Steps (Phase 2: Discovery)

### Priority 1: GA-AppLocker.Discovery Module
1. Create module manifest and loader
2. Implement `Get-DomainInfo` - Auto-detect domain
3. Implement `Get-OUTree` - Build OU hierarchy
4. Implement `Get-ComputersByOU` - Discover machines
5. Implement `Test-MachineConnectivity` - Ping/WinRM check

### Priority 2: AD Discovery Panel UI
1. Create OU TreeView with checkboxes
2. Add machine list DataGrid
3. Implement online/offline status indicators
4. Add "Refresh" and "Select All" buttons
5. Wire up panel to Discovery module

### Priority 3: Machine Type Detection
1. Implement OU path analysis for machine type
2. Add icons for Workstation/Server/DC
3. Store machine type with discovered machines

---

## Upcoming Phases

### Phase 3: Credentials
- [ ] Create GA-AppLocker.Credentials module
- [ ] Implement credential profiles (Tier 0/1/2)
- [ ] Add DPAPI encryption for password storage
- [ ] Build credential management UI
- [ ] Add pre-scan validation

### Phase 4: Scanning
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
- [ ] Add traffic light review system
- [ ] Build Rule Generator panel UI
- [ ] Implement bulk operations

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
