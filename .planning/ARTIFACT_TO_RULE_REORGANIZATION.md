# Artifact-to-Rule Workflow Reorganization Plan

## Executive Summary

**Problem:** The artifact-to-rule generation workflow is slow and the UI is cluttered with too many options scattered across multiple panels/tabs.

**Solution:** Consolidate the workflow into a streamlined 3-step wizard, optimize the rule generation pipeline for batch operations, and move advanced options to expandable sections.

---

## Current State Analysis

### Workflow Issues

| Step | Current Location | Problem |
|------|------------------|---------|
| 1. Scan | Scanner Panel → Config Tab | OK |
| 2. View Artifacts | Scanner Panel → DataGrid | OK |
| 3. Exclude File Types | Scanner Panel (post-scan) + Rules Panel (pre-gen) | **DUPLICATED** - confusing |
| 4. Dedupe Artifacts | Scanner Panel (checkbox) + Rules Panel (button) | **DUPLICATED** |
| 5. Configure Generation | Rules Panel → Generate Tab | **TOO MANY OPTIONS** |
| 6. Generate Rules | Rules Panel → Button | **SLOW** - processes one-by-one |
| 7. Review/Approve | Rules Panel → DataGrid | OK but cluttered |

### Performance Bottlenecks

1. **Single-threaded rule creation**: Each artifact processed sequentially with individual file writes
2. **No batch database operations**: Rules written to disk one at a time
3. **Index rebuilds per-rule**: Storage index updated after each rule instead of batch update
4. **Unnecessary deduplication**: Deduping happens AFTER rules exist instead of BEFORE generation
5. **UI updates during generation**: DataGrid refreshes slowing down the loop

### UI Complexity

**Scanner Panel** (left sidebar tabs):
- Config Tab: 6 checkboxes, 2 text inputs, scan paths
- Machines Tab: Machine selection
- History Tab: Saved scans

**Scanner Panel** (right side - overlapping concerns):
- Artifact DataGrid with 7 filter buttons
- "Exclude from Generation" section (DLLs, JS, Scripts, Unsigned)
- "Dedupe Mode" dropdown + button

**Rules Panel** (left sidebar tabs):
- Generate Tab: 6 dropdowns/inputs, 2 borders with more options, generate button
- Manual Tab: Manual rule creation

**Rules Panel** (right side):
- Rules DataGrid with 7 filter buttons
- 9 action buttons (Approve, Reject, Review, Trusted, Dedupe, Policy, Details, Delete, Export)

**Total Options Count:** 35+ interactive elements across the workflow

---

## Proposed Solution

### Phase 1: Streamlined Wizard UI

Replace the scattered options with a **3-Step Wizard** accessible from Scanner panel:

```
┌─────────────────────────────────────────────────────────────┐
│ GENERATE RULES FROM ARTIFACTS                    [Minimize] │
├─────────────────────────────────────────────────────────────┤
│  Step 1          Step 2          Step 3                     │
│  ● Configure  →  ○ Preview   →  ○ Generate                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  QUICK SETTINGS                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Mode: [Smart ▼]  Action: ◉ Allow ○ Deny             │  │
│  │ Apply To: [Everyone ▼]                               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ARTIFACT SUMMARY                                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Total: 2,450  │  Signed: 1,890  │  Unsigned: 560     │  │
│  │ EXE: 1,200    │  DLL: 800       │  Scripts: 450      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  EXCLUSIONS (what NOT to generate rules for)                │
│  ☑ Skip DLLs (800 artifacts)        ☐ Skip Scripts (450)   │
│  ☐ Skip Unsigned (560 artifacts)    ☐ Skip JS only (50)    │
│                                                             │
│  ▼ Advanced Options                                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Publisher Granularity: [Publisher + Product ▼]       │  │
│  │ Dedupe Mode: [Smart ▼]                               │  │
│  │ Collection Name: [Default]                           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│                           [Next: Preview →]                 │
└─────────────────────────────────────────────────────────────┘
```

**Step 2: Preview** (shows what WILL be generated):
```
┌─────────────────────────────────────────────────────────────┐
│  RULE GENERATION PREVIEW                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  After applying exclusions and deduplication:               │
│                                                             │
│  Artifacts to Process: 1,650 (of 2,450 original)           │
│  ├─ Skipped: 800 DLLs                                      │
│  └─ Deduped: 350 duplicates                                │
│                                                             │
│  Estimated Rules:                                           │
│  ├─ Publisher Rules: ~420 (signed unique publishers)       │
│  └─ Hash Rules: ~180 (unsigned files)                      │
│  ═══════════════════════════════════════════════════════   │
│  Total: ~600 rules                                          │
│                                                             │
│  Sample Rules (first 10):                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Type     │ Name                    │ Action │ Scope  │  │
│  │ Publisher│ O=MICROSOFT, Chrome     │ Allow  │ Exe    │  │
│  │ Publisher│ O=ADOBE, Acrobat        │ Allow  │ Exe    │  │
│  │ Hash     │ custom-tool.exe         │ Allow  │ Exe    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│           [← Back]                    [Generate 600 Rules →]│
└─────────────────────────────────────────────────────────────┘
```

**Step 3: Progress** (during generation):
```
┌─────────────────────────────────────────────────────────────┐
│  GENERATING RULES                                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ████████████████████░░░░░░░░░░░░░░░░░░░░░░  45%           │
│                                                             │
│  Processing: 270 / 600 rules                                │
│  Elapsed: 0:32  │  Remaining: ~0:40                         │
│                                                             │
│  Current: Creating publisher rule for O=GOOGLE CHROME...    │
│                                                             │
│                              [Cancel]                       │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2: Performance Optimizations

#### 2.1 Batch Rule Creation Pipeline

```powershell
# NEW: Invoke-BatchRuleGeneration
# Instead of: foreach ($artifact) { ConvertFrom-Artifact -Save }
# Do: Batch pre-process, then bulk write

function Invoke-BatchRuleGeneration {
    param(
        [array]$Artifacts,
        [hashtable]$Options
    )
    
    # Step 1: Pre-filter (exclusions) - O(n)
    $filtered = Filter-ArtifactsByOptions -Artifacts $Artifacts -Options $Options
    
    # Step 2: Deduplicate in memory - O(n)  
    $unique = Get-UniqueArtifactsForRules -Artifacts $filtered -Mode $Options.DedupeMode
    
    # Step 3: Check existing rules (single index lookup) - O(1)
    $ruleIndex = Get-ExistingRuleIndex
    $toCreate = $unique | Where-Object { -not (Test-RuleExists $_ $ruleIndex) }
    
    # Step 4: Generate rule objects in memory (no disk I/O) - O(n)
    $rules = foreach ($art in $toCreate) {
        New-RuleObject -Artifact $art -Options $Options  # No -Save
    }
    
    # Step 5: Bulk write all rules at once - Single I/O operation
    Save-RulesBulk -Rules $rules
    
    # Step 6: Single index rebuild
    Update-RuleIndex -Rules $rules
}
```

#### 2.2 Memory-Based Rule Generation

```powershell
# NEW: New-RuleObject (no disk writes)
function New-RuleObject {
    param([PSCustomObject]$Artifact, [hashtable]$Options)
    
    # Returns rule object without saving
    # Validation happens here, storage happens in batch
    [PSCustomObject]@{
        Id = [guid]::NewGuid().ToString()
        RuleType = Get-OptimalRuleType -Artifact $Artifact -Mode $Options.Mode
        # ... other properties
    }
}
```

#### 2.3 Bulk Storage Operations

```powershell
# NEW: Save-RulesBulk (single file write or batch DB insert)
function Save-RulesBulk {
    param([array]$Rules)
    
    # Option A: JSON - write all rules to single temp file, then atomic rename
    # Option B: SQLite - single transaction with batch INSERT
    
    $batch = @{
        Rules = $Rules
        Timestamp = Get-Date
        Count = $Rules.Count
    }
    
    # Single write operation
    $batchPath = Join-Path $rulesPath "batch_$(Get-Date -Format 'yyyyMMddHHmmss').json"
    $batch | ConvertTo-Json -Depth 10 -Compress | Set-Content $batchPath -Encoding UTF8
    
    # Index is rebuilt once after all rules are written
}
```

### Phase 3: Simplified Rules Panel

Move rule management actions to contextual menus:

**BEFORE (cluttered toolbar):**
```
[Approve] [Reject] [Review] [+Trusted] [-Dedupe] [+Policy] [Details] [Delete]
```

**AFTER (clean with context menu):**
```
Actions: [▼ Status] [+ Add to Policy] [Delete]

Right-click context menu:
├─ Set Status → Approved / Rejected / Review
├─ Add to Policy...
├─ View Details
├─ Copy Rule ID
└─ Delete
```

### Phase 4: Remove Duplicate UI Elements

| Remove From | Keep In | Element |
|-------------|---------|---------|
| Scanner Panel | Rules Wizard | "Exclude from Generation" checkboxes |
| Scanner Panel | Rules Wizard | "Dedupe Mode" dropdown |
| Rules Panel Generate Tab | Rules Wizard | All generation options |
| Rules Panel | Keep as-is | Manual rule creation (separate tab) |

---

## Implementation Roadmap

### Sprint 1: Performance Foundation (2-3 days)

**Tasks:**
1. Create `Invoke-BatchRuleGeneration` function
2. Create `New-RuleObject` (no-save variant)
3. Create `Save-RulesBulk` function
4. Add batch index update to Storage module
5. Add progress callback support to batch functions

**Files to modify:**
- `GA-AppLocker.Rules/Functions/ConvertFrom-Artifact.ps1` - Add batch mode
- `GA-AppLocker.Rules/GA-AppLocker.Rules.psm1` - Export new functions
- `GA-AppLocker.Storage/Functions/RuleCRUD.ps1` - Add bulk operations
- `GA-AppLocker.Storage/Functions/JsonIndexFallback.ps1` - Batch index update

### Sprint 2: Wizard UI (2-3 days)

**Tasks:**
1. Create `GUI/Wizards/RuleGenerationWizard.ps1`
2. Add wizard XAML to MainWindow.xaml (overlay/popup)
3. Wire up 3-step navigation
4. Implement preview calculation logic
5. Connect wizard to batch generation pipeline

**Files to create:**
- `GA-AppLocker/GUI/Wizards/RuleGenerationWizard.ps1`
- `GA-AppLocker/GUI/Wizards/RuleGenerationWizard.xaml` (or inline)

**Files to modify:**
- `GA-AppLocker/GUI/MainWindow.xaml` - Add wizard overlay
- `GA-AppLocker/GUI/Panels/Scanner.ps1` - Launch wizard button
- `GA-AppLocker/GUI/Panels/Rules.ps1` - Remove/simplify Generate tab

### Sprint 3: UI Cleanup (1-2 days)

**Tasks:**
1. Remove duplicate exclusion/dedupe UI from Scanner panel
2. Simplify Rules panel toolbar
3. Add right-click context menu to Rules DataGrid
4. Update keyboard shortcuts for new layout
5. Test full workflow end-to-end

**Files to modify:**
- `GA-AppLocker/GUI/MainWindow.xaml` - Remove duplicate elements
- `GA-AppLocker/GUI/Panels/Scanner.ps1` - Simplify
- `GA-AppLocker/GUI/Panels/Rules.ps1` - Add context menu

### Sprint 4: Documentation & Testing (1 day)

**Tasks:**
1. Update CLAUDE.md with new workflow
2. Add tests for batch generation
3. Performance benchmarks (before/after)
4. User guide updates

---

## Expected Outcomes

### Performance Improvements

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| 1,000 artifacts → rules | ~5 min | ~30 sec | **10x faster** |
| 5,000 artifacts → rules | ~25 min | ~2 min | **12x faster** |
| Memory usage (5k artifacts) | Spikes during I/O | Stable | **Smoother** |
| UI responsiveness | Freezes during gen | Responsive | **No freezes** |

### UX Improvements

| Metric | Before | After |
|--------|--------|-------|
| Interactive elements | 35+ scattered | 12 in focused wizard |
| Steps to generate | 5-7 manual clicks | 3 wizard steps |
| Duplicate controls | 4 (exclusions, dedupe) | 0 |
| Learning curve | Confusing | Guided |

---

## Decision Points for User

1. **Wizard placement:** Overlay popup (recommended) vs. new panel vs. modal dialog?
2. **Default exclusions:** Should "Skip DLLs" be default checked? (Performance vs. completeness)
3. **Preview depth:** Show 10 sample rules, 25, or make it configurable?
4. **Backward compatibility:** Keep old Generate tab as "Advanced" or remove entirely?

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Batch write failures | Data loss | Atomic writes with rollback |
| Wizard too simple for power users | Frustration | Keep "Advanced Options" expandable |
| Migration breaks existing rules | Data corruption | No migration needed - additive changes |
| Performance regression on small sets | Overhead | Auto-detect: <50 artifacts = old method |

---

## Appendix: Code Snippets

### Batch Generation Entry Point

```powershell
function Start-BatchRuleGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Artifacts,
        
        [Parameter()]
        [ValidateSet('Smart', 'Publisher', 'Hash', 'Path')]
        [string]$Mode = 'Smart',
        
        [Parameter()]
        [ValidateSet('Allow', 'Deny')]
        [string]$Action = 'Allow',
        
        [Parameter()]
        [switch]$SkipDlls,
        
        [Parameter()]
        [switch]$SkipUnsigned,
        
        [Parameter()]
        [switch]$SkipScripts,
        
        [Parameter()]
        [string]$DedupeMode = 'Smart',
        
        [Parameter()]
        [scriptblock]$OnProgress
    )
    
    $result = @{
        Success = $false
        RulesCreated = 0
        Skipped = 0
        Errors = @()
    }
    
    try {
        # Phase 1: Filter
        $filtered = $Artifacts
        if ($SkipDlls) { $filtered = $filtered | Where-Object { $_.ArtifactType -ne 'DLL' } }
        if ($SkipUnsigned) { $filtered = $filtered | Where-Object { $_.IsSigned } }
        if ($SkipScripts) { $filtered = $filtered | Where-Object { $_.ArtifactType -notin @('PS1','BAT','CMD','VBS','JS') } }
        
        $result.Skipped = $Artifacts.Count - $filtered.Count
        if ($OnProgress) { & $OnProgress 10 "Filtered: $($result.Skipped) excluded" }
        
        # Phase 2: Dedupe
        $unique = Get-UniqueArtifactsForRules -Artifacts $filtered -Mode $DedupeMode
        $result.Skipped += $filtered.Count - $unique.Count
        if ($OnProgress) { & $OnProgress 20 "Deduped: $($unique.Count) unique" }
        
        # Phase 3: Check existing
        $ruleIndex = Get-ExistingRuleIndex
        $toCreate = @($unique | Where-Object { -not (Test-RuleExistsInIndex $_ $ruleIndex $Mode) })
        $result.Skipped += $unique.Count - $toCreate.Count
        if ($OnProgress) { & $OnProgress 30 "New: $($toCreate.Count) to create" }
        
        # Phase 4: Generate in memory
        $rules = [System.Collections.Generic.List[PSCustomObject]]::new()
        $total = $toCreate.Count
        $i = 0
        foreach ($art in $toCreate) {
            $rule = New-RuleObjectFromArtifact -Artifact $art -Mode $Mode -Action $Action
            $rules.Add($rule)
            $i++
            if ($OnProgress -and ($i % 100 -eq 0)) {
                $pct = 30 + [int](50 * $i / $total)
                & $OnProgress $pct "Creating: $i / $total"
            }
        }
        if ($OnProgress) { & $OnProgress 80 "Saving $($rules.Count) rules..." }
        
        # Phase 5: Bulk save
        $saveResult = Save-RulesBulk -Rules $rules
        if ($saveResult.Success) {
            $result.RulesCreated = $rules.Count
            $result.Success = $true
        } else {
            $result.Errors += $saveResult.Error
        }
        
        if ($OnProgress) { & $OnProgress 100 "Complete: $($result.RulesCreated) rules created" }
    }
    catch {
        $result.Errors += $_.Exception.Message
    }
    
    return [PSCustomObject]$result
}
```

---

*Plan created: January 23, 2026*
*Author: Claude (GA-AppLocker Development)*
