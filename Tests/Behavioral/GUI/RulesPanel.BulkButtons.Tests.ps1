#Requires -Version 5.1
<#
.SYNOPSIS
    Behavioral test for Rules panel bulk buttons (v1.2.60 bug fix)

.DESCRIPTION
    Verifies that clicking "+ Service Allow", "+ Admin Allow", or "+ Deny Browsers"
    buttons no longer throws "The term 'Write-StorageLog' is not recognized" errors.
    Tests that Initialize-JsonIndex and Write-StorageLog are accessible from dot-sourced
    files within the Storage module.

.NOTES
    Bug: Clicking bulk buttons threw "term not recognized" errors and DataGrid disappeared
    Fix: Removed script: scope from Write-StorageLog (Storage.psm1 line 16) and 
         Initialize-JsonIndex (RuleStorage.ps1 line 73)
    Version: 1.2.60
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force
}

Describe 'Rules Panel Bulk Buttons - Storage Module Scope Fix' {
    Context 'Storage module function accessibility' {
        It 'Write-StorageLog should be defined without script: scope' {
            # Verify the fix: Write-StorageLog should be a regular function, not script: scoped
            $storagePsm1Path = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Storage\GA-AppLocker.Storage.psm1'
            $storagePsm1Content = Get-Content $storagePsm1Path -Raw
            
            # Should have regular function definition
            $storagePsm1Content | Should -Match "function Write-StorageLog"
            
            # Should NOT have script: scope prefix
            $storagePsm1Content | Should -Not -Match "function script:Write-StorageLog"
        }
        
        It 'Initialize-JsonIndex should be defined without script: scope' {
            # Verify the fix: Initialize-JsonIndex should be a regular function, not script: scoped
            $ruleStoragePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Storage\Functions\RuleStorage.ps1'
            $ruleStorageContent = Get-Content $ruleStoragePath -Raw
            
            # Should have regular function definition
            $ruleStorageContent | Should -Match "function Initialize-JsonIndex"
            
            # Should NOT have script: scope prefix
            $ruleStorageContent | Should -Not -Match "function script:Initialize-JsonIndex"
        }
        
        It 'Save-RulesBulk should work without errors (calls Initialize-JsonIndex internally)' {
            # Behavioral test: verify the actual functionality works
            $testRule = @{
                Id = [guid]::NewGuid().ToString()
                Name = "Test Rule for Scope Fix"
                RuleType = "Hash"
                CollectionType = "Exe"
                Status = "Pending"
                Action = "Allow"
                UserOrGroupSid = "S-1-1-0"
                Hash = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
                CreatedDate = (Get-Date -Format 'o')
            }
            
            # This should not throw "term not recognized" errors
            { $result = Save-RulesBulk -Rules @($testRule) } | Should -Not -Throw
            
            # Clean up
            Remove-Rule -RuleId $testRule.Id -ErrorAction SilentlyContinue | Out-Null
        }
        
        It 'Storage module should load without errors' {
            # Verify module loads cleanly
            { Import-Module $modulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }
    }
    
    Context 'BulkOperations.ps1 can call Initialize-JsonIndex' {
        It 'BulkOperations.ps1 should call Initialize-JsonIndex without errors' {
            # Verify BulkOperations.ps1 calls Initialize-JsonIndex
            $bulkOpsPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Storage\Functions\BulkOperations.ps1'
            $bulkOpsContent = Get-Content $bulkOpsPath -Raw
            
            # Should have calls to Initialize-JsonIndex
            $bulkOpsContent | Should -Match "Initialize-JsonIndex"
        }
    }
}
