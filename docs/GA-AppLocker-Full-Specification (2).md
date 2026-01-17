# GA-AppLocker Dashboard
## Vision & Functional Requirements Specification

**Version:** 2.7  
**Last Updated:** 2026-01-16  
**Status:** Planning / Pre-Implementation  
**Classification:** Internal Use Only

---

## [TOC] Table of Contents

1. [Core Vision](#-core-vision)
2. [Functional Requirements](#-functional-requirements)
3. [Key Features Summary](#-key-features-summary)
4. [Tiered Credential Access Model](#-tiered-credential-access-model)
5. [Multi-Administrator Handling](#-multi-administrator-handling)
6. [Documented Assumptions](#-documented-assumptions)
7. [UX Design Principles & Friction Reduction](#-ux-design-principles--friction-reduction)
8. [Development Principles](#-development-principles)
9. [End-to-End Workflow](#-end-to-end-workflow)
10. [Data Models & Schemas](#-data-models--schemas)
11. [Data Interoperability & Field Mapping](#-data-interoperability--field-mapping)
12. [UI/UX Specifications](#-uiux-specifications)
13. [Error Handling & Edge Cases](#-error-handling--edge-cases)
14. [Security Requirements](#-security-requirements)
15. [Performance Requirements](#-performance-requirements)
16. [Configuration & Settings](#-configuration--settings)
17. [Logging & Auditing](#-logging--auditing)
18. [Testing Requirements](#-testing-requirements)
19. [Deployment & Environment](#-deployment--environment)
20. [Module Summary](#-module-summary)
21. [Glossary](#-glossary)
22. [User Stories & Acceptance Criteria](#-user-stories--acceptance-criteria)
23. [API & Function Specifications](#-api--function-specifications)
24. [State Management](#-state-management)
25. [Rollback & Recovery](#-rollback--recovery)
26. [Known Enterprise Vendors List](#-known-enterprise-vendors-list)
27. [Default Deny Rules](#-default-deny-rules)
28. [STIG & Compliance Mapping](#-stig--compliance-mapping)
29. [AppLocker Event Filtering & Analysis](#-applocker-event-filtering--analysis)
30. [Localization & Accessibility](#-localization--accessibility)
31. [Future Roadmap](#-future-roadmap)
32. [Appendices](#-appendices)
    - [A: AppLocker Event IDs Reference](#appendix-a-applocker-event-ids-reference)
    - [B: Common Troubleshooting](#appendix-b-common-troubleshooting)
    - [C: PowerShell Requirements](#appendix-c-powershell-requirements)
    - [D: File Format Specifications](#appendix-d-file-format-specifications)
    - [E: Sample Policy XML Structure](#appendix-e-sample-policy-xml-structure)
    - [F: WinRM Configuration Guide](#appendix-f-winrm-configuration-guide)
    - [G: Glossary (Expanded)](#appendix-g-glossary-expanded)
    - [H: Architecture Diagram](#appendix-h-architecture-diagram)
    - [I: Quick Reference Card](#appendix-i-quick-reference-card)

---

## [TARGET] Core Vision

> Scan AD for hosts, then scan the hosts for artifacts related to AppLocker, for the app to ingest those artifacts seamlessly to automatically create rules based on best practices and security playbook, then merge all rules from various sources by workstation, member server, or domain controller to create a policy and apply to those OUs in audit mode depending on phases. Provide a one-click workflow to import scan artifacts and auto-generate rules from the imported data using AppLocker best-practice logic.

---

## [LIST] Functional Requirements

### 1. Scan AD for Hosts

**Capabilities:**
- Scan Active Directory for users and groups
- Discover machines from AD
- OU-based filtering for targeted discovery
- WinRM GPO management for remote scanning
- Domain auto-detection from Domain Controller

---

### 2. Scan Hosts for AppLocker Artifacts

**Capabilities:**
- Comprehensive artifact collection
- Scan executables, scripts, MSI, DLL
- Collect publisher signatures, hashes, paths
- Include event logs (8003/8004)
- Scan writable paths and system paths
- WinRM-based remote scanning support
- **Credential switching** for scanning different environments (workstations, servers, DCs)

**Artifact Sources:**
- Executables from Program Files, System32, SysWOW64
- Writable path executables
- Event log entries
- Software inventory
- Publisher signatures
- File hashes

---

### 3. Ingest Artifacts Seamlessly

**Capabilities:**
- Multi-format import (CSV, JSON, Comprehensive Scan artifacts)
- Automatic deduplication
- Unified inventory view
- Drag-and-drop file import
- Artifact parsing and validation

**Supported Formats:**
- CSV files
- JSON files
- Comprehensive scan artifacts (JSON)
- Event Viewer logs

---

### 4. Automatically Create Rules Based on Best Practices

**Capabilities:**
- **Smart Rule Priority Engine**: Publisher -> Hash (Path avoided)
- Publisher rules preferred (resilient to updates)
- Hash rules as fallback (secure for unsigned)
- Path rules avoided (too permissive/restrictive)
- Batch rule generation
- One-click rule generation from imported scan artifacts
- Publisher grouping & aggregation
- Duplicate detection
- Rule template library
- **Smart Group Assignment Engine** (auto-suggests allow groups)

**Best Practices Logic:**
| Priority | Rule Type | Use Case |
|----------|-----------|----------|
| 1st | Publisher | Preferred for signed software |
| 2nd | Hash | Fallback for unsigned executables |
| Avoid | Path | Too permissive, rarely used |

**Additional Features:**
- Publisher Grouping: Reduces rule count (e.g., 45 items -> 1 rule)
- Duplicate Detection: Prevents redundant rules
- Template Library: Pre-built rules for common scenarios

---

### 4a. Smart Group Assignment Engine

The app automatically suggests appropriate security groups for allow rules based on multiple factors. Users can accept defaults or override.

#### Group Assignment by Rule Collection Type

| Rule Type | Default Group | Rationale |
|-----------|---------------|-----------|
| **EXE** | Authenticated Users | Standard apps should run for all users |
| **Script** | IT Admins | Limit script execution to administrators |
| **MSI** | IT Admins + Deployment Service Accounts | Only admins/deployment tools install software |
| **DLL** | Everyone | DLLs need to load for applications to function |

#### Group Assignment by Machine Type

| Machine Type | EXE | Script | MSI | DLL |
|--------------|-----|--------|-----|-----|
| **Workstations** | Authenticated Users | IT Admins | IT Admins + Deployment SAs | Everyone |
| **Servers** | Authenticated Users | Server Admins | Server Admins + Deployment SAs | Everyone |
| **Domain Controllers** | Authenticated Users | Domain Admins | Domain Admins | Everyone |

#### Group Assignment by Software Category

| Category | Suggested Group | Detection Method |
|----------|-----------------|------------------|
| **Core OS** | Everyone | Path: C:\Windows\* |
| **Enterprise Apps** | Authenticated Users | Path: C:\Program Files\*, Known publishers |
| **Admin Tools** | IT Admins / Server Admins | Path contains "Admin", "Management", "RSAT" |
| **Dev Tools** | Developers Group | Publisher: Git, VS Code, JetBrains, Python |
| **Security Tools** | Security Admins | Publisher: Splunk, CrowdStrike, etc. |
| **Custom/LOB Apps** | Department-specific groups | Manual tagging or path-based |

#### Smart Detection Logic

**Path-Based Detection:**
- `C:\Windows\*` -> Everyone
- `C:\Program Files\*` -> Authenticated Users
- `C:\Program Files\*\Admin*\*` -> IT Admins
- `C:\Users\*` -> Block or specific user (flag for review)

**Publisher-Based Detection:**
- Microsoft signed -> Everyone
- Known enterprise vendor (Adobe, Google, etc.) -> Authenticated Users
- Unknown/unsigned publisher -> Manual review / IT Admins only

**Machine Type Context:**
- DC scan artifacts -> Default to Domain Admins (most restrictive)
- Server scan artifacts -> Default to Server Admins
- Workstation scan artifacts -> Default to Authenticated Users (broader access)

**Rule Type Context:**
- Script/MSI rules -> Always suggest admin groups first
- EXE/DLL rules -> Suggest broader groups (Everyone/Authenticated Users)

#### Group Assignment Features

**Smart Defaults with Override:**
- App auto-selects group based on detection logic
- User can override any suggestion before rule generation
- Visual indicator: "Suggested: Authenticated Users [v]"

**Group Templates:**
- Pre-built templates for common scenarios:
  - "Standard Workstation" - Balanced security
  - "Locked-Down Server" - Restrictive
  - "DC Hardened" - Maximum restriction
  - "Developer Workstation" - Dev tools enabled
- User selects template, all rules inherit group assignments

**Custom Group Mapping Table:**
- User defines org-specific mappings:
  - "For all MSI rules, use: Domain Admins"
  - "For Publisher=Adobe, use: Authenticated Users"
  - "For path containing 'Finance', use: Finance-Users"
- App applies mappings consistently across all generated rules
- Mappings saved as reusable profiles

---

### 5. Merge Rules by Machine Type

**Capabilities:**
- Policy merging functionality
- Merge multiple policy files
- Conflict resolution options
- Batch rule generation from multiple sources
- OU-based auto-grouping (machines automatically categorized by OU path)
- Machine type detection (Workstation vs Server vs DC)
- Separate policy generation per machine type

**Machine Type Detection:**
- Domain Controllers: Identified by "Domain Controllers" in OU path
- Servers: Identified by "Server" or "SRV" in OU path
- Workstations: Identified by "Workstation" or "Desktop" in OU path

**Auto-Grouping Output:**
- Workstations
- Servers
- Domain Controllers
- Unknown (fallback)

---

### 6. Create Policy

**Capabilities:**
- Policy XML generation
- Rule collection (Exe, Script, MSI, DLL)
- Policy validation
- Health checks
- Policy preview
- Export to XML

---

### 7. Apply to OUs in Audit Mode Based on Phases

**Capabilities:**
- Phase support (Phase 1-4)
- Audit mode enforcement
- GPO deployment
- Policy deployment to GPOs
- OU-based deployment with auto-linking
- Phase-based automatic enforcement mode
- "Deploy to OU" one-click functionality

**Phase-Based Enforcement:**
| Phase | Enforcement Mode | Rule Types |
|-------|-----------------|------------|
| Phase 1 | AuditOnly | EXE rules only - Testing |
| Phase 2 | AuditOnly | EXE + Script rules |
| Phase 3 | AuditOnly | EXE + Script + MSI |
| Phase 4 | Enabled | All rules including DLL |

---

## [KEY] Key Features Summary

### Credential Management
- Credential switching for different scan targets
- Separate credentials for Workstations, Servers, and Domain Controllers
- Secure credential storage during session
- Credential validation before scan execution
- Support for different admin accounts per environment

---

## [LOCK] Tiered Credential Access Model

### The Problem

In enterprise Active Directory environments, administrative access is typically segmented by machine type following the principle of least privilege. This means:

- **Domain Admins** can access Domain Controllers but may be blocked from workstations
- **Server Admins** can access member servers but cannot access DCs or workstations
- **Workstation Admins** can access workstations but cannot access servers or DCs

When scanning machines via WinRM, using a single credential set will fail for machines outside that credential's access tier. **GA-AppLocker must support credential switching to successfully scan across all machine types.**

### Tiered Admin Model

```
+-----------------------------------------------------------------------------+
|                     ENTERPRISE TIERED ADMIN MODEL                           |
+-----------------------------------------------------------------------------+

+-----------------+     +-----------------+     +-----------------+
|   TIER 0        |     |   TIER 1        |     |   TIER 2        |
|   Domain        |     |   Member        |     |   Workstations  |
|   Controllers   |     |   Servers       |     |                 |
+-----------------+     +-----------------+     +-----------------+
| Access Requires:|     | Access Requires:|     | Access Requires:|
| - Domain Admins |     | - Server Admins |     | - Workstation   |
| - Enterprise    |     | - System Admins |     |   Admins        |
|   Admins        |     | - App-specific  |     | - Help Desk     |
|                 |     |   admin groups  |     | - Desktop Admins|
+-----------------+     +-----------------+     +-----------------+
| [X] Server Admins|     | [X] Domain Admins|     | [X] Domain Admins|
| [X] Workstation  |     | [X] Workstation  |     | [X] Server Admins|
|   Admins        |     |   Admins        |     |                 |
+-----------------+     +-----------------+     +-----------------+
        |                       |                       |
        [v]                       [v]                       [v]
   Credential                Credential            Credential
   Profile: DC              Profile: Server       Profile: Workstation
```

### Why Credential Switching is Critical

| Scenario | Single Credential | With Credential Switching |
|----------|-------------------|---------------------------|
| Scan 50 workstations + 10 servers + 2 DCs | [X] Fails on 2 of 3 tiers | [OK] All 62 machines scanned |
| Domain Admin scans workstations | [X] Access Denied (restricted by GPO) | [OK] Uses Workstation Admin profile |
| Server Admin scans DCs | [X] Access Denied | [OK] Uses Domain Admin profile |
| Help Desk scans servers | [X] Access Denied | [OK] Uses Server Admin profile |

### Credential Profile Configuration

```
Settings -> Credentials -> Credential Profiles

+-----------------------------------------------------------------------------+
| CREDENTIAL PROFILES                                            [+ Add New] |
+-----------------------------------------------------------------------------+
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [KEY] DC Admin Account                                    [Default for DC] | |
| |    Username: DOMAIN\dc-admin                                            | |
| |    Target: Domain Controllers                                           | |
| |    Last Used: 2026-01-15 14:30                                         | |
| |    Status: [OK] Validated                                                 | |
| |    [Edit] [Test] [Delete]                                              | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [KEY] Server Admin Account                            [Default for Server] | |
| |    Username: DOMAIN\server-admin                                        | |
| |    Target: Member Servers                                               | |
| |    Last Used: 2026-01-15 14:25                                         | |
| |    Status: [OK] Validated                                                 | |
| |    [Edit] [Test] [Delete]                                              | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [KEY] Workstation Admin Account                  [Default for Workstation] | |
| |    Username: DOMAIN\ws-admin                                            | |
| |    Target: Workstations                                                 | |
| |    Last Used: 2026-01-15 14:20                                         | |
| |    Status: [OK] Validated                                                 | |
| |    [Edit] [Test] [Delete]                                              | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Credential Profile Schema

```typescript
interface CredentialProfile {
  id: string;                    // GUID
  name: string;                  // Display name (e.g., "DC Admin Account")
  description: string;           // Optional notes
  
  // Credential details
  username: string;              // DOMAIN\username or username@domain.com
  domain: string;                // Domain name
  password: SecureString;        // Encrypted, never stored in plaintext
  
  // Target assignment
  targetTier: CredentialTier;    // Tier0_DC, Tier1_Server, Tier2_Workstation, All
  targetOUs: string[];           // Optional: limit to specific OUs
  
  // Defaults
  isDefaultForTier: boolean;     // Auto-select for this tier
  
  // Validation
  lastValidated: datetime | null;
  validationStatus: "Valid" | "Invalid" | "Expired" | "Unknown";
  validationError: string | null;
  
  // Audit
  lastUsed: datetime | null;
  usageCount: number;
  createdAt: datetime;
  createdBy: string;
}

enum CredentialTier {
  Tier0_DC = "Tier0_DC",                   // Domain Controllers
  Tier1_Server = "Tier1_Server",           // Member Servers  
  Tier2_Workstation = "Tier2_Workstation", // Workstations
  All = "All"                              // Universal (rare, not recommended)
}
```

### Auto-Credential Selection Logic

When scanning machines, GA-AppLocker automatically selects the appropriate credential:

```typescript
function selectCredentialForMachine(
  machine: Machine, 
  profiles: CredentialProfile[]
): CredentialProfile | null {
  
  // 1. Determine machine tier from OU path or machine type
  const machineTier = getMachineTier(machine);
  
  // 2. Find matching credential profiles
  const matchingProfiles = profiles.filter(p => 
    p.targetTier === machineTier || p.targetTier === CredentialTier.All
  );
  
  // 3. Check for OU-specific credential
  const ouSpecificProfile = matchingProfiles.find(p =>
    p.targetOUs.length > 0 && 
    p.targetOUs.some(ou => machine.ouPath.includes(ou))
  );
  if (ouSpecificProfile) return ouSpecificProfile;
  
  // 4. Use default for tier
  const defaultProfile = matchingProfiles.find(p => p.isDefaultForTier);
  if (defaultProfile) return defaultProfile;
  
  // 5. Use any matching profile
  if (matchingProfiles.length > 0) return matchingProfiles[0];
  
  // 6. No credential available
  return null;
}

function getMachineTier(machine: Machine): CredentialTier {
  // Check OU path
  if (machine.ouPath.toLowerCase().includes('domain controllers')) {
    return CredentialTier.Tier0_DC;
  }
  
  // Check machine type
  switch (machine.machineType) {
    case MachineType.DomainController:
      return CredentialTier.Tier0_DC;
    case MachineType.Server:
      return CredentialTier.Tier1_Server;
    case MachineType.Workstation:
    default:
      return CredentialTier.Tier2_Workstation;
  }
}
```

### Scan Workflow with Credential Switching

```
+-----------------------------------------------------------------------------+
|                    SCAN WORKFLOW WITH AUTO-CREDENTIAL                       |
+-----------------------------------------------------------------------------+

1. User selects machines to scan (mixed: WS, Servers, DCs)
                    |
                    [v]
2. App groups machines by tier
   +--------------------------------------------------+
   | Tier 0 (DCs):        DC01, DC02                  |
   | Tier 1 (Servers):    SVR01, SVR02, SVR03        |
   | Tier 2 (Workstations): WS001-WS050              |
   +--------------------------------------------------+
                    |
                    [v]
3. App selects credential for each tier
   +--------------------------------------------------+
   | Tier 0 -> DC Admin Account (DOMAIN\dc-admin)     |
   | Tier 1 -> Server Admin Account (DOMAIN\svr-admin)|
   | Tier 2 -> WS Admin Account (DOMAIN\ws-admin)     |
   +--------------------------------------------------+
                    |
                    [v]
4. App validates credentials BEFORE scanning
   +--------------------------------------------------+
   | [OK] DC Admin: Valid                               |
   | [OK] Server Admin: Valid                           |
   | [X] WS Admin: FAILED - Password expired           |
   +--------------------------------------------------+
                    |
                    [v]
5. User prompted to fix invalid credentials
   +--------------------------------------------------+
   | [!] Credential issue detected                     |
   |                                                  |
   | WS Admin Account password has expired.          |
   |                                                  |
   | Options:                                         |
   | [Update Password] [Skip Workstations] [Cancel]  |
   +--------------------------------------------------+
                    |
                    [v]
6. Scan executes with appropriate credentials per tier
   +--------------------------------------------------+
   | Scanning DC01...     [DC Admin]      [OK] Complete |
   | Scanning DC02...     [DC Admin]      [OK] Complete |
   | Scanning SVR01...    [Server Admin]  [OK] Complete |
   | Scanning SVR02...    [Server Admin]  (WAIT) Running  |
   | Scanning WS001...    [WS Admin]      (WAIT) Queued   |
   +--------------------------------------------------+
```

### UI: Scan Configuration with Credentials

```
+-----------------------------------------------------------------------------+
| SCAN CONFIGURATION                                                          |
+-----------------------------------------------------------------------------+
|                                                                             |
| Selected Machines: 55 total                                                 |
| +-------------------------------------------------------------------------+ |
| | Machine Type       | Count | Credential Profile      | Status          | |
| +--------------------+-------+-------------------------+-----------------+ |
| | [WS] Workstations    | 50    | WS Admin Account    [v]  | [OK] Ready        | |
| | [SRV] Servers         | 3     | Server Admin Account [v] | [OK] Ready        | |
| | [DC] Domain Ctrls    | 2     | DC Admin Account    [v]  | [OK] Ready        | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| (i) Different credentials will be used for each machine type.               |
|   You can change the credential for each tier using the dropdowns.          |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | Advanced Options                                              [Expand] | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| [Validate All Credentials]              [Start Scan]            [Cancel]   |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Credential Validation

Before any scan begins, credentials are validated against a test target:

```powershell
function Test-CredentialAccess {
    param(
        [PSCredential]$Credential,
        [string]$TargetComputer,
        [int]$TimeoutSeconds = 30
    )
    
    $result = @{
        IsValid = $false
        Error = $null
        ResponseTime = $null
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Test WinRM connectivity
        $session = New-PSSession -ComputerName $TargetComputer `
                                 -Credential $Credential `
                                 -ErrorAction Stop
        
        # Quick test command
        Invoke-Command -Session $session -ScriptBlock { $env:COMPUTERNAME }
        
        Remove-PSSession -Session $session
        
        $stopwatch.Stop()
        $result.IsValid = $true
        $result.ResponseTime = $stopwatch.ElapsedMilliseconds
    }
    catch [System.UnauthorizedAccessException] {
        $result.Error = "Access Denied: Credential does not have permission"
    }
    catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
        if ($_.Exception.Message -match "Access is denied") {
            $result.Error = "Access Denied: Check credential permissions for this tier"
        }
        elseif ($_.Exception.Message -match "WinRM cannot process the request") {
            $result.Error = "WinRM not available on target machine"
        }
        else {
            $result.Error = "Connection failed: $($_.Exception.Message)"
        }
    }
    catch {
        $result.Error = "Unexpected error: $($_.Exception.Message)"
    }
    
    return $result
}
```

### Common Credential Errors and Solutions

| Error | Likely Cause | Solution |
|-------|--------------|----------|
| "Access Denied" on workstations | Using Domain Admin (blocked by GPO) | Use Workstation Admin credential |
| "Access Denied" on servers | Using Workstation Admin | Use Server Admin credential |
| "Access Denied" on DCs | Using non-Domain Admin | Use Domain Admin credential |
| "Password expired" | Credential password needs reset | Update password in AD, then in profile |
| "Account locked" | Too many failed attempts | Unlock account in AD, verify password |
| "WinRM not available" | WinRM not enabled on target | Enable WinRM via GPO or manually |
| "Kerberos authentication failed" | Time sync or SPN issues | Check time sync, verify SPNs |

### Best Practices for Credential Management

1. **Use Dedicated Service Accounts**
   - Create dedicated accounts for GA-AppLocker scanning
   - Don't use personal admin accounts
   - Example: `svc-applocker-dc`, `svc-applocker-srv`, `svc-applocker-ws`

2. **Follow Least Privilege**
   - Each credential should only have access to its tier
   - Don't use Domain Admins for workstation scanning
   - Consider read-only admin accounts where possible

3. **Secure Credential Storage**
   - Passwords stored encrypted using Windows DPAPI
   - Credentials cleared from memory after use
   - Option to require re-entry each session

4. **Audit Credential Usage**
   - Log which credential was used for each scan
   - Track failed authentication attempts
   - Alert on credential validation failures

5. **Rotate Credentials Regularly**
   - Set password expiry reminders
   - Update profiles when passwords change
   - Test credentials after rotation

### Group Policy Considerations

Your environment may have GPOs that restrict admin access. Common policies that affect WinRM scanning:

| Policy | Effect | GA-AppLocker Implication |
|--------|--------|--------------------------|
| "Deny log on through Remote Desktop Services" | Blocks RDP but not WinRM | Usually not an issue |
| "Deny access to this computer from the network" | Blocks all network access | Will block WinRM - use correct tier credential |
| "Restrict WinRM access to specific groups" | Only listed groups can use WinRM | Ensure scan accounts are in allowed groups |
| "Enable Local Admin Password Solution (LAPS)" | Unique local admin per machine | Use domain accounts, not local admin |
| "Tiered Admin Model GPOs" | Restricts DA from lower tiers | Must use tier-appropriate credentials |

---

## [TARGET] UX Design Principles & Friction Reduction

### Core UX Philosophy

**"Minimum Clicks to Maximum Results"**

Every workflow should be achievable in the fewest clicks possible while maintaining control for power users. The app should:
- Do the right thing by default
- Remember user preferences
- Allow bulk operations everywhere
- Provide one-click workflows for common tasks
- Never require unnecessary confirmation dialogs

### One-Click Workflows

#### Dashboard Quick Actions

```
+-----------------------------------------------------------------------------+
| DASHBOARD - QUICK ACTIONS                                                   |
+-----------------------------------------------------------------------------+
|                                                                             |
| +-----------------+ +-----------------+ +-----------------+                |
| | [SCAN] FULL SCAN    | | [IMPORT] IMPORT &     | | [DEPLOY] DEPLOY ALL   |                |
| |                 | |    GENERATE     | |    DRAFTS       |                |
| | Scan all machines| | Import file,   | | Deploy pending  |                |
| | with auto-creds, | | dedupe, and    | | policies to     |                |
| | generate rules,  | | generate rules | | target OUs      |                |
| | create drafts    | | in one click   | |                 |                |
| |                 | |                 | |                 |                |
| | [Start]         | | [Browse...]     | | [Deploy]        |                |
| +-----------------+ +-----------------+ +-----------------+                |
|                                                                             |
| +-----------------+ +-----------------+ +-----------------+                |
| | [LIST] SCAN GROUP   | | [PERF] QUICK SCAN   | | [CHART] COMPLIANCE   |                |
| |                 | |                 | |    REPORT       |                |
| | Run a saved     | | Scan a single   | | Generate full   |                |
| | scan group with | | hostname or IP  | | compliance      |                |
| | preset creds    | |                 | | report          |                |
| |                 | |                 | |                 |                |
| | [Select [v]]      | | [____________]  | | [Generate]      |                |
| +-----------------+ +-----------------+ +-----------------+                |
|                                                                             |
+-----------------------------------------------------------------------------+
```

#### Full Scan Workflow (One-Click)

```
User clicks [[SCAN] FULL SCAN]
         |
         [v]
+-----------------------------------------+
| FULL ENVIRONMENT SCAN                   |
|                                         |
| This will:                              |
| [x] Discover all machines from AD         |
| [x] Group by Workstation/Server/DC        |
| [x] Use saved credential profiles         |
| [x] Scan all machines for artifacts       |
| [x] Save results to Scans\{date}\         |
| [x] Auto-generate rules (best practices)  |
| [x] Create draft policies by machine type |
|                                         |
| Estimated time: ~45 minutes (150 machines)|
|                                         |
| [x] Remember this choice (don't ask again)|
|                                         |
| [Cancel]                    [Start Now] |
+-----------------------------------------+
         |
         [v]
    Runs in background, notification when complete
```

### Scan Groups (Saved Scan Configurations)

#### Scan Group Schema

```typescript
interface ScanGroup {
  id: string;
  name: string;                          // "Finance Workstations"
  description: string;
  
  // Target Selection
  targetType: "OU" | "Manual" | "Query";
  targetOUs: string[];                   // If OU-based
  targetHostnames: string[];             // If manual
  adQuery: string;                       // If query-based (LDAP filter)
  
  // Credential References (IDs only, not actual credentials)
  credentials: {
    tier0_DC: string | null;             // Credential profile ID
    tier1_Server: string | null;
    tier2_Workstation: string | null;
  };
  
  // Default Group Assignments for this scan group
  defaultGroups: {
    exe: string;                         // Default group for EXE rules
    dll: string;
    msi: string;
    script: string;
  };
  
  // Scan Options
  scanDepth: "Quick" | "Standard" | "Deep";
  includeEventLogs: boolean;
  artifactTypes: FileType[];
  
  // Schedule (optional)
  schedule: {
    enabled: boolean;
    frequency: "Daily" | "Weekly" | "Monthly";
    dayOfWeek?: number;
    timeOfDay: string;                   // "02:00"
  } | null;
  
  // Metadata
  lastRun: datetime | null;
  runCount: number;
  createdAt: datetime;
  createdBy: string;
}
```

#### Scan Group UI

```
+-----------------------------------------------------------------------------+
| SCAN GROUPS                                                    [+ New Group]|
+-----------------------------------------------------------------------------+
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [DIR] Finance Workstations                                                 | |
| |    Target: OU=Finance,OU=Workstations,DC=corp,DC=local (45 machines)   | |
| |    Credentials: WS-Admin-Finance                                        | |
| |    Last Run: 2026-01-15 (Success)                                      | |
| |    Schedule: Weekly, Monday 2:00 AM                                     | |
| |                                                                         | |
| |    [[>] Run Now]  [Edit]  [Clone]  [Delete]                              | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [DIR] All Servers                                                          | |
| |    Target: OU=Servers,DC=corp,DC=local (23 machines)                   | |
| |    Credentials: Server-Admin                                            | |
| |    Last Run: 2026-01-14 (3 failed)                                     | |
| |    Schedule: None                                                       | |
| |                                                                         | |
| |    [[>] Run Now]  [Edit]  [Clone]  [Delete]                              | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [DIR] Domain Controllers                                                   | |
| |    Target: OU=Domain Controllers,DC=corp,DC=local (2 machines)         | |
| |    Credentials: DC-Admin                                                | |
| |    Last Run: 2026-01-15 (Success)                                      | |
| |    Schedule: Monthly, 1st Sunday 3:00 AM                                | |
| |                                                                         | |
| |    [[>] Run Now]  [Edit]  [Clone]  [Delete]                              | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
+-----------------------------------------------------------------------------+
```

#### Create/Edit Scan Group Dialog

```
+-----------------------------------------------------------------------------+
| CREATE SCAN GROUP                                                      [X] |
+-----------------------------------------------------------------------------+
|                                                                             |
| Name: [Finance Workstations_________________]                               |
|                                                                             |
| --- TARGET SELECTION ----------------------------------------------------- |
|                                                                             |
| Target Type: ( ) OU-Based  (-) Manual List  ( ) AD Query                   |
|                                                                             |
| +-OU TREE ----------------------------------------------------------------+ |
| | [x] [DIR] corp.local                                                         | |
| |   [x] [DIR] Workstations                                                     | |
| |     [x] [DIR] Finance (45 computers)                                         | |
| |     [ ] [DIR] HR (32 computers)                                              | |
| |     [ ] [DIR] IT (28 computers)                                              | |
| |   [ ] [DIR] Servers                                                          | |
| |   [ ] [DIR] Domain Controllers                                               | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| --- CREDENTIALS ---------------------------------------------------------- |
|                                                                             |
| Workstations:  [WS-Admin-Finance        [v]]  [Test]                         |
| Servers:       [Server-Admin            [v]]  [Test]  (if any in selection)  |
| DCs:           [DC-Admin                [v]]  [Test]  (if any in selection)  |
|                                                                             |
| --- DEFAULT GROUPS (for rules generated from this scan) ----------------- |
|                                                                             |
| EXE Rules:    [Authenticated Users      [v]]                                 |
| DLL Rules:    [Everyone                 [v]]                                 |
| MSI Rules:    [Finance-IT-Admins        [v]]                                 |
| Script Rules: [Finance-IT-Admins        [v]]                                 |
|                                                                             |
| --- SCAN OPTIONS --------------------------------------------------------- |
|                                                                             |
| Scan Depth:     [Standard [v]]                                               |
| Artifact Types: [x] EXE  [x] DLL  [x] MSI  [x] Script  [ ] Appx                     |
| Include Events: [x] Yes                                                      |
|                                                                             |
| --- SCHEDULE (Optional) -------------------------------------------------- |
|                                                                             |
| [x] Enable scheduled scanning                                                |
| Frequency: [Weekly [v]]  Day: [Monday [v]]  Time: [02:00 [v]]                   |
|                                                                             |
|                                          [Cancel]  [Save]  [Save & Run]   |
+-----------------------------------------------------------------------------+
```

### Artifact Storage Structure

All scan results are automatically saved to a structured folder hierarchy:

```
%LOCALAPPDATA%\GA-AppLocker\
+-- Scans\
|   +-- 2026-01-16\
|   |   +-- _scan_manifest.json        # Scan metadata
|   |   +-- WS001.json                 # Artifacts from WS001
|   |   +-- WS002.json
|   |   +-- SVR01.json
|   |   +-- DC01.json
|   |   +-- _scan_summary.json         # Summary stats
|   +-- 2026-01-15\
|   |   +-- ...
|   +-- 2026-01-14\
|       +-- ...
+-- Credentials\
|   +-- profiles.encrypted             # DPAPI encrypted
+-- ScanGroups\
|   +-- groups.json
+-- Policies\
|   +-- drafts\
|   +-- exported\
+-- Rules\
|   +-- rules.json
+-- Settings\
|   +-- settings.json
+-- Logs\
    +-- ...
```

#### Scan Manifest Schema

```typescript
interface ScanManifest {
  id: string;
  date: string;                          // "2026-01-16"
  startTime: datetime;
  endTime: datetime;
  
  // Source
  scanGroupId: string | null;            // If from saved group
  scanGroupName: string | null;
  triggeredBy: "Manual" | "Scheduled" | "QuickAction";
  
  // Targets
  totalMachines: number;
  machinesByTier: {
    tier0_DC: number;
    tier1_Server: number;
    tier2_Workstation: number;
  };
  
  // Results
  successfulScans: number;
  failedScans: number;
  totalArtifacts: number;
  artifactsByType: {
    exe: number;
    dll: number;
    msi: number;
    script: number;
  };
  
  // Files
  artifactFiles: string[];               // Relative paths to JSON files
  
  // Credentials used (IDs only)
  credentialsUsed: string[];
}
```

#### Per-Host Artifact File

```json
// Scans/2026-01-16/WS001.json
{
  "hostname": "WS001",
  "fqdn": "WS001.corp.local",
  "scanDate": "2026-01-16T14:30:00Z",
  "scanDuration": 45000,
  "machineType": "Workstation",
  "ouPath": "OU=Finance,OU=Workstations,DC=corp,DC=local",
  "status": "Success",
  "artifactCount": 234,
  "artifacts": [
    {
      "fileName": "chrome.exe",
      "filePath": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
      "fileHash_SHA256": "ABC123...",
      "publisher": {
        "name": "O=GOOGLE LLC, L=MOUNTAIN VIEW, S=CA, C=US",
        "isValid": true
      },
      "product": {
        "name": "Google Chrome",
        "version": "120.0.6099.130"
      },
      "fileType": "EXE",
      "fileSize": 3456789
    }
    // ... more artifacts
  ]
}
```

### Review & Approve Suggestions Screen

After rule generation, users see a split-pane review screen with traffic light indicators:

```
+-----------------------------------------------------------------------------+
| REVIEW GENERATED RULES                              Showing 234 of 234 rules|
+-----------------------------------------------------------------------------+
| +- FILTERS ---------------------------------------------------------------+ |
| | Status: [All [v]]  Type: [All [v]]  Collection: [All [v]]  Search: [_______] | |
| |                                                                         | |
| | Quick Filters: [(OK) Good (189)] [(!) Review (38)] [(X) Attention (7)]      | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| +- BULK ACTIONS ----------------------------------------------------------+ |
| | [[x] Accept All Good] [[x] Accept All Visible] [[X] Reject Selected]         | |
| | Selected: 0  |  Ctrl+Click to select multiple, Shift+Click for range   | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| +- ARTIFACT LIST ---------------------------------+- RULE PREVIEW --------+ |
| | St | File Name       | Publisher    | Group    ||                       | |
| +----+-----------------+--------------+----------+| Selected: chrome.exe  | |
| | (OK) | chrome.exe      | Google LLC   | Auth Usr [v]|                       | |
| | (OK) | msedge.exe      | Microsoft    | Auth Usr [v]| --- RULE DETAILS ---- | |
| | (OK) | outlook.exe     | Microsoft    | Auth Usr [v]||                       | |
| | (OK) | excel.exe       | Microsoft    | Auth Usr [v]| Type: Publisher       | |
| | (!) | customapp.exe   | Internal Inc | [Select] [v]| Collection: EXE       | |
| | (!) | legacy.exe      | Unknown      | [Select] [v]| Action: Allow         | |
| | (X) | temp_util.exe   | NOT SIGNED   | [Select] [v]|                       | |
| | (X) | C:\Users\*.exe  | NOT SIGNED   | [Block?] [v]| Publisher:            | |
| |    |                 |              |          || O=GOOGLE LLC, L=...   | |
| |    |                 |              |          ||                       | |
| |    |                 |              |          || Product: Google Chrome| |
| |    |                 |              |          || Version: * and above  | |
| |    |                 |              |          ||                       | |
| |    |                 |              |          || Group: Auth. Users    | |
| |    |                 |              |          ||                       | |
| |    |                 |              |          || --- XML PREVIEW ----- | |
| |    |                 |              |          || <FilePublisherRule    | |
| |    |                 |              |          ||   Id="..."            | |
| |    |                 |              |          ||   Name="Allow Google" | |
| |    |                 |              |          ||   ...                 | |
| |    |                 |              |          || </FilePublisherRule>  | |
| +----+-----------------+--------------+----------++-----------------------+ |
|                                                                             |
| Summary: (OK) 189 Ready  (!) 38 Need Review  (X) 7 Need Attention               |
|                                                                             |
| [Cancel]                      [Save as Draft]              [Accept & Save] |
+-----------------------------------------------------------------------------+
```

#### Traffic Light Status Logic

```typescript
interface RuleSuggestion {
  artifact: CanonicalArtifact;
  suggestedRule: Rule;
  status: SuggestionStatus;
  statusReasons: string[];
}

enum SuggestionStatus {
  Good = "Good",           // (OK) Auto-approve candidate
  Review = "Review",       // (!) Needs human review
  Attention = "Attention"  // (X) Potential issue
}

function calculateSuggestionStatus(artifact: CanonicalArtifact): SuggestionStatus {
  const reasons: string[] = [];
  
  // (X) ATTENTION - Definite concerns
  if (artifact.filePath.toLowerCase().includes('\\users\\')) {
    reasons.push("Located in user profile directory");
    return { status: SuggestionStatus.Attention, reasons };
  }
  
  if (artifact.filePath.toLowerCase().includes('\\temp')) {
    reasons.push("Located in temp directory");
    return { status: SuggestionStatus.Attention, reasons };
  }
  
  if (!artifact.publisher.isValid && !artifact.fileHash_SHA256) {
    reasons.push("No signature and no hash available");
    return { status: SuggestionStatus.Attention, reasons };
  }
  
  if (artifact.riskLevel === RiskLevel.Critical) {
    reasons.push("Critical risk level");
    return { status: SuggestionStatus.Attention, reasons };
  }
  
  // (!) REVIEW - Minor concerns
  if (!artifact.publisher.isValid) {
    reasons.push("Not digitally signed (will use hash rule)");
    return { status: SuggestionStatus.Review, reasons };
  }
  
  if (artifact.category === ArtifactCategory.Unknown) {
    reasons.push("Unknown software category");
    return { status: SuggestionStatus.Review, reasons };
  }
  
  if (!isKnownVendor(artifact.publisher.commonName)) {
    reasons.push("Publisher not in known vendors list");
    return { status: SuggestionStatus.Review, reasons };
  }
  
  if (artifact.publisher.signatureStatus === SignatureStatus.Expired) {
    reasons.push("Publisher signature has expired");
    return { status: SuggestionStatus.Review, reasons };
  }
  
  // (OK) GOOD - No concerns
  return { status: SuggestionStatus.Good, reasons: ["Signed by known vendor, standard location"] };
}
```

#### Inline Group Editing

The Group column is a dropdown that appears on click:

```
+------------------------------------------+
| (!) | customapp.exe | Internal Inc | [v]   |
+------------------------------------------+
                                      |
                    Click dropdown    |
                                      [v]
                    +-------------------------+
                    | [SCAN] Search groups...     |
                    +-------------------------+
                    | [*] Recently Used         |
                    |   Authenticated Users   |
                    |   Finance-Users         |
                    +-------------------------+
                    | [DIR] Suggested            |
                    |   IT Admins (based on   |
                    |   path containing Admin)|
                    +-------------------------+
                    | [DIR] All Groups           |
                    |   Authenticated Users   |
                    |   Domain Admins         |
                    |   Domain Users          |
                    |   Enterprise Admins     |
                    |   Everyone              |
                    |   Finance-IT-Admins     |
                    |   Finance-Users         |
                    |   ...                   |
                    +-------------------------+
                    | [+ Browse AD Groups...] |
                    +-------------------------+
```

### Smart Defaults & Persistence

#### First-Time Setup Wizard

```
+-----------------------------------------------------------------------------+
| WELCOME TO GA-APPLOCKER                                        Step 1 of 4 |
+-----------------------------------------------------------------------------+
|                                                                             |
|                    [BLDG] DOMAIN CONFIGURATION                                  |
|                                                                             |
| We detected you're running on a Domain Controller.                          |
|                                                                             |
| Domain: [corp.local_________________________] (auto-detected)               |
|                                                                             |
| [x] Use current session credentials for initial AD discovery                 |
|                                                                             |
|                                                                             |
| [Skip Setup]                                        [Back]  [Next ->]       |
+-----------------------------------------------------------------------------+

+-----------------------------------------------------------------------------+
| CREDENTIAL PROFILES                                            Step 2 of 4 |
+-----------------------------------------------------------------------------+
|                                                                             |
| Set up credentials for each machine tier:                                   |
|                                                                             |
| --- TIER 0: DOMAIN CONTROLLERS ------------------------------------------- |
| Username: [CORP\dc-admin_______________]                                    |
| Password: [****************************]  [Test Connection]  [OK] Valid       |
|                                                                             |
| --- TIER 1: MEMBER SERVERS ----------------------------------------------- |
| Username: [CORP\server-admin___________]                                    |
| Password: [****************************]  [Test Connection]  [OK] Valid       |
|                                                                             |
| --- TIER 2: WORKSTATIONS ------------------------------------------------- |
| Username: [CORP\ws-admin_______________]                                    |
| Password: [****************************]  [Test Connection]  [OK] Valid       |
|                                                                             |
| [x] Save credentials securely (encrypted with Windows DPAPI)                 |
|                                                                             |
| [Skip Setup]                                        [Back]  [Next ->]       |
+-----------------------------------------------------------------------------+

+-----------------------------------------------------------------------------+
| DEFAULT GROUP ASSIGNMENTS                                      Step 3 of 4 |
+-----------------------------------------------------------------------------+
|                                                                             |
| Set default security groups for generated rules:                            |
|                                                                             |
| --- BY RULE COLLECTION --------------------------------------------------- |
|                                                                             |
| EXE Rules:    [Authenticated Users [v]]  (recommended)                       |
| DLL Rules:    [Everyone            [v]]  (recommended)                       |
| MSI Rules:    [Domain Admins       [v]]  (recommended)                       |
| Script Rules: [Domain Admins       [v]]  (recommended)                       |
|                                                                             |
| --- ADMIN BROWSER RESTRICTIONS ------------------------------------------- |
|                                                                             |
| [x] Block web browsers for admin accounts                                    |
|   Apply to: [x] Domain Admins  [x] Server Admins  [x] Enterprise Admins         |
|                                                                             |
| --- DEFAULT DENY RULES --------------------------------------------------- |
|                                                                             |
| [x] Block executables in Downloads folder                                    |
| [x] Block executables in Temp folders                                        |
| [ ] Block executables in user AppData (may break apps)                       |
|                                                                             |
| [Skip Setup]                                        [Back]  [Next ->]       |
+-----------------------------------------------------------------------------+

+-----------------------------------------------------------------------------+
| SCAN SETTINGS                                                  Step 4 of 4 |
+-----------------------------------------------------------------------------+
|                                                                             |
| Configure default scan behavior:                                            |
|                                                                             |
| --- SCAN DEPTH ----------------------------------------------------------- |
|                                                                             |
| Default scan depth: (-) Quick  ( ) Standard  ( ) Deep                      |
|                                                                             |
|   Quick:    Program Files, System32 only (~30 sec/machine)                 |
|   Standard: + Common app paths, user-installed apps (~2 min/machine)       |
|   Deep:     + Full drive scan, all executables (~5 min/machine)            |
|                                                                             |
| --- ARTIFACT TYPES ------------------------------------------------------- |
|                                                                             |
| Include in scans: [x] EXE  [x] DLL  [x] MSI  [x] Script  [ ] Appx                   |
|                                                                             |
| --- STORAGE -------------------------------------------------------------- |
|                                                                             |
| Save scan results to: [%LOCALAPPDATA%\GA-AppLocker\Scans] [Browse...]      |
| Auto-cleanup scans older than: [30 [v]] days  [ ] Never delete                 |
|                                                                             |
| --- AFTER SCAN ----------------------------------------------------------- |
|                                                                             |
| [x] Automatically generate rules after scan completes                        |
| [x] Auto-save artifacts to scan folder                                       |
| [ ] Auto-create draft policies (manual review preferred)                     |
|                                                                             |
| [Skip Setup]                                      [Back]  [Finish Setup]   |
+-----------------------------------------------------------------------------+
```

#### Settings Persistence

```typescript
interface UserPreferences {
  // === REMEMBERED CHOICES ===
  rememberedDialogs: {
    fullScanConfirmation: boolean;       // Don't ask again for full scan
    deployConfirmation: boolean;         // Don't ask again for deploy
    deleteConfirmation: boolean;         // Always ask for deletes
  };
  
  // === LAST USED VALUES ===
  lastUsed: {
    exportDirectory: string;
    importDirectory: string;
    selectedOUs: string[];
    selectedScanGroup: string;
    ruleViewFilters: RuleFilters;
    artifactViewFilters: ArtifactFilters;
  };
  
  // === UI STATE ===
  ui: {
    sidebarCollapsed: boolean;
    lastActivePanel: string;
    gridColumnWidths: Record<string, number[]>;
    gridSortStates: Record<string, SortState>;
    splitPanePositions: Record<string, number>;
  };
  
  // === FAVORITES ===
  favorites: {
    pinnedOUs: string[];
    pinnedMachines: string[];
    pinnedGroups: string[];              // Frequently used AD groups
    recentPolicies: string[];
  };
}
```

### Multi-Select & Bulk Operations

#### Selection Behaviors

| Action | Result |
|--------|--------|
| Single click | Select single item, deselect others |
| Ctrl + Click | Toggle selection (add/remove from selection) |
| Shift + Click | Select range from last selected to clicked |
| Ctrl + A | Select all visible items |
| Escape | Deselect all |
| Click checkbox | Toggle single item without affecting others |
| Click header checkbox | Select/deselect all visible |

#### Right-Click Context Menus

**Artifact Grid Context Menu:**
```
+---------------------------------+
| Generate Rule for Selected (3)  |
| ------------------------------- |
| Copy Hash                       |
| Copy Path                       |
| Copy Publisher                  |
| ------------------------------- |
| Open File Location              |
| View in Inventory               |
| ------------------------------- |
| Add Tag...                      |
| Mark for Review                 |
| ------------------------------- |
| Delete Selected (3)             |
+---------------------------------+
```

**Rule Grid Context Menu:**
```
+---------------------------------+
| Edit Rule                       |
| Duplicate Rule                  |
| ------------------------------- |
| Change Group -> [submenu]        |
| Change Action -> Allow / Deny    |
| ------------------------------- |
| Add to Policy...                |
| Export Selected (5)...          |
| ------------------------------- |
| View Source Artifacts           |
| ------------------------------- |
| Delete Selected (5)             |
+---------------------------------+
```

**Machine Grid Context Menu:**
```
+---------------------------------+
| Scan Selected (12)              |
| Scan with Credential...         |
| ------------------------------- |
| Add to Scan Group...            |
| ------------------------------- |
| Test WinRM Connection           |
| View Last Scan Results          |
| ------------------------------- |
| Copy Hostname                   |
| Copy FQDN                       |
| ------------------------------- |
| Open Computer Management        |
| Remote Desktop                  |
+---------------------------------+
```

### Keyboard Shortcuts

```
+-----------------------------------------------------------------------------+
| KEYBOARD SHORTCUTS                                                          |
+-----------------------------------------------------------------------------+
|                                                                             |
| --- GLOBAL --------------------------------------------------------------- |
| Ctrl + S          Save current work                                         |
| Ctrl + Z          Undo last action                                          |
| Ctrl + Y          Redo                                                      |
| Ctrl + F          Focus search/filter box                                   |
| F5                Refresh current view                                      |
| F1                Open help                                                 |
| Escape            Close dialog / Cancel operation / Deselect all           |
|                                                                             |
| --- NAVIGATION ----------------------------------------------------------- |
| Ctrl + 1          Go to Dashboard                                           |
| Ctrl + 2          Go to AD Discovery                                        |
| Ctrl + 3          Go to Artifact Scanner                                    |
| Ctrl + 4          Go to Rule Generator                                      |
| Ctrl + 5          Go to Policy Builder                                      |
| Ctrl + 6          Go to Deployment                                          |
| Ctrl + Tab        Next panel                                                |
| Ctrl + Shift + Tab Previous panel                                           |
|                                                                             |
| --- ACTIONS -------------------------------------------------------------- |
| Ctrl + G          Generate rules (from current selection)                   |
| Ctrl + D          Deploy (current policy)                                   |
| Ctrl + E          Export selected                                           |
| Ctrl + I          Import file (opens file browser)                          |
| Ctrl + N          New (context-dependent: rule, policy, scan group)        |
| Delete            Delete selected items (with confirmation)                 |
|                                                                             |
| --- SELECTION ------------------------------------------------------------ |
| Ctrl + A          Select all visible                                        |
| Ctrl + Click      Toggle item selection                                     |
| Shift + Click     Select range                                              |
| Ctrl + Shift + A  Deselect all                                              |
|                                                                             |
| --- GRID NAVIGATION ------------------------------------------------------ |
| Arrow keys        Move selection                                            |
| Page Up/Down      Scroll grid                                               |
| Home              Go to first row                                           |
| End               Go to last row                                            |
| Enter             Edit selected / Open details                              |
| Space             Toggle checkbox (if present)                              |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Policy Auto-Save & Draft Management

```typescript
interface PolicyDraft {
  id: string;
  name: string;
  machineType: MachineType;
  phase: number;
  
  // Auto-save metadata
  isDraft: boolean;
  autoSavedAt: datetime;
  lastManualSave: datetime | null;
  
  // Change tracking
  hasUnsavedChanges: boolean;
  changeHistory: PolicyChange[];
  
  // Deployment status
  deploymentStatus: "NotDeployed" | "Deployed" | "Modified";  // Modified = deployed but changed since
  lastDeployedAt: datetime | null;
  deployedToGPO: string | null;
  deployedToOUs: string[];
}

interface PolicyChange {
  timestamp: datetime;
  changeType: "RuleAdded" | "RuleRemoved" | "RuleModified" | "SettingChanged";
  description: string;
  canUndo: boolean;
}
```

#### Auto-Save Behavior

```
+-----------------------------------------------------------------------------+
| Policy: Workstation-Policy-v2                          Auto-saved 30s ago [*] |
+-----------------------------------------------------------------------------+
|                                                                             |
| Status: [!] MODIFIED (deployed version differs from current draft)           |
|                                                                             |
| ...                                                                         |
|                                                                             |
| [Discard Changes]  [View Deployed Version]      [Save]  [Deploy Update]    |
+-----------------------------------------------------------------------------+
```

- Auto-save every 60 seconds while editing
- Visual indicator shows save status ([*]=saved, [ ]=unsaved)
- "Discard Changes" reverts to last manual save
- Warning when closing with unsaved changes

### Deploy All Workflow

```
+-----------------------------------------------------------------------------+
| DEPLOY ALL POLICIES                                                         |
+-----------------------------------------------------------------------------+
|                                                                             |
| Ready to deploy the following policies:                                     |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [x] | Policy              | Target OUs           | Phase | Status        | |
| +---+---------------------+----------------------+-------+---------------+ |
| | [x] | Workstation-Policy  | OU=Workstations,...  | 2     | [!] Modified   | |
| | [x] | Server-Policy       | OU=Servers,...       | 2     | (NEW) New        | |
| | [x] | DC-Policy           | OU=Domain Ctrl,...   | 1     | [OK] Current    | |
| +---+---------------------+----------------------+-------+---------------+ |
|                                                                             |
| --- DEPLOYMENT OPTIONS --------------------------------------------------- |
|                                                                             |
| [x] Backup existing policies before deployment                               |
| [x] Create GPO if it doesn't exist                                           |
| [x] Link GPO to target OUs automatically                                     |
|                                                                             |
| --- SUMMARY -------------------------------------------------------------- |
|                                                                             |
| - 2 policies will be deployed (1 update, 1 new)                            |
| - 1 policy is already current (DC-Policy) - will be skipped               |
| - Affects 3 GPOs across 3 OUs                                              |
| - ~150 machines will receive updated policies                              |
|                                                                             |
| [ ] Remember these settings for future deployments                           |
|                                                                             |
| [Cancel]                                           [Deploy Selected (2)]   |
+-----------------------------------------------------------------------------+
```

### File Browser Integration

All file operations use native Windows file dialogs with smart defaults:

```typescript
interface FileDialogOptions {
  // Smart defaults
  initialDirectory: string;              // Last used or configured default
  defaultExtension: string;
  
  // Filters
  filters: FileFilter[];
  
  // Behavior
  multiSelect: boolean;
  validateFile: (path: string) => ValidationResult;
}

// Import artifacts dialog
const importDialog: FileDialogOptions = {
  initialDirectory: userPrefs.lastUsed.importDirectory || Desktop,
  defaultExtension: ".json",
  filters: [
    { name: "All Supported", extensions: ["json", "csv", "xml"] },
    { name: "JSON Files", extensions: ["json"] },
    { name: "CSV Files", extensions: ["csv"] },
    { name: "AppLocker XML", extensions: ["xml"] },
    { name: "All Files", extensions: ["*"] }
  ],
  multiSelect: true,  // Can select multiple files at once
  validateFile: validateArtifactFile
};

// Export policy dialog  
const exportDialog: FileDialogOptions = {
  initialDirectory: userPrefs.lastUsed.exportDirectory || Documents,
  defaultExtension: ".xml",
  suggestedFileName: `${policyName}_${dateStamp}.xml`,
  filters: [
    { name: "AppLocker Policy XML", extensions: ["xml"] },
    { name: "JSON (with metadata)", extensions: ["json"] }
  ],
  multiSelect: false
};
```

### In-App Notifications

```
+- NOTIFICATION AREA (top-right) ---------------------------------------------+
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [OK] Scan completed successfully                                    [X]  | |
| |    55 machines scanned, 3,456 artifacts collected                      | |
| |    [View Results]  [Generate Rules]                      5 seconds ago | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | [!] 3 machines failed to scan                                      [X]  | |
| |    WS012, WS015, SVR03 - Access denied                                 | |
| |    [View Details]  [Retry Failed]                       2 minutes ago  | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
+-----------------------------------------------------------------------------+

Notification Types:
  [OK] Success (green)  - Auto-dismiss after 10 seconds, or click to dismiss
  [!] Warning (yellow) - Stays until dismissed, has action buttons
  [X] Error (red)      - Stays until dismissed, has details expandable
  (i) Info (blue)      - Auto-dismiss after 5 seconds
```

### Progress Indicators

#### Status Bar (always visible at bottom)

```
+-----------------------------------------------------------------------------+
| [icon] Scanning WS023... (12 of 55)  ########-------- 22%    [Cancel]      |
+-----------------------------------------------------------------------------+
```

#### Background Operations Queue

```
+-----------------------------------------------------------------------------+
| BACKGROUND OPERATIONS                                          [Clear All] |
+-----------------------------------------------------------------------------+
| (WAIT) Scanning Finance Workstations (45 machines)     ########-- 78%  [Cancel]|
| (PAUSE) Rule generation queued                          Waiting...      [Remove]|
| [OK] Policy export completed                         Done            [Clear] |
+-----------------------------------------------------------------------------+
```

---

## [CODE] Development Principles

### Core Philosophy

**"Simple, Modular, Maintainable"**

All code should be written with the following priorities:
1. **Readability** - Code is read more than written
2. **Simplicity** - The simplest solution that works
3. **Modularity** - Small, focused, reusable components
4. **Testability** - Easy to test in isolation

### KISS - Keep It Simple

| Principle | Do This | Not This |
|-----------|---------|----------|
| Simple logic | Linear flow, early returns | Deeply nested conditionals |
| Clear naming | `Get-ArtifactsByMachine` | `ProcessData` |
| Obvious code | Self-documenting | Clever one-liners |
| Direct approach | Straightforward solution | Over-engineered abstraction |

**Example - Simple over Clever:**
```powershell
# GOOD - Simple and readable
function Get-SignedArtifacts {
    param([array]$Artifacts)
    
    $signed = @()
    foreach ($artifact in $Artifacts) {
        if ($artifact.Publisher.IsValid) {
            $signed += $artifact
        }
    }
    return $signed
}

# BAD - Clever but harder to debug
function Get-SignedArtifacts($a){$a|?{$_.Publisher.IsValid}}
```

### Function Design Rules

**Rule 1: Single Purpose**
Each function does ONE thing and does it well.

```powershell
# GOOD - Single purpose
function Test-WinRMConnection { }
function Get-RemoteArtifacts { }
function Save-ScanResults { }

# BAD - Multiple responsibilities
function ScanAndSaveAndGenerateRules { }
```

**Rule 2: Small Functions (<30 lines)**
If a function exceeds 30 lines, break it into smaller functions.

```powershell
# GOOD - Small, focused functions
function Invoke-MachineScan {
    param([string]$Hostname, [PSCredential]$Credential)
    
    $connection = Connect-RemoteMachine -Hostname $Hostname -Credential $Credential
    if (-not $connection.Success) {
        return $connection
    }
    
    $artifacts = Get-MachineArtifacts -Session $connection.Session
    $results = Format-ScanResults -Artifacts $artifacts -Hostname $Hostname
    
    Disconnect-RemoteMachine -Session $connection.Session
    
    return $results
}

# BAD - Monolithic function doing everything
function Invoke-MachineScan {
    # 200 lines of mixed connection, scanning, formatting, error handling...
}
```

**Rule 3: Clear Input/Output Contracts**
Every function should have explicit parameters and return types.

```powershell
# GOOD - Clear contract
function New-AppLockerRule {
    [CmdletBinding()]
    [OutputType([AppLockerRule])]
    param(
        [Parameter(Mandatory)]
        [Artifact]$Artifact,
        
        [Parameter(Mandatory)]
        [ValidateSet('Publisher', 'Hash', 'Path')]
        [string]$RuleType,
        
        [Parameter()]
        [string]$GroupSid = 'S-1-1-0'
    )
    
    # Implementation...
    return $rule
}

# BAD - Unclear contract
function MakeRule($data) {
    # What is $data? What does this return?
}
```

**Rule 4: Early Returns (Guard Clauses)**
Validate inputs and exit early rather than deep nesting.

```powershell
# GOOD - Early returns
function Get-ArtifactHash {
    param([string]$FilePath)
    
    if ([string]::IsNullOrEmpty($FilePath)) {
        return $null
    }
    
    if (-not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return $null
    }
    
    $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
    return $hash.Hash
}

# BAD - Deep nesting
function Get-ArtifactHash {
    param([string]$FilePath)
    
    if (-not [string]::IsNullOrEmpty($FilePath)) {
        if (Test-Path $FilePath) {
            $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
            return $hash.Hash
        } else {
            Write-Warning "File not found: $FilePath"
            return $null
        }
    } else {
        return $null
    }
}
```

### Module Organization

**Rule: One Module = One Responsibility**

```
GA-AppLocker/
|-- Modules/
|   |-- GA-AppLocker.Core/           # Shared utilities, logging, config
|   |   |-- GA-AppLocker.Core.psd1
|   |   |-- GA-AppLocker.Core.psm1
|   |   |-- Functions/
|   |   |   |-- Write-AppLockerLog.ps1
|   |   |   |-- Get-AppLockerConfig.ps1
|   |   |   +-- Test-Prerequisites.ps1
|   |
|   |-- GA-AppLocker.Discovery/      # AD and machine discovery
|   |   |-- Functions/
|   |   |   |-- Get-ADComputers.ps1
|   |   |   |-- Get-OUStructure.ps1
|   |   |   +-- Test-MachineConnectivity.ps1
|   |
|   |-- GA-AppLocker.Scanning/       # Artifact collection
|   |   |-- Functions/
|   |   |   |-- Get-LocalArtifacts.ps1
|   |   |   |-- Get-RemoteArtifacts.ps1
|   |   |   +-- Export-ScanResults.ps1
|   |
|   |-- GA-AppLocker.Rules/          # Rule generation
|   |   |-- Functions/
|   |   |   |-- New-PublisherRule.ps1
|   |   |   |-- New-HashRule.ps1
|   |   |   |-- ConvertTo-AppLockerXml.ps1
|   |   |   +-- Merge-AppLockerRules.ps1
|   |
|   |-- GA-AppLocker.Policy/         # Policy management
|   |   |-- Functions/
|   |   |   |-- Get-AppLockerPolicy.ps1
|   |   |   |-- Set-AppLockerPolicy.ps1
|   |   |   |-- Backup-AppLockerPolicy.ps1
|   |   |   +-- Import-PolicyToGPO.ps1
|   |
|   +-- GA-AppLocker.Credentials/    # Credential management
|       |-- Functions/
|       |   |-- Get-CredentialProfile.ps1
|       |   |-- Save-CredentialProfile.ps1
|       |   +-- Test-CredentialAccess.ps1
```

**Module Dependency Rules:**
- Core has no dependencies on other GA-AppLocker modules
- All other modules may depend on Core
- No circular dependencies
- Scanning depends on Discovery (needs machine list)
- Rules depends on Scanning (needs artifacts)
- Policy depends on Rules (needs rules to import)

```
[Core] <-- [Discovery] <-- [Scanning] <-- [Rules] <-- [Policy]
              ^                              |
              |                              |
        [Credentials] -----------------------+
```

### Error Handling Pattern

**Consistent Error Handling Across All Functions:**

```powershell
function Invoke-SomeOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target
    )
    
    # 1. Initialize result object
    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }
    
    try {
        # 2. Validate inputs (guard clauses)
        if (-not (Test-Prerequisite)) {
            $result.Error = "Prerequisite not met"
            return $result
        }
        
        # 3. Do the work
        $data = Do-ActualWork -Target $Target
        
        # 4. Return success
        $result.Success = $true
        $result.Data = $data
        return $result
    }
    catch {
        # 5. Handle errors consistently
        $result.Error = $_.Exception.Message
        Write-AppLockerLog -Level Error -Message "Operation failed: $($_.Exception.Message)"
        return $result
    }
}
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Functions | Verb-Noun (approved verbs) | `Get-Artifact`, `New-Rule`, `Test-Connection` |
| Variables | camelCase | `$artifactList`, `$scanResult`, `$isValid` |
| Constants | UPPER_SNAKE | `$MAX_RETRY_COUNT`, `$DEFAULT_TIMEOUT` |
| Parameters | PascalCase | `-FilePath`, `-Credential`, `-OutputDirectory` |
| Private functions | Verb-Noun (no export) | `Get-InternalCache`, `Format-RawData` |
| Classes | PascalCase | `Artifact`, `AppLockerRule`, `ScanResult` |
| Enums | PascalCase | `RuleType`, `MachineType`, `ScanStatus` |

**Approved PowerShell Verbs for This Project:**
- **Get** - Retrieve data
- **Set** - Modify existing
- **New** - Create new
- **Remove** - Delete
- **Test** - Check/validate (returns boolean or result)
- **Invoke** - Execute an action
- **Export** - Save to file
- **Import** - Load from file
- **ConvertTo** - Transform format
- **Initialize** - First-time setup
- **Backup** - Create backup copy
- **Restore** - Restore from backup

### Code Quality Checklist

Before committing any code, verify:

```
[ ] Function has single purpose
[ ] Function is <30 lines
[ ] Parameters are typed and validated
[ ] Return type is documented
[ ] Error handling follows standard pattern
[ ] No hardcoded values (use config/constants)
[ ] No duplicate logic (extract to shared function)
[ ] Variable names are descriptive
[ ] Comments explain WHY, not WHAT
[ ] Edge cases are handled
[ ] Works with empty/null inputs gracefully
```

### Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| God Function | 200+ line function doing everything | Break into focused functions |
| Magic Numbers | `if ($count -gt 50)` | Use constants: `if ($count -gt $MAX_BATCH_SIZE)` |
| Silent Failures | Empty catch blocks | Log errors, return error result |
| Stringly Typed | `$type = "Publisher"` everywhere | Use enums: `[RuleType]::Publisher` |
| Copy-Paste Code | Same logic in 5 places | Extract to shared function |
| Deep Nesting | 5+ levels of if/foreach | Use early returns, extract functions |
| Global State | `$script:data` everywhere | Pass data explicitly via parameters |
| Comment-Heavy | Comments explaining obvious code | Write self-documenting code |

### Testing Requirements

**Every public function needs:**

1. **Unit Test** - Tests function in isolation
2. **Edge Case Tests** - Empty input, null, invalid data
3. **Error Case Tests** - Verifies error handling works

```powershell
# Example test structure
Describe "Get-SignedArtifacts" {
    Context "With valid input" {
        It "Returns only signed artifacts" {
            $artifacts = @(
                [PSCustomObject]@{ Name = "app1.exe"; Publisher = @{ IsValid = $true } }
                [PSCustomObject]@{ Name = "app2.exe"; Publisher = @{ IsValid = $false } }
            )
            
            $result = Get-SignedArtifacts -Artifacts $artifacts
            
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be "app1.exe"
        }
    }
    
    Context "With empty input" {
        It "Returns empty array" {
            $result = Get-SignedArtifacts -Artifacts @()
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "With null input" {
        It "Returns empty array without error" {
            $result = Get-SignedArtifacts -Artifacts $null
            $result | Should -BeNullOrEmpty
        }
    }
}
```

### Documentation Standard

**Every function file includes:**

```powershell
<#
.SYNOPSIS
    Brief one-line description.

.DESCRIPTION
    Detailed explanation of what the function does and why.

.PARAMETER ParameterName
    Description of what this parameter does.

.EXAMPLE
    Get-Artifact -Path "C:\Program Files"
    
    Gets all artifacts from the specified path.

.EXAMPLE
    Get-Artifact -Path "C:\Program Files" -Recurse -Filter "*.exe"
    
    Gets all EXE files recursively.

.OUTPUTS
    [Artifact[]] Array of artifact objects.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>
function Get-Artifact {
    # Implementation
}
```

### Embedded Documentation & Inline Comments

**Philosophy: Code should be self-documenting with strategic comments**

Comments should explain WHY, not WHAT. The code shows what happens; comments explain the reasoning.

**Required Comment Locations:**

```powershell
#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Scanning

.DESCRIPTION
    Artifact collection module for local and remote machines.
    Collects executables, DLLs, scripts, and MSI files with
    publisher signatures and file hashes.

.DEPENDENCIES
    - GA-AppLocker.Core
    - GA-AppLocker.Discovery
    - GA-AppLocker.Credentials

.CHANGELOG
    2026-01-16  v1.0.0  Initial release
    2026-01-20  v1.0.1  Added DLL scanning support
    2026-02-01  v1.1.0  Added event log collection

.NOTES
    Air-gapped environment compatible.
    No external network dependencies.
#>
#endregion

#region ===== CONFIGURATION =====
# These values match STIG requirements for AppLocker scanning
# Reference: V-220848, V-220849
$script:CONFIG = @{
    # Maximum concurrent WinRM sessions (limited by DC resources)
    MaxConcurrentScans = 10
    
    # Timeout for individual machine scans (seconds)
    # 5 minutes allows for slow network segments
    ScanTimeoutSeconds = 300
    
    # Paths to scan for artifacts
    # Based on AppLocker best practices - covers 99% of legitimate software
    DefaultScanPaths = @(
        'C:\Program Files',
        'C:\Program Files (x86)',
        'C:\Windows\System32',
        'C:\Windows\SysWOW64'
    )
    
    # High-risk paths that need special attention
    # These locations are common malware execution points
    HighRiskPaths = @(
        '%USERPROFILE%\Downloads',
        '%USERPROFILE%\Desktop',
        '%TEMP%',
        '%LOCALAPPDATA%\Temp'
    )
}
#endregion

function Get-RemoteArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [Parameter(Mandatory)]
        [PSCredential]$Credential
    )
    
    #region --- Input Validation ---
    # Validate hostname format before attempting connection
    # Prevents wasted WinRM attempts on malformed input
    if ($ComputerName -notmatch '^[a-zA-Z0-9\-\.]+$') {
        Write-AppLockerLog -Level Warning -Message "Invalid hostname format: $ComputerName"
        return $null
    }
    #endregion
    
    #region --- Connection Setup ---
    # Use CredSSP if available for double-hop scenarios
    # Falls back to default auth if CredSSP not configured
    # Reference: https://docs.microsoft.com/en-us/powershell/scripting/learn/remoting/ps-remoting-second-hop
    $sessionOptions = @{
        ComputerName = $ComputerName
        Credential   = $Credential
        ErrorAction  = 'Stop'
    }
    #endregion
    
    try {
        # PERF: Single session for all operations reduces overhead
        # Testing showed 3x improvement vs multiple Enter-PSSession calls
        $session = New-PSSession @sessionOptions
        
        #region --- Artifact Collection ---
        # Collect in specific order: EXE first (most critical), then others
        # This ensures partial results are still useful if scan is interrupted
        
        # 1. Executables - Primary AppLocker target
        $exeArtifacts = Invoke-Command -Session $session -ScriptBlock {
            # Using Get-ChildItem with specific extensions is faster than
            # Get-AppLockerFileInformation for initial discovery
            Get-ChildItem -Path $using:paths -Include '*.exe' -Recurse -ErrorAction SilentlyContinue
        }
        
        # 2. DLLs - Secondary target, often overlooked attack vector
        # NOTE: DLL rules require "DLL rule collection" enabled in AppLocker
        $dllArtifacts = Invoke-Command -Session $session -ScriptBlock {
            Get-ChildItem -Path $using:paths -Include '*.dll' -Recurse -ErrorAction SilentlyContinue
        }
        #endregion
        
        # ... rest of implementation
    }
    catch {
        # Log full exception for troubleshooting but return clean error to caller
        # Stack trace helps identify if issue is auth, network, or WinRM config
        Write-AppLockerLog -Level Error -Message @"
Remote artifact collection failed
Computer: $ComputerName
Error: $($_.Exception.Message)
Stack: $($_.ScriptStackTrace)
"@
        return $null
    }
    finally {
        # CRITICAL: Always clean up sessions to prevent resource exhaustion
        # Leaked sessions can block subsequent connections to same host
        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }
    }
}
```

**Comment Types and When to Use:**

| Comment Type | When to Use | Example |
|--------------|-------------|---------|
| Module Header | Top of every .psm1 file | Module description, dependencies, changelog |
| Region Blocks | Group related code sections | `#region --- Validation ---` |
| Why Comments | Non-obvious decisions | `# Use CredSSP for double-hop scenarios` |
| Reference Comments | External docs/standards | `# Reference: STIG V-220848` |
| Performance Notes | Optimization explanations | `# PERF: Single session reduces overhead 3x` |
| Warning Comments | Gotchas and pitfalls | `# CRITICAL: Always clean up sessions` |
| TODO Comments | Planned improvements | `# TODO: Add retry logic for transient failures` |
| NOTE Comments | Important context | `# NOTE: DLL rules require explicit enablement` |

**Comments to AVOID:**

```powershell
# BAD - States the obvious
$count = 0  # Initialize count to zero

# BAD - Repeats the code
# Get the file hash
$hash = Get-FileHash -Path $file

# BAD - Outdated/wrong comment
# Returns array of strings
function Get-Items { return @{ Name = 'test' } }  # Actually returns hashtable!

# GOOD - Explains WHY
# Initialize to 0; -1 would indicate "not yet counted" in our state machine
$count = 0

# GOOD - Explains non-obvious behavior
# Get-FileHash returns $null for locked files, not an exception
$hash = Get-FileHash -Path $file
```

### Session Context Persistence

**Save development context with each coding session for continuity.**

Every coding session should save context to enable seamless handoff between sessions or developers.

**Session Context File Structure:**

```
GA-AppLocker/
|-- .context/
|   |-- SESSION_LOG.md              # Running log of all sessions
|   |-- CURRENT_STATE.md            # Current development state
|   |-- DECISIONS.md                # Architecture/design decisions
|   |-- BLOCKERS.md                 # Known issues and blockers
|   +-- NEXT_STEPS.md               # Prioritized task list
```

**SESSION_LOG.md Format:**

```markdown
# GA-AppLocker Development Session Log

## Session: 2026-01-16 14:30 - 17:45

### Summary
Implemented credential tier selection for WinRM scanning.

### What Was Done
- [x] Added CredentialProfile class to Core module
- [x] Implemented Get-CredentialForTier function
- [x] Updated Invoke-RemoteScan to use tier-based credentials
- [x] Added unit tests for credential selection logic

### Files Changed
- Modules/GA-AppLocker.Core/Classes/CredentialProfile.ps1 (NEW)
- Modules/GA-AppLocker.Credentials/Functions/Get-CredentialForTier.ps1 (NEW)
- Modules/GA-AppLocker.Scanning/Functions/Invoke-RemoteScan.ps1 (MODIFIED)
- Tests/Unit/Get-CredentialForTier.Tests.ps1 (NEW)

### Decisions Made
- Decision: Store credential profiles as encrypted JSON, not in registry
  - Reason: Easier backup/restore, portable between machines
  - Alternative considered: Windows Credential Manager
  - Why rejected: Harder to script, less transparent

### Issues Encountered
- WinRM double-hop issue when scanning from jumpbox
  - Workaround: Document CredSSP setup in prerequisites
  - TODO: Add Test-CredSSPConfiguration function

### Left Off At
- Credential selection working for Tier 0/1/2
- Need to add UI for credential profile management
- Next: Implement Save-CredentialProfile function

### Context for Next Session
The credential system now has the backend logic but no UI.
The CredentialProfile class is complete. Focus next on:
1. Save-CredentialProfile (encrypt and persist)
2. GUI panel for credential management
3. Integration with scan workflow

---

## Session: 2026-01-15 09:00 - 12:30
...
```

**CURRENT_STATE.md Format:**

```markdown
# GA-AppLocker Current Development State

**Last Updated:** 2026-01-16 17:45
**Current Phase:** Core Module Development
**Overall Progress:** 35%

## Module Status

| Module | Status | Completion | Notes |
|--------|--------|------------|-------|
| Core | In Progress | 70% | Logging, config done. Credentials WIP |
| Discovery | Not Started | 0% | Blocked on Core completion |
| Scanning | In Progress | 40% | Local scan done, remote WIP |
| Rules | Not Started | 0% | - |
| Policy | Not Started | 0% | - |
| Credentials | In Progress | 50% | Classes done, persistence WIP |
| GUI | Not Started | 0% | - |

## Current Working Branch
`feature/credential-tier-selection`

## Active Development Focus
Credential management system for tiered admin access.

## Ready for Testing
- Write-AppLockerLog
- Get-AppLockerConfig
- Get-LocalArtifacts

## Known Working Features
- Local artifact scanning
- Log file generation
- Configuration loading

## Known Broken/Incomplete
- Remote scanning (credential selection incomplete)
- No GUI yet
- No policy import yet
```

**DECISIONS.md Format:**

```markdown
# GA-AppLocker Architecture Decisions

## ADR-001: Use PowerShell Modules over Monolithic Script

**Date:** 2026-01-10
**Status:** Accepted

**Context:**
Need to organize codebase for maintainability and testing.

**Decision:**
Split into 6 PowerShell modules with clear responsibilities.

**Consequences:**
- (+) Each module testable in isolation
- (+) Clear dependency graph
- (+) Easier to maintain
- (-) More files to manage
- (-) Import order matters

---

## ADR-002: Credential Storage Method

**Date:** 2026-01-16
**Status:** Accepted

**Context:**
Need to persist credential profiles securely.

**Options Considered:**
1. Windows Credential Manager
2. Encrypted JSON files (DPAPI)
3. Registry with encryption

**Decision:**
Use encrypted JSON files with DPAPI.

**Rationale:**
- Portable (can backup/restore)
- Scriptable (easy to test)
- Transparent (can see what's stored)
- Secure (DPAPI tied to user/machine)

**Consequences:**
- (+) Easy backup/migration
- (+) Works in air-gapped environment
- (-) File-based (must handle corruption)
- (-) DPAPI tied to specific user account

---
```

**Auto-Save Context Script:**

```powershell
# Save-SessionContext.ps1
# Run at end of each development session

function Save-SessionContext {
    param(
        [string]$Summary,
        [string[]]$FilesChanged,
        [string]$LeftOffAt,
        [string]$NextSessionContext
    )
    
    $contextDir = Join-Path $PSScriptRoot '.context'
    if (-not (Test-Path $contextDir)) {
        New-Item -Path $contextDir -ItemType Directory | Out-Null
    }
    
    $sessionEntry = @"

---

## Session: $(Get-Date -Format 'yyyy-MM-dd HH:mm') - $(Get-Date -Format 'HH:mm')

### Summary
$Summary

### Files Changed
$($FilesChanged | ForEach-Object { "- $_" } | Out-String)

### Left Off At
$LeftOffAt

### Context for Next Session
$NextSessionContext

"@
    
    Add-Content -Path (Join-Path $contextDir 'SESSION_LOG.md') -Value $sessionEntry
    
    Write-Host "Session context saved!" -ForegroundColor Green
}

# Example usage:
# Save-SessionContext -Summary "Implemented credential selection" `
#                     -FilesChanged @("CredentialProfile.ps1", "Get-CredentialForTier.ps1") `
#                     -LeftOffAt "Credential selection working, need UI" `
#                     -NextSessionContext "Focus on Save-CredentialProfile and GUI panel"
```

### Domain Auto-Detection
- Runs on Domain Controller
- Auto-detects domain name (FQDN)
- Shows DC Admin Mode indicator
- Uses current session credentials

### OU-Based Grouping
- Machines categorized by OU path
- Workstation/Server/DC detection
- Separate policies per machine type
- Visual grouping summary

### Phase-Based Deployment

**Phase Definitions (Clarified):**

| Phase | Enforcement | Scope | Purpose |
|-------|-------------|-------|---------|
| **Phase 1** | AuditOnly | Pilot OU (10-50 machines) | Initial testing, identify issues |
| **Phase 2** | AuditOnly | Department OUs (100-500 machines) | Expanded validation |
| **Phase 3** | AuditOnly | All target OUs (full scope) | Final audit before enforcement |
| **Phase 4** | Enabled (Blocking) | All target OUs | Production enforcement |

**Phase Transition Checklist:**
```
Phase 1 -> Phase 2:
  [ ] Zero critical audit events for 7+ days
  [ ] All pilot users validated
  [ ] No help desk tickets related to AppLocker

Phase 2 -> Phase 3:
  [ ] Zero critical audit events for 14+ days
  [ ] Department leads signed off
  [ ] Rollback plan documented

Phase 3 -> Phase 4:
  [ ] Zero audit events for 30+ days
  [ ] Change management approval
  [ ] Support team trained
  [ ] Emergency rollback tested
```

**Note:** The `enforcementMode` in Policy object is automatically derived from Phase:
- Phase 1-3: `enforcementMode = "AuditOnly"`
- Phase 4: `enforcementMode = "Enabled"`

---

## [LOCK] Multi-Administrator Handling

### Concurrent Access Scenarios

When multiple administrators use GA-AppLocker simultaneously:

#### Scenario 1: Simultaneous Scans
| Risk | Impact | Mitigation |
|------|--------|------------|
| Duplicate scans to same machine | Wasted resources, confusing results | Lock machine during scan |
| Conflicting credentials | Scan failures | Credential lock per tier |

#### Scenario 2: Simultaneous Policy Edits
| Risk | Impact | Mitigation |
|------|--------|------------|
| Overwriting each other's changes | Lost work | File lock on policy draft |
| Conflicting rule additions | Inconsistent policy | Merge conflict detection |

#### Scenario 3: Simultaneous Deployments
| Risk | Impact | Mitigation |
|------|--------|------------|
| GPO corruption | Broken policy | GPO lock during deployment |
| Replication conflicts | Inconsistent policy across DCs | Single deployment at a time |

### Lock File Mechanism

```powershell
# Lock file structure
# Location: %LOCALAPPDATA%\GA-AppLocker\locks\

# Machine scan lock
$machineLock = @{
    LockFile = "scan_WS001.lock"
    Content = @{
        MachineName = "WS001"
        LockedBy    = "CORP\admin1"
        LockedAt    = "2026-01-16T14:30:00Z"
        Operation   = "ArtifactScan"
        Expires     = "2026-01-16T14:35:00Z"  # 5-minute timeout
    }
}

# GPO deployment lock
$gpoLock = @{
    LockFile = "deploy_Workstation-Policy.lock"
    Content = @{
        PolicyName  = "Workstation-Policy"
        TargetGPO   = "AppLocker-Workstations"
        LockedBy    = "CORP\admin1"
        LockedAt    = "2026-01-16T14:30:00Z"
        Operation   = "GPODeployment"
        Expires     = "2026-01-16T14:40:00Z"  # 10-minute timeout
    }
}
```

### Lock Management Functions

```powershell
function Request-OperationLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Scan', 'Deploy', 'PolicyEdit')]
        [string]$OperationType,
        
        [Parameter(Mandatory)]
        [string]$ResourceName,
        
        [Parameter()]
        [int]$TimeoutMinutes = 5
    )
    
    $lockDir = Join-Path $env:LOCALAPPDATA "GA-AppLocker\locks"
    $lockFile = Join-Path $lockDir "$($OperationType)_$($ResourceName).lock"
    
    # Check for existing lock
    if (Test-Path $lockFile) {
        $existingLock = Get-Content $lockFile | ConvertFrom-Json
        
        # Check if lock expired
        if ([datetime]$existingLock.Expires -gt (Get-Date)) {
            return [PSCustomObject]@{
                Success    = $false
                LockedBy   = $existingLock.LockedBy
                LockedAt   = $existingLock.LockedAt
                Message    = "Resource locked by $($existingLock.LockedBy) since $($existingLock.LockedAt)"
            }
        }
        
        # Lock expired, remove it
        Remove-Item $lockFile -Force
    }
    
    # Create new lock
    $lockContent = @{
        ResourceName = $ResourceName
        LockedBy     = "$env:USERDOMAIN\$env:USERNAME"
        LockedAt     = (Get-Date -Format 'o')
        Operation    = $OperationType
        Expires      = (Get-Date).AddMinutes($TimeoutMinutes).ToString('o')
    }
    
    $lockContent | ConvertTo-Json | Set-Content $lockFile
    
    return [PSCustomObject]@{
        Success  = $true
        LockFile = $lockFile
        Expires  = $lockContent.Expires
    }
}

function Release-OperationLock {
    param(
        [string]$OperationType,
        [string]$ResourceName
    )
    
    $lockFile = Join-Path $env:LOCALAPPDATA "GA-AppLocker\locks" "$($OperationType)_$($ResourceName).lock"
    
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force
    }
}
```

### UI Lock Indicators

```
+-----------------------------------------------------------------------------+
| DEPLOYMENT                                                                   |
+-----------------------------------------------------------------------------+
|                                                                             |
| [!] WARNING: Another administrator is currently deploying to this GPO      |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | Locked by: CORP\admin2                                                  | |
| | Operation: GPO Deployment                                               | |
| | Started: 2026-01-16 14:30:22                                           | |
| | Expires: 2026-01-16 14:40:22 (8 minutes remaining)                     | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| Options:                                                                    |
| [ ] Wait for lock to release (auto-retry)                                  |
| [ ] Force override (DANGEROUS - may corrupt GPO)                           |
|                                                                             |
| [Cancel]  [Wait]  [Force Override - Requires Confirmation]                 |
+-----------------------------------------------------------------------------+
```

### Best Practice: Single Admin Per Domain

**Recommendation for v1.0:** Only one administrator should actively use GA-AppLocker per domain at any time.

**Future Enhancement (v2.0):** Central management server with proper concurrency control and change queuing.

---

## [LIST] Documented Assumptions

### Environment Assumptions

| Assumption | Details | Impact if False |
|------------|---------|-----------------|
| **Single Forest** | v1.0 supports single AD forest only | Cross-forest scans will fail |
| **Windows Domain** | All targets are domain-joined Windows machines | Workgroup machines won't scan |
| **DNS Resolution** | All hostnames resolvable via DNS | Scans fail with DNS errors |
| **Time Sync** | Kerberos requires <5 minute time drift | Authentication failures |
| **English AD** | AD object names may contain Unicode | App handles Unicode properly |
| **NTFS File System** | Target drives are NTFS | Hash collection may fail on FAT32 |

### Service Assumptions

| Assumption | Details | Verification |
|------------|---------|--------------|
| **WinRM Enabled** | WinRM service running on targets | `Test-WinRMReadiness` function |
| **AppIdentity Running** | Application Identity service enabled | Check during scan |
| **RSAT Installed** | AD/GPO modules available | Startup prerequisite check |
| **Firewall Open** | TCP 5985/5986 allowed | Port connectivity test |

### Permission Assumptions

| Assumption | Details | Required For |
|------------|---------|--------------|
| **Local Admin (App Machine)** | User is local admin where app runs | WinRM operations |
| **Remote Admin (Targets)** | Appropriate tier credentials | Artifact scanning |
| **Domain Admin or Delegated** | GPO creation/modification rights | Policy deployment |
| **SYSVOL Write** | Write access to \\domain\SYSVOL | GPO file updates |

### Verification at Startup

```powershell
function Test-Prerequisites {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    $results = [PSCustomObject]@{
        AllPassed     = $true
        Checks        = @()
    }
    
    # Check 1: Required PowerShell modules
    $requiredModules = @('ActiveDirectory', 'GroupPolicy')
    foreach ($module in $requiredModules) {
        $check = [PSCustomObject]@{
            Name    = "Module: $module"
            Passed  = $false
            Message = ""
        }
        
        if (Get-Module -ListAvailable -Name $module) {
            $check.Passed = $true
            $check.Message = "Installed"
        }
        else {
            $check.Message = "Not installed. Run: Add-WindowsCapability -Online -Name Rsat.*"
            $results.AllPassed = $false
        }
        
        $results.Checks += $check
    }
    
    # Check 2: Local admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $results.Checks += [PSCustomObject]@{
        Name    = "Local Administrator"
        Passed  = $isAdmin
        Message = if ($isAdmin) { "Yes" } else { "Run as Administrator required" }
    }
    if (-not $isAdmin) { $results.AllPassed = $false }
    
    # Check 3: Domain membership
    $isDomainJoined = (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain
    $results.Checks += [PSCustomObject]@{
        Name    = "Domain Joined"
        Passed  = $isDomainJoined
        Message = if ($isDomainJoined) { (Get-WmiObject Win32_ComputerSystem).Domain } else { "Not domain joined" }
    }
    if (-not $isDomainJoined) { $results.AllPassed = $false }
    
    # Check 4: .NET Framework version
    $netVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
    $netOk = $netVersion -ge 461808  # 4.7.2
    $results.Checks += [PSCustomObject]@{
        Name    = ".NET Framework 4.7.2+"
        Passed  = $netOk
        Message = if ($netOk) { "Version $netVersion" } else { "Update required" }
    }
    if (-not $netOk) { $results.AllPassed = $false }
    
    return $results
}
```
- Automatic mode selection based on phase
- Override option for advanced users

### GPO-to-OU Auto-Linking
- Create GPO if doesn't exist
- Link GPO to multiple OUs
- One-click deployment
- Backup existing policies

### Smart Group Assignment
- Auto-suggest security groups based on artifact analysis
- Path-based detection (Windows, Program Files, Admin tools)
- Publisher-based detection (Microsoft, known vendors, unsigned)
- Machine type context (Workstation, Server, DC)
- Rule type context (EXE/DLL broader, Script/MSI restrictive)
- Group templates for common scenarios
- Custom group mapping profiles
- Override capability for all suggestions

---

## [DEPLOY] End-to-End Workflow

1. **Scan AD** -> Auto-detect domain, discover machines by OU
2. **Scan Machines** -> Collect artifacts via WinRM (with credential switching)
3. **Import Artifacts** -> CSV/JSON/Comprehensive scan with deduplication
4. **Auto-Generate Rules** -> Publisher -> Hash priority (best practices)
5. **Smart Group Assignment** -> Auto-suggest allow groups based on path, publisher, machine type
6. **Group by Machine Type** -> Auto-categorize Workstations/Servers/DCs by OU
7. **Merge Policies** -> Combine policies with conflict resolution
8. **Create Policy** -> Generate XML with validation
9. **Deploy to OU** -> Create GPO, link to OUs, set phase enforcement

---

## [CHART] Module Summary

| Module | Purpose |
|--------|---------|
| AD Discovery | Scan AD for hosts and OUs |
| Artifact Scanner | Collect AppLocker-relevant artifacts from hosts |
| Import/Ingestion | Multi-format artifact import with deduplication |
| Rule Generator | Auto-create rules using best practices |
| Group Assignment | Smart security group suggestions for allow rules |
| Policy Merger | Combine rules by machine type |
| Policy Builder | Create and validate policy XML |
| Deployment | Apply policies to OUs with phase-based enforcement |

---

## [SCHEMA] Data Models & Schemas

### Artifact Object
```
Artifact {
  id: string (GUID)
  fileName: string
  filePath: string
  fileHash: string (SHA256)
  publisher: string | null
  productName: string | null
  version: string | null
  isSigned: boolean
  signatureStatus: "Valid" | "Invalid" | "NotSigned" | "Unknown"
  fileType: "EXE" | "DLL" | "MSI" | "Script" | "Appx"
  fileSize: number (bytes)
  lastModified: datetime
  sourceHost: string
  sourceMachineType: "Workstation" | "Server" | "DomainController" | "Unknown"
  sourceOU: string
  scanDate: datetime
  metadata: object (extensible)
}
```

### Rule Object
```
Rule {
  id: string (GUID)
  name: string
  description: string
  ruleType: "Publisher" | "Hash" | "Path"
  ruleCollection: "Exe" | "Msi" | "Script" | "Dll" | "Appx"
  action: "Allow" | "Deny"
  userOrGroupSid: string
  userOrGroupName: string
  enforcementMode: "Enabled" | "AuditOnly" | "NotConfigured"
  conditions: RuleCondition[]
  exceptions: RuleException[]
  sourceArtifacts: string[] (artifact IDs)
  createdDate: datetime
  createdBy: string
  isAutoGenerated: boolean
  templateSource: string | null
}
```

### Policy Object
```
Policy {
  id: string (GUID)
  name: string
  description: string
  version: string
  machineType: "Workstation" | "Server" | "DomainController" | "All"
  phase: 1 | 2 | 3 | 4
  enforcementMode: "Enabled" | "AuditOnly"
  ruleCollections: {
    exe: Rule[]
    msi: Rule[]
    script: Rule[]
    dll: Rule[]
    appx: Rule[]
  }
  targetOUs: string[]
  linkedGPOs: string[]
  createdDate: datetime
  lastModified: datetime
  exportedXML: string | null
  validationStatus: "Valid" | "Invalid" | "NotValidated"
  validationErrors: string[]
}
```

### Machine Object
```
Machine {
  id: string (GUID)
  hostname: string
  fqdn: string
  ipAddress: string
  operatingSystem: string
  osVersion: string
  machineType: "Workstation" | "Server" | "DomainController" | "Unknown"
  ouPath: string
  ouName: string
  domain: string
  isOnline: boolean
  lastSeen: datetime
  winRMStatus: "Available" | "Unavailable" | "Unknown"
  lastScanDate: datetime | null
  artifactCount: number
}
```

### Scan Job Object
```
ScanJob {
  id: string (GUID)
  status: "Pending" | "Running" | "Completed" | "Failed" | "Cancelled"
  targetMachines: string[] (machine IDs)
  totalMachines: number
  completedMachines: number
  failedMachines: number
  startTime: datetime
  endTime: datetime | null
  credentialId: string
  scanOptions: ScanOptions
  results: ScanResult[]
  errors: ScanError[]
}
```

### Credential Profile Object
```
CredentialProfile {
  id: string (GUID)
  name: string
  description: string
  username: string
  domain: string
  targetEnvironment: "Workstation" | "Server" | "DomainController" | "All"
  isDefault: boolean
  lastUsed: datetime | null
  lastValidated: datetime | null
  validationStatus: "Valid" | "Invalid" | "Unknown"
}
```

### Group Mapping Object
```
GroupMapping {
  id: string (GUID)
  name: string
  priority: number (lower = higher priority)
  matchType: "Path" | "Publisher" | "RuleType" | "MachineType" | "Category"
  matchPattern: string (regex or exact match)
  assignedGroup: string (SID or name)
  assignedGroupName: string
  isEnabled: boolean
}
```

---

## [SYNC] Data Interoperability & Field Mapping

This section defines how artifact data flows from various sources through normalization to rule generation, ensuring consistent and reliable rule creation regardless of input format.

### Data Pipeline Overview

```
+-----------------------------------------------------------------------------+
|                        ARTIFACT DATA PIPELINE                               |
+-----------------------------------------------------------------------------+

  +--------------+    +--------------+    +--------------+    +--------------+
  |   INGEST     |---[>]|  NORMALIZE   |---[>]|   ENRICH     |---[>]|   VALIDATE   |
  |              |    |              |    |              |    |              |
  | - CSV        |    | - Field Map  |    | - Lookup     |    | - Required   |
  | - JSON       |    | - Type Cast  |    | - Derive     |    | - Format     |
  | - WinRM Scan |    | - Dedupe     |    | - Categorize |    | - Integrity  |
  | - Event Log  |    | - Merge      |    |              |    |              |
  +--------------+    +--------------+    +--------------+    +--------------+
                                                                      |
                                                                      [v]
  +--------------+    +--------------+    +--------------+    +--------------+
  |   OUTPUT     |<---|   GENERATE   |<---|   DECIDE     |<---|    STORE     |
  |              |    |              |    |              |    |              |
  | - Policy XML |    | - Publisher  |    | - Rule Type  |    | - Inventory  |
  | - Report     |    | - Hash       |    | - Group      |    | - Index      |
  | - Export     |    | - Path       |    | - Priority   |    | - Cache      |
  +--------------+    +--------------+    +--------------+    +--------------+
```

### Canonical Artifact Schema (Internal Standard)

All ingested data is normalized to this canonical schema before processing:

```typescript
interface CanonicalArtifact {
  // === IDENTITY (Required for deduplication) ===
  id: string;                    // Generated GUID
  fileHash_SHA256: string;       // Primary dedup key
  fileHash_SHA1?: string;        // Secondary hash
  fileHash_MD5?: string;         // Legacy hash (not used for rules)
  
  // === FILE INFO (Required) ===
  fileName: string;              // e.g., "chrome.exe"
  fileExtension: string;         // e.g., ".exe" (normalized lowercase)
  filePath: string;              // Full path on source machine
  fileSize: number;              // Bytes
  
  // === PUBLISHER INFO (For Publisher Rules) ===
  publisher: {
    name: string | null;         // e.g., "O=GOOGLE LLC, L=MOUNTAIN VIEW, S=CA, C=US"
    commonName: string | null;   // e.g., "Google LLC" (extracted)
    isValid: boolean;            // Signature validation status
    signatureStatus: SignatureStatus;
    certificateThumbprint?: string;
    certificateExpiry?: datetime;
  };
  
  // === PRODUCT INFO (For Publisher Rules) ===
  product: {
    name: string | null;         // e.g., "Google Chrome"
    description: string | null;  // File description from version info
    company: string | null;      // Company name from version info
    version: string | null;      // e.g., "120.0.6099.130"
    versionMajor?: number;       // Parsed: 120
    versionMinor?: number;       // Parsed: 0
    versionBuild?: number;       // Parsed: 6099
    versionRevision?: number;    // Parsed: 130
    originalFileName?: string;   // Original filename from manifest
    internalName?: string;       // Internal name from manifest
  };
  
  // === CLASSIFICATION ===
  fileType: FileType;            // EXE, DLL, MSI, Script, Appx
  category: ArtifactCategory;    // CoreOS, Enterprise, Admin, Dev, Security, Custom
  riskLevel: RiskLevel;          // Low, Medium, High, Critical
  
  // === SOURCE INFO ===
  source: {
    hostname: string;            // Machine scanned
    machineType: MachineType;    // Workstation, Server, DC
    ouPath: string;              // OU path of source machine
    domain: string;              // Domain name
    scanDate: datetime;          // When artifact was collected
    scanMethod: ScanMethod;      // WinRM, Local, Import
    importSource?: string;       // Original file if imported
  };
  
  // === RULE GENERATION HINTS ===
  ruleHints: {
    recommendedRuleType: RuleType;     // Publisher, Hash, Path
    recommendedGroup: string;           // SID or group name
    recommendedGroupReason: string;     // Why this group
    canUsePublisher: boolean;           // Has valid signature
    canUseHash: boolean;                // Has valid hash
    requiresReview: boolean;            // Flagged for manual review
    reviewReasons: string[];            // Why review needed
  };
  
  // === METADATA ===
  metadata: {
    createdAt: datetime;
    updatedAt: datetime;
    importedFrom?: string;
    tags: string[];
    notes: string;
    customFields: Record<string, any>;
  };
}

// Enums
enum SignatureStatus {
  Valid = "Valid",
  Invalid = "Invalid", 
  Expired = "Expired",
  NotSigned = "NotSigned",
  NotTrusted = "NotTrusted",
  Unknown = "Unknown"
}

enum FileType {
  EXE = "EXE",
  DLL = "DLL",
  MSI = "MSI",
  Script = "Script",    // .ps1, .bat, .cmd, .vbs, .js
  Appx = "Appx"
}

enum ArtifactCategory {
  CoreOS = "CoreOS",
  Enterprise = "Enterprise",
  Admin = "Admin",
  Dev = "Dev",
  Security = "Security",
  Custom = "Custom",
  Unknown = "Unknown"
}

enum RiskLevel {
  Low = "Low",
  Medium = "Medium",
  High = "High",
  Critical = "Critical"
}

enum MachineType {
  Workstation = "Workstation",
  Server = "Server",
  DomainController = "DomainController",
  Unknown = "Unknown"
}

enum ScanMethod {
  WinRM = "WinRM",
  Local = "Local",
  CSV = "CSV",
  JSON = "JSON",
  EventLog = "EventLog"
}

enum RuleType {
  Publisher = "Publisher",
  Hash = "Hash",
  Path = "Path"
}
```

### Input Format Field Mappings

#### WinRM Scan Output -> Canonical Schema

```powershell
# Raw WinRM scan output from Get-AppLockerFileInformation
$rawArtifact = @{
    Path           = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    Publisher      = @{
        PublisherName  = "O=GOOGLE LLC, L=MOUNTAIN VIEW, S=CA, C=US"
        ProductName    = "Google Chrome"
        BinaryName     = "CHROME.EXE"
        BinaryVersion  = "120.0.6099.130"
    }
    Hash           = @{
        HashType       = "SHA256"
        HashValue      = "0xABC123..."
        SourceFileName = "chrome.exe"
        SourceFileLength = 3456789
    }
}
```

**Field Mapping:**
| WinRM Field | Canonical Field | Transform |
|-------------|-----------------|-----------|
| `Path` | `filePath` | Direct |
| `Path` | `fileName` | Extract filename via `Split-Path -Leaf` |
| `Path` | `fileExtension` | Extract extension, lowercase |
| `Publisher.PublisherName` | `publisher.name` | Direct |
| `Publisher.PublisherName` | `publisher.commonName` | Extract CN via regex |
| `Publisher.ProductName` | `product.name` | Direct |
| `Publisher.BinaryName` | `product.originalFileName` | Direct |
| `Publisher.BinaryVersion` | `product.version` | Direct |
| `Publisher.BinaryVersion` | `product.versionMajor/Minor/Build/Revision` | Parse "x.x.x.x" |
| `Hash.HashValue` | `fileHash_SHA256` | Remove "0x" prefix, uppercase |
| `Hash.SourceFileLength` | `fileSize` | Direct |
| (computed) | `publisher.isValid` | Check if PublisherName exists and valid |
| (computed) | `ruleHints.canUsePublisher` | `publisher.isValid && publisher.name != null` |

#### CSV Import -> Canonical Schema

**Supported CSV Column Names (case-insensitive, with aliases):**

| Canonical Field | Accepted CSV Headers |
|-----------------|---------------------|
| `filePath` | `Path`, `FilePath`, `FullPath`, `FullName`, `Location` |
| `fileName` | `Name`, `FileName`, `File`, `Binary`, `BinaryName` |
| `fileHash_SHA256` | `SHA256`, `Hash`, `FileHash`, `SHA256Hash`, `Thumbprint` |
| `fileHash_SHA1` | `SHA1`, `SHA1Hash` |
| `publisher.name` | `Publisher`, `PublisherName`, `Signer`, `SignerName`, `Certificate` |
| `product.name` | `Product`, `ProductName`, `Application`, `AppName` |
| `product.version` | `Version`, `FileVersion`, `ProductVersion`, `Ver` |
| `product.company` | `Company`, `CompanyName`, `Vendor`, `Manufacturer` |
| `product.description` | `Description`, `FileDescription`, `Desc` |
| `fileSize` | `Size`, `FileSize`, `Length`, `Bytes` |
| `source.hostname` | `Host`, `Hostname`, `Computer`, `ComputerName`, `Machine`, `Source` |
| `publisher.signatureStatus` | `Signed`, `IsSigned`, `SignatureStatus`, `SignatureValid` |

**CSV Parsing Rules:**
```typescript
function parseCSVArtifact(row: CSVRow): CanonicalArtifact {
  return {
    // Identity
    id: generateGUID(),
    fileHash_SHA256: normalizeHash(
      row['SHA256'] || row['Hash'] || row['FileHash'] || null
    ),
    
    // File Info
    fileName: row['Name'] || row['FileName'] || extractFileName(row['Path']),
    filePath: row['Path'] || row['FilePath'] || row['FullPath'],
    fileExtension: extractExtension(row['Name'] || row['Path']).toLowerCase(),
    fileSize: parseInt(row['Size'] || row['FileSize'] || '0'),
    
    // Publisher
    publisher: {
      name: row['Publisher'] || row['PublisherName'] || null,
      commonName: extractCommonName(row['Publisher']),
      isValid: parseBoolean(row['Signed'] || row['IsSigned'], false),
      signatureStatus: mapSignatureStatus(row['SignatureStatus'] || row['Signed'])
    },
    
    // Product
    product: {
      name: row['Product'] || row['ProductName'] || null,
      version: row['Version'] || row['FileVersion'] || null,
      company: row['Company'] || row['CompanyName'] || null,
      description: row['Description'] || null,
      ...parseVersion(row['Version'])
    },
    
    // Classification (derived)
    fileType: classifyFileType(row['Name'] || row['Path']),
    category: ArtifactCategory.Unknown,  // Enriched later
    riskLevel: RiskLevel.Medium,          // Enriched later
    
    // Source
    source: {
      hostname: row['Host'] || row['Hostname'] || row['Computer'] || 'IMPORTED',
      machineType: MachineType.Unknown,
      ouPath: '',
      domain: '',
      scanDate: new Date(),
      scanMethod: ScanMethod.CSV,
      importSource: csvFileName
    },
    
    // Rule hints (computed after normalization)
    ruleHints: computeRuleHints(artifact)
  };
}
```

#### JSON Import -> Canonical Schema

**Supported JSON Structures:**

**Format A: Flat Array**
```json
{
  "artifacts": [
    {
      "path": "C:\\Program Files\\App\\app.exe",
      "hash": "ABC123...",
      "publisher": "Vendor Inc.",
      "product": "App Name",
      "version": "1.0.0",
      "signed": true
    }
  ]
}
```

**Format B: Nested Objects**
```json
{
  "scanResults": {
    "hostname": "WORKSTATION01",
    "scanDate": "2026-01-16T12:00:00Z",
    "items": [
      {
        "file": {
          "path": "C:\\Program Files\\App\\app.exe",
          "name": "app.exe",
          "size": 12345
        },
        "signature": {
          "publisher": "O=Vendor Inc., C=US",
          "product": "App Name",
          "version": "1.0.0",
          "isValid": true
        },
        "hashes": {
          "sha256": "ABC123...",
          "sha1": "DEF456..."
        }
      }
    ]
  }
}
```

**Format C: AppLocker Native Export**
```json
{
  "AppLockerFileInformation": [
    {
      "Path": "C:\\Program Files\\App\\app.exe",
      "Publisher": {
        "PublisherName": "O=VENDOR INC., C=US",
        "ProductName": "APP NAME",
        "BinaryName": "APP.EXE",
        "BinaryVersion": "1.0.0.0"
      },
      "Hash": {
        "SHA256": "ABC123...",
        "SHA1": "DEF456..."
      }
    }
  ]
}
```

**JSON Field Resolution Order:**
```typescript
function resolveJSONField(obj: any, ...paths: string[]): any {
  for (const path of paths) {
    const value = getNestedValue(obj, path);
    if (value !== undefined && value !== null && value !== '') {
      return value;
    }
  }
  return null;
}

// Example: Resolve file path from multiple possible locations
const filePath = resolveJSONField(item,
  'path',
  'Path', 
  'filePath',
  'FilePath',
  'file.path',
  'file.Path',
  'FullPath',
  'Location'
);
```

#### Event Log (8003/8004) -> Canonical Schema

```powershell
# Raw event log entry
$event = @{
    Id = 8004
    TimeCreated = "2026-01-16T10:30:00Z"
    Message = "chrome.exe was prevented from running."
    Properties = @(
        @{ Name = "FilePath"; Value = "C:\Program Files\Google\Chrome\Application\chrome.exe" }
        @{ Name = "FileHash"; Value = "SHA256:ABC123..." }
        @{ Name = "Fqbn"; Value = "O=GOOGLE LLC\GOOGLE CHROME\CHROME.EXE\120.0.6099.130" }
        @{ Name = "TargetUser"; Value = "DOMAIN\user" }
        @{ Name = "PolicyName"; Value = "EXE" }
    )
}
```

**Field Mapping:**
| Event Field | Canonical Field | Transform |
|-------------|-----------------|-----------|
| `Properties[FilePath]` | `filePath` | Direct |
| `Properties[FilePath]` | `fileName` | Extract filename |
| `Properties[FileHash]` | `fileHash_SHA256` | Remove "SHA256:" prefix |
| `Properties[Fqbn]` | `publisher.name` | Extract publisher segment |
| `Properties[Fqbn]` | `product.name` | Extract product segment |
| `Properties[Fqbn]` | `product.version` | Extract version segment |
| `Properties[PolicyName]` | `fileType` | Map: EXE->EXE, MSI->MSI, Script->Script, DLL->DLL |
| `Id` | `metadata.eventId` | Direct (8003=audit, 8004=blocked) |
| `TimeCreated` | `source.scanDate` | Direct |

**FQBN (Fully Qualified Binary Name) Parsing:**
```typescript
// FQBN format: "O=PUBLISHER\PRODUCT\BINARY\VERSION"
function parseFQBN(fqbn: string): Partial<CanonicalArtifact> {
  const parts = fqbn.split('\\');
  return {
    publisher: { name: parts[0] || null },
    product: { 
      name: parts[1] || null,
      originalFileName: parts[2] || null,
      version: parts[3] || null
    }
  };
}
```

### Data Normalization Rules

#### Hash Normalization
```typescript
function normalizeHash(hash: string | null): string | null {
  if (!hash) return null;
  
  // Remove common prefixes
  let normalized = hash
    .replace(/^0x/i, '')
    .replace(/^SHA256:/i, '')
    .replace(/^SHA1:/i, '')
    .replace(/^MD5:/i, '');
  
  // Remove spaces and dashes
  normalized = normalized.replace(/[\s-]/g, '');
  
  // Uppercase
  normalized = normalized.toUpperCase();
  
  // Validate length (SHA256 = 64 chars, SHA1 = 40 chars)
  if (normalized.length === 64 || normalized.length === 40) {
    return normalized;
  }
  
  return null;  // Invalid hash
}
```

#### Publisher Name Normalization
```typescript
function normalizePublisher(publisher: string | null): NormalizedPublisher {
  if (!publisher) return { name: null, commonName: null };
  
  // Handle various formats:
  // "O=GOOGLE LLC, L=MOUNTAIN VIEW, S=CA, C=US"
  // "Google LLC"
  // "CN=Google LLC, O=Google LLC"
  
  let name = publisher.trim();
  let commonName: string | null = null;
  
  // Extract CN if present
  const cnMatch = name.match(/CN=([^,]+)/i);
  if (cnMatch) {
    commonName = cnMatch[1].trim();
  }
  
  // Extract O= if present (primary identifier)
  const oMatch = name.match(/O=([^,]+)/i);
  if (oMatch) {
    commonName = commonName || oMatch[1].trim();
  }
  
  // If no structured format, use as-is
  if (!cnMatch && !oMatch) {
    commonName = name;
  }
  
  // Normalize common variations
  commonName = normalizeCompanyName(commonName);
  
  return { name, commonName };
}

function normalizeCompanyName(name: string | null): string | null {
  if (!name) return null;
  
  // Remove common suffixes for grouping
  return name
    .replace(/,?\s*(Inc\.?|LLC|Ltd\.?|Corp\.?|Corporation|Company)$/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}
```

#### Version Normalization
```typescript
interface ParsedVersion {
  version: string;
  versionMajor: number | null;
  versionMinor: number | null;
  versionBuild: number | null;
  versionRevision: number | null;
}

function parseVersion(version: string | null): ParsedVersion {
  if (!version) {
    return { version: '*', versionMajor: null, versionMinor: null, versionBuild: null, versionRevision: null };
  }
  
  // Handle various formats: "1.0", "1.0.0", "1.0.0.0", "v1.0", "1.0-beta"
  const cleaned = version.replace(/^v/i, '').split('-')[0].split('+')[0];
  const parts = cleaned.split('.').map(p => parseInt(p, 10));
  
  return {
    version: cleaned,
    versionMajor: isNaN(parts[0]) ? null : parts[0],
    versionMinor: isNaN(parts[1]) ? null : parts[1],
    versionBuild: isNaN(parts[2]) ? null : parts[2],
    versionRevision: isNaN(parts[3]) ? null : parts[3]
  };
}
```

#### Path Normalization
```typescript
function normalizePath(path: string): NormalizedPath {
  // Normalize separators
  let normalized = path.replace(/\//g, '\\');
  
  // Expand environment variables for display
  const envExpanded = expandEnvironmentVariables(normalized);
  
  // Detect path type
  const pathType = detectPathType(normalized);
  
  // Extract components
  const fileName = normalized.split('\\').pop() || '';
  const directory = normalized.substring(0, normalized.length - fileName.length - 1);
  const extension = fileName.includes('.') ? '.' + fileName.split('.').pop()?.toLowerCase() : '';
  
  return {
    original: path,
    normalized,
    envExpanded,
    pathType,
    fileName,
    directory,
    extension
  };
}

enum PathType {
  ProgramFiles = "ProgramFiles",       // C:\Program Files\*
  ProgramFilesX86 = "ProgramFilesX86", // C:\Program Files (x86)\*
  Windows = "Windows",                  // C:\Windows\*
  System32 = "System32",               // C:\Windows\System32\*
  UserProfile = "UserProfile",         // C:\Users\*
  AppData = "AppData",                 // %APPDATA%, %LOCALAPPDATA%
  Temp = "Temp",                       // %TEMP%
  Downloads = "Downloads",             // Downloads folder
  UNC = "UNC",                         // \\server\share\*
  Removable = "Removable",             // D:\, E:\ (non-system drives)
  Other = "Other"
}
```

### Deduplication Strategy

```typescript
interface DeduplicationResult {
  unique: CanonicalArtifact[];
  duplicates: DuplicateGroup[];
  stats: {
    totalInput: number;
    uniqueOutput: number;
    duplicatesFound: number;
  };
}

interface DuplicateGroup {
  primaryKey: string;
  artifacts: CanonicalArtifact[];
  keptArtifact: CanonicalArtifact;
  mergedFrom: string[];  // Source IDs that were merged
}

function deduplicateArtifacts(artifacts: CanonicalArtifact[]): DeduplicationResult {
  const seen = new Map<string, CanonicalArtifact[]>();
  
  for (const artifact of artifacts) {
    // Primary dedup key: SHA256 hash
    const primaryKey = artifact.fileHash_SHA256;
    
    if (primaryKey) {
      if (!seen.has(primaryKey)) {
        seen.set(primaryKey, []);
      }
      seen.get(primaryKey)!.push(artifact);
    } else {
      // No hash - use secondary key: normalized path + size
      const secondaryKey = `${artifact.filePath.toLowerCase()}|${artifact.fileSize}`;
      if (!seen.has(secondaryKey)) {
        seen.set(secondaryKey, []);
      }
      seen.get(secondaryKey)!.push(artifact);
    }
  }
  
  const unique: CanonicalArtifact[] = [];
  const duplicates: DuplicateGroup[] = [];
  
  for (const [key, group] of seen) {
    if (group.length === 1) {
      unique.push(group[0]);
    } else {
      // Merge duplicates - prefer artifact with most complete data
      const merged = mergeArtifacts(group);
      unique.push(merged);
      duplicates.push({
        primaryKey: key,
        artifacts: group,
        keptArtifact: merged,
        mergedFrom: group.map(a => a.id)
      });
    }
  }
  
  return {
    unique,
    duplicates,
    stats: {
      totalInput: artifacts.length,
      uniqueOutput: unique.length,
      duplicatesFound: artifacts.length - unique.length
    }
  };
}

function mergeArtifacts(artifacts: CanonicalArtifact[]): CanonicalArtifact {
  // Sort by completeness score (most complete first)
  const sorted = artifacts.sort((a, b) => 
    calculateCompletenessScore(b) - calculateCompletenessScore(a)
  );
  
  // Start with most complete, fill in gaps from others
  const merged = { ...sorted[0] };
  
  for (const artifact of sorted.slice(1)) {
    // Fill in missing publisher info
    if (!merged.publisher.name && artifact.publisher.name) {
      merged.publisher = artifact.publisher;
    }
    // Fill in missing product info
    if (!merged.product.name && artifact.product.name) {
      merged.product = artifact.product;
    }
    // Collect all source machines
    merged.metadata.tags.push(`also-found-on:${artifact.source.hostname}`);
  }
  
  return merged;
}

function calculateCompletenessScore(artifact: CanonicalArtifact): number {
  let score = 0;
  if (artifact.fileHash_SHA256) score += 10;
  if (artifact.publisher.name) score += 10;
  if (artifact.publisher.isValid) score += 5;
  if (artifact.product.name) score += 5;
  if (artifact.product.version) score += 3;
  if (artifact.product.company) score += 2;
  if (artifact.fileSize > 0) score += 1;
  return score;
}
```

### Data Enrichment

After normalization, artifacts are enriched with derived data:

```typescript
function enrichArtifact(artifact: CanonicalArtifact): CanonicalArtifact {
  return {
    ...artifact,
    
    // Classify file type from extension
    fileType: classifyFileType(artifact.fileExtension),
    
    // Categorize based on path and publisher
    category: categorizeArtifact(artifact),
    
    // Assess risk level
    riskLevel: assessRiskLevel(artifact),
    
    // Compute rule generation hints
    ruleHints: computeRuleHints(artifact)
  };
}

function classifyFileType(extension: string): FileType {
  const extMap: Record<string, FileType> = {
    '.exe': FileType.EXE,
    '.com': FileType.EXE,
    '.dll': FileType.DLL,
    '.ocx': FileType.DLL,
    '.sys': FileType.DLL,
    '.msi': FileType.MSI,
    '.msp': FileType.MSI,
    '.mst': FileType.MSI,
    '.ps1': FileType.Script,
    '.psm1': FileType.Script,
    '.psd1': FileType.Script,
    '.bat': FileType.Script,
    '.cmd': FileType.Script,
    '.vbs': FileType.Script,
    '.vbe': FileType.Script,
    '.js': FileType.Script,
    '.jse': FileType.Script,
    '.wsf': FileType.Script,
    '.wsh': FileType.Script,
    '.appx': FileType.Appx,
    '.msix': FileType.Appx,
    '.appxbundle': FileType.Appx,
    '.msixbundle': FileType.Appx
  };
  
  return extMap[extension.toLowerCase()] || FileType.EXE;
}

function categorizeArtifact(artifact: CanonicalArtifact): ArtifactCategory {
  const path = artifact.filePath.toLowerCase();
  const publisher = artifact.publisher.commonName?.toLowerCase() || '';
  
  // Core OS
  if (path.includes('\\windows\\') && publisher.includes('microsoft')) {
    return ArtifactCategory.CoreOS;
  }
  
  // Admin tools
  if (path.includes('\\admin') || 
      path.includes('\\rsat') ||
      path.includes('\\sysinternals') ||
      isAdminTool(publisher)) {
    return ArtifactCategory.Admin;
  }
  
  // Dev tools
  if (isDevTool(publisher) || path.includes('\\dev\\') || path.includes('\\sdk\\')) {
    return ArtifactCategory.Dev;
  }
  
  // Security tools
  if (isSecurityTool(publisher)) {
    return ArtifactCategory.Security;
  }
  
  // Enterprise apps (signed, in Program Files)
  if (artifact.publisher.isValid && 
      (path.includes('\\program files') || path.includes('\\program files (x86)'))) {
    return ArtifactCategory.Enterprise;
  }
  
  return ArtifactCategory.Unknown;
}

function assessRiskLevel(artifact: CanonicalArtifact): RiskLevel {
  const path = artifact.filePath.toLowerCase();
  
  // Critical risk: unsigned in system paths
  if (!artifact.publisher.isValid && path.includes('\\windows\\system32')) {
    return RiskLevel.Critical;
  }
  
  // High risk: user-writable locations
  if (path.includes('\\users\\') || 
      path.includes('\\temp') || 
      path.includes('\\downloads')) {
    return RiskLevel.High;
  }
  
  // Medium risk: unsigned anywhere
  if (!artifact.publisher.isValid) {
    return RiskLevel.Medium;
  }
  
  // Low risk: signed in standard locations
  return RiskLevel.Low;
}

function computeRuleHints(artifact: CanonicalArtifact): RuleHints {
  const canUsePublisher = artifact.publisher.isValid && 
                          artifact.publisher.name !== null;
  const canUseHash = artifact.fileHash_SHA256 !== null;
  
  // Determine recommended rule type
  let recommendedRuleType: RuleType;
  if (canUsePublisher) {
    recommendedRuleType = RuleType.Publisher;
  } else if (canUseHash) {
    recommendedRuleType = RuleType.Hash;
  } else {
    recommendedRuleType = RuleType.Path;  // Last resort
  }
  
  // Determine recommended group
  const { group, reason } = suggestGroup(artifact);
  
  // Flag for review
  const reviewReasons: string[] = [];
  if (!canUsePublisher && !canUseHash) {
    reviewReasons.push('No signature or hash available - path rule required');
  }
  if (artifact.riskLevel === RiskLevel.High || artifact.riskLevel === RiskLevel.Critical) {
    reviewReasons.push(`High risk location: ${artifact.filePath}`);
  }
  if (artifact.category === ArtifactCategory.Unknown) {
    reviewReasons.push('Unknown software category - verify legitimacy');
  }
  
  return {
    recommendedRuleType,
    recommendedGroup: group,
    recommendedGroupReason: reason,
    canUsePublisher,
    canUseHash,
    requiresReview: reviewReasons.length > 0,
    reviewReasons
  };
}
```

### Validation Rules

Before artifacts can be used for rule generation, they must pass validation:

```typescript
interface ValidationResult {
  isValid: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
}

interface ValidationError {
  field: string;
  message: string;
  value: any;
}

interface ValidationWarning {
  field: string;
  message: string;
  suggestion: string;
}

function validateArtifact(artifact: CanonicalArtifact): ValidationResult {
  const errors: ValidationError[] = [];
  const warnings: ValidationWarning[] = [];
  
  // === REQUIRED FIELDS ===
  
  if (!artifact.fileName) {
    errors.push({
      field: 'fileName',
      message: 'File name is required',
      value: artifact.fileName
    });
  }
  
  if (!artifact.filePath) {
    errors.push({
      field: 'filePath',
      message: 'File path is required',
      value: artifact.filePath
    });
  }
  
  // Must have either hash OR publisher for rule generation
  if (!artifact.fileHash_SHA256 && !artifact.publisher.name) {
    errors.push({
      field: 'fileHash_SHA256/publisher.name',
      message: 'Either a valid hash or publisher signature is required for rule generation',
      value: null
    });
  }
  
  // === FORMAT VALIDATION ===
  
  if (artifact.fileHash_SHA256 && artifact.fileHash_SHA256.length !== 64) {
    errors.push({
      field: 'fileHash_SHA256',
      message: 'SHA256 hash must be exactly 64 characters',
      value: artifact.fileHash_SHA256
    });
  }
  
  if (artifact.fileExtension && !artifact.fileExtension.startsWith('.')) {
    warnings.push({
      field: 'fileExtension',
      message: 'File extension should start with a period',
      suggestion: `.${artifact.fileExtension}`
    });
  }
  
  // === SECURITY WARNINGS ===
  
  if (artifact.publisher.signatureStatus === SignatureStatus.Expired) {
    warnings.push({
      field: 'publisher.signatureStatus',
      message: 'Publisher signature has expired',
      suggestion: 'Consider using hash rule or obtaining updated signed version'
    });
  }
  
  if (artifact.publisher.signatureStatus === SignatureStatus.NotTrusted) {
    warnings.push({
      field: 'publisher.signatureStatus',
      message: 'Publisher signature is not from a trusted CA',
      suggestion: 'Verify publisher legitimacy before creating rule'
    });
  }
  
  if (artifact.riskLevel === RiskLevel.Critical) {
    warnings.push({
      field: 'riskLevel',
      message: 'Artifact is in a critical location',
      suggestion: 'Verify this is legitimate before allowing'
    });
  }
  
  return {
    isValid: errors.length === 0,
    errors,
    warnings
  };
}
```

### Rule Generation from Canonical Artifacts

```typescript
function generateRuleFromArtifact(
  artifact: CanonicalArtifact,
  options: RuleGenerationOptions
): AppLockerRule | null {
  
  // Validate first
  const validation = validateArtifact(artifact);
  if (!validation.isValid) {
    console.error('Cannot generate rule for invalid artifact:', validation.errors);
    return null;
  }
  
  const ruleType = options.forceRuleType || artifact.ruleHints.recommendedRuleType;
  const group = options.forceGroup || artifact.ruleHints.recommendedGroup;
  
  switch (ruleType) {
    case RuleType.Publisher:
      return generatePublisherRule(artifact, group, options);
    case RuleType.Hash:
      return generateHashRule(artifact, group, options);
    case RuleType.Path:
      return generatePathRule(artifact, group, options);
    default:
      return null;
  }
}

function generatePublisherRule(
  artifact: CanonicalArtifact,
  group: string,
  options: RuleGenerationOptions
): PublisherRule {
  
  // Determine version constraint
  let versionConstraint: VersionConstraint;
  if (options.publisherVersionHandling === 'exact') {
    versionConstraint = {
      lowSection: artifact.product.version || '*',
      highSection: artifact.product.version || '*'
    };
  } else if (options.publisherVersionHandling === 'andAbove') {
    versionConstraint = {
      lowSection: artifact.product.version || '*',
      highSection: '*'
    };
  } else {
    versionConstraint = { lowSection: '*', highSection: '*' };
  }
  
  // Determine binary name constraint
  const binaryName = options.publisherBinaryHandling === 'specific' 
    ? artifact.fileName.toUpperCase()
    : '*';
  
  return {
    id: generateGUID(),
    name: `Allow ${artifact.publisher.commonName || 'Unknown'} - ${artifact.product.name || artifact.fileName}`,
    description: `Auto-generated publisher rule for ${artifact.filePath}`,
    ruleType: RuleType.Publisher,
    ruleCollection: mapFileTypeToCollection(artifact.fileType),
    action: 'Allow',
    userOrGroupSid: resolveSID(group),
    userOrGroupName: group,
    conditions: [{
      type: 'Publisher',
      publisherName: artifact.publisher.name!,
      productName: options.publisherProductHandling === 'specific' 
        ? artifact.product.name || '*'
        : '*',
      binaryName: binaryName,
      versionRange: versionConstraint
    }],
    sourceArtifacts: [artifact.id],
    isAutoGenerated: true
  };
}

function generateHashRule(
  artifact: CanonicalArtifact,
  group: string,
  options: RuleGenerationOptions
): HashRule {
  return {
    id: generateGUID(),
    name: `Allow ${artifact.fileName} (Hash)`,
    description: `Auto-generated hash rule for ${artifact.filePath}`,
    ruleType: RuleType.Hash,
    ruleCollection: mapFileTypeToCollection(artifact.fileType),
    action: 'Allow',
    userOrGroupSid: resolveSID(group),
    userOrGroupName: group,
    conditions: [{
      type: 'Hash',
      hashType: 'SHA256',
      hashValue: artifact.fileHash_SHA256!,
      sourceFileName: artifact.fileName,
      sourceFileLength: artifact.fileSize
    }],
    sourceArtifacts: [artifact.id],
    isAutoGenerated: true
  };
}
```

### Import/Export Format Compatibility Matrix

| Source Format | Publisher Info | Hash Info | Path Info | Version Info | Notes |
|--------------|----------------|-----------|-----------|--------------|-------|
| WinRM Scan | [OK] Full | [OK] SHA256 | [OK] Full | [OK] Full | Best source |
| Get-AppLockerFileInformation | [OK] Full | [OK] SHA256 | [OK] Full | [OK] Full | Native cmdlet |
| Event Log (8003/8004) | [OK] FQBN | [!] Varies | [OK] Full | [OK] From FQBN | May need enrichment |
| CSV (GA-AppLocker format) | [OK] Full | [OK] SHA256 | [OK] Full | [OK] Full | Recommended export |
| CSV (Generic) | [!] Varies | [!] Varies | [OK] Usually | [!] Varies | Map columns |
| JSON (GA-AppLocker format) | [OK] Full | [OK] SHA256 | [OK] Full | [OK] Full | Recommended export |
| JSON (Generic) | [!] Varies | [!] Varies | [!] Varies | [!] Varies | Auto-detect |
| Sigcheck output | [OK] Full | [OK] Multiple | [OK] Full | [OK] Full | Sysinternals |
| SCCM/Intune export | [!] Varies | [!] Varies | [OK] Usually | [!] Varies | Needs mapping |

### Troubleshooting Data Issues

| Issue | Detection | Resolution |
|-------|-----------|------------|
| Missing hash | `fileHash_SHA256 === null` | Use publisher rule, or flag for manual scan |
| Invalid hash length | `hash.length !== 64` | Re-scan file, check for truncation |
| Missing publisher | `publisher.name === null` | Use hash rule, flag for review |
| Expired signature | `signatureStatus === 'Expired'` | Warn user, consider hash rule |
| Duplicate artifacts | Dedup process detects | Merge, keep most complete |
| Unknown file type | Extension not in map | Default to EXE collection |
| Malformed path | Path validation fails | Attempt normalization, flag if fails |
| Encoding issues | Unicode detection | Ensure UTF-8 throughout pipeline |

---

## [UI] UI/UX Specifications

### Navigation Structure
```
SIDEBAR NAVIGATION
===============================

[CHART] OVERVIEW
   +-- Dashboard

[SCAN] DISCOVERY
   +-- AD Discovery
   +-- Artifact Scanner

[IMPORT] DATA MANAGEMENT
   +-- Import / Ingestion
   +-- Inventory View

[GEAR] RULE MANAGEMENT
   +-- Rule Generator
   +-- Group Assignment
   +-- Rule Templates

[LIST] POLICY MANAGEMENT
   +-- Policy Builder
   +-- Policy Merger
   +-- Policy Lab

[DEPLOY] DEPLOYMENT
   +-- Deploy to OU
   +-- Phase Manager

[MONITOR] MONITORING
   +-- Events
   +-- Compliance

[GEAR] SETTINGS
   +-- Credentials
   +-- Group Mappings
   +-- Preferences
```

### Screen Specifications

#### Dashboard
- **Purpose:** At-a-glance environment health
- **Key Metrics:**
  - Total machines discovered
  - Machines scanned vs pending
  - Total artifacts collected
  - Rules generated (by type)
  - Policies created (by machine type)
  - Deployment status (by phase)
  - Recent activity feed
- **Quick Actions:**
  - Start New Scan
  - Import Artifacts
  - Generate Rules
  - Deploy Policy
- **Visualizations:**
  - Pie chart: Artifacts by type (EXE/DLL/MSI/Script)
  - Bar chart: Rules by collection type
  - Progress bars: Phase deployment status
  - Status indicators: Online/Offline machines

#### AD Discovery Screen
- **Inputs:**
  - Domain (auto-detected, editable)
  - OU filter (tree selector or path input)
  - Machine type filter (checkboxes)
  - Online status filter
- **Outputs:**
  - Machine grid (sortable, filterable)
  - OU grouping summary
  - Selection count
- **Actions:**
  - Select All / Deselect All
  - Select by OU
  - Scan Selected
  - Export Machine List

#### Artifact Scanner Screen
- **Inputs:**
  - Target machines (from selection or manual entry)
  - Credential profile selector
  - Scan options:
    - Include EXE [x]
    - Include DLL [x]
    - Include MSI [x]
    - Include Script [x]
    - Include Event Logs [x]
    - Scan depth (Quick / Standard / Deep)
- **Progress Display:**
  - Overall progress bar
  - Per-machine status list
  - Live artifact count
  - Error count with expand details
- **Actions:**
  - Start Scan
  - Pause / Resume
  - Cancel
  - View Results (when complete)

#### Rule Generator Screen
- **Inputs:**
  - Source artifacts (selected or all)
  - Rule type preference (Publisher preferred [x], Hash fallback [x], Path avoid [x])
  - Group assignment mode (Auto / Template / Manual)
  - Template selector (if template mode)
- **Preview Panel:**
  - Rules to be generated (expandable list)
  - Group assignments (editable inline)
  - Duplicate warnings
  - Validation warnings
- **Actions:**
  - Generate Rules
  - Edit Before Generate
  - Save as Template

#### Policy Builder Screen
- **Inputs:**
  - Policy name
  - Machine type target
  - Phase selection
  - Rules to include (multi-select from generated rules)
- **Preview Panel:**
  - Policy XML preview (collapsible)
  - Rule count by collection
  - Validation status
- **Actions:**
  - Validate Policy
  - Export XML
  - Save Policy
  - Deploy to OU

#### Credential Manager Screen
- **Display:**
  - Credential profiles grid
  - Columns: Name, Username, Domain, Target Environment, Last Used, Status
- **Actions:**
  - Add Credential
  - Edit Credential
  - Delete Credential
  - Test Credential
  - Set as Default

### UI Components

#### Progress Indicators
- **Scan Progress:** Determinate progress bar with percentage + "X of Y machines"
- **Rule Generation:** Indeterminate spinner with status text
- **Policy Deployment:** Step indicator (1. Create GPO -> 2. Apply Policy -> 3. Link to OU)

#### Notifications
- **Success:** Green toast, auto-dismiss 5 seconds
- **Warning:** Yellow toast, manual dismiss
- **Error:** Red toast, manual dismiss, expandable details
- **Info:** Blue toast, auto-dismiss 3 seconds

#### Confirmation Dialogs
- **Destructive Actions:** "Are you sure?" with action summary
- **Deploy Actions:** Summary of what will be deployed + environment impact

---

## [!] Error Handling & Edge Cases

### Error Code System

All errors return a structured error code for programmatic handling:

| Range | Category | Examples |
|-------|----------|----------|
| 1xxx | Connection Errors | WinRM, network, DNS |
| 2xxx | Data Errors | Import, parsing, validation |
| 3xxx | Policy Errors | XML, GPO, deployment |
| 4xxx | System Errors | Memory, disk, permissions |
| 5xxx | Authentication Errors | Credentials, Kerberos |

**Complete Error Code Reference:**

```
CONNECTION ERRORS (1xxx)
------------------------
1001  WinRM service unavailable on target
1002  WinRM connection refused (firewall)
1003  Network timeout
1004  DNS resolution failed
1005  Target machine offline
1006  Port 5985/5986 blocked
1007  SSL/TLS handshake failed
1008  Connection limit exceeded

DATA ERRORS (2xxx)
------------------
2001  Import file corrupt or unreadable
2002  Import file format not recognized
2003  Required field missing in import
2004  Invalid hash format
2005  Invalid path format
2006  Duplicate artifact detected
2007  Data validation failed
2008  Encoding error (non-UTF8)
2009  File too large to process
2010  JSON/CSV parse error

POLICY ERRORS (3xxx)
--------------------
3001  Generated XML invalid
3002  XML schema validation failed
3003  GPO creation failed
3004  GPO link failed
3005  SYSVOL write failed
3006  Policy conflict detected
3007  Rule limit exceeded (AppLocker max)
3008  Invalid SID in rule
3009  GPO not found
3010  OU not found

SYSTEM ERRORS (4xxx)
--------------------
4001  Out of memory
4002  Disk full
4003  Temp folder inaccessible
4004  Log write failed
4005  Settings file corrupt
4006  Lock file conflict
4007  Background task failed
4008  UI thread blocked

AUTHENTICATION ERRORS (5xxx)
----------------------------
5001  Invalid credentials
5002  Credential expired
5003  Account locked
5004  Password expired
5005  Kerberos ticket expired
5006  NTLM not allowed
5007  CredSSP not configured
5008  Insufficient permissions
5009  Domain trust failed
```

### Connection Errors
| Error | User Message | Recovery Action |
|-------|--------------|-----------------|
| WinRM unavailable | "Cannot connect to {hostname}. WinRM may be disabled." | Offer to skip or retry, show WinRM troubleshooting link |
| Credential rejected | "Access denied to {hostname}. Check credentials." | Prompt credential re-entry or switch profile |
| Network timeout | "Connection to {hostname} timed out." | Auto-retry (3x), then skip with warning |
| DNS resolution failure | "Cannot resolve hostname {hostname}." | Skip with error logged |

### Data Errors
| Error | User Message | Recovery Action |
|-------|--------------|-----------------|
| Corrupt import file | "Import file is corrupt or invalid format." | Show specific parse error, reject file |
| Duplicate artifact | "Artifact already exists in inventory." | Auto-dedupe, show count of duplicates skipped |
| Missing required field | "Artifact missing required field: {field}" | Skip artifact, log warning |
| Invalid hash format | "Invalid hash format for {filename}" | Skip hash, fall back to publisher rule |

### Policy Errors
| Error | User Message | Recovery Action |
|-------|--------------|-----------------|
| Invalid XML generated | "Generated policy XML is invalid." | Show validation errors, prevent export |
| GPO creation failed | "Failed to create GPO: {error}" | Show AD error, suggest permissions check |
| OU link failed | "Failed to link GPO to OU: {error}" | Offer manual linking instructions |
| Policy conflict | "Conflicting rule detected: {rule}" | Show conflict details, offer resolution options |

### Edge Cases to Handle
- **Empty scan results:** No artifacts found on machine -> Show info message, suggest checking paths
- **All machines offline:** No machines reachable -> Show warning, offer to save machine list for later
- **Unsigned executables:** No publisher info -> Auto-generate hash rule, flag for review
- **Duplicate publishers:** Same publisher, different products -> Group intelligently by ProductName
- **Very long paths:** Path exceeds 260 chars -> Truncate display, full path in tooltip
- **Non-English characters:** Unicode in paths/publishers -> Ensure proper encoding in XML
- **Large datasets:** 10,000+ artifacts -> Enable virtual scrolling, batch processing
- **Concurrent scans:** Multiple scan jobs -> Queue management, prevent duplicate scans
- **Credential expiration mid-scan:** Detect 401 after initial success -> Pause, prompt refresh, resume
- **Locked/in-use files:** Cannot hash open files -> Log warning, skip file, don't fail scan
- **GPO replication lag:** Policy deployed but not visible -> Warn user, suggest 90-120 min wait
- **Orphaned GPOs:** GPO created but linking failed -> Track in local DB, offer cleanup
- **AppIdentity service stopped:** AppLocker won't function -> Check during scan, warn user
- **Partial scan failure:** Some machines fail, others succeed -> Complete scan, report failures separately

### Scan Depth Definitions

| Depth | Paths Scanned | Estimated Time | Use Case |
|-------|---------------|----------------|----------|
| **Quick** | Program Files, Program Files (x86), System32 | ~30 sec/machine | Daily monitoring |
| **Standard** | Quick + SysWOW64, ProgramData, Common user apps | ~2 min/machine | Weekly baseline |
| **Deep** | Standard + Full C:\ drive, all fixed drives, all user profiles | ~5 min/machine | Initial deployment, audit |

**Quick Scan Paths:**
```
C:\Program Files\*
C:\Program Files (x86)\*
C:\Windows\System32\*
```

**Standard Scan Paths (adds):**
```
C:\Windows\SysWOW64\*
C:\ProgramData\*
C:\Users\Default\AppData\*
Common application paths:
  - %LOCALAPPDATA%\Programs\*
  - %LOCALAPPDATA%\Microsoft\*
```

**Deep Scan Paths (adds):**
```
C:\* (entire drive, excluding system-protected)
D:\* (and other fixed drives)
C:\Users\*\* (all user profiles)
Excludes:
  - C:\Windows\WinSxS (too many files)
  - C:\$Recycle.Bin
  - System Volume Information
```

---

## [SECURE] Security Requirements

### Credential Handling
- Credentials stored in Windows Credential Manager (not plaintext)
- SecureString used for password handling in memory
- Credentials never written to logs or exported files
- Session-only credential caching option
- Credential validation before scan execution

### Access Control
- App requires local admin to run (for WinRM operations)
- Domain Admin or delegated permissions for GPO operations
- Read access to target machines for scanning
- Write access to SYSVOL for GPO deployment

### Data Protection
- Exported policy XML contains no credentials
- Scan results stored locally (user-specified path)
- Option to encrypt exported data
- Automatic cleanup of temp files

### Audit Trail
- All GPO changes logged with timestamp and user
- Credential usage logged (without password)
- Policy deployments logged with full details
- Export/import operations logged

### Network Security
- WinRM over HTTPS preferred (configurable)
- Kerberos authentication preferred
- NTLM fallback (configurable, warn if used)
- No credentials transmitted in cleartext

---

## [PERF] Performance Requirements

### Scalability Targets
| Operation | Target | Maximum |
|-----------|--------|---------|
| AD Discovery | 1,000 machines in < 30 seconds | 10,000 machines |
| Artifact Scan (per machine) | < 2 minutes | 5 minutes timeout |
| Concurrent scans | 10 machines parallel | 50 machines |
| Rule generation | 1,000 rules in < 5 seconds | 10,000 rules |
| Policy XML generation | < 2 seconds | 5 seconds |
| UI responsiveness | < 100ms for interactions | Never block UI |

### Optimization Strategies
- **Virtual scrolling** for large grids (1,000+ rows)
- **Lazy loading** for artifact details
- **Background threads** for all scan/generation operations
- **Caching** for AD queries (configurable TTL)
- **Batch processing** for rule generation
- **Incremental updates** for scan progress

### Resource Limits
- Memory usage: < 500MB typical, < 2GB maximum
- Disk usage: Configurable scan result storage location
- Network: Throttle concurrent connections (configurable)
- CPU: Background operations on low priority threads

---

## [GEAR] Configuration & Settings

### Application Settings
```
General:
  - Theme: Dark / Light / System
  - Language: English (expandable)
  - Auto-save interval: 5 minutes (configurable)
  - Startup behavior: Last view / Dashboard

Scanning:
  - Default scan depth: Quick / Standard / Deep
  - Concurrent scan limit: 10 (1-50)
  - Scan timeout per machine: 120 seconds (30-600)
  - Auto-retry failed scans: Yes/No (count: 3)
  - Include hidden files: Yes/No
  - Include system files: Yes/No

Rule Generation:
  - Preferred rule type: Publisher -> Hash -> Path
  - Auto-group publishers: Yes/No
  - Duplicate detection: Yes/No
  - Default enforcement mode: AuditOnly / Enabled

Deployment:
  - Backup existing policy before deploy: Yes/No
  - Auto-link GPO to OU: Yes/No
  - Default phase: Phase 1

Network:
  - WinRM transport: HTTP / HTTPS
  - Authentication: Kerberos / NTLM / Negotiate
  - Connection timeout: 30 seconds

Storage:
  - Data directory: %LOCALAPPDATA%\GA-AppLocker\
  - Export directory: (user-specified)
  - Log retention: 30 days
  - Max log size: 100MB
```

### User Preferences
```
Credential Profiles:
  - [List of saved profiles]
  - Default profile per environment

Group Mappings:
  - [List of custom mappings]
  - Enable/disable individual mappings

Templates:
  - [List of saved rule templates]
  - [List of saved policy templates]

Favorites:
  - Pinned OUs
  - Pinned machines
  - Recent policies
```

---

## [LOG] Logging & Auditing

### Log Levels
- **DEBUG:** Verbose, for troubleshooting
- **INFO:** Normal operations
- **WARN:** Potential issues, non-fatal
- **ERROR:** Operation failures
- **AUDIT:** Security-relevant events (always logged)

### Log Categories
```
[SCAN] - Artifact scanning operations
[RULE] - Rule generation operations
[POLICY] - Policy creation/modification
[DEPLOY] - GPO deployment operations
[AUTH] - Authentication/credential operations
[IMPORT] - Data import operations
[EXPORT] - Data export operations
[CONFIG] - Configuration changes
[UI] - User interactions (optional)
```

### Audit Events (Always Logged)
- Credential profile created/modified/deleted
- Scan initiated (target machines, credential used)
- Rules generated (count, type breakdown)
- Policy created/modified/exported
- GPO deployed (GPO name, target OUs, phase)
- Settings changed (what changed, old/new values)

### Log Format
```
[TIMESTAMP] [LEVEL] [CATEGORY] [USER] Message
{Optional JSON details}

Example:
[2026-01-16 14:32:15] [AUDIT] [DEPLOY] [DOMAIN\admin] Policy deployed to GPO
{"gpoName": "AppLocker-WS-Policy", "targetOUs": ["OU=Workstations,DC=domain,DC=com"], "phase": 2, "ruleCount": 145}
```

### Log Storage
- Location: %LOCALAPPDATA%\GA-AppLocker\Logs\
- Rotation: Daily, keep 30 days
- Format: Plain text + JSON structured (configurable)
- Export: CSV/JSON export for SIEM ingestion

---

## [TEST] Testing Requirements

### Unit Tests
- [ ] Artifact parsing (all file types)
- [ ] Rule generation logic (Publisher, Hash, Path)
- [ ] Group assignment logic (all detection methods)
- [ ] Policy XML generation
- [ ] Policy validation
- [ ] Deduplication logic
- [ ] OU path parsing
- [ ] Machine type detection

### Integration Tests
- [ ] AD connectivity and discovery
- [ ] WinRM connectivity and scanning
- [ ] Credential validation
- [ ] GPO creation and linking
- [ ] Policy deployment
- [ ] Multi-machine parallel scanning

### UI Tests
- [ ] All navigation paths
- [ ] Form validation
- [ ] Progress indicators
- [ ] Error displays
- [ ] Grid sorting/filtering
- [ ] Export/import workflows

### Edge Case Tests
- [ ] Empty results handling
- [ ] Large dataset performance (10,000+ items)
- [ ] Network timeout recovery
- [ ] Invalid input handling
- [ ] Concurrent operation handling
- [ ] Unicode/special character handling

### Environment Tests
- [ ] Windows 10 compatibility
- [ ] Windows 11 compatibility
- [ ] Windows Server 2019 compatibility
- [ ] Windows Server 2022 compatibility
- [ ] Domain-joined machine
- [ ] Workgroup machine (limited functionality)
- [ ] Air-gapped network (no internet)

---

## [DEPLOY] Deployment & Environment

### System Requirements
```
Minimum:
  - OS: Windows 10 1909+ / Windows Server 2019+
  - RAM: 4GB
  - Disk: 500MB + data storage
  - .NET: 4.8 or .NET 6+
  - PowerShell: 5.1+

Recommended:
  - OS: Windows 11 / Windows Server 2022
  - RAM: 8GB+
  - Disk: SSD recommended
  - PowerShell: 7.x
```

### Prerequisites
- [ ] WinRM enabled on target machines
- [ ] Appropriate firewall rules (TCP 5985/5986)
- [ ] Domain Admin or delegated GPO permissions
- [ ] RSAT (Remote Server Administration Tools) for AD cmdlets

### Installation
- Single EXE deployment (self-contained)
- No installer required (portable option)
- Optional: MSI installer for enterprise deployment
- Optional: SCCM/Intune deployment package

### First-Run Configuration
1. Domain auto-detection (confirm or override)
2. Credential profile setup
3. Default settings review
4. Test connectivity
5. Ready to scan

---

## [BOOK] Glossary

| Term | Definition |
|------|------------|
| **Artifact** | A file (EXE, DLL, MSI, Script) discovered during scanning that may need an AppLocker rule |
| **Rule Collection** | AppLocker category: Exe, Msi, Script, Dll, Appx |
| **Publisher Rule** | Rule based on digital signature (most flexible) |
| **Hash Rule** | Rule based on file hash (secure but breaks on updates) |
| **Path Rule** | Rule based on file location (least secure, avoid) |
| **Enforcement Mode** | AuditOnly (log only) or Enabled (block violations) |
| **Phase** | Deployment stage (1-4) with progressive rule enforcement |
| **OU** | Organizational Unit in Active Directory |
| **GPO** | Group Policy Object for deploying AppLocker policy |
| **WinRM** | Windows Remote Management for remote scanning |
| **STIG** | Security Technical Implementation Guide (DoD compliance) |

---

## [USER] User Stories & Acceptance Criteria

### Epic 1: Discovery & Scanning

**US-1.1: As an admin, I want to discover all machines in my domain so I know what to scan.**
```
Given: I am connected to a domain
When: I click "Discover Machines" 
Then: All machines in AD are listed with hostname, OU, OS, and online status
And: I can filter by OU, machine type, or online status
Acceptance: < 30 seconds for 1,000 machines
```

**US-1.2: As an admin, I want to scan selected machines for AppLocker artifacts.**
```
Given: I have selected one or more machines
When: I click "Scan Selected" and choose a credential profile
Then: Artifacts are collected from each machine via WinRM
And: Progress is shown per-machine with success/failure status
And: Results are stored in the artifact inventory
Acceptance: < 2 minutes per machine, parallel execution
```

**US-1.3: As an admin, I want to use different credentials for different environments.**
```
Given: I have workstations, servers, and DCs to scan
When: I create credential profiles for each environment
Then: I can assign the appropriate profile before scanning
And: Credentials are validated before scan starts
Acceptance: Credential switch takes < 5 seconds
```

### Epic 2: Rule Generation

**US-2.1: As an admin, I want to auto-generate rules from scanned artifacts.**
```
Given: I have artifacts in my inventory
When: I click "Generate Rules"
Then: Rules are created using Publisher (preferred) or Hash (fallback)
And: Duplicates are detected and skipped
And: I can review rules before saving
Acceptance: 1,000 rules generated in < 5 seconds
```

**US-2.2: As an admin, I want the app to suggest appropriate security groups.**
```
Given: I am generating rules
When: Rules are created
Then: Each rule has a suggested group based on path, publisher, and machine type
And: I can override any suggestion
And: I can save my overrides as a custom mapping
Acceptance: 100% of rules have a suggestion
```

**US-2.3: As an admin, I want to use templates for common scenarios.**
```
Given: I want to apply a "Locked-Down Server" policy
When: I select that template
Then: All rules inherit the template's group assignments
And: I can modify individual rules after applying
Acceptance: Template applies in < 1 second
```

### Epic 3: Policy Management

**US-3.1: As an admin, I want to create separate policies by machine type.**
```
Given: I have rules for workstations, servers, and DCs
When: I create policies
Then: Rules are automatically grouped by source machine type
And: I get three separate policy files
Acceptance: Correct separation 100% of the time
```

**US-3.2: As an admin, I want to merge policies from multiple sources.**
```
Given: I have multiple policy XML files
When: I use the merge function
Then: Rules are combined with conflict detection
And: I can choose how to resolve conflicts (keep both, keep first, keep newest)
Acceptance: Merge completes in < 10 seconds for 1,000 rules
```

**US-3.3: As an admin, I want to validate policies before deployment.**
```
Given: I have created a policy
When: I click "Validate"
Then: The app checks XML syntax, rule conflicts, and best practices
And: Warnings and errors are clearly displayed
And: I cannot deploy an invalid policy
Acceptance: Validation < 2 seconds, catches all XML errors
```

### Epic 4: Deployment

**US-4.1: As an admin, I want to deploy policies to specific OUs.**
```
Given: I have a validated policy
When: I select target OUs and click "Deploy"
Then: A GPO is created (or updated) with the policy
And: The GPO is linked to the selected OUs
And: Existing policy is backed up first
Acceptance: Deployment < 30 seconds per GPO
```

**US-4.2: As an admin, I want to deploy in phases (audit first).**
```
Given: I am deploying a new policy
When: I select Phase 1
Then: Only EXE rules are deployed in AuditOnly mode
And: I can progress through phases as I validate
Acceptance: Phase selection works correctly 100% of the time
```

**US-4.3: As an admin, I want to rollback a deployment if needed.**
```
Given: I have deployed a policy that causes issues
When: I click "Rollback"
Then: The previous policy backup is restored
And: The GPO is updated with the old policy
Acceptance: Rollback < 30 seconds
```

### Epic 5: Monitoring & Compliance

**US-5.1: As an admin, I want to see AppLocker events from my environment.**
```
Given: AppLocker is running in audit or enforce mode
When: I open the Events panel
Then: I see recent 8003/8004/8006/8007 events
And: I can filter by machine, event type, or time range
And: I can create rules directly from blocked events
Acceptance: Events load in < 10 seconds
```

**US-5.2: As an admin, I want compliance reports for auditors.**
```
Given: I have deployed policies
When: I generate a compliance report
Then: I see which machines have policies applied
And: I see rule coverage statistics
And: I can export to PDF/CSV for auditors
Acceptance: Report generates in < 30 seconds
```

---

## [API] API & Function Specifications

### Core PowerShell Functions

#### Discovery Functions
```powershell
Get-ADMachines
  -Domain <string>           # Target domain (auto-detected if omitted)
  -OUPath <string>           # Filter by OU path
  -MachineType <string[]>    # Filter: Workstation, Server, DomainController
  -OnlineOnly <switch>       # Only return machines that respond to ping
  -Credential <PSCredential> # Alternate credentials
  Returns: Machine[]

Test-WinRMConnectivity
  -ComputerName <string[]>   # Target machines
  -Credential <PSCredential> # Credentials to test
  -Timeout <int>             # Seconds (default: 30)
  Returns: ConnectionResult[]
```

#### Scanning Functions
```powershell
Get-AppLockerArtifacts
  -ComputerName <string[]>   # Target machines
  -Credential <PSCredential> # Credentials for WinRM
  -ScanDepth <string>        # Quick, Standard, Deep
  -IncludeEventLogs <switch> # Include 8003/8004 events
  -ArtifactTypes <string[]>  # EXE, DLL, MSI, Script (default: all)
  -ExcludePaths <string[]>   # Paths to skip
  Returns: Artifact[]

Import-ArtifactsFromFile
  -Path <string>             # File path (CSV, JSON)
  -Format <string>           # Auto-detect or specify
  -Deduplicate <switch>      # Remove duplicates
  Returns: Artifact[]
```

#### Rule Generation Functions
```powershell
New-AppLockerRulesFromArtifacts
  -Artifacts <Artifact[]>    # Source artifacts
  -RulePreference <string[]> # Priority order: Publisher, Hash, Path
  -GroupAssignmentMode <string> # Auto, Template, Manual
  -Template <string>         # Template name (if mode=Template)
  -GroupMappings <GroupMapping[]> # Custom mappings
  Returns: Rule[]

Get-SuggestedGroup
  -Artifact <Artifact>       # Single artifact
  -MachineType <string>      # Context: Workstation, Server, DC
  -RuleCollection <string>   # EXE, DLL, MSI, Script
  Returns: GroupSuggestion

Merge-AppLockerRules
  -Rules <Rule[][]>          # Multiple rule sets
  -ConflictResolution <string> # KeepBoth, KeepFirst, KeepNewest
  Returns: Rule[]
```

#### Policy Functions
```powershell
New-AppLockerPolicy
  -Rules <Rule[]>            # Rules to include
  -Name <string>             # Policy name
  -MachineType <string>      # Target machine type
  -Phase <int>               # 1-4
  -EnforcementMode <string>  # AuditOnly, Enabled (auto from phase)
  Returns: Policy

Test-AppLockerPolicy
  -Policy <Policy>           # Policy to validate
  -Strict <switch>           # Fail on warnings too
  Returns: ValidationResult

Export-AppLockerPolicyXML
  -Policy <Policy>           # Policy to export
  -Path <string>             # Output file path
  Returns: void

Merge-AppLockerPolicies
  -Policies <Policy[]>       # Policies to merge
  -ConflictResolution <string>
  Returns: Policy
```

#### Deployment Functions
```powershell
Deploy-AppLockerPolicy
  -Policy <Policy>           # Policy to deploy
  -GPOName <string>          # GPO name (create if not exists)
  -TargetOUs <string[]>      # OUs to link
  -BackupExisting <switch>   # Backup current policy first
  -CreateGPO <switch>        # Create GPO if missing
  Returns: DeploymentResult

Backup-AppLockerPolicy
  -GPOName <string>          # Source GPO
  -Path <string>             # Backup location
  Returns: BackupResult

Restore-AppLockerPolicy
  -BackupPath <string>       # Backup file
  -GPOName <string>          # Target GPO
  Returns: RestoreResult
```

### IPC Handlers (Electron <-> PowerShell)

```typescript
// Discovery
ipcMain.handle('ad:discover', (options: DiscoverOptions) => Machine[])
ipcMain.handle('ad:testConnection', (machines: string[], credential: string) => ConnectionResult[])

// Scanning  
ipcMain.handle('scan:start', (options: ScanOptions) => ScanJob)
ipcMain.handle('scan:status', (jobId: string) => ScanStatus)
ipcMain.handle('scan:cancel', (jobId: string) => void)
ipcMain.handle('scan:results', (jobId: string) => Artifact[])

// Artifacts
ipcMain.handle('artifacts:import', (path: string, options: ImportOptions) => Artifact[])
ipcMain.handle('artifacts:list', (filters: ArtifactFilters) => Artifact[])
ipcMain.handle('artifacts:delete', (ids: string[]) => void)

// Rules
ipcMain.handle('rules:generate', (options: GenerateOptions) => Rule[])
ipcMain.handle('rules:suggestGroup', (artifact: Artifact, context: Context) => GroupSuggestion)
ipcMain.handle('rules:list', (filters: RuleFilters) => Rule[])
ipcMain.handle('rules:save', (rules: Rule[]) => void)
ipcMain.handle('rules:delete', (ids: string[]) => void)

// Policies
ipcMain.handle('policy:create', (options: PolicyOptions) => Policy)
ipcMain.handle('policy:validate', (policy: Policy) => ValidationResult)
ipcMain.handle('policy:export', (policy: Policy, path: string) => void)
ipcMain.handle('policy:merge', (policies: Policy[], options: MergeOptions) => Policy)
ipcMain.handle('policy:list', () => Policy[])

// Deployment
ipcMain.handle('deploy:execute', (options: DeployOptions) => DeploymentResult)
ipcMain.handle('deploy:backup', (gpoName: string) => BackupResult)
ipcMain.handle('deploy:rollback', (backupPath: string, gpoName: string) => RestoreResult)

// Credentials
ipcMain.handle('credentials:list', () => CredentialProfile[])
ipcMain.handle('credentials:save', (profile: CredentialProfile) => void)
ipcMain.handle('credentials:delete', (id: string) => void)
ipcMain.handle('credentials:test', (id: string, target: string) => boolean)

// Settings
ipcMain.handle('settings:get', () => Settings)
ipcMain.handle('settings:save', (settings: Settings) => void)
```

---

## [SYNC] State Management

### Application State Structure
```typescript
interface AppState {
  // Session
  session: {
    domain: string
    isDomainController: boolean
    currentUser: string
    startTime: datetime
  }
  
  // Discovery
  discovery: {
    machines: Machine[]
    selectedMachines: string[]
    lastDiscovery: datetime
    filters: MachineFilters
  }
  
  // Scanning
  scanning: {
    activeJobs: ScanJob[]
    completedJobs: ScanJob[]
    currentCredentialId: string
  }
  
  // Artifacts
  artifacts: {
    items: Artifact[]
    selected: string[]
    filters: ArtifactFilters
    sortBy: string
    sortOrder: 'asc' | 'desc'
  }
  
  // Rules
  rules: {
    items: Rule[]
    selected: string[]
    pendingGeneration: Rule[]  // Preview before save
    filters: RuleFilters
  }
  
  // Policies
  policies: {
    items: Policy[]
    activePolicyId: string
    validationResults: Map<string, ValidationResult>
  }
  
  // Deployment
  deployment: {
    history: DeploymentResult[]
    backups: BackupInfo[]
  }
  
  // UI
  ui: {
    activePanel: string
    isLoading: boolean
    loadingMessage: string
    notifications: Notification[]
    modals: ModalState[]
  }
  
  // Settings
  settings: Settings
  credentials: CredentialProfile[]
  groupMappings: GroupMapping[]
  templates: Template[]
}
```

### State Persistence
```
Persisted (survives app restart):
  - settings
  - credentials (encrypted)
  - groupMappings
  - templates
  - deployment.backups (metadata only)

Session-only (cleared on restart):
  - discovery.machines
  - scanning.activeJobs
  - artifacts.items (can be re-imported)
  - rules.items (can be regenerated)
  - policies.items (can be re-exported from saved XML)
  - ui state
```

---

## [BACK] Rollback & Recovery

### Backup Strategy

#### Automatic Backups
| Event | What's Backed Up | Location |
|-------|------------------|----------|
| Before GPO deployment | Existing AppLocker policy XML | `%LOCALAPPDATA%\GA-AppLocker\Backups\{GPOName}\{timestamp}.xml` |
| Before policy merge | Source policies | `%LOCALAPPDATA%\GA-AppLocker\Backups\Merge\{timestamp}\` |
| Before settings change | Previous settings | `%LOCALAPPDATA%\GA-AppLocker\Backups\Settings\{timestamp}.json` |

#### Manual Backups
- User can export any policy to XML at any time
- User can export full artifact inventory to JSON
- User can export all rules to JSON
- User can export settings + mappings + templates bundle

### Recovery Procedures

#### Scenario: Bad policy deployed, apps are blocked
```
1. Open GA-AppLocker
2. Go to Deployment -> Backup History
3. Find the backup from before deployment
4. Click "Rollback to this backup"
5. Confirm the target GPO
6. Policy is restored in < 30 seconds
```

#### Scenario: App crashes during rule generation
```
1. Restart app
2. Artifacts are preserved (if already saved)
3. Rules in "pending" state are lost
4. Re-run rule generation
```

#### Scenario: Corrupt data file
```
1. App detects corruption on startup
2. Offers to restore from last known good backup
3. Or start fresh with empty state
```

### Rollback Limitations
- Cannot rollback AD Discovery (stateless)
- Cannot rollback completed scans (artifacts persist until deleted)
- Cannot rollback to a state before app was first used
- GPO rollback requires the backup file to exist

---

## [LIST] Known Enterprise Vendors List

The app maintains a list of known enterprise software vendors for smart group assignment. This list is updatable.

### Tier 1: Core OS & Infrastructure (-> Everyone)
```
Microsoft Corporation
Microsoft Windows
```

### Tier 2: Enterprise Standard (-> Authenticated Users)
```
Adobe Inc.
Adobe Systems Incorporated
Google LLC
Google Inc.
Mozilla Corporation
Mozilla Foundation
Cisco Systems, Inc.
Citrix Systems, Inc.
VMware, Inc.
Oracle Corporation
Oracle America, Inc.
SAP SE
Salesforce, Inc.
Zoom Video Communications, Inc.
Slack Technologies, Inc.
Atlassian Pty Ltd
Dropbox, Inc.
Box, Inc.
DocuSign, Inc.
```

### Tier 3: Security Tools (-> Security Admins)
```
CrowdStrike, Inc.
Splunk Inc.
Palo Alto Networks
Fortinet, Inc.
McAfee, LLC
Symantec Corporation
Trend Micro Inc.
Carbon Black, Inc.
SentinelOne
Tanium Inc.
Tenable, Inc.
Qualys, Inc.
Rapid7 LLC
```

### Tier 4: Development Tools (-> Developers)
```
JetBrains s.r.o.
GitHub, Inc.
GitLab Inc.
Notepad++ Team
VS Code / Microsoft (when in dev paths)
Python Software Foundation
Node.js Foundation
Docker Inc.
Hashicorp, Inc.
```

### Tier 5: Admin/IT Tools (-> IT Admins)
```
SolarWinds Worldwide, LLC
ManageEngine
PDQ.com
Sysinternals (Microsoft)
Wireshark Foundation
PuTTY (Simon Tatham)
WinSCP (Martin Prikryl)
7-Zip (Igor Pavlov)
```

### Custom Vendors
- Users can add custom vendors to any tier
- Custom vendors override defaults
- Vendors can be assigned to custom groups

---

## [SHIELD] Default Deny Rules

The app can optionally include default deny rules for high-risk locations and restricted software:

### Recommended Deny Rules - High-Risk Locations
| Location | Rationale | Default State |
|----------|-----------|---------------|
| `%USERPROFILE%\Downloads\*` | Common malware entry point | Suggested |
| `%USERPROFILE%\Desktop\*` | Users may run untrusted files | Suggested |
| `%TEMP%\*` | Malware often executes from temp | Suggested |
| `%LOCALAPPDATA%\Temp\*` | Additional temp location | Suggested |
| `C:\Users\*\AppData\Local\*` (non-whitelisted) | Unauthorized app installs | Optional |
| `\\*\*` (UNC paths) | Network-based attacks | Optional |
| `Removable Media\*` | USB-based malware | Optional |

### Recommended Deny Rules - Admin Browser Restrictions
Block web browsers for privileged accounts to prevent credential theft and drive-by attacks on admin workstations/servers.

| Application | Publisher | Applies To | Rationale |
|-------------|-----------|------------|-----------|
| Chrome | Google LLC | Domain Admins, Server Admins, Enterprise Admins | Prevent admin credential phishing |
| Edge | Microsoft Corporation | Domain Admins, Server Admins, Enterprise Admins | Prevent drive-by downloads |
| Firefox | Mozilla Corporation | Domain Admins, Server Admins, Enterprise Admins | Reduce attack surface |
| Brave | Brave Software, Inc. | Domain Admins, Server Admins, Enterprise Admins | Block all browser variants |
| Opera | Opera Norway AS | Domain Admins, Server Admins, Enterprise Admins | Block all browser variants |
| Vivaldi | Vivaldi Technologies AS | Domain Admins, Server Admins, Enterprise Admins | Block all browser variants |

**Browser Executable Patterns to Block:**
```
chrome.exe
msedge.exe
firefox.exe
brave.exe
opera.exe
vivaldi.exe
iexplore.exe
browser_broker.exe
```

**Browser Deny Rule Logic:**
- Deny rules apply to specific admin groups (not Everyone)
- Standard users retain browser access
- Admins can use dedicated non-privileged accounts for browsing
- Consider PAW (Privileged Access Workstation) scenarios

### Recommended Deny Rules - Servers & Domain Controllers
Additional restrictions for server environments:

| Application | Applies To | Rationale |
|-------------|------------|-----------|
| All web browsers | Servers, Domain Controllers | No browsing on servers |
| Gaming platforms (Steam, Epic) | Servers, Domain Controllers | No gaming software |
| Consumer chat apps (Discord, Telegram) | Servers, Domain Controllers | Unauthorized communication |
| Remote access tools (TeamViewer, AnyDesk) | All (unless explicitly approved) | Prevent unauthorized remote access |
| Torrent clients | All | Prevent P2P file sharing |
| Crypto miners | All | Block known mining executables |

**Known Unauthorized Software Patterns:**
```
# Gaming
steam.exe, steamwebhelper.exe
EpicGamesLauncher.exe
Origin.exe, OriginWebHelperService.exe

# Consumer Chat
Discord.exe, Update.exe (Discord)
Telegram.exe
Slack.exe (if not enterprise-approved)

# Remote Access (block unless approved)
TeamViewer.exe, TeamViewer_Service.exe
AnyDesk.exe
LogMeIn.exe
ammyy.exe

# Torrent/P2P
utorrent.exe, bittorrent.exe
qbittorrent.exe
deluge.exe

# Crypto Miners (common names)
xmrig.exe, minergate.exe
nicehash.exe, ethminer.exe
```

### Default Deny Rule Configuration
```
Settings -> Rule Generation -> Default Deny Rules

HIGH-RISK LOCATIONS
  [x] Block Downloads folder
  [x] Block Desktop executables  
  [x] Block Temp folders
  [ ] Block AppData (may break apps)
  [ ] Block UNC paths
  [ ] Block Removable Media

ADMIN BROWSER RESTRICTIONS
  [x] Block browsers for Domain Admins
  [x] Block browsers for Server Admins
  [x] Block browsers for Enterprise Admins
  [ ] Block browsers for all admins (custom groups)
  
  Admin Groups to Apply:
    - Domain Admins (default)
    - Server Admins (default)
    - Enterprise Admins (default)
    - [+ Add Custom Admin Group]

SERVER RESTRICTIONS
  [x] Block all browsers on Servers
  [x] Block all browsers on Domain Controllers
  [x] Block gaming platforms
  [x] Block consumer chat apps
  [x] Block unauthorized remote access tools
  [ ] Block torrent clients
  [ ] Block crypto miners

EXCEPTIONS
  - [User can add specific allowed paths/apps]
  - [Override for specific machines/OUs]
```

### Deny Rule Generation Output
When deny rules are enabled, the app generates:

```xml
<!-- Example: Block Chrome for Domain Admins -->
<FilePublisherRule Id="..." Name="Deny Chrome for Domain Admins" 
                   Description="Block web browsers for privileged accounts" 
                   UserOrGroupSid="S-1-5-21-...-512" Action="Deny">
  <Conditions>
    <FilePublisherCondition PublisherName="O=GOOGLE LLC, L=MOUNTAIN VIEW, S=CA, C=US" 
                            ProductName="GOOGLE CHROME" BinaryName="CHROME.EXE">
      <BinaryVersionRange LowSection="*" HighSection="*"/>
    </FilePublisherCondition>
  </Conditions>
</FilePublisherRule>

<!-- Example: Block all browsers on Servers via Path -->
<FilePathRule Id="..." Name="Deny Browsers on Servers" 
              Description="No web browsing on servers" 
              UserOrGroupSid="S-1-1-0" Action="Deny">
  <Conditions>
    <FilePathCondition Path="%PROGRAMFILES%\Google\Chrome\Application\chrome.exe"/>
  </Conditions>
</FilePathRule>
```

### Best Practices for Admin Browser Restrictions
1. **Use Tiered Admin Model:** Tier 0 (DC admins), Tier 1 (Server admins), Tier 2 (Workstation admins)
2. **Separate Accounts:** Admins should have separate accounts for admin tasks vs daily work
3. **PAW Strategy:** Privileged Access Workstations should have maximum restrictions
4. **Allow Exceptions:** Document any exceptions with business justification
5. **Monitor Violations:** Review audit logs for blocked browser attempts

---

## [OK] STIG & Compliance Mapping

### AppLocker STIG Requirements (Windows 10/11)

| STIG ID | Requirement | How GA-AppLocker Helps |
|---------|-------------|------------------------|
| V-220848 | AppLocker must be configured to restrict software execution | Policy deployment with enforcement |
| V-220849 | AppLocker EXE rules must be configured | Phase 1+ deployment |
| V-220850 | AppLocker MSI rules must be configured | Phase 3+ deployment |
| V-220851 | AppLocker Script rules must be configured | Phase 2+ deployment |
| V-220852 | AppLocker DLL rules should be configured | Phase 4 deployment |
| V-220853 | AppLocker must have rules for packaged apps | Appx rule support |

### Compliance Report Mapping
```
Compliance Report includes:
  - STIG ID coverage checklist
  - Per-machine policy status
  - Rule collection enforcement status
  - Audit vs Enforce mode status
  - Exceptions documentation
  - Last policy update timestamp
  - Auditor signature line
```

### NIST 800-53 Mapping
| Control | Description | Coverage |
|---------|-------------|----------|
| CM-7 | Least functionality | Application whitelisting |
| CM-11 | User-installed software | MSI/EXE restrictions |
| SI-7 | Software integrity | Publisher verification |
| AU-2 | Audit events | Event log collection |

---

## [GLOBE] Localization & Accessibility

### Localization Support
```
Supported Languages (v1.0):
  - English (US) - Default

Future Languages (v2.0+):
  - English (UK)
  - Spanish
  - French
  - German
  - Japanese

Localization Scope:
  - UI labels and text
  - Error messages
  - Help documentation
  - Report templates
  
NOT Localized:
  - Log files (always English)
  - PowerShell output
  - XML policy content
  - AD/Windows system data
```

### Accessibility (WCAG 2.1 AA Target)
```
Keyboard Navigation:
  - All functions accessible via keyboard
  - Logical tab order
  - Keyboard shortcuts for common actions
  - Focus indicators visible

Screen Reader:
  - All controls labeled
  - Status changes announced
  - Data grids navigable
  - Progress updates announced

Visual:
  - Minimum 4.5:1 contrast ratio
  - No color-only indicators
  - Resizable text (up to 200%)
  - High contrast theme support

Motor:
  - No time-limited interactions
  - Large click targets (44x44px minimum)
  - Drag-and-drop has keyboard alternative
```

---

## [MAP] Future Roadmap

### Version 1.1 (Q2 2026)
- [ ] Scheduled scans (recurring)
- [ ] Email notifications for events
- [ ] SIEM integration (Splunk HEC)
- [ ] Policy comparison view (diff)

### Version 1.2 (Q3 2026)
- [ ] Multi-domain support
- [ ] Forest-wide discovery
- [ ] Central management server mode
- [ ] REST API for automation

### Version 2.0 (Q4 2026)
- [ ] Web-based dashboard (optional)
- [ ] Multi-user with RBAC
- [ ] Policy simulation/what-if
- [ ] Machine learning for anomaly detection

### Version 2.1 (2027)
- [ ] Integration with WDAC (Windows Defender Application Control)
- [ ] Cloud-managed policies (Azure/Intune)
- [ ] Automated policy recommendations
- [ ] Cross-platform agent (limited)

---

## [ATTACH] Appendices

### Appendix A: AppLocker Event IDs Reference

#### Event Categories

| Category | Event IDs | Description |
|----------|-----------|-------------|
| **Allowed** | 8001, 8005, 8020, 8023 | Application/script was allowed to run |
| **Audit (Would Block)** | 8002, 8006, 8021, 8024 | Would be blocked if enforced |
| **Blocked** | 8003, 8004, 8007, 8022, 8025 | Application/script was blocked |
| **Policy** | 8000 | Policy applied successfully |

#### Complete Event ID Reference

| Event ID | Level | Category | Rule Type | Description |
|----------|-------|----------|-----------|-------------|
| 8000 | Info | Policy | All | AppLocker policy applied successfully |
| 8001 | Info | Allowed | EXE/DLL | Executable or DLL was allowed |
| 8002 | Warning | Audit | EXE/DLL | Would be blocked (audit mode) |
| 8003 | Warning | Blocked | EXE/DLL | Executable or DLL was blocked |
| 8004 | Error | Blocked | EXE/DLL | Blocked (enforcement mode) |
| 8005 | Info | Allowed | Script/MSI | Script or MSI was allowed |
| 8006 | Warning | Audit | Script/MSI | Would be blocked (audit mode) |
| 8007 | Error | Blocked | Script/MSI | Script or MSI was blocked |
| 8020 | Info | Allowed | Appx | Packaged app allowed |
| 8021 | Warning | Audit | Appx | Packaged app would be blocked |
| 8022 | Error | Blocked | Appx | Packaged app blocked |
| 8023 | Info | Allowed | Appx Installer | Packaged app installer allowed |
| 8024 | Warning | Audit | Appx Installer | Packaged app installer would be blocked |
| 8025 | Error | Blocked | Appx Installer | Packaged app installer blocked |

#### Event Log Locations

```
Windows Logs:
  - Application and Services Logs
    - Microsoft
      - Windows
        - AppLocker
          - EXE and DLL        (8001-8004)
          - MSI and Script     (8005-8007)
          - Packaged app-Deployment  (8023-8025)
          - Packaged app-Execution   (8020-8022)
```

---

## [FILTER] AppLocker Event Filtering & Analysis

### Event Filter Categories

The app provides filtering capabilities for AppLocker events collected during scans:

#### Filter by Event Action

| Filter | Event IDs | Use Case |
|--------|-----------|----------|
| **All Events** | 8000-8025 | Complete audit trail |
| **Allowed Only** | 8001, 8005, 8020, 8023 | See what's currently running |
| **Audit Only (Would Block)** | 8002, 8006, 8021, 8024 | Preview impact before enforcement |
| **Blocked Only** | 8003, 8004, 8007, 8022, 8025 | Identify enforcement issues |
| **Policy Events** | 8000 | Track policy application |

#### Filter UI

```
+-----------------------------------------------------------------------------+
| EVENT LOG VIEWER                                             [Export CSV]   |
+-----------------------------------------------------------------------------+
| FILTERS                                                                     |
| +-------------------------------------------------------------------------+ |
| | Action: [All v] [x Allowed] [x Audit] [x Blocked]                       | |
| | Type:   [All v] [x EXE/DLL] [x Script/MSI] [x Appx]                    | |
| | Date:   [Last 24 hours v]  From: [__________] To: [__________]         | |
| | Machine: [All Machines v]  OU: [All OUs v]                              | |
| | Search:  [___________________________] [Search]                         | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| RESULTS (1,234 events)                                     [Refresh]        |
| +---------------------------------------------------------------------------+
| | Time       | Machine | Action  | Type    | File              | User      |
| +------------+---------+---------+---------+-------------------+-----------+
| | 14:32:01   | WS001   | Blocked | EXE     | malware.exe       | jsmith    |
| | 14:31:45   | WS001   | Audit   | Script  | custom.ps1        | jsmith    |
| | 14:30:22   | WS002   | Allowed | EXE     | chrome.exe        | mwilson   |
| | 14:29:58   | SVR01   | Blocked | MSI     | unknown.msi       | svc_deploy|
| | ...        | ...     | ...     | ...     | ...               | ...       |
| +---------------------------------------------------------------------------+
|                                                                             |
| SELECTED EVENT DETAILS                                                      |
| +-------------------------------------------------------------------------+ |
| | Event ID: 8004                                                          | |
| | Time: 2026-01-16 14:32:01                                               | |
| | Machine: WS001.corp.local                                               | |
| | User: CORP\jsmith                                                       | |
| | Action: BLOCKED                                                         | |
| | File: C:\Users\jsmith\Downloads\malware.exe                            | |
| | Hash: ABC123...                                                         | |
| | Publisher: (Not Signed)                                                 | |
| | Rule: Default Deny - Downloads Folder                                   | |
| |                                                                         | |
| | [Create Allow Rule] [Add to Exceptions] [View Similar Events]          | |
| +-------------------------------------------------------------------------+ |
+-----------------------------------------------------------------------------+
```

### Event Collection During Scans

```powershell
function Get-AppLockerEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [Parameter()]
        [PSCredential]$Credential,
        
        [Parameter()]
        [ValidateSet('All', 'Allowed', 'Audit', 'Blocked')]
        [string]$ActionFilter = 'All',
        
        [Parameter()]
        [ValidateSet('All', 'ExeDll', 'ScriptMsi', 'Appx')]
        [string]$TypeFilter = 'All',
        
        [Parameter()]
        [datetime]$StartTime = (Get-Date).AddDays(-7),
        
        [Parameter()]
        [datetime]$EndTime = (Get-Date),
        
        [Parameter()]
        [int]$MaxEvents = 1000
    )
    
    # Define event ID mappings
    $eventIdMap = @{
        'Allowed' = @(8001, 8005, 8020, 8023)
        'Audit'   = @(8002, 8006, 8021, 8024)
        'Blocked' = @(8003, 8004, 8007, 8022, 8025)
    }
    
    $typeLogMap = @{
        'ExeDll'    = 'Microsoft-Windows-AppLocker/EXE and DLL'
        'ScriptMsi' = 'Microsoft-Windows-AppLocker/MSI and Script'
        'Appx'      = 'Microsoft-Windows-AppLocker/Packaged app-Execution'
    }
    
    # Build event ID filter
    $eventIds = switch ($ActionFilter) {
        'Allowed' { $eventIdMap.Allowed }
        'Audit'   { $eventIdMap.Audit }
        'Blocked' { $eventIdMap.Blocked }
        'All'     { $eventIdMap.Allowed + $eventIdMap.Audit + $eventIdMap.Blocked + @(8000) }
    }
    
    # Build log names filter
    $logNames = switch ($TypeFilter) {
        'ExeDll'    { @($typeLogMap.ExeDll) }
        'ScriptMsi' { @($typeLogMap.ScriptMsi) }
        'Appx'      { @($typeLogMap.Appx) }
        'All'       { $typeLogMap.Values }
    }
    
    # Collect events from remote machine
    $scriptBlock = {
        param($logNames, $eventIds, $startTime, $endTime, $maxEvents)
        
        $allEvents = @()
        foreach ($logName in $logNames) {
            try {
                $events = Get-WinEvent -FilterHashtable @{
                    LogName   = $logName
                    Id        = $eventIds
                    StartTime = $startTime
                    EndTime   = $endTime
                } -MaxEvents $maxEvents -ErrorAction SilentlyContinue
                
                $allEvents += $events
            }
            catch {
                # Log not available or empty
            }
        }
        return $allEvents
    }
    
    $sessionParams = @{ ComputerName = $ComputerName }
    if ($Credential) { $sessionParams.Credential = $Credential }
    
    $events = Invoke-Command @sessionParams -ScriptBlock $scriptBlock `
        -ArgumentList $logNames, $eventIds, $StartTime, $EndTime, $MaxEvents
    
    # Parse and return structured event data
    return $events | ForEach-Object {
        [PSCustomObject]@{
            EventId      = $_.Id
            Time         = $_.TimeCreated
            MachineName  = $ComputerName
            Action       = Get-EventAction -EventId $_.Id
            Type         = Get-EventType -EventId $_.Id
            FilePath     = $_.Properties[1].Value
            FileHash     = $_.Properties[2].Value
            UserName     = $_.Properties[4].Value
            RuleName     = $_.Properties[5].Value
            Message      = $_.Message
        }
    }
}

function Get-EventAction {
    param([int]$EventId)
    switch ($EventId) {
        { $_ -in @(8001, 8005, 8020, 8023) } { return 'Allowed' }
        { $_ -in @(8002, 8006, 8021, 8024) } { return 'Audit' }
        { $_ -in @(8003, 8004, 8007, 8022, 8025) } { return 'Blocked' }
        8000 { return 'Policy' }
        default { return 'Unknown' }
    }
}

function Get-EventType {
    param([int]$EventId)
    switch ($EventId) {
        { $_ -in @(8001, 8002, 8003, 8004) } { return 'EXE/DLL' }
        { $_ -in @(8005, 8006, 8007) } { return 'Script/MSI' }
        { $_ -in @(8020, 8021, 8022, 8023, 8024, 8025) } { return 'Appx' }
        8000 { return 'Policy' }
        default { return 'Unknown' }
    }
}
```

### Event-Based Rule Generation

Create rules directly from blocked/audit events:

```
+-----------------------------------------------------------------------------+
| CREATE RULES FROM EVENTS                                                    |
+-----------------------------------------------------------------------------+
|                                                                             |
| Source: 47 Audit events selected (would be blocked)                         |
|                                                                             |
| +-------------------------------------------------------------------------+ |
| | File                  | Count | Publisher        | Suggested Rule       | |
| +-----------------------+-------+------------------+----------------------+ |
| | custom_app.exe        | 23    | Internal Corp    | Publisher Rule   [v]| |
| | legacy_tool.exe       | 15    | (Not Signed)     | Hash Rule        [v]| |
| | update_helper.exe     | 9     | UpdateCorp Inc   | Publisher Rule   [v]| |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| Options:                                                                    |
| [x] Group by publisher (reduce rule count)                                  |
| [x] Use hash for unsigned files                                             |
| [ ] Include version restrictions                                            |
|                                                                             |
| Target Policy: [Workstation-Policy-v2 v]                                    |
| Action: (x) Allow  ( ) Deny                                                 |
| Group:  [Authenticated Users v]                                             |
|                                                                             |
| [Cancel]                           [Preview Rules]  [Create 3 Rules]        |
+-----------------------------------------------------------------------------+
```

### Event Analysis Dashboard

```
+-----------------------------------------------------------------------------+
| EVENT ANALYSIS DASHBOARD                            Period: Last 7 Days     |
+-----------------------------------------------------------------------------+
|                                                                             |
| SUMMARY                                                                     |
| +-------------------+  +-------------------+  +-------------------+         |
| | ALLOWED           |  | AUDIT             |  | BLOCKED           |         |
| |      12,456       |  |        847        |  |        23         |         |
| | [OK]              |  | (!) Review        |  | (X) Critical      |         |
| +-------------------+  +-------------------+  +-------------------+         |
|                                                                             |
| TOP BLOCKED APPLICATIONS                     TOP AUDIT (WOULD BLOCK)        |
| +--------------------------------+          +--------------------------------+
| | 1. malware.exe (12)            |          | 1. custom_tool.ps1 (234)      |
| | 2. unauthorized.msi (8)        |          | 2. legacy_app.exe (189)       |
| | 3. game.exe (3)                |          | 3. dept_script.bat (156)      |
| +--------------------------------+          +--------------------------------+
|                                                                             |
| EVENTS BY MACHINE TYPE                      EVENTS BY RULE TYPE             |
| +--------------------------------+          +--------------------------------+
| | Workstations: 11,234 (87%)     |          | EXE/DLL: 10,890 (84%)         |
| | Servers: 1,456 (11%)           |          | Script/MSI: 1,923 (15%)       |
| | DCs: 246 (2%)                  |          | Appx: 113 (1%)                |
| +--------------------------------+          +--------------------------------+
|                                                                             |
| TREND (Last 7 Days)                                                         |
| Blocked: __|__|##|__|__|__|__  (spike on day 3 - investigate)              |
| Audit:   ##|##|##|##|##|##|##  (consistent - ready for enforcement?)       |
|                                                                             |
| [Export Report]  [Create Rules from Audit]  [Investigate Blocked]           |
+-----------------------------------------------------------------------------+
```

### Event Filter Presets

| Preset | Filters Applied | Use Case |
|--------|-----------------|----------|
| **Pre-Enforcement Review** | Audit events only, last 30 days | See what will break before enforcing |
| **Active Blocks** | Blocked events, last 24 hours | Immediate issues to resolve |
| **New Applications** | Allowed + Audit, unknown publishers | Discover new software |
| **Admin Activity** | All events, admin users only | Audit privileged actions |
| **Server Issues** | Blocked + Audit, Servers only | Server-specific problems |
| **Script Audit** | Script/MSI type, all actions | Review script execution |

### Appendix B: Common Troubleshooting

| Issue | Likely Cause | Solution |
|-------|--------------|----------|
| WinRM connection failed | WinRM not enabled | Run `Enable-PSRemoting -Force` on target |
| Access denied during scan | Wrong credentials | Check credential profile, verify permissions |
| GPO not applying | Replication delay | Wait or run `gpupdate /force` |
| Policy validation fails | Invalid XML | Check for special characters, validate manually |
| Slow AD discovery | Large AD | Use OU filtering, increase timeout |
| Missing artifacts | Scan depth too shallow | Use "Deep" scan depth |
| Rules not generating | No valid artifacts | Check artifact signatures, use Hash fallback |

### Appendix C: PowerShell Requirements

```powershell
# Required Modules
ActiveDirectory    # AD discovery, GPO management
GroupPolicy        # GPO creation and linking
AppLocker          # Policy generation and testing

# Verify installation
Get-Module -ListAvailable ActiveDirectory, GroupPolicy, AppLocker

# Install if missing (requires RSAT)
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
```

### Appendix D: File Format Specifications

#### CSV Import Format
```csv
FilePath,FileName,FileHash,Publisher,ProductName,Version,IsSigned,FileType
"C:\Program Files\App\app.exe","app.exe","ABC123...","Vendor Inc.","App Name","1.0.0","True","EXE"
```

#### JSON Import Format
```json
{
  "artifacts": [
    {
      "filePath": "C:\\Program Files\\App\\app.exe",
      "fileName": "app.exe",
      "fileHash": "ABC123...",
      "publisher": "Vendor Inc.",
      "productName": "App Name",
      "version": "1.0.0",
      "isSigned": true,
      "fileType": "EXE"
    }
  ],
  "exportDate": "2026-01-16T12:00:00Z",
  "sourceHost": "WORKSTATION01"
}
```

### Appendix E: Sample Policy XML Structure
```xml
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FilePublisherRule Id="..." Name="..." Description="..." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=MICROSOFT..." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FileHashRule Id="..." Name="..." Description="..." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x..." SourceFileName="app.exe" SourceFileLength="12345"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
  <!-- Additional RuleCollections: Msi, Script, Dll, Appx -->
</AppLockerPolicy>
```

### Appendix F: WinRM Configuration Guide

#### GPO Settings for WinRM

To enable WinRM via Group Policy for remote scanning:

```
Computer Configuration
  -> Policies
    -> Administrative Templates
      -> Windows Components
        -> Windows Remote Management (WinRM)
          -> WinRM Service
            -> Allow remote server management through WinRM
              [Enabled]
              IPv4 filter: * (or specific subnets)
              IPv6 filter: * (or specific subnets)

Computer Configuration
  -> Policies
    -> Administrative Templates
      -> Windows Components
        -> Windows Remote Shell
          -> Allow Remote Shell Access
            [Enabled]
```

#### Firewall Rules

```
Inbound Rules Required:
  - Windows Remote Management (HTTP-In)
    Protocol: TCP
    Port: 5985
    Action: Allow
    Profile: Domain (minimum), Private (optional)

  - Windows Remote Management (HTTPS-In) [Optional, recommended]
    Protocol: TCP
    Port: 5986
    Action: Allow
    Profile: Domain

GPO Path:
  Computer Configuration
    -> Policies
      -> Windows Settings
        -> Security Settings
          -> Windows Defender Firewall with Advanced Security
            -> Inbound Rules
```

#### PowerShell Verification Script

```powershell
function Test-WinRMReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [Parameter()]
        [PSCredential]$Credential
    )
    
    $result = [PSCustomObject]@{
        ComputerName     = $ComputerName
        WinRMEnabled     = $false
        Port5985Open     = $false
        Port5986Open     = $false
        CanConnect       = $false
        AuthMethod       = $null
        ErrorMessage     = $null
    }
    
    # Test port connectivity
    $result.Port5985Open = (Test-NetConnection -ComputerName $ComputerName -Port 5985 -WarningAction SilentlyContinue).TcpTestSucceeded
    $result.Port5986Open = (Test-NetConnection -ComputerName $ComputerName -Port 5986 -WarningAction SilentlyContinue).TcpTestSucceeded
    
    if (-not $result.Port5985Open -and -not $result.Port5986Open) {
        $result.ErrorMessage = "Neither port 5985 nor 5986 is accessible"
        return $result
    }
    
    # Test WinRM connection
    try {
        $sessionParams = @{
            ComputerName = $ComputerName
            ErrorAction  = 'Stop'
        }
        if ($Credential) {
            $sessionParams.Credential = $Credential
        }
        
        $session = New-PSSession @sessionParams
        $result.WinRMEnabled = $true
        $result.CanConnect = $true
        $result.AuthMethod = $session.Transport
        Remove-PSSession $session
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    
    return $result
}

# Bulk test multiple machines
function Test-WinRMBulk {
    param([string[]]$ComputerNames, [PSCredential]$Credential)
    
    $results = @()
    foreach ($computer in $ComputerNames) {
        Write-Progress -Activity "Testing WinRM" -Status $computer
        $results += Test-WinRMReadiness -ComputerName $computer -Credential $Credential
    }
    return $results
}
```

#### CredSSP Configuration for Double-Hop

When scanning from a jump server, CredSSP may be required:

```powershell
# On the admin workstation (client)
Enable-WSManCredSSP -Role Client -DelegateComputer "*.corp.local" -Force

# On target machines (server) - via GPO recommended
Enable-WSManCredSSP -Role Server -Force

# GPO Path for CredSSP:
#   Computer Configuration
#     -> Policies
#       -> Administrative Templates
#         -> System
#           -> Credentials Delegation
#             -> Allow delegating fresh credentials
#               [Enabled]
#               Add servers: WSMAN/*.corp.local
```

#### Common WinRM Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "WinRM client cannot process the request" | WinRM not enabled | `Enable-PSRemoting -Force` on target |
| "Access denied" | Insufficient permissions | Use correct tier credentials |
| "The WinRM client sent a request to an HTTP server and got a response saying the requested HTTP URL was not available" | HTTP listener not configured | `winrm quickconfig` on target |
| "The connection to the specified remote host was refused" | Firewall blocking | Check Windows Firewall rules |
| "Kerberos authentication error" | Time sync or SPN issue | Verify time sync within 5 minutes |
| "CredSSP authentication failed" | CredSSP not enabled | Enable CredSSP on client and server |

### Appendix G: Glossary (Expanded)

| Term | Definition |
|------|------------|
| **AppLocker** | Windows feature for application whitelisting/blacklisting |
| **Artifact** | File metadata collected during scans (exe, dll, script, msi) |
| **CredSSP** | Credential Security Support Provider - allows credential delegation |
| **DPAPI** | Data Protection API - Windows encryption tied to user/machine |
| **FQBN** | Fully Qualified Binary Name - Publisher\Product\Binary\Version |
| **FQDN** | Fully Qualified Domain Name - hostname.domain.com |
| **GPO** | Group Policy Object - AD policy container |
| **Hash Rule** | AppLocker rule based on file SHA256 hash |
| **NIST 800-53** | Security and privacy controls framework |
| **OU** | Organizational Unit - AD container for objects |
| **PAW** | Privileged Access Workstation - hardened admin workstation |
| **Path Rule** | AppLocker rule based on file path (least secure) |
| **Publisher Rule** | AppLocker rule based on digital signature (most flexible) |
| **RSAT** | Remote Server Administration Tools |
| **SID** | Security Identifier - unique ID for security principals |
| **STIG** | Security Technical Implementation Guide (DoD) |
| **SYSVOL** | Shared folder on DCs for GPO files and scripts |
| **Tier 0** | Domain Controllers (highest privilege) |
| **Tier 1** | Member Servers (medium privilege) |
| **Tier 2** | Workstations (standard privilege) |
| **WinRM** | Windows Remote Management - PowerShell remoting protocol |

### Appendix H: Architecture Diagram

```
+-----------------------------------------------------------------------------+
|                         GA-APPLOCKER ARCHITECTURE                           |
+-----------------------------------------------------------------------------+

  +---------------------------+
  |      USER INTERFACE       |
  |       (WPF/XAML)          |
  +-------------+-------------+
                |
                | Events / Commands
                v
  +---------------------------+
  |     VIEW MODELS           |
  |   (MVVM Data Binding)     |
  +-------------+-------------+
                |
                | Function Calls
                v
+---------------+---------------+---------------+---------------+
|               |               |               |               |
v               v               v               v               v
+-----------+ +-----------+ +-----------+ +-----------+ +-----------+
|   Core    | | Discovery | | Scanning  | |   Rules   | |  Policy   |
|  Module   | |  Module   | |  Module   | |  Module   | |  Module   |
+-----------+ +-----------+ +-----------+ +-----------+ +-----------+
| - Logging | | - AD Query| | - WinRM   | | - Generate| | - Build   |
| - Config  | | - OU Tree | | - Artifact| | - Validate| | - Merge   |
| - Utils   | | - Machine | |   Collect | | - Group   | | - Export  |
+-----------+ +-----------+ +-----------+ +-----------+ +-----------+
      |             |              |             |             |
      +-------------+--------------+-------------+-------------+
                                   |
                                   v
              +--------------------+--------------------+
              |                                         |
              v                                         v
  +---------------------+                   +---------------------+
  |   LOCAL STORAGE     |                   |  EXTERNAL SYSTEMS   |
  +---------------------+                   +---------------------+
  | - Scans/*.json      |                   | - Active Directory  |
  | - Settings.json     |                   | - WinRM Targets     |
  | - Credentials.enc   |                   | - SYSVOL/GPO        |
  | - Logs/*.log        |                   | - DNS               |
  +---------------------+                   +---------------------+

DATA FLOW:
==========

1. DISCOVERY FLOW:
   AD --> [Discovery Module] --> Machine List --> [UI Grid]

2. SCAN FLOW:
   Machine List --> [Credential Selection] --> [WinRM] --> Target Machine
   Target Machine --> Artifacts --> [Scanning Module] --> Scans/*.json

3. RULE GENERATION FLOW:
   Artifacts --> [Rules Module] --> Smart Assignment --> Rules List

4. DEPLOYMENT FLOW:
   Rules --> [Policy Module] --> Policy XML --> [GPO] --> SYSVOL --> Targets
```

### Appendix I: Quick Reference Card

```
+-----------------------------------------------------------------------------+
|                    GA-APPLOCKER QUICK REFERENCE                             |
+-----------------------------------------------------------------------------+

KEYBOARD SHORTCUTS
------------------
Ctrl+S          Save current work
Ctrl+Z          Undo last action
Ctrl+Y          Redo
Ctrl+F          Search/Filter
Ctrl+G          Generate rules
Ctrl+D          Deploy policy
Ctrl+A          Select all
Ctrl+1-6        Navigate panels
F5              Refresh
Escape          Cancel/Deselect

COMMON WORKFLOWS
----------------
Full Scan:      Dashboard -> [SCAN] Full Scan -> Wait -> Review -> Generate
Quick Import:   Dashboard -> [IMPORT] Import & Generate -> Select file -> Done
Deploy Policy:  Policy Builder -> Select policy -> [DEPLOY] -> Confirm

ERROR CODES
-----------
1xxx  Connection errors    (1001=WinRM unavailable, 1002=Access denied)
2xxx  Data errors          (2001=Corrupt file, 2002=Missing field)
3xxx  Policy errors        (3001=Invalid XML, 3002=GPO failed)
4xxx  System errors        (4001=Out of memory, 4002=Disk full)

PHASE DEFINITIONS
-----------------
Phase 1:  Pilot deployment, AuditOnly, limited OU scope
Phase 2:  Expanded deployment, AuditOnly, broader scope
Phase 3:  Full deployment, AuditOnly, all target OUs
Phase 4:  Enforcement enabled (blocking mode)

SCAN DEPTHS
-----------
Quick:    Program Files, System32 only (~30 sec/machine)
Standard: + SysWOW64, ProgramData, user apps (~2 min/machine)
Deep:     + Full drive scan, all users (~5 min/machine)

TIER MODEL
----------
Tier 0:  Domain Controllers  -> Use Domain Admin credentials
Tier 1:  Member Servers      -> Use Server Admin credentials
Tier 2:  Workstations        -> Use Workstation Admin credentials

SUPPORT
-------
Logs:     %LOCALAPPDATA%\GA-AppLocker\Logs\
Config:   %LOCALAPPDATA%\GA-AppLocker\Settings\
Scans:    %LOCALAPPDATA%\GA-AppLocker\Scans\
+-----------------------------------------------------------------------------+
```

---

*End of Specification Document*

**Document Control:**
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-13 | Tony | Initial vision document |
| 2.0 | 2026-01-16 | Tony | Added full specification |
| 2.1 | 2026-01-16 | Tony | Added user stories, API specs, state management, rollback, vendor lists, compliance, roadmap, appendices |
| 2.2 | 2026-01-16 | Tony | Added comprehensive data interoperability & field mapping, expanded deny rules for admin browsers |
| 2.3 | 2026-01-16 | Tony | Added tiered credential access model (Tier 0/1/2), auto-credential selection, credential validation, GPO considerations |
| 2.4 | 2026-01-16 | Tony | Added UX friction reduction: one-click workflows, scan groups with OU-based defaults, artifact storage structure (Scans/date/hostname), review & approve screen with traffic lights, inline editing, multi-select, context menus, keyboard shortcuts, auto-save, deploy all, first-time wizard |
| 2.5 | 2026-01-16 | Tony | Added development principles: KISS, single-purpose functions (<30 lines), clear contracts, early returns, module organization, error handling patterns, naming conventions, code quality checklist, anti-patterns, testing requirements, documentation standards |
| 2.6 | 2026-01-16 | Tony | Added embedded documentation standards (inline comments, region blocks, why/reference/perf comments), session context persistence (SESSION_LOG.md, CURRENT_STATE.md, DECISIONS.md, auto-save script) |
| 2.7 | 2026-01-16 | Tony | Added from spec review: AppLocker event filtering (Allowed/Audit/Blocked), error code system (1xxx-5xxx), multi-admin handling with lock files, documented assumptions, phase definitions clarified, scan depth definitions, WinRM configuration guide (Appendix F), expanded glossary (Appendix G), architecture diagram (Appendix H), quick reference card (Appendix I), additional edge cases |
