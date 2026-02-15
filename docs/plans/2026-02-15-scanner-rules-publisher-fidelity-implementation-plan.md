# Scanner/Rules Publisher Fidelity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enforce a canonical artifact contract so signed artifacts retain publisher metadata across scan/export/import and continue generating publisher rules, while tier credential mapping stays deterministic across legacy/current config shapes.

**Architecture:** Introduce one shared artifact normalization function and route Scanner/Scanning boundaries through it. Keep generation logic in Rules module unchanged, but guarantee upstream artifact fidelity and typed fields (`IsSigned`, signer identity, size bytes). Add behavioral tests that prove roundtrip publisher fidelity and tier mapping normalization in must-pass coverage.

**Tech Stack:** PowerShell 5.1, GA-AppLocker modular scripts, WPF Scanner panel code-behind, Pester 5 behavioral tests

---

### Task 1: Add failing behavioral tests for canonical artifact normalization

**Files:**
- Modify: `Tests/Behavioral/Core/Rules.Behavior.Tests.ps1`
- Test: `Tests/Behavioral/Core/Rules.Behavior.Tests.ps1`

**Step 1: Write the failing test**

```powershell
It 'Normalizes legacy artifact fields into publisher-ready contract' {
    $legacy = [PSCustomObject]@{
        FileName          = 'signed-app.exe'
        FilePath          = 'C:\Program Files\Contoso\signed-app.exe'
        IsSigned          = 'True'
        FileSize          = '2048'
        SignerCertificate = 'CN=Contoso Ltd'
        PublisherName     = ''
        ArtifactType      = 'EXE'
    }

    $normalized = Normalize-ArtifactRecord -Artifact $legacy

    $normalized.IsSigned | Should -BeTrue
    $normalized.SizeBytes | Should -Be 2048
    $normalized.SignerCertificate | Should -Be 'CN=Contoso Ltd'
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests\Behavioral\Core\Rules.Behavior.Tests.ps1' -Output Detailed`
Expected: FAIL with `Normalize-ArtifactRecord` not found.

**Step 3: Keep test focused and deterministic**

```powershell
# Add one negative assertion in same test block:
$normalized.IsSigned.GetType().Name | Should -Be 'Boolean'
```

**Step 4: Re-run to confirm still failing for missing implementation**

Run: `Invoke-Pester -Path 'Tests\Behavioral\Core\Rules.Behavior.Tests.ps1' -Output Detailed`
Expected: FAIL only for missing implementation path.

**Step 5: Commit**

```bash
git add Tests/Behavioral/Core/Rules.Behavior.Tests.ps1
git commit -m "test: add failing normalization contract behavior"
```

### Task 2: Implement shared normalization function and wire exports

**Files:**
- Create: `GA-AppLocker/Modules/GA-AppLocker.Core/Functions/Normalize-ArtifactRecord.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Core/GA-AppLocker.Core.psm1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Core/GA-AppLocker.Core.psd1`
- Modify: `GA-AppLocker/GA-AppLocker.psm1`
- Modify: `GA-AppLocker/GA-AppLocker.psd1`
- Test: `Tests/Behavioral/Core/Rules.Behavior.Tests.ps1`

**Step 1: Write minimal implementation**

```powershell
function Normalize-ArtifactRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Artifact)

    $isSignedRaw = if ($Artifact.PSObject.Properties['IsSigned']) { [string]$Artifact.IsSigned } else { '' }
    $isSigned = [string]::Equals($isSignedRaw, 'True', [System.StringComparison]::OrdinalIgnoreCase) -or $isSignedRaw -eq '1' -or ($Artifact.IsSigned -eq $true)

    $sizeBytes = $null
    if ($Artifact.PSObject.Properties['SizeBytes'] -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.SizeBytes)) {
        $sizeBytes = [int64]$Artifact.SizeBytes
    }
    elseif ($Artifact.PSObject.Properties['FileSize'] -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.FileSize)) {
        $sizeBytes = [int64]$Artifact.FileSize
    }

    $normalized = [PSCustomObject]@{}
    foreach ($p in $Artifact.PSObject.Properties) {
        $normalized | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
    }
    $normalized | Add-Member -NotePropertyName 'IsSigned' -NotePropertyValue $isSigned -Force
    $normalized | Add-Member -NotePropertyName 'SizeBytes' -NotePropertyValue $sizeBytes -Force

    return $normalized
}
```

**Step 2: Add function to module load/export lists**

```powershell
# GA-AppLocker.Core.psm1: dot-source Normalize-ArtifactRecord.ps1
# GA-AppLocker.Core.psd1 + root manifests: add Normalize-ArtifactRecord to exports
```

**Step 3: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests\Behavioral\Core\Rules.Behavior.Tests.ps1' -Output Detailed`
Expected: PASS for normalization contract test.

**Step 4: Verify module import exposes function**

Run: `Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force; Get-Command Normalize-ArtifactRecord`
Expected: command is present.

**Step 5: Commit**

```bash
git add GA-AppLocker/Modules/GA-AppLocker.Core/Functions/Normalize-ArtifactRecord.ps1 GA-AppLocker/Modules/GA-AppLocker.Core/GA-AppLocker.Core.psm1 GA-AppLocker/Modules/GA-AppLocker.Core/GA-AppLocker.Core.psd1 GA-AppLocker/GA-AppLocker.psm1 GA-AppLocker/GA-AppLocker.psd1 Tests/Behavioral/Core/Rules.Behavior.Tests.ps1
git commit -m "feat: add shared artifact normalization contract"
```

### Task 3: Add failing roundtrip and tier-normalization workflow tests

**Files:**
- Modify: `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1`
- Test: `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1`

**Step 1: Write failing roundtrip test**

```powershell
It 'Preserves signer identity through scan CSV roundtrip for publisher generation' {
    # Mock local scan artifact with SignerCertificate and IsSigned true
    # Run Start-ArtifactScan -ScanLocal
    # Import generated CSV
    # ConvertFrom-Artifact -PreferredRuleType Auto
    # Assert first rule is Publisher
}
```

**Step 2: Write failing tier key/value normalization test**

```powershell
It 'Normalizes machine type keys and legacy T1 tier values for credential lookup' {
    # Mock Get-AppLockerConfig returning keys like 'Domain Controller' and 'server'
    # Mock tier values as 'T0'/'T1'/'T2'
    # Assert Get-CredentialForTier called with Tier 1 for Server machine
}
```

**Step 3: Run test to verify failure**

Run: `Invoke-Pester -Path 'Tests\Behavioral\Workflows\CoreFlows.E2E.Tests.ps1' -Output Detailed`
Expected: FAIL in new tests before wiring changes.

**Step 4: Keep assertions behavioral (not regex source checks)**

```powershell
# Use Assert-MockCalled and output object assertions only.
```

**Step 5: Commit**

```bash
git add Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1
git commit -m "test: add failing publisher roundtrip and tier normalization workflows"
```

### Task 4: Wire Scanning module to canonical contract and normalized tier resolution

**Files:**
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Start-ArtifactScan.ps1`
- Test: `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1`

**Step 1: Normalize tier keys and values before machine grouping**

```powershell
# Add helper functions in Start-ArtifactScan:
# - Normalize-ScanMachineTypeKey
# - Resolve-ScanTierNumber
# Apply them when building machineTypeTiers and grouping machines.
```

**Step 2: Preserve canonical publisher fields in per-host export projection**

```powershell
$group.Group | Select-Object FileName, FilePath, Extension, ArtifactType, CollectionType,
    Publisher, PublisherName, ProductName, ProductVersion, FileVersion,
    IsSigned, SignerCertificate, SignatureStatus,
    SHA256Hash, FileSize, SizeBytes, ComputerName
```

**Step 3: Run workflow tests**

Run: `Invoke-Pester -Path 'Tests\Behavioral\Workflows\CoreFlows.E2E.Tests.ps1' -Output Detailed`
Expected: PASS for roundtrip and tier tests.

**Step 4: Run focused rule behavior test as regression guard**

Run: `Invoke-Pester -Path 'Tests\Behavioral\Core\Rules.Behavior.Tests.ps1' -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Start-ArtifactScan.ps1 Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1
git commit -m "fix: normalize scan tiers and preserve publisher metadata export"
```

### Task 5: Wire Scanner panel import/export to canonical contract

**Files:**
- Modify: `GA-AppLocker/GUI/Panels/Scanner.ps1`
- Test: `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1`

**Step 1: Update import coercion to use canonical normalization behavior**

```powershell
# In CSV import loop:
# - Coerce IsSigned case-insensitively
# - Populate SizeBytes from FileSize fallback
# - Log debug details when coercion fails (no empty catch)
```

**Step 2: Update Scanner export projection to canonical field set**

```powershell
$exportData = $artifacts | Select-Object FileName, FilePath, Extension, ArtifactType, CollectionType,
    Publisher, PublisherName, ProductName, ProductVersion, FileVersion,
    IsSigned, SignerCertificate, SignatureStatus,
    SHA256Hash, FileSize, SizeBytes, ComputerName
```

**Step 3: Re-run workflow tests**

Run: `Invoke-Pester -Path 'Tests\Behavioral\Workflows\CoreFlows.E2E.Tests.ps1' -Output Detailed`
Expected: PASS with signed roundtrip still producing publisher rules.

**Step 4: Re-run curated regressions test file**

Run: `Invoke-Pester -Path 'Tests\Behavioral\GUI\RecentRegressions.Tests.ps1' -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add GA-AppLocker/GUI/Panels/Scanner.ps1 Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1
git commit -m "fix: preserve canonical artifact fields in scanner import and export"
```

### Task 6: Verify curated gate and finalize

**Files:**
- Test: `Tests/Run-MustPass.ps1`

**Step 1: Run curated must-pass gate**

Run: `.\Tests\Run-MustPass.ps1`
Expected: all tests pass, zero failures.

**Step 2: Run git diff and ensure scope is minimal**

Run: `git status --short && git diff --name-only`
Expected: only intended Scanner/Scanning/Core/test files changed.

**Step 3: Confirm acceptance criteria checklist**

```text
- Signed roundtrip -> Publisher rules: PASS
- Tier mapping variants normalized: PASS
- No silent coercion failures in import path: PASS
- Must-pass gate green: PASS
```

**Step 4: Final commit (if verification changes were needed)**

```bash
git add <verification-related-files>
git commit -m "test: finalize publisher fidelity gate verification"
```

**Step 5: Prepare PR summary (no push unless requested)**

```text
Summarize why the canonical contract prevents metadata drift and how behavioral tests prove publisher fidelity.
```

## Execution notes

- Use @superpowers:test-driven-development for every code path change.
- Use @superpowers:requesting-code-review after each task commit.
- Use @superpowers:verification-before-completion before any completion claim.
- Keep changes DRY and YAGNI: do not add new rule semantics, only contract fidelity and normalization.
