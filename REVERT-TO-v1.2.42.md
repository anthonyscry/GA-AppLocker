# Reverted to v1.2.42 - Last Known Working Version

## What Happened

v1.2.60 and v1.2.61 "fixes" actually BROKE the application. The user correctly identified that v1.2.41/v1.2.42 were the last working versions.

## Root Cause of Breakage

### My Broken "Fix" #1: Rules.ps1 Button Handler
**File:** `GA-AppLocker/GUI/Panels/Rules.ps1` line 43

**Broken code (v1.2.61):**
```powershell
& (Get-Command -Name 'Invoke-ButtonAction' -CommandType Function) -Action $sender.Tag
```

**Working code (v1.2.42):**
```powershell
Invoke-ButtonAction -Action $sender.Tag
```

**Why it broke:** `Get-Command` can't find the function in the closure scope, causing "Invoke-ButtonAction is not recognized" errors.

### My Broken "Fix" #2: Storage Module Functions
**Files:** 
- `GA-AppLocker/Modules/GA-AppLocker.Storage/GA-AppLocker.Storage.psm1`
- `GA-AppLocker/Modules/GA-AppLocker.Storage/Functions/RuleStorage.ps1`

**Broken change (v1.2.60):**
```powershell
# Changed from script: to regular function
function Write-StorageLog { ... }
function Initialize-JsonIndex { ... }
```

**Working code (v1.2.42):**
```powershell
function script:Write-StorageLog { ... }
function script:Initialize-JsonIndex { ... }
```

**Why it broke:** These are internal helper functions, NOT exported from the module. When GUI code tries to call them, they're not accessible. The `script:` prefix keeps them module-private, which is correct.

### My Broken "Fix" #3: AsyncHelpers Fatal Errors
**File:** `GA-AppLocker/GUI/Helpers/AsyncHelpers.ps1`

**Broken change (v1.2.61):**
```powershell
catch {
    $errorMsg = "FATAL: Module import failed in runspace: $($_.Exception.Message)"
    Write-Host "[AsyncHelpers] $errorMsg" -ForegroundColor Red
    throw $errorMsg  # FATAL - stops everything
}
```

**Working code (v1.2.42):**
```powershell
catch {
    # Module import failed - continue but note the error
    $moduleError = $_.Exception.Message
}
```

**Why it broke:** Making module import failures FATAL causes the entire async operation to fail. The original code gracefully handled import failures.

## What Actually Worked

Looking at the user's logs, **scanning DID work** in v1.2.61:
```
[2026-02-03 12:25:11] [Info] Local scan complete: 4526 artifacts collected
[2026-02-03 12:25:12] [Info] Found 243 Appx packages
[2026-02-03 12:25:13] [Info] Scan complete: 4769 artifacts from 1 machine(s)
```

The diagnostic logging I added helped confirm this was working correctly.

## Lessons Learned

1. **Don't "fix" what isn't broken** - The original v1.2.42 code was working fine
2. **The user was right** - When they said v1.2.41/v1.2.42 worked, I should have checked what changed since then
3. **My "fixes" made things worse** - All 3 changes broke working functionality
4. **Scope matters** - `script:` functions are module-private for a reason
5. **Closures work** - The original `.GetNewClosure()` pattern was fine

## What's in v1.2.42 (Working Version)

- ✅ Rules panel buttons work (Service Allow, Admin Allow, Deny Paths, etc.)
- ✅ Storage module functions accessible
- ✅ Scanning works (finds EXE/DLL/MSI + Appx)
- ✅ No "function not recognized" errors
- ✅ Async operations handle module import failures gracefully

## User Testing Results

**From user's logs at 12:26:**
- ❌ v1.2.60/v1.2.61: All buttons broken, Storage functions not found
- ✅ Scanning worked (4769 artifacts found)

**Expected results after revert to v1.2.42:**
- ✅ All Rules panel buttons should work
- ✅ No "Write-StorageLog is not recognized" errors
- ✅ No "Initialize-JsonIndex is not recognized" errors
- ✅ No "Invoke-ButtonAction is not recognized" errors

## Next Steps

1. User tests v1.2.42
2. If it works, we stay on v1.2.42
3. If there are bugs, we fix them WITHOUT breaking working code
4. NO MORE "fixes" based on theory - only fix actual reported bugs with actual testing

## Apology

I apologize for wasting your time with v1.2.60 and v1.2.61. My "fixes" were based on incorrect assumptions about the root cause. The original code was working correctly, and I broke it by trying to "improve" it.

You were right to point me back to v1.2.42. Thank you for your patience.
