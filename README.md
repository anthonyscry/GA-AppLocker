# GA-AppLocker v1.2.43

Enterprise AppLocker policy management for air-gapped, classified, and highly secure Windows environments. Complete workflow from AD discovery through GPO deployment — no internet required.

## Quick Start

```powershell
.\Run-Dashboard.ps1
```

Or import manually:

```powershell
Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force
Start-AppLockerDashboard
```

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Windows 10 / Server 2019+ |
| PowerShell | 5.1+ |
| .NET Framework | 4.7.2+ |
| RSAT | Required for AD features (graceful fallback via LDAP if missing) |
| GroupPolicy module | Required for GPO deployment (exports XML for manual import if missing) |

## Workflow

```
AD Discovery ──► Artifact Scanning ──► Rule Generation ──► Policy Building ──► GPO Deployment
```

1. **Discover** — Enumerate domain OUs and computers via AD module or LDAP fallback
2. **Scan** — Collect executables (EXE, DLL, MSI, scripts) from local and remote machines via WinRM
3. **Generate** — Create Publisher, Hash, or Path rules with the 3-step wizard or batch operations
4. **Build** — Combine approved rules into policies with phased enforcement (Audit → Enforce)
5. **Deploy** — Push policies to GPOs and link to target OUs
6. **Validate** — 5-stage XML validation pipeline ensures STIG-compliant policy output

## Features

### Core Workflow
- **AD Discovery** with LDAP fallback for environments without RSAT
- **Local & remote artifact scanning** (14 file types) with parallel WinRM collection
- **Three rule types**: Publisher (digital signature), Hash (SHA256), Path (filesystem)
- **3-step Rule Generation Wizard**: Configure → Preview → Generate (10x faster batch processing)
- **Phased policy enforcement**: Phase 1 (EXE only) → Phase 4 (full enforcement)
- **5-stage policy validation**: Schema, GUIDs, SIDs, conditions, live import test
- **Async GPO deployment** with fallback to XML export for manual import

### Management & Operations
- **Rule history & versioning** with rollback capability
- **Bulk operations**: Admin Allow (4 rules), Deny Browsers (8 rules), Deny Paths (21 rules), batch status/group/action changes
- **Policy comparison & snapshots** with restore
- **Deploy panel editing** — Edit policy name, description, and target GPO inline; backup/export/import policies
- **Tiered credentials** (T0/T1/T2) with DPAPI encryption
- **Scheduled scans** with configurable targets
- **Software inventory** — Scan local/remote installed software, CSV export/import, cross-system comparison

### User Interface
- **Dark theme** with native dark title bar (DwmSetWindowAttribute)
- **9 dedicated panels**: Dashboard, AD Discovery, Credentials, Scanner, Rules, Policy, Deploy, Software Inventory, Setup
- **Keyboard shortcuts**: Ctrl+1-9 navigation, F5 refresh, Ctrl+F search, Ctrl+S save
- **Drag-and-drop**: Drop files to scan or import rules/policies
- **Context menus**: Right-click rules for approve/reject/delete/copy
- **Toast notifications** and loading overlays for async operations
- **Session persistence** across restarts (7-day expiry)
- **Global search** across rules, policies, and artifacts
- **Workflow breadcrumb** showing progress through stages

## Architecture

```
GA-AppLocker/
├── GA-AppLocker.psd1              # Module manifest
├── GA-AppLocker.psm1              # Module loader
├── GUI/
│   ├── MainWindow.xaml            # WPF UI (dark theme, 9 panels)
│   ├── MainWindow.xaml.ps1        # Core UI logic
│   ├── ToastHelpers.ps1           # Notifications
│   ├── Helpers/                   # Async, search, theme, keyboard, drag-drop
│   ├── Wizards/                   # Rule generation wizard, setup wizard
│   ├── Dialogs/                   # Rules and scanner dialogs
│   └── Panels/                    # Per-panel event handlers (9 files)
└── Modules/
    ├── GA-AppLocker.Core/         # Logging, config, cache, events, validation helpers
    ├── GA-AppLocker.Discovery/    # AD/LDAP discovery, parallel connectivity testing
    ├── GA-AppLocker.Credentials/  # DPAPI credential storage, tiered access
    ├── GA-AppLocker.Scanning/     # Local/remote artifact collection, scheduled scans
    ├── GA-AppLocker.Rules/        # Rule generation, history, bulk ops, templates
    ├── GA-AppLocker.Policy/       # Policy builder, comparison, snapshots, XML export
    ├── GA-AppLocker.Deployment/   # GPO deployment with fallback
    ├── GA-AppLocker.Setup/        # Environment initialization
    ├── GA-AppLocker.Storage/      # JSON index with O(1) lookups (35k+ rules)
    └── GA-AppLocker.Validation/   # 5-stage policy XML validation pipeline
```

**10 sub-modules**, ~192 exported functions. All functions return standardized result objects:

```powershell
@{ Success = $true; Data = <result>; Error = $null }
```

## Performance

Optimized for large enterprise environments:

| Operation | Performance |
|-----------|-------------|
| Rule loading (35k+) | ~100ms (indexed) |
| Hash / Publisher lookup | O(1) hashtable |
| Batch rule generation (1k artifacts) | ~30 seconds |
| Connectivity test (100 machines) | Parallel via WMI jobs |
| UI during long operations | Non-blocking (background runspaces) |

## Data Storage

All data stored locally in `%LOCALAPPDATA%\GA-AppLocker\`:

| Path | Purpose |
|------|---------|
| `config.json` | Application settings |
| `session.json` | UI state (7-day expiry) |
| `Credentials\` | DPAPI-encrypted credential profiles |
| `Scans\` | Scan results |
| `Rules\` | Generated rules + JSON index |
| `Policies\` | Policy definitions + snapshots |
| `Deployments\` | Deployment job history |
| `Logs\` | Daily log files |

## Testing

```powershell
# Pester unit tests (1545/1545 passing — 100%)
Invoke-Pester -Path Tests\Unit\ -Output Detailed

# UI automation (requires interactive PowerShell session)
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Standard

# Full automated suite with mock data
.\Tests\Automation\Run-AutomatedTests.ps1 -All -UseMockData
```

## Standard Operating Procedure

Step-by-step. Do them in order. Don't skip steps.

### PHASE 0: Install the Tool

1. Copy the `GA-AppLocker\` folder and `Run-Dashboard.ps1` to your admin workstation
2. Open PowerShell **as Administrator**
3. Run `.\Run-Dashboard.ps1` -- the dashboard opens
4. If this is the first time, go to the **Setup** panel (Ctrl+9) and click **Initialize Environment**

### PHASE 1: Set Up WinRM on Target Machines

Machines need WinRM enabled so you can scan them remotely. Pick ONE method:

**Method A -- GPO (recommended, does all machines at once):**
1. Go to the **Setup** panel (Ctrl+9)
2. Click **Create WinRM GPO** -- this creates an enforced GPO at domain root
3. Wait for Group Policy to propagate (up to 90 minutes), or run `Troubleshooting\Force-GPOSync.ps1` on the DC

**Method B -- Manual (one machine at a time):**
1. Copy `Troubleshooting\Enable-WinRM.ps1` to each target machine
2. Run it as Administrator on each machine
3. To undo later: run `Troubleshooting\Disable-WinRM.ps1`

### PHASE 2: Store Credentials

1. Go to **Credentials** panel (Ctrl+3)
2. Click **New Profile**
3. Enter a name (e.g., "Domain Admin"), username, and password
4. Set the tier: **T0** = Domain Controllers, **T1** = Servers, **T2** = Workstations
5. Repeat for each tier you need to scan

### PHASE 3: Discover Machines

1. Go to **AD Discovery** panel (Ctrl+2)
2. Domain info loads automatically -- wait for the OU tree to populate
3. Click an OU in the tree to filter machines
4. Select machines you want to scan (click rows, Shift+Click for range, Ctrl+Click for multi)
5. Click **Test Connectivity** to verify WinRM is working (green = good)
6. Click **Add to Scanner** to send selected machines to the Scanner

### PHASE 4: Scan for Software Artifacts

1. Go to **Scanner** panel (Ctrl+4)
2. Verify your machines are listed in the Machines tab
3. Go to the **Config** tab:
   - Check scan paths (default: Program Files, System32)
   - Check file types (EXE, DLL, MSI, scripts)
   - Set target group (default: AppLocker-Users)
4. Click **Start Local Scan** (scans your own machine) and/or **Start Remote Scan** (scans the added machines)
5. Wait for the progress bar to finish -- artifacts appear in the Results tab

### PHASE 5: Generate Rules

**Quick method (bulk buttons):**
1. Go to **Rules** panel (Ctrl+5)
2. Click **+ Admin Allow** -- creates 4 allow-all rules for AppLocker-Admins (so admins aren't locked out)
3. Click **+ Deny Paths** -- creates 21 deny rules blocking user-writable directories
4. Click **+ Deny Browsers** -- creates 8 deny rules blocking browsers for admins (optional)
5. Click **Generate Rules** -- opens the 3-step wizard for your scanned artifacts:
   - Step 1: Pick rule type (Publisher preferred, Hash as fallback)
   - Step 2: Preview the rules
   - Step 3: Generate

**Review rules:**
1. Use filter buttons (All / Pending / Approved / Rejected) to sort
2. Select rules and use **Approve** / **Reject** buttons, or right-click for more options
3. Use **Group** and **Action** buttons to bulk-change target group or Allow/Deny

### PHASE 6: Build a Policy

1. Go to **Policy** panel (Ctrl+6)
2. Click **New Policy** -- give it a name and pick a phase:
   - **Phase 1**: EXE rules only (start here)
   - **Phase 2**: EXE + Scripts
   - **Phase 3**: EXE + Scripts + MSI
   - **Phase 4**: Full enforcement (all types)
3. Click **Add Rules** -- select your approved rules
4. Policy starts in **Audit mode** (logs violations but doesn't block anything)

### PHASE 7: Deploy to GPO

1. Go to **Deploy** panel (Ctrl+7)
2. Select your policy from the dropdown
3. Go to the **Edit** tab -- set the Target GPO (AppLocker-DC, AppLocker-Servers, or AppLocker-Workstations)
4. Click **Save Changes**
5. Go to the **Actions** tab -- click **Create Job**, then **Deploy**
6. The policy is pushed to the GPO. Run `gpupdate /force` on target machines or wait for propagation.

### PHASE 8: Monitor and Enforce

1. Check Event Viewer on target machines: `Applications and Services Logs > Microsoft > Windows > AppLocker`
2. **8003** = file would have been blocked (Audit mode) -- review these
3. **8004** = file was blocked (Enforce mode)
4. If Audit mode looks clean (no legitimate apps blocked), go back to the Policy panel and change enforcement from Audit to Enforce
5. Redeploy

### If Something Goes Wrong

| Problem | Fix |
|---------|-----|
| Can't scan remote machines | Run `Troubleshooting\Enable-WinRM.ps1` on them, or check the WinRM GPO |
| "Access Denied" on remote scan | Check credentials in Credentials panel. Make sure the right tier is set |
| GPO not applying | Run `Troubleshooting\Force-GPOSync.ps1` on the DC |
| App hangs on startup | Close and reopen. Check `%LOCALAPPDATA%\GA-AppLocker\Logs\` |
| Legitimate app getting blocked | Create a Publisher or Hash allow rule for it, add to policy, redeploy |
| Need to undo WinRM on a machine | Run `Troubleshooting\Disable-WinRM.ps1` on it |
| Need to remove WinRM GPO entirely | Setup panel > Remove GPO button |

## Air-Gap Deployment

GA-AppLocker is designed for networks with no internet access:

1. Copy the `GA-AppLocker\` folder and `Run-Dashboard.ps1` to the target machine
2. Run `.\Run-Dashboard.ps1` from PowerShell
3. No external package managers, no NuGet, no internet calls at runtime

## License

Proprietary -- internal enterprise use only.
