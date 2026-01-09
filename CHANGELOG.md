# Changelog

All notable changes to GA-AppLocker are documented in this file.

## [Unreleased]

### Added
- **AD Computer Export**: New `[C] Computers` menu option to export computer names from Active Directory for scanning
  - Filter by computer type: All, Workstations, Servers, or Domain Controllers
  - Exports to `.\ADManagement\computers.csv` by default with ComputerName, OperatingSystem, Enabled, LastLogonDate columns
- **CSV Computer List Support**: All scripts now support CSV format with `ComputerName` column header
  - TXT format still supported for backwards compatibility (one computer per line, # for comments)
  - `Get-ComputerList` helper function in Common.psm1 for consistent parsing
- **ADManagement folder**: Centralized location for AD-related files
  - Computer lists: `.\ADManagement\computers.csv`
  - User exports: `.\ADManagement\ADUserGroups-Export.csv`
  - Group imports: `.\ADManagement\groups.csv`
  - User list: `.\ADManagement\users.csv`
- **Comparison results folder**: Compare workflow now saves results to `.\SoftwareLists\Comparisons\`
- **Troubleshooting section** in README with common issues and solutions
- **Policy Merge SID Replacement** documentation with examples

### Changed
- **BREAKING**: Default computer list path changed from `.\computers.txt` to `.\ADManagement\computers.csv`
- All scan/event workflows now default to `.\ADManagement\computers.csv`
- Improved default paths throughout the menu to reduce manual typing

## [2025-01-09]

### Added
- `RemoveDefaultRules` switch to filter out default AppLocker rules during merge
- `ReplaceMode` parameter for flexible SID replacement modes
- `TargetGroup` parameter to replace Everyone SID in merged policies
- `users.csv` export with semicolon-separated usernames per group
- Simple two-column CSV format for user imports (Group, Users)
- New trusted publishers: WinZip, MATLAB, Splunk, Trellix, Cisco, Forescout

### Changed
- Improved user import workflow with better log file handling
- Changed simple import format to group-centric (Group, Users columns)
- Default event collection to ADManagement\computers.csv and Events folder

## [2025-01-08]

### Added
- Remote AppLocker event collection feature (`[E] Events` menu)
- Event collection parameters: `-DaysBack`, `-BlockedOnly`, `-IncludeAllowedEvents`
- `UniqueBlockedApps.csv` output with occurrence counts and affected computers

## [Earlier Releases]

### Core Features
- Remote scanning via WinRM with parallel job execution
- Build Guide policy generation with phased deployment
- Simplified policy generation for quick deployments
- Policy merging with deduplication
- Software list management with trusted publishers
- AD OU and security group creation
- Software inventory comparison
- Diagnostic tools for troubleshooting
- WinRM GPO deployment/removal

---

For full documentation, see [README.md](README.md).
