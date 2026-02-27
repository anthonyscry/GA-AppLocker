# STIG Compliance Mapping

## Overview

This document maps GA-AppLocker features to the **Windows 10 STIG** (Security Technical Implementation Guide) controls for AppLocker application whitelisting. It serves as an auditor reference to verify each STIG control is addressed by the tooling.

**Applicable STIGs:**
- Windows 10 STIG V2R8+ (Application Whitelisting section)
- Windows Server 2019 STIG V2R8+ (Application Whitelisting section)

**Last Updated:** 2026-01-28

## Phase 13 Operational Validation Addendum

- Phase 13 release-readiness runbook checks are recorded in `docs/plans/2026-02-18-phase-13-operator-runbook-checks.md`.
- Final verification evidence used for release sign-off is recorded in `docs/plans/2026-02-18-phase-13-verification-evidence.md`.
- Scoped P0/P1 release-blocker triage traceability is maintained in `docs/plans/2026-02-18-phase-13-p0-p1-triage.md`.

---

## Control-to-Feature Matrix

| STIG ID | Severity | Requirement | GA-AppLocker Feature | Module | Validation Stage |
|---------|----------|-------------|----------------------|--------|------------------|
| **V-63329** | CAT II | Configure AppLocker to control executable files | EXE rule generation via `New-HashRule`, `New-PublisherRule`, `New-PathRule` | Rules | Stage 4 (Condition Validation) |
| **V-63331** | CAT II | Configure AppLocker to control script execution | Script artifact scanning (`.ps1`, `.bat`, `.cmd`, `.vbs`, `.js`, `.wsf`); Script collection type in policies | Scanning, Rules, Policy | Stage 1 (Schema: Script collection present) |
| **V-63333** | CAT II | Configure AppLocker to control Windows Installer packages | MSI artifact scanning; MSI collection type in policies | Scanning, Rules, Policy | Stage 1 (Schema: Msi collection present) |
| **V-63335** | CAT III | Configure AppLocker to control DLL files | DLL artifact scanning (configurable via Skip DLL toggle); DLL collection type in policies | Scanning, Rules, Policy | Stage 1 (Schema: Dll collection present) |
| **V-63337** | CAT II | Configure AppLocker rules to allow only authorized applications | Approval workflow: all rules default to `Pending` status; only `Approved` rules included in policy export | Rules, Policy | Stage 4 (User-writable path warnings) |
| **V-63341** | CAT II | Configure AppLocker to enforce rules (not AuditOnly) | Phase-based enforcement: Phase 1-4 = AuditOnly, Phase 5 = Enabled; `Export-PolicyToXml -PhaseOverride 5` | Policy | Stage 1 (EnforcementMode validation), Stage 5 (Live import test) |

---

## Detailed Control Mapping

### V-63329: Executable Control

**Requirement:** The operating system must be configured to use AppLocker to control executable files.

**How GA-AppLocker Addresses This:**
- The **Scanning module** collects EXE artifacts from target machines via `Get-LocalArtifacts` and `Get-RemoteArtifacts`
- The **Rules module** generates Publisher, Hash, and Path rules for EXE files via `New-PublisherRule`, `New-HashRule`, `New-PathRule`
- The **Policy module** groups EXE rules into the `Exe` RuleCollection via `Export-PolicyToXml`
- The **Validation module** verifies the exported XML contains a valid `<RuleCollection Type="Exe">` element

**Verification Command:**
```powershell
$result = Invoke-AppLockerPolicyValidation -XmlPath 'C:\Policies\baseline.xml'
$result.SchemaResult.Details.RuleCollections -contains 'Exe'
# Expected: $true
```

---

### V-63331: Script Control

**Requirement:** Windows PowerShell must be configured to use AppLocker to control script execution.

**How GA-AppLocker Addresses This:**
- The **Scanning module** collects script artifacts: `.ps1`, `.bat`, `.cmd`, `.vbs`, `.js`, `.wsf`
- The **Rules module** generates rules with `CollectionType = 'Script'`
- The **Policy module** includes a `<RuleCollection Type="Script">` element in exported XML
- Phase 2+ policies include script rules (Phase 1 is EXE-only)

**Verification Command:**
```powershell
$result = Invoke-AppLockerPolicyValidation -XmlPath 'C:\Policies\baseline.xml'
$result.SchemaResult.Details.RuleCollections -contains 'Script'
# Expected: $true (Phase 2+)
```

---

### V-63333: Windows Installer Control

**Requirement:** Windows Installer must be configured to use AppLocker to control installation packages.

**How GA-AppLocker Addresses This:**
- The **Scanning module** collects MSI artifacts
- The **Rules module** generates rules with `CollectionType = 'Msi'`
- The **Policy module** includes a `<RuleCollection Type="Msi">` element in exported XML
- Phase 3+ policies include MSI rules

**Verification Command:**
```powershell
$result = Invoke-AppLockerPolicyValidation -XmlPath 'C:\Policies\baseline.xml'
$result.SchemaResult.Details.RuleCollections -contains 'Msi'
# Expected: $true (Phase 3+)
```

---

### V-63335: DLL Control

**Requirement:** AppLocker must be configured to control DLL files.

**How GA-AppLocker Addresses This:**
- The **Scanning module** supports DLL artifact collection (disabled by default via "Skip DLL Scanning" for performance)
- The **Rules module** generates rules with `CollectionType = 'Dll'`
- The **Policy module** includes a `<RuleCollection Type="Dll">` element in Phase 5 exports
- Phase 5 policies include DLL rules (full enforcement)

**Note:** This is a CAT III finding (lower severity). DLL rule enforcement has significant performance impact. Enable DLL scanning only after EXE/Script/MSI rules are stable.

**Verification Command:**
```powershell
# Enable DLL scanning
Start-ArtifactScan -ScanLocal -SkipDllScanning:$false

# Verify DLL collection in policy
$result = Invoke-AppLockerPolicyValidation -XmlPath 'C:\Policies\phase5.xml'
$result.SchemaResult.Details.RuleCollections -contains 'Dll'
# Expected: $true (Phase 5 only)
```

---

### V-63337: Authorized Applications Only

**Requirement:** AppLocker rules must be configured to allow only authorized applications.

**How GA-AppLocker Addresses This:**
- **Approval Workflow:** All generated rules default to `Status = 'Pending'`
- Rules must be explicitly approved via `Set-RuleStatus -Status Approved` before inclusion in policies
- `Export-PolicyToXml` excludes rejected rules by default (`-IncludeRejected` flag required to override)
- Trusted vendor bulk approval via `Approve-TrustedVendorRules` (Microsoft, Adobe, Google, etc.)
- **Validation Stage 4** warns about user-writable paths (`%TEMP%`, `%USERPROFILE%\Downloads`, etc.) that would allow unauthorized execution

**Verification Commands:**
```powershell
# Check rule status distribution
Get-RuleCounts
# Expected: Approved count = only explicitly reviewed rules

# Validate no user-writable path rules
$result = Invoke-AppLockerPolicyValidation -XmlPath 'C:\Policies\baseline.xml'
$result.ConditionResult.Warnings | Where-Object { $_ -match 'user-writable' }
# Expected: No warnings (or acknowledged exceptions)
```

---

### V-63341: Enforce Rules

**Requirement:** AppLocker must be configured to use the "Enforce rules" setting (not AuditOnly).

**How GA-AppLocker Addresses This:**
- **Phase-based deployment model:**
  - Phase 1-3: `EnforcementMode = 'AuditOnly'` (testing period)
  - Phase 4: `EnforcementMode = 'Enabled'` (full enforcement)
- `Export-PolicyToXml -PhaseOverride 4` generates enforcement-ready policies
- **Validation Stage 1** verifies EnforcementMode is a valid value (`NotConfigured`, `AuditOnly`, `Enabled`)
- **Validation Stage 5** performs a live import test to ensure the policy can be applied by the AppLocker service (AppIDSvc)

**Verification Commands:**
```powershell
# Export with enforcement
Export-PolicyToXml -PolicyId 'abc123' -OutputPath 'C:\Policies\enforce.xml' -PhaseOverride 4

# Validate enforcement mode
$result = Invoke-AppLockerPolicyValidation -XmlPath 'C:\Policies\enforce.xml'
$result.OverallSuccess -and $result.CanBeImported
# Expected: $true
```

---

## Validation Pipeline ↔ STIG Mapping

| Validation Stage | Function | STIG Controls Addressed |
|------------------|----------|------------------------|
| **Stage 1: XML Schema** | `Test-AppLockerXmlSchema` | V-63329, V-63331, V-63333, V-63335, V-63341 |
| **Stage 2: GUID Validation** | `Test-AppLockerRuleGuids` | (Technical prerequisite for all controls) |
| **Stage 3: SID Validation** | `Test-AppLockerRuleSids` | V-63337 (correct security principals) |
| **Stage 4: Condition Validation** | `Test-AppLockerRuleConditions` | V-63329, V-63337 (valid rules, no writable paths) |
| **Stage 5: Live Import Test** | `Test-AppLockerPolicyImport` | V-63341 (policy can be enforced) |

---

## Compliance Workflow

The recommended workflow to achieve full STIG compliance:

```
1. DISCOVER    → Get-DomainInfo, Get-OUTree, Get-ComputersByOU
2. SCAN        → Start-ArtifactScan (all artifact types)
3. GENERATE    → Invoke-BatchRuleGeneration -Mode Smart
4. REVIEW      → Set-RuleStatus (approve/reject each rule)
5. BUILD       → New-Policy, Add-RuleToPolicy
6. VALIDATE    → Invoke-AppLockerPolicyValidation (5-stage pipeline)
7. AUDIT       → Export-PolicyToXml -PhaseOverride 1..3 (AuditOnly phases)
8. ENFORCE     → Export-PolicyToXml -PhaseOverride 4 (Enabled)
9. DEPLOY      → Start-Deployment (GPO import)
```

**CRITICAL:** Step 6 (Validation) is MANDATORY before Step 9 (Deploy). The `Export-PolicyToXml` function automatically runs validation unless `-SkipValidation` is specified.

---

## Auditor Checklist

| # | Check | Command | Expected Result |
|---|-------|---------|-----------------|
| 1 | Module loads successfully | `Import-Module GA-AppLocker; (Get-Command -Module GA-AppLocker).Count` | 194+ commands |
| 2 | Validation module available | `Get-Command Invoke-AppLockerPolicyValidation` | Command found |
| 3 | Policy passes all 5 stages | `Invoke-AppLockerPolicyValidation -XmlPath $xml` | `OverallSuccess = $true` |
| 4 | Policy can be imported | `(Invoke-AppLockerPolicyValidation -XmlPath $xml).CanBeImported` | `$true` |
| 5 | EXE rules present | Check `SchemaResult.Details.RuleCollections` | Contains `Exe` |
| 6 | Script rules present | Check `SchemaResult.Details.RuleCollections` | Contains `Script` |
| 7 | Enforcement mode set | Check exported XML `EnforcementMode` attribute | `Enabled` (Phase 4) |
| 8 | No user-writable paths | Check `ConditionResult.Warnings` | No writable path warnings |
| 9 | All rules approved | `Get-RuleCounts` | No `Pending` rules in active policy |
| 10 | Validation report saved | `Invoke-AppLockerPolicyValidation -OutputReport $path` | JSON report at path |
