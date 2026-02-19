# GA-AppLocker Quick Start Guide

Get AppLocker policies deployed to your enterprise in 7 steps.

**Version:** January 2026 | **Module Commands:** 182

## Phase 13 Release Readiness Notes

- Use `docs/plans/2026-02-18-phase-13-operator-runbook-checks.md` as the operator checklist source of truth.
- For release gate evidence, capture targeted verification results in `docs/plans/2026-02-18-phase-13-verification-evidence.md`.
- If GroupPolicy tooling is unavailable, use XML export/manual import fallback and record outcome in the runbook checks.

---

## Prerequisites

Before you begin, ensure:

- [ ] Windows 10 or Server 2019+ with PowerShell 5.1+
- [ ] Domain-joined machine with RSAT installed
- [ ] Domain Admin or equivalent credentials for GPO management
- [ ] WinRM enabled on target machines (for remote scanning)

---

## Step 1: Launch the Dashboard

Open PowerShell as Administrator and run:

```powershell
cd C:\Path\To\GA-AppLocker2
.\Run-Dashboard.ps1
```

The dark-themed dashboard will appear with 8 navigation panels on the left.

**Keyboard Shortcuts:**
- `Ctrl+1-9`: Navigate to panels
- `F5`: Refresh current panel
- `Ctrl+F`: Focus search box
- `Ctrl+S`: Save current state

---

## Step 2: Configure Credentials (Settings Panel)

1. Click **Settings** in the left navigation
2. Under "Credential Profiles", click **Add Profile**
3. Create tiered credentials:
   - **T0 - Domain Controllers**: Highest privilege (Domain Admin)
   - **T1 - Servers**: Server admin credentials
   - **T2 - Workstations**: Workstation admin credentials
4. Click **Test** to verify each credential works

> **Security Note**: Credentials are stored locally using DPAPI encryption.

---

## Step 3: Discover Network Assets (Discovery Panel)

1. Click **Discovery** in the left navigation
2. Click **Refresh Domain Info** to load your AD forest
3. Expand the OU tree and select target OUs
4. Click **Get Computers** to enumerate machines
5. Click **Test Connectivity** to verify WinRM access

> **Tip**: Green checkmarks indicate successful connectivity.

---

## Step 4: Scan for Artifacts (Scanner Panel)

1. Click **Scanner** in the left navigation
2. Select target machines from the list
3. Configure scan options:
   - **Scan Paths**: e.g., `C:\Program Files`, `C:\Program Files (x86)`
   - **Include DLLs**: Check if you need DLL rules
   - **Recursive**: Scan subdirectories
4. Click **Start Scan**
5. Wait for scan completion (progress bar shows status)

> **Performance**: Scanning 1000 files takes approximately 2-5 minutes per machine.

---

## Step 5: Generate Rules (Rules Panel)

### Option A: Rule Generation Wizard (Recommended - 10x Faster)

1. Click **Rules** in the left navigation (or `Ctrl+4`)
2. Click **Generate Rules from Current Scan** button
3. Follow the 3-step wizard:
   - **Step 1 - Configure**: Set mode (Smart/Publisher/Hash), action, exclusions, deduplication
   - **Step 2 - Preview**: See exactly what rules will be created before committing
   - **Step 3 - Generate**: Execute batch generation with progress bar
4. Click **Generate** to create rules

**Performance:**
- Old method: ~2 rules/second
- Wizard: ~20 rules/second (10x faster)

### Option B: Manual Rule Creation

1. Right-click any artifact in the Scanner panel
2. Select **Create Rule** from context menu
3. Choose rule type: Publisher (recommended), Hash, or Path

### Review Rules

- **Pending**: Needs review
- **Approved**: Ready for policy
- **Rejected**: Excluded from policies

**Bulk Operations:**
- Use the context menu (right-click) to approve/reject rules in bulk
- Dashboard Quick Action: "Approve Trusted Vendors" (Microsoft, Adobe, Oracle, Google, etc.)
- Dashboard Quick Action: "Remove Duplicate Rules"

### Rule History

Every rule change is versioned:
```powershell
# View history
Get-RuleHistory -RuleId $ruleId

# Rollback to previous version
Restore-RuleVersion -RuleId $ruleId -Version 1
```

---

## Step 6: Build Policy (Policy Panel)

1. Click **Policy** in the left navigation
2. Click **New Policy**
3. Configure:
   - **Name**: e.g., "Workstation-Baseline-2026"
   - **Enforcement Mode**: Start with "Audit Only"
   - **Phase**: Select deployment phase (1-5)
4. Click **Add Rules** and select approved rules
5. Click **Export to XML** to generate AppLocker policy

---

## Step 7: Deploy to GPO (Deployment Panel)

1. Click **Deployment** in the left navigation
2. Select policy to deploy
3. Configure target:
   - **GPO Name**: Create new or use existing
   - **Target OU**: Where to link the GPO
4. Click **Deploy**
5. Monitor progress in the deployment log

> **Important**: Always test in "Audit Only" mode first!

---

## Deployment Phases

GA-AppLocker uses a phased approach to minimize disruption:

| Phase | Mode | Description |
|-------|------|-------------|
| 1 | Audit Only | EXE collection only |
| 2 | Audit Only | EXE + Script collections |
| 3 | Audit Only | EXE + Script + MSI collections |
| 4 | Audit Only | Adds APPX collection |
| 5 | Enforce | Full enforcement including DLL |

**Recommendation**: Spend at least 2 weeks in each audit phase before progressing.

---

## Common Workflows

### Adding a New Application

1. Install the application on a test machine
2. Run a local scan: **Scanner** → **Scan Local**
3. Find the new artifacts in the list
4. Right-click → **Create Rule**
5. Approve the rule
6. Add to existing policy
7. Re-deploy policy

### Investigating Blocked Applications

1. Check AppLocker event logs: **Scanner** → **Get Event Logs**
2. Find the blocked file hash or publisher
3. Create an allow rule for legitimate applications
4. Add to policy and redeploy

### Bulk Rule Operations

1. In **Rules** panel, use the filter to find rules
2. Select multiple rules (Ctrl+Click or Shift+Click)
3. Right-click → **Approve Selected** or **Reject Selected**

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+1 | Dashboard |
| Ctrl+2 | Discovery |
| Ctrl+3 | Scanner |
| Ctrl+4 | Rules |
| Ctrl+5 | Policy |
| Ctrl+6 | Deploy |
| Ctrl+7 | Settings |
| Ctrl+8 | Setup |
| Ctrl+9 | About |
| F5 / Ctrl+R | Refresh current panel |
| Ctrl+F | Focus search box |
| Ctrl+S | Save (context-dependent) |
| Ctrl+E | Export (context-dependent) |
| Ctrl+N | New item (context-dependent) |
| Ctrl+A | Select all in data grid |
| Delete | Delete selected items |
| Escape | Cancel/Clear |
| F1 | Help/About |

## Drag-and-Drop

- **Scanner Panel**: Drop executable files to scan them
- **Rules Panel**: Drop files to create rules, drop XML to import rules
- **Policy Panel**: Drop AppLocker XML files to import policies

---

## Troubleshooting

### "WinRM connection failed"
- Ensure WinRM is enabled: `winrm quickconfig`
- Check firewall rules (TCP 5985/5986)
- Verify credentials have remote admin rights

### "GPO not found"
- Ensure RSAT is installed
- Verify account has GPO management permissions
- Check domain connectivity

### "Rule generation slow"
- Use the Rule Generation Wizard for batch processing
- The old method processes ~2 rules/second
- The wizard processes 10-20 rules/second

### "Rules not updating in index"
- All rule operations (create, update, delete) now auto-sync to index
- If index seems stale, manually rebuild: `Invoke-RuleIndexRebuild`
- Check logs for sync errors

### "Duplicate rules detected"
- Use Dashboard Quick Action: "Remove Duplicate Rules"
- Or run: `Remove-DuplicateRules -RuleType All -Strategy KeepOldest`

### Application Data Location

All data is stored in:
```
%LOCALAPPDATA%\GA-AppLocker\
├── config.json         # Application settings
├── session.json        # UI state (auto-saved)
├── rules-index.json    # Fast rule index (O(1) lookups)
├── Credentials\        # Encrypted credentials
├── Scans\             # Scan results
├── Rules\             # Generated rules (JSON files)
├── RuleHistory\       # Rule version history
├── Policies\          # Built policies
├── PolicySnapshots\   # Policy version backups
├── Deployments\       # Deployment job history
└── Logs\              # Application logs
```

---

## Getting Help

- **Logs**: Check `%LOCALAPPDATA%\GA-AppLocker\Logs\` for detailed logs
- **Developer Guide**: See `CLAUDE.md` in the project root
- **Full Spec**: See `docs\GA-AppLocker-Full-Specification.md`

---

## Next Steps

After completing this quick start:

1. Review the full specification for advanced features
2. Set up scheduled scans for automated artifact collection
3. Create baseline policies for different machine types (T0/T1/T2)
4. Document your organization's AppLocker rule approval process
5. Enable policy snapshots for rollback capability
6. Configure theme preference (dark/light) in Settings
7. Learn keyboard shortcuts for faster navigation

## PowerShell Commands Reference

```powershell
# Quick module import
Import-Module .\GA-AppLocker\GA-AppLocker.psd1

# Check rule counts
Get-RuleCounts

# Bulk approve trusted vendors
Set-BulkRuleStatus -PublisherPattern '*MICROSOFT*' -Status Approved

# Find duplicates (preview only)
Find-DuplicateRules -RuleType Hash

# Remove duplicates
Remove-DuplicateRules -RuleType All -Strategy KeepOldest

# Create policy snapshot before changes
New-PolicySnapshot -PolicyId $id -Description 'Before Chrome update'

# Compare two policies
Compare-Policies -SourcePolicyId $id1 -TargetPolicyId $id2

# Export policy comparison report
Get-PolicyDiffReport -SourcePolicyId $id1 -TargetPolicyId $id2 -Format Markdown
```
