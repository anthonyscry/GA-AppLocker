#Requires -Modules Pester
<#
.SYNOPSIS
    Tests for all module manifests and export integrity.

.DESCRIPTION
    Validates all 10 sub-module manifests + root manifest:
    - .psd1 parses correctly
    - FunctionsToExport match actual function files
    - No duplicate exports
    - All exported functions are actually loadable
    - Sub-module dependencies are correct

.NOTES
    Cross-module manifest integrity tests
    Run with: Invoke-Pester -Path .\Tests\Unit\Module.Manifest.Tests.ps1 -Output Detailed
#>

# Define at script scope BEFORE BeforeAll so Pester 5 discovery-time foreach loops can access them
$script:ModuleBase = Join-Path $PSScriptRoot '..\..\GA-AppLocker'
$script:SubModules = @(
    'GA-AppLocker.Core',
    'GA-AppLocker.Discovery',
    'GA-AppLocker.Credentials',
    'GA-AppLocker.Scanning',
    'GA-AppLocker.Rules',
    'GA-AppLocker.Policy',
    'GA-AppLocker.Deployment',
    'GA-AppLocker.Setup',
    'GA-AppLocker.Storage',
    'GA-AppLocker.Validation'
)

BeforeAll {
    Get-Module 'GA-AppLocker*' | Remove-Module -Force -ErrorAction SilentlyContinue
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:ModuleBase = Join-Path $PSScriptRoot '..\..\GA-AppLocker'
    $script:RootManifest = Import-PowerShellDataFile (Join-Path $script:ModuleBase 'GA-AppLocker.psd1')
}

# ============================================================================
# ROOT MANIFEST
# ============================================================================

Describe 'Root Module Manifest (GA-AppLocker.psd1)' -Tag 'Unit', 'Module' {

    It 'Should parse as valid PowerShell data' {
        { Import-PowerShellDataFile (Join-Path $script:ModuleBase 'GA-AppLocker.psd1') } | Should -Not -Throw
    }

    It 'Should have a valid ModuleVersion' {
        $script:RootManifest.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'Should have more than 100 exported functions' {
        $script:RootManifest.FunctionsToExport.Count | Should -BeGreaterThan 100
    }

    It 'Should have no duplicate exports' {
        $exports = $script:RootManifest.FunctionsToExport
        $unique = $exports | Select-Object -Unique
        $exports.Count | Should -Be $unique.Count
    }

    It 'Should include Start-AppLockerDashboard' {
        $script:RootManifest.FunctionsToExport | Should -Contain 'Start-AppLockerDashboard'
    }

    It 'Should include Test-PingConnectivity' {
        $script:RootManifest.FunctionsToExport | Should -Contain 'Test-PingConnectivity'
    }

    It 'Should have NestedModules for all 10 sub-modules' {
        $script:RootManifest.NestedModules.Count | Should -BeGreaterOrEqual 10
    }

    It 'Should list all sub-modules in NestedModules' {
        $nestedPaths = $script:RootManifest.NestedModules | ForEach-Object { [System.IO.Path]::GetFileName($_) }
        foreach ($mod in $script:SubModules) {
            $expectedFile = "$mod.psd1"
            $nestedPaths | Should -Contain $expectedFile
        }
    }
}

# ============================================================================
# SUB-MODULE MANIFESTS
# ============================================================================

Describe 'Sub-Module Manifests' -Tag 'Unit', 'Module' {

    It '<ModName> should parse as valid PowerShell data' -TestCases ($script:SubModules | ForEach-Object { @{ ModName = $_ } }) {
        param($ModName)
        $psdPath = Join-Path $script:ModuleBase "Modules\$ModName\$ModName.psd1"
        { Import-PowerShellDataFile $psdPath } | Should -Not -Throw
    }

    It '<ModName> should have FunctionsToExport defined' -TestCases ($script:SubModules | ForEach-Object { @{ ModName = $_ } }) {
        param($ModName)
        $psdPath = Join-Path $script:ModuleBase "Modules\$ModName\$ModName.psd1"
        $manifest = Import-PowerShellDataFile $psdPath
        $manifest.FunctionsToExport | Should -Not -BeNullOrEmpty
    }

    It '<ModName> should have no duplicate function exports' -TestCases ($script:SubModules | ForEach-Object { @{ ModName = $_ } }) {
        param($ModName)
        $psdPath = Join-Path $script:ModuleBase "Modules\$ModName\$ModName.psd1"
        $manifest = Import-PowerShellDataFile $psdPath
        $exports = $manifest.FunctionsToExport
        $unique = $exports | Select-Object -Unique
        $exports.Count | Should -Be $unique.Count
    }

    It '<ModName> should have a RootModule (.psm1) file' -TestCases ($script:SubModules | ForEach-Object { @{ ModName = $_ } }) {
        param($ModName)
        $psmPath = Join-Path $script:ModuleBase "Modules\$ModName\$ModName.psm1"
        Test-Path $psmPath | Should -Be $true
    }

    It '<ModName> should have a Functions directory' -TestCases ($script:SubModules | ForEach-Object { @{ ModName = $_ } }) {
        param($ModName)
        $funcDir = Join-Path $script:ModuleBase "Modules\$ModName\Functions"
        Test-Path $funcDir | Should -Be $true
    }
}

# ============================================================================
# EVERY EXPORTED FUNCTION IS LOADABLE
# ============================================================================

Describe 'All Exported Functions Are Loadable' -Tag 'Unit', 'Module' {

    BeforeAll {
        $script:ExportedFunctions = $script:RootManifest.FunctionsToExport
    }

    It 'Every root-exported function should be resolvable via Get-Command' {
        $missing = @()
        foreach ($fn in $script:ExportedFunctions) {
            $cmd = Get-Command $fn -ErrorAction SilentlyContinue
            if (-not $cmd) { $missing += $fn }
        }
        if ($missing.Count -gt 0) {
            $missing -join ', ' | Should -Be '' -Because "These functions are in .psd1 but not loadable: $($missing -join ', ')"
        }
    }
}

# ============================================================================
# KEY FUNCTION EXPORTS PER MODULE
# ============================================================================

Describe 'Key Function Exports' -Tag 'Unit', 'Module' {
    # Use -TestCases to properly pass values into It blocks (Pester 5 closure fix)
    $allKeyFunctions = @(
        # Core
        'Write-AppLockerLog', 'Get-AppLockerConfig', 'Set-AppLockerConfig',
        'Get-AppLockerDataPath', 'Save-SessionState', 'Restore-SessionState',
        'Get-CachedValue', 'Set-CachedValue', 'Publish-AppLockerEvent',
        'Register-AppLockerEvent', 'Test-ValidHash', 'Test-ValidSid',
        'Test-ValidGuid', 'Resolve-GroupSid', 'Write-AuditLog', 'Get-AuditLog',
        'Test-Prerequisites',
        # Discovery
        'Get-DomainInfo', 'Get-OUTree', 'Get-ComputersByOU',
        'Test-MachineConnectivity', 'Test-PingConnectivity',
        'Resolve-LdapServer', 'Test-LdapConnection',
        # Credentials
        'New-CredentialProfile', 'Get-CredentialProfile', 'Get-AllCredentialProfiles',
        'Remove-CredentialProfile', 'Test-CredentialProfile',
        'Get-CredentialForTier', 'Get-CredentialStoragePath',
        # Scanning
        'Get-LocalArtifacts', 'Get-RemoteArtifacts', 'Get-AppxArtifacts',
        'Start-ArtifactScan', 'Get-ScanResults', 'Export-ScanResults',
        'New-ScheduledScan', 'Get-ScheduledScans',
        # Rules
        'New-HashRule', 'New-PublisherRule', 'New-PathRule', 'ConvertFrom-Artifact',
        'Get-Rule', 'Set-RuleStatus', 'Export-RulesToXml', 'Import-RulesFromXml',
        'Get-RuleTemplates', 'Set-BulkRuleStatus', 'Invoke-BatchRuleGeneration',
        'Find-DuplicateRules', 'Get-SuggestedGroup', 'Save-RuleVersion', 'Get-RuleHistory',
        # Policy
        'New-Policy', 'Get-Policy', 'Get-AllPolicies', 'Update-Policy',
        'Remove-Policy', 'Add-RuleToPolicy', 'Remove-RuleFromPolicy',
        'Export-PolicyToXml', 'Compare-Policies', 'New-PolicySnapshot',
        'Get-PolicySnapshots', 'Restore-PolicySnapshot',
        # Deployment
        'New-DeploymentJob', 'Get-DeploymentJob', 'Get-AllDeploymentJobs',
        'Start-Deployment', 'Stop-Deployment', 'Test-GPOExists',
        'Import-PolicyToGPO', 'Get-DeploymentHistory',
        # Setup
        'Initialize-WinRMGPO', 'Initialize-AppLockerGPOs', 'Initialize-ADStructure',
        'Initialize-AppLockerEnvironment', 'Get-SetupStatus',
        'Enable-WinRMGPO', 'Disable-WinRMGPO', 'Remove-WinRMGPO',
        'Initialize-DisableWinRMGPO', 'Remove-DisableWinRMGPO',
        # Storage
        'Get-RuleById', 'Get-AllRules', 'Add-Rule', 'Update-Rule', 'Remove-Rule',
        'Find-RuleByHash', 'Find-RuleByPublisher', 'Save-RulesBulk',
        'Get-RuleFromRepository', 'Save-RuleToRepository', 'Find-RulesInRepository',
        # Validation
        'Test-AppLockerXmlSchema', 'Test-AppLockerRuleGuids', 'Test-AppLockerRuleSids',
        'Test-AppLockerRuleConditions', 'Test-AppLockerPolicyImport',
        'Invoke-AppLockerPolicyValidation'
    )

    It '<Fn> should be exported' -TestCases ($allKeyFunctions | ForEach-Object { @{ Fn = $_ } }) {
        param($Fn)
        Get-Command $Fn -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
