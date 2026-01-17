# GA-AppLocker Dashboard
## Vision & Functional Requirements

---

## 🎯 Core Vision

> Scan AD for hosts, then scan the hosts for artifacts related to AppLocker, for the app to ingest those artifacts seamlessly to automatically create rules based on best practices and security playbook, then merge all rules from various sources by workstation, member server, or domain controller to create a policy and apply to those OUs in audit mode depending on phases. Provide a one-click workflow to import scan artifacts and auto-generate rules from the imported data using AppLocker best-practice logic.

---

## 📋 Functional Requirements

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
- **Smart Rule Priority Engine**: Publisher → Hash (Path avoided)
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
- Publisher Grouping: Reduces rule count (e.g., 45 items → 1 rule)
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
- `C:\Windows\*` → Everyone
- `C:\Program Files\*` → Authenticated Users
- `C:\Program Files\*\Admin*\*` → IT Admins
- `C:\Users\*` → Block or specific user (flag for review)

**Publisher-Based Detection:**
- Microsoft signed → Everyone
- Known enterprise vendor (Adobe, Google, etc.) → Authenticated Users
- Unknown/unsigned publisher → Manual review / IT Admins only

**Machine Type Context:**
- DC scan artifacts → Default to Domain Admins (most restrictive)
- Server scan artifacts → Default to Server Admins
- Workstation scan artifacts → Default to Authenticated Users (broader access)

**Rule Type Context:**
- Script/MSI rules → Always suggest admin groups first
- EXE/DLL rules → Suggest broader groups (Everyone/Authenticated Users)

#### Group Assignment Features

**Smart Defaults with Override:**
- App auto-selects group based on detection logic
- User can override any suggestion before rule generation
- Visual indicator: "Suggested: Authenticated Users ▼"

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

## 🔑 Key Features Summary

### Credential Management
- Credential switching for different scan targets
- Separate credentials for Workstations, Servers, and Domain Controllers
- Secure credential storage during session
- Credential validation before scan execution
- Support for different admin accounts per environment

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
- Phase 1-3: Audit mode (testing)
- Phase 4: Enforce mode (production)
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

## 🚀 End-to-End Workflow

1. **Scan AD** → Auto-detect domain, discover machines by OU
2. **Scan Machines** → Collect artifacts via WinRM (with credential switching)
3. **Import Artifacts** → CSV/JSON/Comprehensive scan with deduplication
4. **Auto-Generate Rules** → Publisher → Hash priority (best practices)
5. **Smart Group Assignment** → Auto-suggest allow groups based on path, publisher, machine type
6. **Group by Machine Type** → Auto-categorize Workstations/Servers/DCs by OU
7. **Merge Policies** → Combine policies with conflict resolution
8. **Create Policy** → Generate XML with validation
9. **Deploy to OU** → Create GPO, link to OUs, set phase enforcement

---

## 📊 Module Summary

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
