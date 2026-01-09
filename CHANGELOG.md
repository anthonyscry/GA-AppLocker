# Changelog

All notable changes to GA-AppLocker are documented in this file.

## [Unreleased]

### Added
- **AD Computer Export**: New `[C] Computers` menu option to export computer names from Active Directory for scanning
  - Filter by computer type: All, Workstations, Servers, or Domain Controllers
  - Exports to `.\ADManagement\AD-computers.txt` by default
- **ADManagement folder**: Centralized location for AD-related files
  - AD exports now default to `.\ADManagement\`
  - AD imports now default to `.\ADManagement\groups.csv`
- **Comparison results folder**: Compare workflow now saves results to `.\SoftwareLists\Comparisons\`
- **Troubleshooting section** in README with common issues and solutions
- **Policy Merge SID Replacement** documentation with examples

### Changed
- Scan workflow now auto-detects `.\ADManagement\AD-computers.txt` if `.\computers.txt` doesn't exist
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
- Default event collection to computers.txt and Events folder

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
