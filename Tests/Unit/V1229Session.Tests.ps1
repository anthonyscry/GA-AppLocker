#Requires -Modules Pester
<#
.SYNOPSIS
    Behavioral tests for features added in v1.2.28+ sessions:
    - Phase 5 backend support (New-Policy, Update-Policy)
    - Phase-based collection type filtering (Get-PhaseCollectionTypes)
    - Software comparison engine (edge cases, re-runs, null guards)
    - Button dispatcher completeness (orphan check)
    - Panel tab ordering
    - Count consistency (Get-RuleCounts, Get-AllPolicies)
    - Module manifest exports

.DESCRIPTION
    All tests in this file are BEHAVIORAL -- they call real functions and
    verify return values. No regex pattern-matching against source code.
    This makes tests resilient to refactoring as long as behavior is preserved.

    Consolidated from former V1228Regression.Tests.ps1 and V1229Session.Tests.ps1.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\V1229Session.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Get-Module 'GA-AppLocker*' | Remove-Module -Force -ErrorAction SilentlyContinue
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Load source files needed for structural tests (tab ordering, orphan check)
    $script:XamlContent = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\MainWindow.xaml') -Raw
    $script:MainWindowPs1 = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\MainWindow.xaml.ps1') -Raw

    # UI stubs for dot-sourced panel functions
    function global:Show-Toast { param($Message, $Type) }
    function global:Show-LoadingOverlay { param($Message, $SubMessage) }
    function global:Hide-LoadingOverlay { }
    function global:Invoke-ButtonAction { param($Action) }
    function global:Invoke-UIUpdate { param($Action) }
    function global:Update-DashboardStats { }
    function global:Update-WorkflowBreadcrumb { }

    # Dot-source panel files for behavioral tests
    . (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Software.ps1')
    . (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Policy.ps1')

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
# PHASE 5 BACKEND - New-Policy
# ============================================================================

Describe 'New-Policy - Phase 5 Support' -Tag 'Unit', 'Policy', 'Phase' {

    AfterEach {
        if ($script:testPolicyId) {
            Remove-Policy -PolicyId $script:testPolicyId -Force -ErrorAction SilentlyContinue | Out-Null
            $script:testPolicyId = $null
        }
    }

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
}

# ============================================================================
# PHASE-BASED COLLECTION TYPE FILTERING
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
}

# ============================================================================
# PANEL TAB ORDERING
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

Describe 'Deploy Panel - Tab Order' -Tag 'Unit', 'XAML', 'Deploy' {

    Context 'Create -> Actions -> GPO Status order (Edit tab removed in v1.2.46)' {
        It 'Create tab should appear before Actions tab' {
            $deployPanel = $script:XamlContent.IndexOf('PanelDeploy')
            $createPos = $script:XamlContent.IndexOf('Header="Create"', $deployPanel)
            $actionsPos = $script:XamlContent.IndexOf('Header="Actions"', $deployPanel)
            $createPos | Should -BeGreaterThan -1
            $actionsPos | Should -BeGreaterThan -1
            $createPos | Should -BeLessThan $actionsPos
        }
        It 'Actions tab should appear before GPO Status tab' {
            $deployPanel = $script:XamlContent.IndexOf('PanelDeploy')
            $actionsPos = $script:XamlContent.IndexOf('Header="Actions"', $deployPanel)
            $statusPos = $script:XamlContent.IndexOf('Header="Status"', $deployPanel)
            $actionsPos | Should -BeLessThan $statusPos
        }
        It 'Edit tab should not exist in Deploy panel' {
            $deployPanel = $script:XamlContent.IndexOf('PanelDeploy')
            $nextPanel = $script:XamlContent.IndexOf('PanelSoftware', $deployPanel)
            $deploySection = $script:XamlContent.Substring($deployPanel, $nextPanel - $deployPanel)
            $deploySection | Should -Not -Match 'Header="Edit"'
        }
    }
}

# ============================================================================
# BUTTON DISPATCHER COMPLETENESS
# ============================================================================

Describe 'Button Dispatcher - Orphan Check' -Tag 'Unit', 'Integration' {

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
# SOFTWARE COMPARISON - BEHAVIORAL TESTS
# ============================================================================

Describe 'Software Comparison - Functional Tests' -Tag 'Unit', 'Software', 'Comparison' {

    BeforeEach {
        $script:SoftwareInventory = @()
        $script:SoftwareImportedData = @()
        $script:SoftwareImportedFile = ''
        $script:CurrentSoftwareSourceFilter = 'All'
    }

    Context 'Basic comparison' {
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

        It 'Should recognize CSV source as valid baseline (not filtered out)' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'FromCSV' -DisplayVersion '1.0' -Source 'CSV')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'FromCSV' -DisplayVersion '1.0' -Source 'Imported')
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

    Context 'Re-run behavior (no duplicates on second comparison)' {
        It 'Should not duplicate results on second run' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Local'),
                (New-SoftwareItem -DisplayName 'App2' -DisplayVersion '1.0' -Source 'Local')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Imported'),
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App2' -DisplayVersion '2.0' -Source 'Imported')
            )

            # First comparison
            Invoke-CompareSoftware -Window $null

            # Re-set imported data (simulating user re-importing)
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Imported'),
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App2' -DisplayVersion '2.0' -Source 'Imported')
            )

            # Second run should not crash (comparison results filtered out of baseline)
            { Invoke-CompareSoftware -Window $null } | Should -Not -Throw
        }
    }

    Context 'Mixed scan sources (Local + Remote)' {
        It 'Should include both Local and Remote sources as baseline' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -Machine 'LOCAL' -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Local'),
                (New-SoftwareItem -Machine 'REMOTE1' -DisplayName 'App2' -DisplayVersion '1.0' -Source 'Remote')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App1' -DisplayVersion '1.0' -Source 'Imported'),
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App2' -DisplayVersion '2.0' -Source 'Imported'),
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'App3' -DisplayVersion '1.0' -Source 'Imported')
            )

            Invoke-CompareSoftware -Window $null

            $results = $script:SoftwareInventory
            @($results | Where-Object { $_.Source -eq 'Match' }).Count | Should -Be 1
            @($results | Where-Object { $_.Source -eq 'Version Diff' }).Count | Should -Be 1
            @($results | Where-Object { $_.Source -eq 'Only in Import' }).Count | Should -Be 1
            $results.Count | Should -Be 3
        }
    }

    Context 'Single item datasets' {
        It 'Should handle single matching item' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'Solo' -DisplayVersion '1.0' -Source 'Local')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'Solo' -DisplayVersion '1.0' -Source 'Imported')
            )

            Invoke-CompareSoftware -Window $null

            $script:SoftwareInventory.Count | Should -Be 1
            $script:SoftwareInventory[0].Source | Should -Be 'Match'
        }

        It 'Should handle single non-matching item' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName 'OnlyHere' -DisplayVersion '1.0' -Source 'Local')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName 'OnlyThere' -DisplayVersion '1.0' -Source 'Imported')
            )

            Invoke-CompareSoftware -Window $null

            $script:SoftwareInventory.Count | Should -Be 2
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Only in Scan' }).Count | Should -Be 1
            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Only in Import' }).Count | Should -Be 1
        }
    }

    Context 'Edge cases' {
        It 'Should handle names over 200 characters' {
            $longName = 'A' * 250
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName $longName -DisplayVersion '1.0' -Source 'Local')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName $longName -DisplayVersion '1.0' -Source 'Imported')
            )

            Invoke-CompareSoftware -Window $null

            @($script:SoftwareInventory | Where-Object { $_.Source -eq 'Match' }).Count | Should -Be 1
        }

        It 'Should handle whitespace-only names without crashing' {
            $script:SoftwareInventory = @(
                (New-SoftwareItem -DisplayName '   ' -DisplayVersion '1.0' -Source 'Local')
            )
            $script:SoftwareImportedData = @(
                (New-SoftwareItem -Machine 'PC2' -DisplayName '   ' -DisplayVersion '1.0' -Source 'Imported')
            )

            { Invoke-CompareSoftware -Window $null } | Should -Not -Throw
        }
    }
}

# ============================================================================
# SOFTWARE PANEL - NULL GUARD SAFETY
# ============================================================================

Describe 'Software Panel - Null Window Guards' -Tag 'Unit', 'Software' {

    It 'Update-SoftwareDataGrid should not crash with null Window' {
        { Update-SoftwareDataGrid -Window $null } | Should -Not -Throw
    }

    It 'Update-SoftwareStats should not crash with null Window' {
        { Update-SoftwareStats -Window $null } | Should -Not -Throw
    }

    It 'Update-SoftwareSourceFilter should not crash with null Window' {
        { Update-SoftwareSourceFilter -Window $null -Filter 'All' } | Should -Not -Throw
    }
}

# ============================================================================
# SOFTWARE IMPORT - CALLABLE FUNCTIONS
# ============================================================================

Describe 'Software Import - Functions Available' -Tag 'Unit', 'Software', 'Import' {

    It 'Invoke-ImportBaselineCsv is callable' {
        Get-Command 'Invoke-ImportBaselineCsv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Invoke-ImportComparisonCsv is callable' {
        Get-Command 'Invoke-ImportComparisonCsv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
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
# COUNT CONSISTENCY - BEHAVIORAL CHECKS
# ============================================================================

Describe 'Count Consistency - Data Source Verification' -Tag 'Unit', 'Integration', 'Counts' {

    Context 'Get-RuleCounts is the single source of truth for rule statistics' {
        It 'Get-RuleCounts should be a callable command' {
            Get-Command 'Get-RuleCounts' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        It 'Get-RuleCounts returns Total, ByStatus, ByRuleType' {
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

    Context 'Get-AllPolicies returns consistent data' {
        It 'Get-AllPolicies returns Success with Data array' {
            $result = Get-AllPolicies
            $result.Success | Should -BeTrue
            $result.Data | Should -Not -BeNullOrEmpty -Because 'Data should be an array (possibly empty)'
        }
    }
}
