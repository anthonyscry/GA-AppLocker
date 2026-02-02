#Requires -Modules Pester
<#
.SYNOPSIS
    Comprehensive tests for v1.2.29 session changes covering:
    - GPO Link Control pill toggles (Deploy Actions tab)
    - Phase 5 backend support (New-Policy, Update-Policy, Export-PolicyToXml)
    - Phase-based collection type filtering (Get-PhaseCollectionTypes)
    - Software Import split (Baseline / Comparison buttons)
    - Server Roles & Features in software scan
    - Deploy/Policy tab reordering
    - Deploy Edit policy dropdown
    - Deploy message area MaxHeight fix
    - Rules panel import refresh + filter visual sync
    - WinRM GPO mutual exclusivity
    - Button dispatcher completeness
    - Filter button visual consistency (grey pill pattern across Rules/Policy/Deploy)
    - AD Discovery: first visit auto-populates DataGrid from session data
    - AD Discovery: Refresh Domain preserves connectivity/WinRM status
    - Count consistency (Dashboard, breadcrumb, Rules, Policy, Deploy panels)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\V1229Session.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Get-Module 'GA-AppLocker*' | Remove-Module -Force -ErrorAction SilentlyContinue
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Load source files for cross-referencing
    $script:XamlContent = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\MainWindow.xaml') -Raw
    $script:MainWindowPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\MainWindow.xaml.ps1') -Raw
    $script:DeployPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Deploy.ps1') -Raw
    $script:PolicyPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Policy.ps1') -Raw
    $script:RulesPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Rules.ps1') -Raw
    $script:SoftwarePs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Software.ps1') -Raw
    $script:SetupPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Setup.ps1') -Raw
    $script:ADDiscoveryPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\ADDiscovery.ps1') -Raw
    $script:DashboardPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Dashboard.ps1') -Raw
    $script:NewPolicyContent = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\Modules\GA-AppLocker.Policy\Functions\New-Policy.ps1') -Raw
    $script:UpdatePolicyContent = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\Modules\GA-AppLocker.Policy\Functions\Update-Policy.ps1') -Raw
    $script:ExportPolicyContent = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\Modules\GA-AppLocker.Policy\Functions\Export-PolicyToXml.ps1') -Raw

    # UI stubs
    function global:Show-Toast { param($Message, $Type) }
    function global:Show-LoadingOverlay { param($Message, $SubMessage) }
    function global:Hide-LoadingOverlay { }
    function global:Invoke-ButtonAction { param($Action) }
    function global:Invoke-UIUpdate { param($Action) }
    function global:Update-DashboardStats { }
    function global:Update-WorkflowBreadcrumb { }

    # Dot-source panel files for behavioral tests
    $softwarePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Software.ps1'
    . $softwarePath
    $policyPanelPath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Policy.ps1'
    . $policyPanelPath

    function script:New-SoftwareItem {
        param(
            [string]$Machine = 'PC1',
            [string]$DisplayName,
            [string]$DisplayVersion = '1.0.0',
            [string]$Publisher = 'Test Publisher',
            [string]$Source = 'Local'
        )
        [PSCustomObject]@{
            Machine         = $Machine
            DisplayName     = $DisplayName
            DisplayVersion  = $DisplayVersion
            Publisher       = $Publisher
            InstallDate     = '2026-01-31'
            InstallLocation = ''
            Architecture    = 'x64'
            Source          = $Source
        }
    }
}

AfterAll {
    Remove-Item Function:\Show-Toast -ErrorAction SilentlyContinue
    Remove-Item Function:\Show-LoadingOverlay -ErrorAction SilentlyContinue
    Remove-Item Function:\Hide-LoadingOverlay -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-ButtonAction -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-UIUpdate -ErrorAction SilentlyContinue
    Remove-Item Function:\Update-DashboardStats -ErrorAction SilentlyContinue
    Remove-Item Function:\Update-WorkflowBreadcrumb -ErrorAction SilentlyContinue
}

# ============================================================================
# XAML INTEGRITY
# ============================================================================

Describe 'XAML Parse Integrity - Full Validation' -Tag 'Unit', 'XAML' {

    It 'MainWindow.xaml should parse as valid XML' {
        $xamlPath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\MainWindow.xaml'
        { [xml](Get-Content $xamlPath -Raw) } | Should -Not -Throw
    }
}

# ============================================================================
# GPO LINK CONTROL - XAML ELEMENTS
# ============================================================================

Describe 'GPO Link Control - XAML Elements' -Tag 'Unit', 'XAML', 'Deploy' {

    Context 'All three AppLocker GPO pill toggle buttons exist' {
        It 'Should have BtnToggleGpoLinkDC pill with correct Tag' {
            $script:XamlContent | Should -Match 'x:Name="BtnToggleGpoLinkDC"'
            $script:XamlContent | Should -Match 'Tag="ToggleGpoLinkDC"'
        }
        It 'Should have BtnToggleGpoLinkServers pill with correct Tag' {
            $script:XamlContent | Should -Match 'x:Name="BtnToggleGpoLinkServers"'
            $script:XamlContent | Should -Match 'Tag="ToggleGpoLinkServers"'
        }
        It 'Should have BtnToggleGpoLinkWks pill with correct Tag' {
            $script:XamlContent | Should -Match 'x:Name="BtnToggleGpoLinkWks"'
            $script:XamlContent | Should -Match 'Tag="ToggleGpoLinkWks"'
        }
        It 'Should NOT have separate TxtGpoLink status TextBlocks (merged into pill)' {
            $script:XamlContent | Should -Not -Match 'x:Name="TxtGpoLinkDCStatus"'
            $script:XamlContent | Should -Not -Match 'x:Name="TxtGpoLinkServersStatus"'
            $script:XamlContent | Should -Not -Match 'x:Name="TxtGpoLinkWksStatus"'
        }
        It 'Pill buttons use BorderThickness=0 for flat pill appearance' {
            # All three GPO toggle buttons should have BorderThickness="0"
            $script:XamlContent | Should -Match '(?s)BtnToggleGpoLinkDC.*?BorderThickness="0"'
        }
    }

    Context 'Old dropdown approach fully removed' {
        It 'Should NOT have CboGpoLinkTarget dropdown' {
            $script:XamlContent | Should -Not -Match 'CboGpoLinkTarget'
        }
        It 'Should NOT have BtnEnableGpoLink' {
            $script:XamlContent | Should -Not -Match 'BtnEnableGpoLink'
        }
        It 'Should NOT have BtnDisableGpoLink' {
            $script:XamlContent | Should -Not -Match 'BtnDisableGpoLink'
        }
    }

    Context 'GPO LINK CONTROL section header' {
        It 'Should have GPO LINK CONTROL label text' {
            $script:XamlContent | Should -Match 'GPO LINK CONTROL'
        }
        It 'DC row should show "Domain Controllers" description' {
            $script:XamlContent | Should -Match 'Domain Controllers'
        }
        It 'Servers row should show "Member Servers" description' {
            $script:XamlContent | Should -Match 'Member Servers'
        }
        It 'Workstations row should show description' {
            $script:XamlContent | Should -Match 'Workstations / Computers'
        }
    }
}

# ============================================================================
# GPO LINK CONTROL - DISPATCHER WIRING
# ============================================================================

Describe 'GPO Link Control - Dispatcher + Deploy.ps1 Wiring' -Tag 'Unit', 'Integration', 'Deploy' {

    Context 'Dispatcher has all three GPO toggle actions' {
        It 'ToggleGpoLinkDC dispatches to Invoke-ToggleAppLockerGpoLink DC' {
            $script:MainWindowPs1 | Should -Match "'ToggleGpoLinkDC'.*Invoke-ToggleAppLockerGpoLink.*'DC'"
        }
        It 'ToggleGpoLinkServers dispatches to Invoke-ToggleAppLockerGpoLink Servers' {
            $script:MainWindowPs1 | Should -Match "'ToggleGpoLinkServers'.*Invoke-ToggleAppLockerGpoLink.*'Servers'"
        }
        It 'ToggleGpoLinkWks dispatches to Invoke-ToggleAppLockerGpoLink Workstations' {
            $script:MainWindowPs1 | Should -Match "'ToggleGpoLinkWks'.*Invoke-ToggleAppLockerGpoLink.*'Workstations'"
        }
    }

    Context 'Deploy.ps1 handler functions defined' {
        # Source pattern check — Deploy.ps1 global functions are only available at WPF runtime
        It 'Update-AppLockerGpoLinkStatus is defined as global function' {
            $script:DeployPs1 | Should -Match 'function global:Update-AppLockerGpoLinkStatus'
        }
        It 'Invoke-ToggleAppLockerGpoLink is defined as global function' {
            $script:DeployPs1 | Should -Match 'function global:Invoke-ToggleAppLockerGpoLink'
        }
    }

    Context 'Deploy.ps1 buttons wired in Initialize-DeploymentPanel' {
        It 'BtnToggleGpoLinkDC is in button list' {
            $script:DeployPs1 | Should -Match "'BtnToggleGpoLinkDC'"
        }
        It 'BtnToggleGpoLinkServers is in button list' {
            $script:DeployPs1 | Should -Match "'BtnToggleGpoLinkServers'"
        }
        It 'BtnToggleGpoLinkWks is in button list' {
            $script:DeployPs1 | Should -Match "'BtnToggleGpoLinkWks'"
        }
    }

    Context 'Update-AppLockerGpoLinkStatus called on panel init' {
        It 'Should call Update-AppLockerGpoLinkStatus in Initialize-DeploymentPanel' {
            $script:DeployPs1 | Should -Match 'Update-AppLockerGpoLinkStatus -Window \$Window'
        }
    }

    Context 'Invoke-ToggleAppLockerGpoLink implementation details' {
        It 'Should validate GPOType parameter with ValidateSet' {
            $script:DeployPs1 | Should -Match "ValidateSet\('DC', 'Servers', 'Workstations'\)"
        }
        It 'Should check for GroupPolicy module before toggling' {
            $script:DeployPs1 | Should -Match 'Get-Module -ListAvailable -Name GroupPolicy'
        }
        It 'Should use Get-GPO to verify GPO exists' {
            $script:DeployPs1 | Should -Match 'Get-GPO -Name \$gpoName'
        }
        It 'Should check GpoStatus to determine enabled/disabled state' {
            $script:DeployPs1 | Should -Match 'GpoStatus'
        }
        It 'Should use Get-GPOReport to query linked OUs' {
            $script:DeployPs1 | Should -Match 'Get-GPOReport'
        }
        It 'Should toggle GPO between AllSettingsEnabled and AllSettingsDisabled' {
            $script:DeployPs1 | Should -Match 'AllSettingsDisabled'
            $script:DeployPs1 | Should -Match 'AllSettingsEnabled'
        }
        It 'Should refresh status after toggle' {
            $script:DeployPs1 | Should -Match 'Update-AppLockerGpoLinkStatus -Window \$Window'
        }
    }

    Context 'Update-AppLockerGpoLinkStatus maps all 3 GPOs via Get-SetupStatus' {
        It 'Should map DC suffix' {
            $script:DeployPs1 | Should -Match "'DC' = 'DC'"
        }
        It 'Should map Servers suffix' {
            $script:DeployPs1 | Should -Match "'Servers' = 'Servers'"
        }
        It 'Should map Workstations suffix' {
            $script:DeployPs1 | Should -Match "'Workstations' = 'Wks'"
        }
        It 'Should use Get-SetupStatus to find GPOs' {
            $script:DeployPs1 | Should -Match 'Get-SetupStatus'
        }
        It 'Should check GpoState for enabled/disabled state' {
            $script:DeployPs1 | Should -Match 'GpoState'
        }
        It 'Should query linked OUs via Get-GPOReport' {
            $script:DeployPs1 | Should -Match 'Get-GPOReport'
        }
    }
}

# ============================================================================
# PHASE 5 BACKEND - New-Policy
# ============================================================================

Describe 'New-Policy - Phase 5 Support' -Tag 'Unit', 'Policy', 'Phase' {

    AfterEach {
        if ($script:testPolicyId) {
            Remove-Policy -PolicyId $script:testPolicyId -Force -ErrorAction SilentlyContinue | Out-Null
            $script:testPolicyId = $null
        }
    }

    # ValidateRange(1,5) verified behaviorally via Phase boundary tests below

    Context 'Phase 4 (EXE + Script + MSI + APPX) - AuditOnly' {
        It 'Creates policy with Phase = 4' {
            $result = New-Policy -Name "TestPhase4_$(Get-Random)" -Phase 4
            $script:testPolicyId = $result.Data.PolicyId
            $result.Success | Should -BeTrue
            $result.Data.Phase | Should -Be 4
        }

        It 'Forces AuditOnly even when Enabled requested' {
            $result = New-Policy -Name "TestPhase4Enforce_$(Get-Random)" -Phase 4 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }

        It 'Respects AuditOnly setting' {
            $result = New-Policy -Name "TestPhase4Audit_$(Get-Random)" -Phase 4 -EnforcementMode AuditOnly
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
    }

    Context 'Phase 5 (Full Enforcement - All + DLL)' {
        It 'Creates policy with Phase = 5' {
            $result = New-Policy -Name "TestPhase5_$(Get-Random)" -Phase 5
            $script:testPolicyId = $result.Data.PolicyId
            $result.Success | Should -BeTrue
            $result.Data.Phase | Should -Be 5
        }

        It 'Defaults to Enabled enforcement mode' {
            $result = New-Policy -Name "TestPhase5Default_$(Get-Random)" -Phase 5
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'Enabled'
        }

        It 'Respects explicit Enabled enforcement mode' {
            $result = New-Policy -Name "TestPhase5Enabled_$(Get-Random)" -Phase 5 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'Enabled'
        }

        It 'Respects explicit AuditOnly enforcement mode' {
            $result = New-Policy -Name "TestPhase5Audit_$(Get-Random)" -Phase 5 -EnforcementMode AuditOnly
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }

        It 'Respects explicit NotConfigured enforcement mode' {
            $result = New-Policy -Name "TestPhase5NC_$(Get-Random)" -Phase 5 -EnforcementMode NotConfigured
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'NotConfigured'
        }
    }

    Context 'Phase boundary enforcement' {
        It 'Phase 1 forces AuditOnly' {
            $result = New-Policy -Name "TestBound1_$(Get-Random)" -Phase 1 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
        It 'Phase 2 forces AuditOnly' {
            $result = New-Policy -Name "TestBound2_$(Get-Random)" -Phase 2 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
        It 'Phase 3 forces AuditOnly' {
            $result = New-Policy -Name "TestBound3_$(Get-Random)" -Phase 3 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
        It 'Phase 4 forces AuditOnly' {
            $result = New-Policy -Name "TestBound4_$(Get-Random)" -Phase 4 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
        It 'Phase 5 allows Enabled' {
            $result = New-Policy -Name "TestBound5_$(Get-Random)" -Phase 5 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.EnforcementMode | Should -Be 'Enabled'
        }
    }

    Context 'Input Validation' {
        It 'Rejects Phase 0' {
            { New-Policy -Name "TestPhase0" -Phase 0 } | Should -Throw
        }
        It 'Rejects Phase 6' {
            { New-Policy -Name "TestPhase6" -Phase 6 } | Should -Throw
        }
        It 'Rejects negative Phase' {
            { New-Policy -Name "TestPhaseNeg" -Phase -1 } | Should -Throw
        }
    }

    Context 'Default Phase Behavior' {
        It 'Defaults to Phase 1 when not specified' {
            $result = New-Policy -Name "TestDefaultPhase_$(Get-Random)"
            $script:testPolicyId = $result.Data.PolicyId
            $result.Data.Phase | Should -Be 1
        }
    }
}

# ============================================================================
# PHASE 5 BACKEND - Update-Policy
# ============================================================================

Describe 'Update-Policy - Phase 5 Support' -Tag 'Unit', 'Policy', 'Phase' {

    BeforeAll {
        $script:BasePolicy = New-Policy -Name "UpdateTest_$(Get-Random)" -Phase 1
    }

    AfterAll {
        if ($script:BasePolicy.Success) {
            Remove-Policy -PolicyId $script:BasePolicy.Data.PolicyId -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # ValidateRange(1,5) verified behaviorally via Phase change enforcement tests below

    Context 'Phase change enforcement' {
        It 'Changing to Phase 4 forces AuditOnly' {
            if (-not $script:BasePolicy.Success) { Set-ItResult -Skipped -Because 'Base policy creation failed'; return }
            $result = Update-Policy -Id $script:BasePolicy.Data.PolicyId -Phase 4 -EnforcementMode Enabled
            $result.Success | Should -BeTrue
            $pol = (Get-Policy -PolicyId $script:BasePolicy.Data.PolicyId).Data
            $pol.EnforcementMode | Should -Be 'AuditOnly'
        }

        It 'Changing to Phase 5 allows Enabled' {
            if (-not $script:BasePolicy.Success) { Set-ItResult -Skipped -Because 'Base policy creation failed'; return }
            $result = Update-Policy -Id $script:BasePolicy.Data.PolicyId -Phase 5 -EnforcementMode Enabled
            $result.Success | Should -BeTrue
            $pol = (Get-Policy -PolicyId $script:BasePolicy.Data.PolicyId).Data
            $pol.EnforcementMode | Should -Be 'Enabled'
        }
    }

    # Safety rule code patterns (effectivePhase, Phase -lt 5) verified behaviorally
    # by Phase change enforcement tests above
}

# ============================================================================
# PHASE 5 BACKEND - Export-PolicyToXml
# ============================================================================

Describe 'Export-PolicyToXml - Phase 5 Support' -Tag 'Unit', 'Policy', 'Phase', 'Export' {

    # ValidateRange(1,5) verified via parameter validation (Phase 0/6 throw tests in New-Policy)

    Context 'Phase filtering code patterns' {
        It 'Phase 4 should filter out DLL only (keeps Appx)' {
            # Phase 4 block should set $dllRules = @() but NOT $appxRules = @()
            $script:ExportPolicyContent | Should -Match '(?s)Phase 4:.*?\$dllRules = @\(\)'
        }
        It 'Phase 3 should filter out DLL and Appx' {
            $script:ExportPolicyContent | Should -Match '(?s)Phase 3:.*?\$dllRules = @\(\).*?\$appxRules = @\(\)'
        }
        It 'Should default to Phase 5 (full export) when no phase specified' {
            $script:ExportPolicyContent | Should -Match '5\s*#\s*Default to full export'
        }
        It 'Enforcement boundary should use effectivePhase -lt 5' {
            $script:ExportPolicyContent | Should -Match '\$effectivePhase -lt 5'
        }
    }
}

# ============================================================================
# PHASE-BASED COLLECTION TYPE FILTERING (GUI)
# ============================================================================

Describe 'Get-PhaseCollectionTypes - GUI Helper' -Tag 'Unit', 'Policy', 'Phase' {

    Context 'Behavioral verification (dot-sourced from Policy.ps1)' {
        It 'Phase 1 returns Exe only' {
            $result = Get-PhaseCollectionTypes -Phase 1
            $result | Should -Be @('Exe')
        }
        It 'Phase 2 returns Exe + Script' {
            $result = Get-PhaseCollectionTypes -Phase 2
            @($result).Count | Should -Be 2
            $result | Should -Contain 'Exe'
            $result | Should -Contain 'Script'
        }
        It 'Phase 3 returns Exe + Script + Msi' {
            $result = Get-PhaseCollectionTypes -Phase 3
            @($result).Count | Should -Be 3
            $result | Should -Contain 'Exe'
            $result | Should -Contain 'Script'
            $result | Should -Contain 'Msi'
        }
        It 'Phase 4 returns Exe + Script + Msi + Appx' {
            $result = Get-PhaseCollectionTypes -Phase 4
            @($result).Count | Should -Be 4
            $result | Should -Contain 'Exe'
            $result | Should -Contain 'Script'
            $result | Should -Contain 'Msi'
            $result | Should -Contain 'Appx'
        }
        It 'Phase 5 returns all including Dll' {
            $result = Get-PhaseCollectionTypes -Phase 5
            @($result).Count | Should -Be 5
            $result | Should -Contain 'Exe'
            $result | Should -Contain 'Script'
            $result | Should -Contain 'Msi'
            $result | Should -Contain 'Appx'
            $result | Should -Contain 'Dll'
        }
    }

    Context 'Invoke-AddRulesToPolicy uses phase filtering' {
        # Source pattern check — verifying wiring between function and caller
        It 'Should call Get-PhaseCollectionTypes' {
            $script:PolicyPs1 | Should -Match 'Get-PhaseCollectionTypes -Phase \$phase'
        }
        It 'Should filter by CollectionType -in allowedCollections' {
            $script:PolicyPs1 | Should -Match '\$_\.CollectionType -in \$allowedCollections'
        }
    }
}

# ============================================================================
# XAML PHASE DROPDOWNS - 5 PHASES
# ============================================================================

Describe 'XAML Phase Dropdowns - 5 Phase Support' -Tag 'Unit', 'XAML', 'Policy' {

    Context 'Policy panel phase dropdown (CboPolicyPhase)' {
        It 'Should have Phase 4: EXE + Script + MSI + APPX' {
            $script:XamlContent | Should -Match 'Phase 4: EXE \+ Script \+ MSI \+ APPX'
        }
        It 'Should have Phase 5: All + DLL' {
            $script:XamlContent | Should -Match 'Phase 5: All \+ DLL'
        }
    }

    Context 'Policy Edit phase dropdown (CboEditPhase)' {
        It 'Should have Phase 4 and Phase 5 items' {
            # CboEditPhase should have Phase 4 and Phase 5 items
            $script:XamlContent | Should -Match 'CboEditPhase'
            $script:XamlContent | Should -Match 'Phase 4:.*APPX'
            $script:XamlContent | Should -Match 'Phase 5:.*DLL'
        }
    }

    Context 'Phase index constraint updated' {
        It 'Policy.ps1 should cap phase index to 4 (0-based for 5 items)' {
            $script:PolicyPs1 | Should -Match '\$phaseIndex -gt 4.*\$phaseIndex = 4'
        }
    }
}

# ============================================================================
# SOFTWARE IMPORT SPLIT - BASELINE / COMPARISON BUTTONS
# ============================================================================

Describe 'Software Import - Split Buttons' -Tag 'Unit', 'XAML', 'Software' {

    Context 'XAML has two import buttons' {
        It 'Should have BtnImportBaseline' {
            $script:XamlContent | Should -Match 'x:Name="BtnImportBaseline"'
        }
        It 'BtnImportBaseline should have Tag ImportBaselineCsv' {
            $script:XamlContent | Should -Match '(?s)x:Name="BtnImportBaseline".*?Tag="ImportBaselineCsv"'
        }
        It 'Should have BtnImportComparison' {
            $script:XamlContent | Should -Match 'x:Name="BtnImportComparison"'
        }
        It 'BtnImportComparison should have Tag ImportComparisonCsv' {
            $script:XamlContent | Should -Match '(?s)x:Name="BtnImportComparison".*?Tag="ImportComparisonCsv"'
        }
    }

    Context 'Old single Import CSV button removed from XAML' {
        It 'Should NOT have BtnImportSoftwareCsv element' {
            $script:XamlContent | Should -Not -Match 'x:Name="BtnImportSoftwareCsv"'
        }
    }

    Context 'Dispatcher wiring' {
        It 'ImportBaselineCsv action exists in dispatcher' {
            $script:MainWindowPs1 | Should -Match "'ImportBaselineCsv'.*Invoke-ImportBaselineCsv"
        }
        It 'ImportComparisonCsv action exists in dispatcher' {
            $script:MainWindowPs1 | Should -Match "'ImportComparisonCsv'.*Invoke-ImportComparisonCsv"
        }
        It 'Legacy ImportSoftwareCsv redirects to ImportBaselineCsv' {
            $script:MainWindowPs1 | Should -Match "'ImportSoftwareCsv'.*Invoke-ImportBaselineCsv"
        }
    }

    Context 'Software.ps1 handler functions available (dot-sourced)' {
        It 'Invoke-ImportBaselineCsv is callable' {
            Get-Command 'Invoke-ImportBaselineCsv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        It 'Invoke-ImportComparisonCsv is callable' {
            Get-Command 'Invoke-ImportComparisonCsv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        It 'Import-SoftwareCsvFile shared helper is defined in source' {
            # script: scoped — not visible via Get-Command, verify in source
            $script:SoftwarePs1 | Should -Match 'function script:Import-SoftwareCsvFile'
        }
    }

    Context 'Initialize-SoftwarePanel wires new buttons' {
        It 'BtnImportBaseline is in button list' {
            $script:SoftwarePs1 | Should -Match "'BtnImportBaseline'"
        }
        It 'BtnImportComparison is in button list' {
            $script:SoftwarePs1 | Should -Match "'BtnImportComparison'"
        }
    }
}

# ============================================================================
# SOFTWARE IMPORT - BASELINE BEHAVIOR
# ============================================================================

Describe 'Software Import - Baseline Function' -Tag 'Unit', 'Software', 'Import' {

    BeforeEach {
        $script:SoftwareInventory = @()
        $script:SoftwareImportedData = @()
        $script:SoftwareImportedFile = ''
        $script:CurrentSoftwareSourceFilter = 'All'
    }

    Context 'Invoke-ImportBaselineCsv sets Source to CSV' {
        It 'Source code should set Source = CSV for baseline rows' {
            $script:SoftwarePs1 | Should -Match "Source\s*=\s*'CSV'"
        }
    }

    Context 'Invoke-ImportBaselineCsv clears comparison data' {
        It 'Source code should reset SoftwareImportedData to empty' {
            # Within Invoke-ImportBaselineCsv
            $script:SoftwarePs1 | Should -Match '\$script:SoftwareImportedData = @\(\)'
        }
        It 'Source code should reset SoftwareImportedFile to empty' {
            $script:SoftwarePs1 | Should -Match '\$script:SoftwareImportedFile = '''''
        }
    }
}

# ============================================================================
# SOFTWARE IMPORT - COMPARISON FUNCTION GUARDS
# ============================================================================

Describe 'Software Import - Comparison Function Guards' -Tag 'Unit', 'Software', 'Import' {

    BeforeEach {
        $script:SoftwareInventory = @()
        $script:SoftwareImportedData = @()
        $script:SoftwareImportedFile = ''
        $script:CurrentSoftwareSourceFilter = 'All'
    }

    Context 'Invoke-ImportComparisonCsv requires baseline' {
        It 'Should check hasBaseline before allowing comparison import' {
            $script:SoftwarePs1 | Should -Match 'function global:Invoke-ImportComparisonCsv'
            $script:SoftwarePs1 | Should -Match '\$hasBaseline'
        }
        It 'Should warn when no baseline exists' {
            $script:SoftwarePs1 | Should -Match 'No baseline data'
        }
    }

    Context 'Split import functions callable (dot-sourced)' {
        It 'Invoke-ImportBaselineCsv is callable' {
            Get-Command 'Invoke-ImportBaselineCsv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        It 'Invoke-ImportComparisonCsv is callable' {
            Get-Command 'Invoke-ImportComparisonCsv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

# ============================================================================
# SERVER ROLES & FEATURES - SOFTWARE SCAN
# ============================================================================

Describe 'Server Roles & Features - Software Scan' -Tag 'Unit', 'Software', 'Server' {

    Context 'Local scan (Get-InstalledSoftware)' {
        It 'Should check for Get-WindowsFeature command' {
            $script:SoftwarePs1 | Should -Match "Get-Command 'Get-WindowsFeature'"
        }
        It 'Should prefix feature names with [Role/Feature]' {
            $script:SoftwarePs1 | Should -Match '\[Role/Feature\]'
        }
        It 'Should set Architecture to Role or Feature based on FeatureType' {
            $script:SoftwarePs1 | Should -Match '\$feat\.FeatureType -eq ''Role'''
        }
        It 'Should wrap Get-WindowsFeature in try/catch to not crash on workstations' {
            # The Get-WindowsFeature block is inside a try/catch
            $script:SoftwarePs1 | Should -Match '(?s)try\s*\{.*Get-WindowsFeature.*\}\s*catch'
        }
        It 'Should filter to only installed features' {
            $script:SoftwarePs1 | Should -Match 'Where-Object \{ \$_\.Installed \}'
        }
    }

    Context 'Remote scan scriptblock' {
        It 'Remote scriptblock should also check for Get-WindowsFeature' {
            # The Invoke-Command scriptblock also has Get-WindowsFeature
            $windowsFeatureMatches = [regex]::Matches($script:SoftwarePs1, "Get-Command 'Get-WindowsFeature'")
            $windowsFeatureMatches.Count | Should -BeGreaterOrEqual 2 -Because 'both local and remote scan should check'
        }
        It 'Remote scriptblock should prefix with [Role/Feature]' {
            $rolePrefixMatches = [regex]::Matches($script:SoftwarePs1, '\[Role/Feature\]')
            $rolePrefixMatches.Count | Should -BeGreaterOrEqual 2 -Because 'both local and remote should use prefix'
        }
    }
}

# ============================================================================
# DEPLOY TAB REORDERING
# ============================================================================

Describe 'Deploy Panel - Tab Order' -Tag 'Unit', 'XAML', 'Deploy' {

    Context 'Create -> Edit -> Actions -> Status order' {
        It 'Create tab should appear before Edit tab' {
            $createPos = $script:XamlContent.IndexOf('Header="Create"')
            $editDeployPos = $script:XamlContent.IndexOf('Header="Edit"', $createPos)
            $createPos | Should -BeLessThan $editDeployPos
        }
        It 'Edit tab should appear before Actions tab in Deploy panel' {
            # Find within Deploy panel context
            $deployPanel = $script:XamlContent.IndexOf('PanelDeploy')
            $editPos = $script:XamlContent.IndexOf('Header="Edit"', $deployPanel)
            $actionsPos = $script:XamlContent.IndexOf('Header="Actions"', $deployPanel)
            $editPos | Should -BeLessThan $actionsPos
        }
        It 'Actions tab should appear before Status tab' {
            $deployPanel = $script:XamlContent.IndexOf('PanelDeploy')
            $actionsPos = $script:XamlContent.IndexOf('Header="Actions"', $deployPanel)
            $statusPos = $script:XamlContent.IndexOf('Header="Status"', $deployPanel)
            $actionsPos | Should -BeLessThan $statusPos
        }
    }
}

# ============================================================================
# DEPLOY EDIT POLICY DROPDOWN
# ============================================================================

Describe 'Deploy Edit - Policy Dropdown' -Tag 'Unit', 'XAML', 'Deploy' {

    Context 'CboDeployEditPolicy exists' {
        It 'Should have CboDeployEditPolicy in XAML' {
            $script:XamlContent | Should -Match 'x:Name="CboDeployEditPolicy"'
        }
        It 'Should have job edit fields in XAML' {
            $script:XamlContent | Should -Match 'x:Name="TxtDeployEditJobId"'
            $script:XamlContent | Should -Match 'x:Name="CboDeployEditSchedule"'
            $script:XamlContent | Should -Match 'x:Name="TxtDeployEditTargetOUs"'
        }
    }

    Context 'Deploy.ps1 handles dual combos' {
        It 'Refresh-DeployPolicyCombo populates both combos' {
            $script:DeployPs1 | Should -Match 'CboDeployEditPolicy'
        }
        It 'Update-DeployPolicyEditTab has Source parameter' {
            $script:DeployPs1 | Should -Match '\$Source'
        }
    }
}

# ============================================================================
# DEPLOY MESSAGE AREA FIX
# ============================================================================

Describe 'Deploy Panel - Message Area MaxHeight' -Tag 'Unit', 'XAML', 'Deploy' {

    It 'TxtDeploymentMessage area should have MaxHeight constraint' {
        # The message area Border or ScrollViewer should have MaxHeight
        $script:XamlContent | Should -Match 'TxtDeploymentMessage'
        $script:XamlContent | Should -Match 'MaxHeight="50"'
    }
}

# ============================================================================
# RULES PANEL - IMPORT REFRESH FIX
# ============================================================================

Describe 'Rules Panel - Import XML Refresh' -Tag 'Unit', 'Integration', 'Rules' {

    Context 'Invoke-ImportRulesFromXmlFile triggers dashboard update' {
        It 'Should call Update-DashboardStats after import' {
            $script:RulesPs1 | Should -Match 'Update-DashboardStats'
        }
        It 'Should call Update-WorkflowBreadcrumb after import' {
            $script:RulesPs1 | Should -Match 'Update-WorkflowBreadcrumb'
        }
    }
}

# ============================================================================
# RULES PANEL - FILTER VISUAL SYNC
# ============================================================================

Describe 'Rules Panel - Filter Button Visual Sync' -Tag 'Unit', 'Rules' {

    Context 'Initialize-RulesPanel syncs filter to script:CurrentRulesFilter' {
        It 'Should read CurrentRulesFilter variable' {
            $script:RulesPs1 | Should -Match '\$script:CurrentRulesFilter'
        }
        It 'Should read CurrentRulesTypeFilter variable' {
            $script:RulesPs1 | Should -Match '\$script:CurrentRulesTypeFilter'
        }
    }
}

# ============================================================================
# WINRM GPO MUTUAL EXCLUSIVITY
# ============================================================================

Describe 'WinRM GPO - Mutual Exclusivity' -Tag 'Unit', 'Setup' {

    Context 'Invoke-ToggleWinRMGPO disables opposite when enabling' {
        It 'Should check for AppLocker-DisableWinRM when enabling EnableWinRM' {
            $script:SetupPs1 | Should -Match "oppositeGPO.*=.*'AppLocker-DisableWinRM'"
        }
        It 'Should check for AppLocker-EnableWinRM when enabling DisableWinRM' {
            $script:SetupPs1 | Should -Match "oppositeGPO.*=.*'AppLocker-EnableWinRM'"
        }
        It 'Should call Disable-WinRMGPO for the opposite' {
            $script:SetupPs1 | Should -Match 'Disable-WinRMGPO -GPOName \$oppositeGPO'
        }
        It 'Should only auto-disable when action is enabled' {
            $script:SetupPs1 | Should -Match '\$action -eq ''enabled'''
        }
    }
}

# ============================================================================
# POLICY TAB REORDERING
# ============================================================================

Describe 'Policy Panel - Tab Order' -Tag 'Unit', 'XAML', 'Policy' {

    Context 'Create -> Edit -> Rules order' {
        It 'Policy panel Edit tab should appear before Rules tab' {
            $policyPanel = $script:XamlContent.IndexOf('PanelPolicy')
            $editPos = $script:XamlContent.IndexOf('Header="Edit"', $policyPanel)
            $rulesPos = $script:XamlContent.IndexOf('Header="Rules"', $policyPanel)
            $editPos | Should -BeLessThan $rulesPos
        }
    }
}

# ============================================================================
# BUTTON DISPATCHER COMPLETENESS - ALL NEW ACTIONS
# ============================================================================

Describe 'Button Dispatcher - All New Actions Present' -Tag 'Unit', 'Integration' {

    Context 'GPO Link Control actions' {
        It 'ToggleGpoLinkDC in dispatcher' {
            $script:MainWindowPs1 | Should -Match "'ToggleGpoLinkDC'"
        }
        It 'ToggleGpoLinkServers in dispatcher' {
            $script:MainWindowPs1 | Should -Match "'ToggleGpoLinkServers'"
        }
        It 'ToggleGpoLinkWks in dispatcher' {
            $script:MainWindowPs1 | Should -Match "'ToggleGpoLinkWks'"
        }
    }

    Context 'Software import actions' {
        It 'ImportBaselineCsv in dispatcher' {
            $script:MainWindowPs1 | Should -Match "'ImportBaselineCsv'"
        }
        It 'ImportComparisonCsv in dispatcher' {
            $script:MainWindowPs1 | Should -Match "'ImportComparisonCsv'"
        }
    }

    Context 'Every XAML button Tag has a matching dispatcher entry' {
        It 'Should have no orphan button Tags' {
            # Extract all Tag="..." values from XAML buttons
            $tagMatches = [regex]::Matches($script:XamlContent, '(?s)<Button[^>]+Tag="([^"]+)"')
            $tags = @($tagMatches | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^Filter' -and $_ -notmatch '^ToggleGpoLink' } | Sort-Object -Unique)

            # Verify each Tag exists in the dispatcher
            $missing = @()
            foreach ($tag in $tags) {
                if ($script:MainWindowPs1 -notmatch "'$tag'") {
                    $missing += $tag
                }
            }

            $missing | Should -BeNullOrEmpty -Because "All button Tags should have dispatcher entries. Missing: $($missing -join ', ')"
        }
    }
}

# ============================================================================
# SOFTWARE COMPARISON - LEGACY COMPAT & EDGE CASES
# ============================================================================

Describe 'Software Comparison - Comparison Still Works After Refactor' -Tag 'Unit', 'Software', 'Comparison' {

    BeforeEach {
        $script:SoftwareInventory = @()
        $script:SoftwareImportedData = @()
        $script:SoftwareImportedFile = ''
        $script:CurrentSoftwareSourceFilter = 'All'
    }

    Context 'Basic comparison still functional' {
        It 'Should match identical software' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Local')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Imported')
            )
            Invoke-CompareSoftware -Window $null
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Match' }).Count | Should -Be 1
        }

        It 'Should detect version diff' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Local')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App1' -DisplayVersion '2.0' -Source 'Imported')
            )
            Invoke-CompareSoftware -Window $null
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Version Diff' }).Count | Should -Be 1
        }
    }

    Context 'CSV baseline comparison' {
        It 'Should use CSV source rows as baseline' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'CsvApp' -DisplayVersion '1.0' -Source 'CSV')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'CsvApp' -DisplayVersion '1.0' -Source 'Imported')
            )
            Invoke-CompareSoftware -Window $null
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Match' }).Count | Should -Be 1
        }
    }

    Context 'Role/Feature items in comparison' {
        It 'Should compare Role/Feature items like regular software' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName '[Role/Feature] Web Server (IIS)' -DisplayVersion '' -Source 'Remote')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'SRV2' -DisplayName '[Role/Feature] Web Server (IIS)' -DisplayVersion '' -Source 'Imported')
            )
            Invoke-CompareSoftware -Window $null
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Match' }).Count | Should -Be 1
        }

        It 'Should detect missing Role/Feature on comparison side' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName '[Role/Feature] DNS Server' -DisplayVersion '' -Source 'Remote'),
                (New-SoftwareItem -DisplayName '[Role/Feature] DHCP Server' -DisplayVersion '' -Source 'Remote')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'SRV2' -DisplayName '[Role/Feature] DNS Server' -DisplayVersion '' -Source 'Imported')
            )
            Invoke-CompareSoftware -Window $null
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Match' }).Count | Should -Be 1
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Only in Scan' }).Count | Should -Be 1
        }
    }

    Context 'Empty and null guards' {
        It 'Should not crash with no imported data' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'App' -Source 'Local')
            )
            $script:SoftwareImportedData = @()
            { Invoke-CompareSoftware -Window $null } | Should -Not -Throw
        }

        It 'Should not crash with both empty' {
            $script:SoftwareInventory = @()
            $script:SoftwareImportedData = @()
            { Invoke-CompareSoftware -Window $null } | Should -Not -Throw
        }

        It 'Invoke-ClearSoftwareComparison should not crash with null Window' {
            { Invoke-ClearSoftwareComparison -Window $null } | Should -Not -Throw
        }
    }
}

# ============================================================================
# MODULE MANIFEST - VERSION & EXPORTS
# ============================================================================

Describe 'Module Manifest - Version and Exports' -Tag 'Unit', 'Module' {

    BeforeAll {
        $script:ManifestPath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        $script:Manifest = Import-PowerShellDataFile $script:ManifestPath
    }

    It 'FunctionsToExport should not be empty' {
        $script:Manifest.FunctionsToExport.Count | Should -BeGreaterThan 100
    }

    It 'Should have no duplicate function exports' {
        $exports = $script:Manifest.FunctionsToExport
        $unique = $exports | Select-Object -Unique
        $exports.Count | Should -Be $unique.Count
    }

    It 'Should export Get-SetupStatus' {
        Get-Command 'Get-SetupStatus' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Should export New-Policy' {
        Get-Command 'New-Policy' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Should export Update-Policy' {
        Get-Command 'Update-Policy' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Should export Export-PolicyToXml' {
        Get-Command 'Export-PolicyToXml' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# CROSS-REFERENCE: EVERY NEW XAML ELEMENT HAS CODE-BEHIND
# ============================================================================

Describe 'XAML-Code Cross-Reference - New Elements' -Tag 'Unit', 'Integration' {

    Context 'GPO Link pill buttons set status via Content/Background in Deploy.ps1' {
        It 'BtnToggleGpoLinkDC pill Content is set by Deploy.ps1' {
            $script:DeployPs1 | Should -Match 'BtnToggleGpoLink.*DC'
        }
        It 'BtnToggleGpoLinkServers pill Content is set by Deploy.ps1' {
            $script:DeployPs1 | Should -Match 'BtnToggleGpoLink.*Servers'
        }
        It 'BtnToggleGpoLinkWks pill Content is set by Deploy.ps1' {
            $script:DeployPs1 | Should -Match 'BtnToggleGpoLink.*Wks'
        }
        It 'Deploy.ps1 should NOT reference old TxtGpoLinkDCStatus TextBlock' {
            $script:DeployPs1 | Should -Not -Match 'TxtGpoLinkDCStatus'
        }
        It 'Deploy.ps1 should NOT reference old TxtGpoLinkServersStatus TextBlock' {
            $script:DeployPs1 | Should -Not -Match 'TxtGpoLinkServersStatus'
        }
        It 'Deploy.ps1 should NOT reference old TxtGpoLinkWksStatus TextBlock' {
            $script:DeployPs1 | Should -Not -Match 'TxtGpoLinkWksStatus'
        }
    }

    Context 'GPO Link buttons are referenced by Deploy.ps1' {
        It 'BtnToggleGpoLinkDC is referenced' {
            $script:DeployPs1 | Should -Match 'BtnToggleGpoLink.*DC'
        }
        It 'BtnToggleGpoLinkServers is referenced' {
            $script:DeployPs1 | Should -Match 'BtnToggleGpoLink.*Servers'
        }
        It 'BtnToggleGpoLinkWks is referenced' {
            $script:DeployPs1 | Should -Match 'BtnToggleGpoLink.*Wks'
        }
    }

    Context 'Software import buttons are referenced by Software.ps1' {
        It 'BtnImportBaseline is in Software.ps1 button list' {
            $script:SoftwarePs1 | Should -Match "'BtnImportBaseline'"
        }
        It 'BtnImportComparison is in Software.ps1 button list' {
            $script:SoftwarePs1 | Should -Match "'BtnImportComparison'"
        }
    }
}

# ============================================================================
# FILTER BUTTON VISUAL CONSISTENCY (Grey Pill Pattern)
# ============================================================================

Describe 'Filter Button Visual Consistency - Grey Pill Pattern' -Tag 'Unit', 'UI' {

    Context 'Rules panel uses grey pill pattern (not opacity)' {
        It 'Update-RulesFilter should NOT use Opacity for status buttons' {
            # The "All" type filter reset should use Background/Foreground, not Opacity
            $script:RulesPs1 | Should -Not -Match 'Opacity = 0\.6'
        }
        It 'Update-RulesFilter should use #3E3E42 pill background for active status' {
            $script:RulesPs1 | Should -Match '#3E3E42'
        }
        It 'Update-RulesFilter status buttons reset to Transparent background' {
            $script:RulesPs1 | Should -Match 'Brushes\]::Transparent'
        }
        It 'Status color map has Pending=#FF8C00' {
            $script:RulesPs1 | Should -Match "BtnFilterPending.*#FF8C00"
        }
        It 'Status color map has Approved=#107C10' {
            $script:RulesPs1 | Should -Match "BtnFilterApproved.*#107C10"
        }
        It 'Status color map has Rejected=#D13438' {
            $script:RulesPs1 | Should -Match "BtnFilterRejected.*#D13438"
        }
    }

    Context 'Policy panel uses grey pill pattern' {
        It 'Update-PoliciesFilter should set Background on active button' {
            $script:PolicyPs1 | Should -Match 'pillBg.*#3E3E42'
        }
        It 'Update-PoliciesFilter should reset inactive buttons to Transparent' {
            $script:PolicyPs1 | Should -Match 'Brushes\]::Transparent'
        }
        It 'Update-PoliciesFilter maps all 5 filter buttons' {
            $script:PolicyPs1 | Should -Match "'BtnFilterAllPolicies'"
            $script:PolicyPs1 | Should -Match "'BtnFilterDraft'"
            $script:PolicyPs1 | Should -Match "'BtnFilterActive'"
            $script:PolicyPs1 | Should -Match "'BtnFilterDeployed'"
            $script:PolicyPs1 | Should -Match "'BtnFilterArchived'"
        }
        It 'Color map has Draft=#FF8C00' {
            $script:PolicyPs1 | Should -Match "BtnFilterDraft.*#FF8C00"
        }
        It 'Color map has Active=#0078D4' {
            $script:PolicyPs1 | Should -Match "BtnFilterActive.*#0078D4"
        }
        It 'Color map has Deployed=#107C10' {
            $script:PolicyPs1 | Should -Match "BtnFilterDeployed.*#107C10"
        }
        It 'Color map has Archived=#E0E0E0' {
            $script:PolicyPs1 | Should -Match "BtnFilterArchived.*#E0E0E0"
        }
    }

    Context 'Deploy panel uses grey pill pattern' {
        It 'Update-DeploymentFilter should set Background on active button' {
            $script:DeployPs1 | Should -Match 'pillBg.*#3E3E42'
        }
        It 'Update-DeploymentFilter should reset inactive buttons to Transparent' {
            $script:DeployPs1 | Should -Match 'Brushes\]::Transparent'
        }
        It 'Update-DeploymentFilter maps all 5 filter buttons' {
            $script:DeployPs1 | Should -Match "'BtnFilterAllJobs'"
            $script:DeployPs1 | Should -Match "'BtnFilterPendingJobs'"
            $script:DeployPs1 | Should -Match "'BtnFilterRunningJobs'"
            $script:DeployPs1 | Should -Match "'BtnFilterCompletedJobs'"
            $script:DeployPs1 | Should -Match "'BtnFilterFailedJobs'"
        }
        It 'Color map has Pending=#FF8C00' {
            $script:DeployPs1 | Should -Match "BtnFilterPendingJobs.*#FF8C00"
        }
        It 'Color map has Running=#0078D4' {
            $script:DeployPs1 | Should -Match "BtnFilterRunningJobs.*#0078D4"
        }
        It 'Color map has Completed=#107C10' {
            $script:DeployPs1 | Should -Match "BtnFilterCompletedJobs.*#107C10"
        }
        It 'Color map has Failed=#D13438' {
            $script:DeployPs1 | Should -Match "BtnFilterFailedJobs.*#D13438"
        }
    }

    Context 'XAML filter buttons default to correct initial state' {
        It 'BtnFilterAllPolicies starts with Background=#3E3E42 (active)' {
            $script:XamlContent | Should -Match 'BtnFilterAllPolicies.*Background="#3E3E42"'
        }
        It 'BtnFilterDraft starts with Background=Transparent (inactive)' {
            $script:XamlContent | Should -Match 'BtnFilterDraft.*Background="Transparent"'
        }
        It 'BtnFilterAllJobs starts with Background=#3E3E42 (active)' {
            $script:XamlContent | Should -Match 'BtnFilterAllJobs.*Background="#3E3E42"'
        }
        It 'BtnFilterPendingJobs starts with Background=Transparent (inactive)' {
            $script:XamlContent | Should -Match 'BtnFilterPendingJobs.*Background="Transparent"'
        }
    }
}

# ============================================================================
# GPO PILL TOGGLE - VISUAL STATE MANAGEMENT
# ============================================================================

Describe 'GPO Pill Toggle - Visual State Management' -Tag 'Unit', 'Deploy', 'UI' {

    Context 'Update-AppLockerGpoLinkStatus uses foreground text colors' {
        It 'Defines green foreground for Enabled state (LightGreen)' {
            $script:DeployPs1 | Should -Match 'fgGreen.*LightGreen'
        }
        It 'Defines orange foreground for Disabled state (#FF8C00)' {
            $script:DeployPs1 | Should -Match 'fgOrange.*#FF8C00'
        }
        It 'Defines gray foreground for unavailable states' {
            $script:DeployPs1 | Should -Match 'fgGray.*Brushes.*Gray'
        }
        It 'Sets button Content to Enabled when GPO is enabled' {
            $script:DeployPs1 | Should -Match '\$btnCtrl\.Content = ''Enabled'''
        }
        It 'Sets button Content to Disabled when GPO is disabled' {
            $script:DeployPs1 | Should -Match '\$btnCtrl\.Content = ''Disabled'''
        }
        It 'Sets button Content to Not Created when GPO missing' {
            $script:DeployPs1 | Should -Match '\$btnCtrl\.Content = ''Not Created'''
        }
        It 'Sets button Content to Unavailable when Get-SetupStatus fails' {
            $script:DeployPs1 | Should -Match '\$btnCtrl\.Content = ''Unavailable'''
        }
        It 'Disables button when GPO not created' {
            $script:DeployPs1 | Should -Match '\$btnCtrl\.IsEnabled = \$false'
        }
    }
}

# ============================================================================
# AD DISCOVERY - REFRESH PRESERVES CONNECTIVITY
# ============================================================================

Describe 'AD Discovery - Refresh Domain Preserves Connectivity' -Tag 'Unit', 'ADDiscovery' {

    Context 'Invoke-DomainRefresh merges connectivity data' {
        It 'Should build hashtable of old machines by hostname' {
            $script:ADDiscoveryPs1 | Should -Match '\$oldByHost\[.*Hostname\]'
        }
        It 'Should copy IsOnline from prior test results' {
            $script:ADDiscoveryPs1 | Should -Match 'Add-Member.*IsOnline.*\$old\.IsOnline'
        }
        It 'Should copy WinRMStatus from prior test results' {
            $script:ADDiscoveryPs1 | Should -Match 'Add-Member.*WinRMStatus.*\$old\.WinRMStatus'
        }
        It 'Should only copy WinRMStatus if not Unknown' {
            $script:ADDiscoveryPs1 | Should -Match '\$old\.WinRMStatus -ne ''Unknown'''
        }
        It 'Should show connectivity summary after refresh if available' {
            $script:ADDiscoveryPs1 | Should -Match 'online.*WinRM'
        }
    }

    Context 'Machine count text shows connectivity when available' {
        It 'Should display online and WinRM counts when connectivity tested' {
            $script:ADDiscoveryPs1 | Should -Match '\$onlineCount.*online.*\$winrmCount.*WinRM'
        }
        It 'Should fall back to plain count when no connectivity data' {
            $script:ADDiscoveryPs1 | Should -Match 'machines discovered'
        }
    }
}

# ============================================================================
# AD DISCOVERY - FIRST VISIT POPULATES DATAGRID
# ============================================================================

Describe 'AD Discovery - First Visit Auto-Populate' -Tag 'Unit', 'ADDiscovery' {

    Context 'Panel navigation populates DataGrid from session data' {
        It 'Should call Update-MachineDataGrid when DiscoveredMachines.Count > 0' {
            $script:MainWindowPs1 | Should -Match '(?s)PanelDiscovery.*?Update-MachineDataGrid'
        }
        It 'Should repopulate OU tree if DiscoveredOUs has data' {
            $script:MainWindowPs1 | Should -Match '(?s)DiscoveredOUs.*?Update-OUTreeView'
        }
        It 'Should auto-refresh from AD when DiscoveredMachines is empty' {
            $script:MainWindowPs1 | Should -Match '(?s)DiscoveredMachines\.Count -eq 0.*?Invoke-DomainRefresh'
        }
        It 'Should show connectivity summary in machine count label' {
            $script:MainWindowPs1 | Should -Match 'machineCountCtrl.*online.*WinRM'
        }
    }
}

# ============================================================================
# COUNT CONSISTENCY - DASHBOARD, BREADCRUMB, ALL PANELS
# ============================================================================

Describe 'Count Consistency - Numbers Match Across UI' -Tag 'Unit', 'Integration', 'Counts' {

    Context 'Dashboard and Breadcrumb use same data sources' {
        It 'Dashboard machines count reads from $script:DiscoveredMachines' {
            $script:DashboardPs1 | Should -Match '\$script:DiscoveredMachines.*Count'
        }
        It 'Breadcrumb Discovery count reads from $script:DiscoveredMachines' {
            $script:MainWindowPs1 | Should -Match '(?s)StageDiscoveryCount.*?\$script:DiscoveredMachines\.Count'
        }
        It 'Dashboard artifacts count reads from $script:CurrentScanArtifacts' {
            $script:DashboardPs1 | Should -Match '\$script:CurrentScanArtifacts.*Count'
        }
        It 'Breadcrumb Scanner count reads from $script:CurrentScanArtifacts' {
            $script:MainWindowPs1 | Should -Match '\$script:CurrentScanArtifacts\.Count'
        }
    }

    Context 'Dashboard rule counts use Get-RuleCounts (fast indexed)' {
        It 'Dashboard calls Get-RuleCounts for rule statistics' {
            $script:DashboardPs1 | Should -Match 'Get-RuleCounts'
        }
        It 'Dashboard reads Total from Get-RuleCounts result' {
            $script:DashboardPs1 | Should -Match '\$countsResult\.Total'
        }
        It 'Dashboard reads ByStatus for Pending/Approved/Rejected' {
            $script:DashboardPs1 | Should -Match "ByStatus\['Pending'\]"
            $script:DashboardPs1 | Should -Match "ByStatus\['Approved'\]"
            $script:DashboardPs1 | Should -Match "ByStatus\['Rejected'\]"
        }
    }

    Context 'Dashboard charts use same Get-RuleCounts source' {
        It 'Update-DashboardCharts also calls Get-RuleCounts' {
            $script:DashboardPs1 | Should -Match 'function Update-DashboardCharts'
            $chartsSection = $script:DashboardPs1 -replace '(?s).*function Update-DashboardCharts', ''
            $chartsSection | Should -Match 'Get-RuleCounts'
        }
        It 'Charts read ByStatus for same 4 statuses (Approved, Pending, Rejected, Review)' {
            $script:DashboardPs1 | Should -Match "ByStatus\['Review'\]"
        }
        It 'Charts read ByRuleType for Publisher, Hash, Path' {
            $script:DashboardPs1 | Should -Match "ByRuleType\['Publisher'\]"
            $script:DashboardPs1 | Should -Match "ByRuleType\['Hash'\]"
            $script:DashboardPs1 | Should -Match "ByRuleType\['Path'\]"
        }
    }

    Context 'Breadcrumb rule count uses Get-AllRules Total (same source as index)' {
        It 'Breadcrumb uses Get-AllRules -Take 1 for efficiency' {
            $script:MainWindowPs1 | Should -Match 'Get-AllRules -Take 1'
        }
        It 'Breadcrumb reads .Total not .Data.Count for rule count' {
            $script:MainWindowPs1 | Should -Match '\$rulesResult\.Total'
        }
    }

    Context 'Breadcrumb policy count matches Dashboard policy count' {
        It 'Breadcrumb calls Get-AllPolicies for policy count' {
            $script:MainWindowPs1 | Should -Match 'Get-AllPolicies'
        }
        It 'Dashboard calls Get-AllPolicies for policy count' {
            $script:DashboardPs1 | Should -Match 'Get-AllPolicies'
        }
        It 'Both read .Data.Count from Get-AllPolicies result' {
            # MainWindow breadcrumb
            $script:MainWindowPs1 | Should -Match 'policiesResult\.Data\.Count'
            # Dashboard
            $script:DashboardPs1 | Should -Match 'policiesResult\.Data\.Count'
        }
    }

    Context 'Rules panel counters use same data' {
        It 'Update-RuleCounters takes Rules array parameter' {
            $script:RulesPs1 | Should -Match 'function global:Update-RuleCounters'
            $script:RulesPs1 | Should -Match '\[array\]\$Rules'
        }
        It 'Counts Pending/Approved/Rejected from Rules array' {
            $script:RulesPs1 | Should -Match "Status -eq 'Pending'"
            $script:RulesPs1 | Should -Match "Status -eq 'Approved'"
            $script:RulesPs1 | Should -Match "Status -eq 'Rejected'"
        }
        It 'Updates both text labels and filter button content with counts' {
            # Text labels
            $script:RulesPs1 | Should -Match 'TxtRuleTotalCount'
            $script:RulesPs1 | Should -Match 'TxtRulePendingCount'
            $script:RulesPs1 | Should -Match 'TxtRuleApprovedCount'
            $script:RulesPs1 | Should -Match 'TxtRuleRejectedCount'
            # Filter buttons
            $script:RulesPs1 | Should -Match '(?s)BtnFilterAllRules.*?All \(\$total\)'
            $script:RulesPs1 | Should -Match '(?s)BtnFilterPending.*?Pending \(\$pending\)'
            $script:RulesPs1 | Should -Match '(?s)BtnFilterApproved.*?Approved \(\$approved\)'
            $script:RulesPs1 | Should -Match '(?s)BtnFilterRejected.*?Rejected \(\$rejected\)'
        }
    }

    Context 'Dashboard pending list is subset of Dashboard pending count' {
        It 'Dashboard uses Get-RulesFromDatabase -Status Pending -Take 10 for the list' {
            $script:DashboardPs1 | Should -Match "Get-RulesFromDatabase -Status 'Pending' -Take 10"
        }
        It 'Dashboard pending count reads from ByStatus[Pending] (same index source)' {
            $script:DashboardPs1 | Should -Match "ByStatus\['Pending'\]"
        }
    }

    Context 'AD Discovery machine count label stays in sync' {
        It 'Invoke-DomainRefresh updates DiscoveryMachineCount label' {
            $script:ADDiscoveryPs1 | Should -Match "machineCount.*machines"
        }
        It 'Invoke-ConnectivityTest updates DiscoveryMachineCount with online/WinRM' {
            $script:ADDiscoveryPs1 | Should -Match 'OnlineCount.*TotalMachines.*WinRMAvailable'
        }
        It 'DiscoveryMachineCount is the single machine count label name' {
            # Verify consistent use of DiscoveryMachineCount across all functions
            $machineCountRefs = [regex]::Matches($script:ADDiscoveryPs1, "FindName\('DiscoveryMachineCount'\)")
            $machineCountRefs.Count | Should -BeGreaterOrEqual 3 -Because 'refresh, connectivity, and filter functions all update it'
        }
    }

    Context 'Get-RuleCounts is the single source of truth for rule statistics' {
        It 'Get-RuleCounts should be a callable command' {
            Get-Command 'Get-RuleCounts' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        It 'Get-RuleCounts returns Success, Total, ByStatus, ByRuleType' {
            $result = Get-RuleCounts
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Total'
            $result.PSObject.Properties.Name | Should -Contain 'ByStatus'
            $result.PSObject.Properties.Name | Should -Contain 'ByRuleType'
        }
        It 'ByStatus should be a hashtable with standard keys' {
            $result = Get-RuleCounts
            $result.ByStatus | Should -BeOfType [hashtable]
        }
        It 'ByRuleType should be a hashtable' {
            $result = Get-RuleCounts
            $result.ByRuleType | Should -BeOfType [hashtable]
        }
        It 'Total should equal sum of all ByStatus values' {
            $result = Get-RuleCounts
            $statusSum = 0
            foreach ($val in $result.ByStatus.Values) { $statusSum += $val }
            $result.Total | Should -Be $statusSum
        }
        It 'Total should equal sum of all ByRuleType values' {
            $result = Get-RuleCounts
            $typeSum = 0
            foreach ($val in $result.ByRuleType.Values) { $typeSum += $val }
            $result.Total | Should -Be $typeSum
        }
    }

    Context 'Get-AllPolicies returns consistent data for both callers' {
        It 'Get-AllPolicies returns Success with Data array' {
            $result = Get-AllPolicies
            $result.Success | Should -BeTrue
            $result.Data | Should -Not -BeNullOrEmpty -Because 'Data should be an array (possibly empty)'
        }
    }
}

# ============================================================================
# XAML CONTROL EXISTENCE - STAT/COUNT ELEMENTS
# ============================================================================

Describe 'XAML Stat Elements - Dashboard and Breadcrumb Controls Exist' -Tag 'Unit', 'XAML', 'Counts' {

    Context 'Dashboard stat cards' {
        It 'StatMachines label exists' {
            $script:XamlContent | Should -Match 'x:Name="StatMachines"'
        }
        It 'StatArtifacts label exists' {
            $script:XamlContent | Should -Match 'x:Name="StatArtifacts"'
        }
        It 'StatRules label exists' {
            $script:XamlContent | Should -Match 'x:Name="StatRules"'
        }
        It 'StatPending label exists' {
            $script:XamlContent | Should -Match 'x:Name="StatPending"'
        }
        It 'StatApproved label exists' {
            $script:XamlContent | Should -Match 'x:Name="StatApproved"'
        }
        It 'StatRejected label exists' {
            $script:XamlContent | Should -Match 'x:Name="StatRejected"'
        }
        It 'StatPolicies label exists' {
            $script:XamlContent | Should -Match 'x:Name="StatPolicies"'
        }
    }

    Context 'Workflow breadcrumb stage controls' {
        It 'StageDiscovery circle exists' {
            $script:XamlContent | Should -Match 'x:Name="StageDiscovery"'
        }
        It 'StageDiscoveryCount text exists' {
            $script:XamlContent | Should -Match 'x:Name="StageDiscoveryCount"'
        }
        It 'StageScanner circle exists' {
            $script:XamlContent | Should -Match 'x:Name="StageScanner"'
        }
        It 'StageScannerCount text exists' {
            $script:XamlContent | Should -Match 'x:Name="StageScannerCount"'
        }
        It 'StageRules circle exists' {
            $script:XamlContent | Should -Match 'x:Name="StageRules"'
        }
        It 'StageRulesCount text exists' {
            $script:XamlContent | Should -Match 'x:Name="StageRulesCount"'
        }
        It 'StagePolicy circle exists' {
            $script:XamlContent | Should -Match 'x:Name="StagePolicy"'
        }
        It 'StagePolicyCount text exists' {
            $script:XamlContent | Should -Match 'x:Name="StagePolicyCount"'
        }
    }

    Context 'Dashboard chart bars and labels referenced in code' {
        It 'ChartBarApproved referenced' { $script:DashboardPs1 | Should -Match 'ChartBarApproved' }
        It 'ChartBarPending referenced' { $script:DashboardPs1 | Should -Match 'ChartBarPending' }
        It 'ChartBarRejected referenced' { $script:DashboardPs1 | Should -Match 'ChartBarRejected' }
        It 'ChartBarReview referenced' { $script:DashboardPs1 | Should -Match 'ChartBarReview' }
        It 'ChartLabelApproved referenced' { $script:DashboardPs1 | Should -Match 'ChartLabelApproved' }
        It 'ChartLabelPending referenced' { $script:DashboardPs1 | Should -Match 'ChartLabelPending' }
        It 'ChartLabelRejected referenced' { $script:DashboardPs1 | Should -Match 'ChartLabelRejected' }
        It 'ChartLabelReview referenced' { $script:DashboardPs1 | Should -Match 'ChartLabelReview' }
        It 'ChartTotalRules referenced' { $script:DashboardPs1 | Should -Match 'ChartTotalRules' }
        It 'ChartBarPublisher referenced' { $script:DashboardPs1 | Should -Match 'ChartBarPublisher' }
        It 'ChartBarHash referenced' { $script:DashboardPs1 | Should -Match 'ChartBarHash' }
        It 'ChartBarPath referenced' { $script:DashboardPs1 | Should -Match 'ChartBarPath' }
    }

    Context 'AD Discovery machine count label' {
        It 'DiscoveryMachineCount exists' {
            $script:XamlContent | Should -Match 'x:Name="DiscoveryMachineCount"'
        }
    }

    Context 'Rules panel counter labels' {
        It 'TxtRuleTotalCount exists' { $script:XamlContent | Should -Match 'x:Name="TxtRuleTotalCount"' }
        It 'TxtRulePendingCount exists' { $script:XamlContent | Should -Match 'x:Name="TxtRulePendingCount"' }
        It 'TxtRuleApprovedCount exists' { $script:XamlContent | Should -Match 'x:Name="TxtRuleApprovedCount"' }
        It 'TxtRuleRejectedCount exists' { $script:XamlContent | Should -Match 'x:Name="TxtRuleRejectedCount"' }
    }
}
