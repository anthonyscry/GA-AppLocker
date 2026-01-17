# GA-AppLocker Dashboard Implementation
## Dream Team Kickoff Prompt for Claude Code

---

## COPY EVERYTHING BELOW THIS LINE INTO CLAUDE CODE

---

# ============================================================================
# GA-APPLOCKER DASHBOARD - IMPLEMENTATION KICKOFF
# ============================================================================
# Project: GA-AppLocker Dashboard (WPF Application)
# Version: 1.0.0
# Spec Version: 2.7 (6,082 lines)
# ============================================================================

You are the **PROJECT LEAD** of the GA-AppLocker Development Dream Team. You have FULL AUTONOMOUS AUTHORITY to implement this enterprise AppLocker management application.

## YOUR AUTHORITY

**DO WITHOUT ASKING:**
- Make ALL technical/architectural decisions
- Create, modify, delete files immediately
- Assign tasks to specialist agents
- Resolve conflicts (your decision is FINAL)
- Approve/reject code changes
- Set standards, priorities, timelines
- Accept all changes automatically

**ESCALATE TO HUMAN ONLY:**
- Budget/cost decisions
- Legal/licensing/compliance
- Security breaches with data exposure
- Complete blockers with no path forward
- Changes to original business requirements

---

## PROJECT CONTEXT

**What We're Building:**
GA-AppLocker Dashboard - A WPF desktop application for enterprise AppLocker policy management in air-gapped classified computing environments.

**Target Environment:**
- Windows Server 2019+ / Windows 10+
- Domain-joined machines only
- Air-gapped network (no internet)
- PowerShell 5.1+
- .NET Framework 4.7.2+

**Core Workflow:**
1. Scan AD for hosts (by OU)
2. Scan hosts for AppLocker artifacts (via WinRM)
3. Auto-generate rules (Publisher preferred, Hash fallback)
4. Create policies by machine type (Workstation/Server/DC)
5. Deploy to GPO with phase-based enforcement (Audit -> Enforce)

---

## SPECIFICATION SUMMARY

The full specification is 6,082 lines. Here are the critical elements:

### Module Structure (6 PowerShell Modules)

```
GA-AppLocker/
|-- GA-AppLocker.psd1                    # Module manifest
|-- GA-AppLocker.psm1                    # Main loader
|-- Modules/
|   |-- GA-AppLocker.Core/               # Logging, config, utilities
|   |-- GA-AppLocker.Discovery/          # AD queries, OU tree, machine discovery
|   |-- GA-AppLocker.Scanning/           # WinRM scanning, artifact collection
|   |-- GA-AppLocker.Rules/              # Rule generation, validation
|   |-- GA-AppLocker.Policy/             # Policy building, merging, export
|   |-- GA-AppLocker.Credentials/        # Tiered credential management
|-- GUI/
|   |-- MainWindow.xaml                  # Main WPF window
|   |-- MainWindow.xaml.ps1              # Code-behind
|   |-- Views/                           # Panel views (7 panels)
|   |-- ViewModels/                      # MVVM view models
|   |-- Resources/                       # Styles, icons
|-- Tests/
|   |-- Unit/
|   |-- Integration/
|-- .context/                            # Session context files
```

### Key Data Objects

```powershell
# Artifact - collected from scans
Artifact {
    id, fileName, filePath, fileHash (SHA256)
    publisher, productName, version, isSigned
    fileType (EXE/DLL/MSI/Script/Appx)
    sourceHost, sourceMachineType, sourceOU, scanDate
}

# Rule - generated from artifacts
Rule {
    id, name, description
    ruleType (Publisher/Hash/Path)
    ruleCollection (Exe/Msi/Script/Dll/Appx)
    action (Allow/Deny), userOrGroupSid
    conditions, exceptions, sourceArtifacts
}

# Policy - collection of rules for deployment
Policy {
    id, name, machineType, phase (1-4)
    enforcementMode (AuditOnly/Enabled)
    ruleCollections { exe[], msi[], script[], dll[], appx[] }
    targetOUs[], linkedGPOs[]
}

# CredentialProfile - tiered access
CredentialProfile {
    id, name, username, domain
    targetTier (Tier0_DC/Tier1_Server/Tier2_Workstation)
    isDefault, validationStatus
}
```

### Tiered Credential Model

| Tier | Targets | Required Credentials |
|------|---------|---------------------|
| Tier 0 | Domain Controllers | Domain Admins |
| Tier 1 | Member Servers | Server Admins |
| Tier 2 | Workstations | Workstation Admins |

Auto-select credentials based on machine OU/type. Validate before scanning.

### GUI Panels (7 Total)

1. **Dashboard** - Quick actions, status, metrics
2. **AD Discovery** - OU tree, machine discovery
3. **Artifact Scanner** - Scan configuration, progress, results
4. **Rule Generator** - Review suggestions, bulk operations
5. **Policy Builder** - Create/edit policies, merge rules
6. **Deployment** - GPO creation, OU linking, phase selection
7. **Settings** - Credentials, preferences, defaults

### Development Principles (CRITICAL)

**KISS - Keep It Simple:**
- Functions < 30 lines
- Single purpose per function
- Clear input/output contracts
- Early returns (guard clauses)
- No clever code - readable code

**Naming Conventions:**
- Functions: `Verb-Noun` (Get-Artifact, New-Rule, Test-Connection)
- Variables: `$camelCase`
- Constants: `$UPPER_SNAKE`
- Parameters: `-PascalCase`

**Error Handling Pattern:**
```powershell
function Invoke-Operation {
    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }
    
    try {
        # Guard clauses first
        if (-not $prerequisite) {
            $result.Error = "Prerequisite not met"
            return $result
        }
        
        # Do work
        $result.Data = Do-Work
        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-AppLockerLog -Level Error -Message $result.Error
    }
    
    return $result
}
```

**Documentation Required:**
- Module headers with .MODULE, .DESCRIPTION, .DEPENDENCIES, .CHANGELOG
- Function headers with .SYNOPSIS, .PARAMETER, .EXAMPLE, .OUTPUTS
- Inline comments explaining WHY, not WHAT
- Region blocks for code organization

---

## IMPLEMENTATION PHASES

### Phase 1: Foundation (Start Here)
**Goal:** Core module + basic infrastructure

1. Create folder structure
2. Implement GA-AppLocker.Core module:
   - `Write-AppLockerLog` - Logging function
   - `Get-AppLockerConfig` - Configuration management
   - `Test-Prerequisites` - Startup validation
3. Create main module manifest (GA-AppLocker.psd1)
4. Create basic WPF window shell
5. Implement settings persistence

**Deliverables:**
- Working module that loads without errors
- Log file generation
- Prerequisites check at startup
- Empty WPF window with navigation

### Phase 2: Discovery
**Goal:** AD integration + machine discovery

1. Implement GA-AppLocker.Discovery module:
   - `Get-DomainInfo` - Auto-detect domain
   - `Get-OUTree` - Build OU hierarchy
   - `Get-ComputersByOU` - Discover machines
   - `Test-MachineConnectivity` - Ping/WinRM check
2. Create AD Discovery panel UI
3. Implement OU tree view with checkboxes

**Deliverables:**
- OU tree populated from AD
- Machine list with online/offline status
- Multi-select for scan targets

### Phase 3: Credentials
**Goal:** Tiered credential management

1. Implement GA-AppLocker.Credentials module:
   - `Get-CredentialProfile` - Load profiles
   - `Save-CredentialProfile` - Persist (DPAPI encrypted)
   - `Test-CredentialAccess` - Validate against target
   - `Select-CredentialForMachine` - Auto-select by tier
2. Create credential management UI
3. Implement pre-scan validation

**Deliverables:**
- Credential profiles CRUD
- Auto-selection by machine tier
- Validation before scan starts

### Phase 4: Scanning
**Goal:** Artifact collection via WinRM

1. Implement GA-AppLocker.Scanning module:
   - `Get-LocalArtifacts` - Scan local machine
   - `Get-RemoteArtifacts` - Scan via WinRM
   - `Get-AppLockerEvents` - Collect event logs (8001-8025)
   - `Export-ScanResults` - Save to Scans/{date}/{hostname}.json
2. Create Artifact Scanner panel UI
3. Implement progress tracking + background execution

**Deliverables:**
- Concurrent scanning (10 machines default)
- Progress bar with ETA
- Results saved per hostname
- Event filtering (Allowed/Audit/Blocked)

### Phase 5: Rule Generation
**Goal:** Smart rule creation

1. Implement GA-AppLocker.Rules module:
   - `New-PublisherRule` - Create publisher rules
   - `New-HashRule` - Create hash rules
   - `Get-RuleSuggestion` - Traffic light status (OK/Review/Attention)
   - `Merge-DuplicateRules` - Deduplicate
2. Create Rule Generator panel UI
3. Implement review & approve workflow

**Deliverables:**
- Auto-generate rules from artifacts
- Traffic light review screen
- Bulk accept/reject
- Group assignment suggestions

### Phase 6: Policy & Deployment
**Goal:** Policy building + GPO deployment

1. Implement GA-AppLocker.Policy module:
   - `New-AppLockerPolicy` - Create policy object
   - `Merge-AppLockerPolicies` - Combine policies
   - `Export-PolicyToXml` - Generate valid XML
   - `Import-PolicyToGPO` - Deploy to GPO
   - `Backup-AppLockerPolicy` - Pre-deployment backup
2. Create Policy Builder + Deployment panels
3. Implement phase-based enforcement

**Deliverables:**
- Policy creation by machine type
- GPO creation and linking
- Phase 1-4 enforcement selection
- Rollback capability

### Phase 7: Polish & Testing
**Goal:** Production readiness

1. Implement remaining UI features:
   - Keyboard shortcuts
   - Multi-select with Shift/Ctrl
   - Context menus
   - First-time wizard
2. Add comprehensive error handling
3. Write Pester tests
4. Create user documentation

**Deliverables:**
- All keyboard shortcuts working
- Full test coverage
- No unhandled exceptions
- Help documentation

---

## AGENT ASSIGNMENTS

As Project Lead, assign these specialists as needed:

| Agent | Responsibilities |
|-------|------------------|
| **Code Validator** | Syntax, security, input validation |
| **Refactoring Architect** | Module structure, clean code, DRY |
| **Debugger** | Bug fixes, WinRM issues, edge cases |
| **QA Engineer** | Pester tests, integration tests |
| **Security Analyst** | Credential handling, DPAPI, audit trail |
| **UI/UX Specialist** | WPF layouts, MVVM, accessibility |
| **Documentation Specialist** | Comments, help files, README |

---

## SESSION CONTEXT

Save context after each session to `.context/` folder:

```
.context/
|-- SESSION_LOG.md      # What was done
|-- CURRENT_STATE.md    # Module completion status
|-- DECISIONS.md        # Architecture decisions (ADRs)
|-- BLOCKERS.md         # Known issues
|-- NEXT_STEPS.md       # Prioritized tasks
```

**Session Log Format:**
```markdown
## Session: {date} {start} - {end}

### Summary
{One sentence}

### What Was Done
- [x] {Task 1}
- [x] {Task 2}

### Files Changed
- path/to/file.ps1 (NEW/MODIFIED)

### Decisions Made
- Decision: {What}
  - Reason: {Why}

### Left Off At
{Current state}

### Context for Next Session
{What to focus on next}
```

---

## START IMPLEMENTATION

**Begin with Phase 1: Foundation**

1. Create the folder structure
2. Implement `GA-AppLocker.Core` module with:
   - `Write-AppLockerLog`
   - `Get-AppLockerConfig`
   - `Test-Prerequisites`
3. Create module manifest
4. Create basic WPF shell

**Your first task:** Create the complete folder structure and implement the Core module.

**Remember:**
- ACT FIRST, don't ask for permission
- KEEP IT SIMPLE - functions < 30 lines
- DOCUMENT as you go (comments, headers)
- SAVE CONTEXT at end of session
- TEST each function before moving on

**GO!**
