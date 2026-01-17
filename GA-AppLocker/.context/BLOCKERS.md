# GA-AppLocker Known Blockers

---

## Active Blockers

*No active blockers at this time.*

---

## Resolved Blockers

### B-RESOLVED-001: App Crash on Startup
**Date Resolved:** 2026-01-17
**Severity:** Critical

**Description:**
The WPF app was crashing on startup. Multiple debugging commits were made to isolate the issue by progressively disabling event handlers.

**Root Cause:**
Unknown - the handlers were disabled in debugging commit `ddf093c` but after re-enabling them with proper try/catch blocks, the app works correctly. May have been a transient issue or race condition that was resolved by the defensive coding approach.

**Resolution:**
- Re-enabled all navigation, discovery, and credentials panel handlers
- Added try/catch wrappers around each initialization block
- Replaced debug Write-Host statements with proper logging

---

## Potential Future Blockers

### B-001: RSAT Modules Not Installed
**Severity:** High
**Phase Affected:** Phase 2 (Discovery)

**Description:**
ActiveDirectory and GroupPolicy modules require RSAT to be installed.

**Mitigation:**
- Test-Prerequisites checks for these modules at startup
- Clear error message with installation command provided
- Application can still run but AD features will be disabled

### B-002: WinRM Not Enabled on Target Machines
**Severity:** High
**Phase Affected:** Phase 4 (Scanning)

**Description:**
Remote artifact scanning requires WinRM to be enabled on target machines.

**Mitigation:**
- Pre-scan connectivity test
- GPO template to enable WinRM
- Clear error messages identifying which machines failed

### B-003: Credential Access Denied
**Severity:** Medium
**Phase Affected:** Phase 3 (Credentials), Phase 4 (Scanning)

**Description:**
Tiered admin model may prevent credentials from accessing certain machine types.

**Mitigation:**
- Credential validation before scan
- Tiered credential profiles
- Clear guidance on which credentials work for which tier

### B-004: Air-Gapped Environment
**Severity:** Low
**Phase Affected:** All

**Description:**
No internet access means no external dependencies or updates.

**Mitigation:**
- All code is self-contained
- No external API calls
- No telemetry or update checks
- All documentation included locally
