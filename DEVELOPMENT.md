# GA-AppLocker Development Guide

This document provides technical details for developers working on the GA-AppLocker codebase.

## Architecture Overview

### Module Structure

GA-AppLocker follows a modular architecture with 10 specialized sub-modules:

```
GA-AppLocker (Parent Module)
├── GA-AppLocker.Core         - Foundation: logging, config, cache, events, validation helpers
├── GA-AppLocker.Storage      - JSON index with O(1) lookups, repository pattern
├── GA-AppLocker.Discovery    - AD/LDAP discovery, parallel connectivity testing
├── GA-AppLocker.Credentials  - Secure credential storage with DPAPI, tiered access (T0/T1/T2)
├── GA-AppLocker.Scanning     - Local/remote artifact collection (14 file types), scheduled scans
├── GA-AppLocker.Rules        - Rule generation, history, bulk ops, templates, deduplication
├── GA-AppLocker.Policy       - Policy builder, comparison, snapshots, XML export
├── GA-AppLocker.Deployment   - GPO deployment with fallback to XML export
├── GA-AppLocker.Setup        - Environment initialization
└── GA-AppLocker.Validation   - 5-stage policy XML validation pipeline
```

### Standard Return Pattern

**All functions MUST return a consistent hashtable structure:**

```powershell
@{
    Success = $true | $false
    Data    = <result object or array>
    Error   = "Error message if Success is $false"
    Message = "Optional success message"
}
```

Example:
```powershell
function Get-Something {
    try {
        $result = # ... do work
        return @{
            Success = $true
            Data    = $result
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
```

### UI Architecture

The WPF UI follows a **central dispatcher pattern**:

1. **MainWindow.xaml** - Defines all visual elements and styles
2. **MainWindow.xaml.ps1** - Contains all event handlers and UI logic

Key patterns:
- `Invoke-ButtonAction` - Central dispatcher for all button clicks
- `Set-ActivePanel` - Manages panel visibility (navigation)
- `Initialize-*Panel` - Each panel has its own initialization function
- Global functions (prefixed with `global:`) for closures that need module access

```powershell
# Button dispatcher pattern
function global:Invoke-ButtonAction {
    param([string]$Action)
    switch ($Action) {
        'NavDashboard' { Set-ActivePanel -PanelName 'PanelDashboard' }
        'StartScan'    { Invoke-StartArtifactScan -Window $win }
        # ... more actions
    }
}
```

### DataGrid Column Standards

All DataGrid panels follow standardized column widths and ordering for consistency:

#### Standard Column Widths

| Data Type | Width | Notes |
|-----------|-------|-------|
| Checkbox | 40 | Selection column |
| Status Icon | 40-50 | Single character/emoji |
| Type | 80 | Consistent across all grids |
| Name/Primary | 160-180 | Main identifier |
| Publisher | 160 | Vendor name |
| Product | 160 or * | Product name (often fill) |
| Description | * | Fill remaining space |
| Collection | 80 | Exe/Dll/Script/etc. |
| Action | 60 | Allow/Deny |
| Status Badge | 85 | Colored status indicator |
| Date | 100 | Created/Modified |
| Version | 50-70 | Short version string |
| Count | 60 | Numeric values |

#### Panel Column Layouts

**AD Discovery (MachineDataGrid)**
| Column | Width | Binding |
|--------|-------|---------|
| ☑️ | 40 | (checkbox) |
| Status | 50 | StatusIcon |
| Type | 80 | MachineType |
| Hostname | 160 | Hostname |
| Operating System | * | OperatingSystem |
| Last Logon | 100 | LastLogon |
| WinRM | 70 | WinRMStatus |

**Artifact Scanner (ArtifactDataGrid)**
| Column | Width | Binding |
|--------|-------|---------|
| S | 40 | SignedIcon |
| Type | 80 | ArtifactType |
| File Name | 180 | FileName |
| Publisher | 160 | Publisher |
| Version | 70 | FileVersion |
| Machine | 100 | ComputerName |
| Path | * | FilePath |

**Rule Generator (RulesDataGrid)**
| Column | Width | Binding |
|--------|-------|---------|
| Type | 80 | RuleType |
| Name | 180 | Name |
| Publisher | 160 | PublisherName |
| Product | * | ProductName |
| Group | 100 | GroupName (template) |
| Collection | 80 | Collection |
| Action | 60 | Action |
| Status | 85 | Status (template) |
| Created | 100 | CreatedDisplay |

**Policy Builder (PoliciesDataGrid)**
| Column | Width | Binding |
|--------|-------|---------|
| Policy Name | 180 | Name |
| Description | * | Description |
| Rules | 60 | RuleCount |
| Mode | 80 | EnforcementMode |
| Phase | 60 | Phase |
| Status | 85 | Status (template) |
| Target GPO | 120 | TargetGPO |
| Ver | 50 | Version |
| Modified | 100 | ModifiedDisplay |

## Coding Standards

### Function Requirements

1. **CmdletBinding**: Always use `[CmdletBinding()]`
2. **Parameter Validation**: Use `[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`, etc.
3. **Try/Catch**: Wrap all I/O operations
4. **Comment-Based Help**: Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`

```powershell
function New-ExampleRule {
    <#
    .SYNOPSIS
        Creates a new example rule.
    
    .DESCRIPTION
        Detailed description of what this function does.
    
    .PARAMETER Name
        The name of the rule.
    
    .EXAMPLE
        New-ExampleRule -Name "TestRule"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    
    try {
        # Implementation
        return @{ Success = $true; Data = $result }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Functions | Verb-Noun | `Get-PolicyTarget`, `New-DeploymentJob` |
| Variables | camelCase | `$policyResult`, `$targetOUs` |
| Script Variables | $script: prefix | `$script:CurrentFilter` |
| Global Variables | $global: prefix | `$global:GA_MainWindow` |
| Constants | UPPER_CASE | `$APP_VERSION` |

### Approved Verbs

Use standard PowerShell approved verbs:
- **Get** - Retrieve data
- **Set** - Modify data
- **New** - Create new item
- **Remove** - Delete item
- **Test** - Validate/check
- **Start/Stop** - Begin/end processes
- **Export/Import** - File operations
- **Add/Remove** - Collection operations

## Adding a New Module

1. Create the module directory:
```
GA-AppLocker/Modules/GA-AppLocker.NewModule/
├── GA-AppLocker.NewModule.psd1
├── GA-AppLocker.NewModule.psm1
└── Functions/
    ├── Function1.ps1
    └── Function2.ps1
```

2. Create the manifest (`.psd1`):
```powershell
@{
    RootModule        = 'GA-AppLocker.NewModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '<new-guid>'
    FunctionsToExport = @('Function1', 'Function2')
}
```

3. Create the module loader (`.psm1`):
```powershell
$ModulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$FunctionsPath = Join-Path $ModulePath 'Functions'

Get-ChildItem -Path $FunctionsPath -Filter '*.ps1' -File | ForEach-Object {
    . $_.FullName
}

Export-ModuleMember -Function @('Function1', 'Function2')
```

4. Add to parent module manifest (`GA-AppLocker.psd1`):
```powershell
NestedModules = @(
    # ... existing modules
    'Modules\GA-AppLocker.NewModule\GA-AppLocker.NewModule.psd1'
)

FunctionsToExport = @(
    # ... existing functions
    'Function1',
    'Function2'
)
```

5. Add to parent module exports (`GA-AppLocker.psm1`):
```powershell
Export-ModuleMember -Function @(
    # ... existing functions
    'Function1',
    'Function2'
)
```

## Adding a New UI Panel

1. **Add XAML** in `MainWindow.xaml`:
```xml
<Grid x:Name="PanelNewFeature" Visibility="Collapsed">
    <!-- Panel content -->
</Grid>
```

2. **Add navigation button** in sidebar:
```xml
<Button x:Name="NavNewFeature" 
        Style="{StaticResource NavButtonStyle}"
        Content="&#x1F4CB;  New Feature"/>
```

3. **Add to dispatcher** in `MainWindow.xaml.ps1`:
```powershell
switch ($Action) {
    'NavNewFeature' { Set-ActivePanel -PanelName 'PanelNewFeature' }
}
```

4. **Add panel list** for navigation:
```powershell
$allPanels = @(
    'PanelDashboard', 'PanelDiscovery', 'PanelScanner',
    'PanelRules', 'PanelPolicy', 'PanelDeploy',
    'PanelSoftware', 'PanelSettings', 'PanelSetup', 'PanelAbout',
    'PanelNewFeature'  # Add new panel
)
```

5. **Create initialization function**:
```powershell
function Initialize-NewFeaturePanel {
    param($Window)  # Untyped for testability (all GUI functions use untyped $Window)
    # Wire up event handlers
}
```

6. **Call initialization** in `Initialize-MainWindow`:
```powershell
try {
    Initialize-NewFeaturePanel -Window $Window
    Write-Log -Message 'NewFeature panel initialized'
}
catch {
    Write-Log -Level Error -Message "NewFeature panel init failed: $($_.Exception.Message)"
}
```

## Testing

GA-AppLocker has a comprehensive testing infrastructure covering unit tests, integration tests, and UI automation.

### Test Structure

```
Tests/
├── Unit/                           # Pester unit tests
│   ├── Rules.Tests.ps1             # Rule module tests
│   ├── Storage.Tests.ps1           # Storage module tests
│   ├── GUI.RulesPanel.Tests.ps1    # GUI logic tests (mocked)
│   └── ...
├── Integration/                    # Integration tests
│   ├── AD.Discovery.Tests.ps1      # Live AD tests
│   └── Export.PhaseFiltering.Tests.ps1
├── Automation/                     # Automated test suites
│   ├── Run-AutomatedTests.ps1      # Unified test runner
│   ├── UI/
│   │   └── FlaUIBot.ps1            # UI automation bot
│   ├── Workflows/
│   │   └── Test-FullWorkflow.ps1   # E2E workflow tests
│   └── MockData/
│       └── New-MockTestData.psm1   # Mock data generator
└── Performance/                    # Benchmarks
    └── Benchmark-RuleGeneration.ps1
```

### Running Tests

```powershell
# Quick module tests
.\Test-AllModules.ps1

# Pester unit tests
Invoke-Pester -Path Tests\Unit\ -Output Detailed

# UI automation (requires interactive session)
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Standard

# Full automated suite
.\Tests\Automation\Run-AutomatedTests.ps1 -All

# With mock data (no AD required)
.\Tests\Automation\Run-AutomatedTests.ps1 -Workflows -UseMockData
```

### UI Automation Testing

The `FlaUIBot.ps1` uses Windows UIAutomation to test the WPF GUI:

```powershell
# Quick navigation test
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Quick

# Standard test (navigation + panel interactions)
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Standard

# Full test (all panels + workflows)
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Full

# Keep dashboard open after tests
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Standard -KeepOpen
```

**FlaUIBot Features:**
- `Wait-ForElement`: Retry logic with configurable timeout
- `Capture-Screenshot`: Auto-screenshot on test failure (saved to `TestResults/`)
- `Get-DataGridRowCount`: Verify data grid population
- `Assert-Condition`: Assertions with auto-screenshot on failure

**Important**: UI tests require an interactive PowerShell session. They cannot run in CI/CD pipelines without desktop access.

### Pester Unit Tests

Unit tests use Pester 5+ with mocking for GUI logic:

```powershell
# Run specific test file
Invoke-Pester -Path Tests\Unit\GUI.RulesPanel.Tests.ps1 -Output Detailed

# Run all unit tests
Invoke-Pester -Path Tests\Unit\ -Output Detailed
```

**Mocking WPF Components:**
```powershell
# Create mock window for testing
$mockWindow = [PSCustomObject]@{}
$mockWindow | Add-Member -MemberType ScriptMethod -Name 'FindName' -Value {
    param($name)
    switch ($name) {
        'RulesDataGrid' { [PSCustomObject]@{ SelectedItems = @() } }
        default { $null }
    }
}

# Mock external functions
Mock -CommandName 'Show-Toast' -MockWith { }
Mock -CommandName 'Remove-Rules' -MockWith { @{ Success = $true } }
```

### Test Categories

| Category | Location | Framework | CI-Compatible |
|----------|----------|-----------|---------------|
| Unit Tests | `Tests/Unit/` | Pester 5+ | ✅ Yes |
| Integration | `Tests/Integration/` | Pester 5+ | ⚠️ Requires AD |
| UI Automation | `Tests/Automation/UI/` | UIAutomation | ❌ Interactive only |
| Workflows | `Tests/Automation/Workflows/` | Custom | ✅ With mock data |
| Performance | `Tests/Performance/` | Custom | ✅ Yes |

### Adding New Tests

**Pester Unit Test:**
```powershell
Describe 'MyFeature' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\..\GA-AppLocker\GA-AppLocker.psd1" -Force
    }
    
    Context 'Function behavior' {
        It 'Should return success' {
            $result = My-Function -Param 'value'
            $result.Success | Should -BeTrue
        }
    }
}
```

**UI Automation Test (add to FlaUIBot.ps1):**
```powershell
# Navigate to panel
Invoke-Button -Parent $script:Window -Name "My Panel" | Out-Null
Start-Sleep -Milliseconds $DelayMs

# Find and verify element
$element = Wait-ForElement -Parent $script:Window -Name "MyButton" -TimeoutSec 10
Assert-Condition -TestName "MyFeature: Button exists" -Condition ($element -ne $null) -ScreenshotOnFail
```

## Data Storage

All data is stored in `%LOCALAPPDATA%\GA-AppLocker\`:

| Directory | Purpose | Format |
|-----------|---------|--------|
| `/` | Root config | `config.json` |
| `/` | Session state | `session.json` |
| `Credentials/` | Encrypted credentials | `{name}.json` (DPAPI) |
| `Scans/` | Scan results | `{guid}.json` |
| `Rules/` | Generated rules | `{guid}.json` |
| `Policies/` | Policy definitions | `{guid}.json` |
| `Deployments/` | Deployment jobs | `{guid}.json` |
| `DeploymentHistory/` | Deployment logs | `{guid}.json` |
| `Logs/` | Application logs | `GA-AppLocker_{date}.log` |

## Session State Management

The application automatically saves and restores UI state across restarts.

### How It Works

1. **Auto-Save**: Session state is saved whenever the user navigates between panels
2. **Auto-Restore**: On startup, previous session is restored if less than 7 days old
3. **Expiry**: Sessions older than 7 days are automatically deleted

### Session State Functions

```powershell
# Save current state
Save-SessionState -State @{
    discoveredMachines = @('PC001', 'PC002')
    selectedMachines   = @('PC001')
    currentPanel       = 'PanelScanner'
    workflowStage      = 2
}

# Restore previous state
$session = Restore-SessionState
if ($session.Success) {
    $machines = $session.Data.discoveredMachines
}

# Force restore expired session
$session = Restore-SessionState -Force

# Custom expiry window
$session = Restore-SessionState -ExpiryDays 30

# Clear saved session
Clear-SessionState
```

### What Gets Saved

| Data | Description |
|------|-------------|
| `discoveredMachines` | Array of machine names from AD discovery |
| `selectedMachines` | Currently selected machines for scanning |
| `scanArtifacts` | Collected artifacts from completed scans |
| `generatedRules` | Rule IDs created from artifacts |
| `approvedRules` | Rule IDs approved for policy inclusion |
| `currentPanel` | Active UI panel name (saved but NOT restored -- app always starts on Dashboard) |
| `workflowStage` | Progress indicator (1-4) |
| `discoveryCount` | Number of discovered machines |
| `scanCount` | Number of scanned artifacts |
| `ruleCount` | Number of generated rules |
| `policyCount` | Number of created policies |

### Workflow Breadcrumbs

The UI displays a visual progress indicator in the sidebar:

```
[●] Discovery  (3)    <- Green when complete with count
[●] Scanner    (150)  <- Current stage highlighted
[○] Rules      (0)    <- Gray when not yet reached
[○] Policy     (0)
```

Stages progress automatically as work is completed:
1. **Discovery**: Machines discovered via AD
2. **Scanner**: Artifacts collected from machines
3. **Rules**: Rules generated from artifacts
4. **Policy**: Policies created from rules

## Debugging

### Enable Verbose Logging
```powershell
$VerbosePreference = 'Continue'
Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force
```

### Check Logs
```powershell
$logPath = Join-Path (Get-AppLockerDataPath) 'Logs'
Get-ChildItem $logPath | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

### Test Individual Functions
```powershell
Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force

# Test a function
$result = Get-DomainInfo
$result | ConvertTo-Json -Depth 3
```

## Common Issues

### "Function not found in closure"
**Problem**: Button click handlers can't access module functions.
**Solution**: Make the function global with `function global:FunctionName`.

### "Get-Command fails in WPF dispatcher context"
**Problem**: `Get-Command -Name 'FunctionName'` returns `$null` when called from WPF event handlers, even though the function exists.
**Cause**: WPF dispatcher context has limited access to PowerShell command discovery.
**Solution**: Use try-catch instead of Get-Command checks:

```powershell
# BAD - fails in WPF context
if (Get-Command -Name 'SomeFunction' -ErrorAction SilentlyContinue) {
    SomeFunction
}

# GOOD - works in WPF context
try { SomeFunction } catch { }
```

This pattern was applied across the codebase in commits `be3c62f` through `c261d61`.

### "XAML parsing error"
**Problem**: Missing style or resource reference.
**Solution**: Ensure all `StaticResource` references exist in `Window.Resources`.

### "Module not loading"
**Problem**: Nested module path incorrect.
**Solution**: Check `NestedModules` paths in `GA-AppLocker.psd1` use backslashes.

## Performance Tips

1. **Limit recursion** - Use `MaxDepth` parameter in scanning
2. **Batch operations** - Group file writes where possible
3. **Lazy loading** - Don't load all data on panel init, load on demand
4. **Deferred panel loading** - Use `$Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, ...)` for heavy panel data loads (e.g., Deploy combo with 1000+ policies) so the panel renders immediately while data loads at background priority

## Critical Warnings

### Never use manual Import-Module in GA-AppLocker.psm1

All nested sub-modules are loaded via `NestedModules` in `GA-AppLocker.psd1`. **DO NOT** add `Import-Module` calls back to `GA-AppLocker.psm1`. This caused double-loading and duplicate log entries in v1.2.13 and earlier.

### Never use Get-CimInstance in WPF STA thread code

`Get-CimInstance -ClassName Win32_ComputerSystem` (and similar WMI calls) can block 5-60+ seconds on the WPF STA thread, preventing `ShowDialog()` from ever executing. Use .NET alternatives instead:

```powershell
# BAD - blocks WPF STA thread
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
$domain = $cs.Domain

# GOOD - returns in 0-1ms
$ipProperties = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
$domain = $ipProperties.DomainName
```

This pattern was applied in v1.2.14 to fix the dashboard not appearing.

### SID-to-Friendly-Name Resolver Pattern (v1.2.11)

Rules store `UserOrGroupSid` as raw SIDs (e.g., `S-1-1-0`). The Rules DataGrid uses a `GroupName` column template with a value converter that resolves SIDs to friendly names and assigns circle colors by scope:

- **S-1-1-0** (Everyone) → green circle
- **S-1-5-32-***, **S-1-5-21-*-512** → blue circle (domain/built-in groups)
- **AppLocker-*** → purple circle (custom AppLocker groups)
- Other → gray circle

This is done via the `Resolve-GroupSid` helper function and XAML `DataTemplate` in the Rules panel.

## Security Considerations

1. **Credentials** - Always use DPAPI encryption via `New-CredentialProfile`
2. **No plaintext** - Never store passwords in config files
3. **Validate input** - Use `[ValidateSet()]` and `[ValidatePattern()]`
4. **Principle of least privilege** - Request only necessary permissions
5. **Audit logging** - Log all security-relevant operations
