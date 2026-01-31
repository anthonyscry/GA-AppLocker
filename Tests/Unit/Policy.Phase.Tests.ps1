#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for Phase-Based Enforcement feature in GA-AppLocker Policy module.

.DESCRIPTION
    Tests the following behaviors:
    - New-Policy Phase parameter creates correct enforcement mode
    - Phase 1-3 always set AuditOnly regardless of user preference
    - Phase 4 respects user's EnforcementMode setting
    - Backward compatibility: policies without Phase default to Phase 4 behavior

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\Policy.Phase.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'New-Policy Phase Parameter' -Tag 'Unit', 'Policy', 'Phase' {
    
    AfterEach {
        # Cleanup: Remove test policies
        if ($script:testPolicyId) {
            Remove-Policy -PolicyId $script:testPolicyId -Force -ErrorAction SilentlyContinue | Out-Null
            $script:testPolicyId = $null
        }
    }

    Context 'Phase 1 (EXE Only)' {
        It 'Creates policy with Phase = 1' {
            $result = New-Policy -Name "TestPhase1_$(Get-Random)" -Phase 1
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Success | Should -BeTrue
            $result.Data.Phase | Should -Be 1
        }

        It 'Sets EnforcementMode to AuditOnly regardless of user request' {
            $result = New-Policy -Name "TestPhase1Enforce_$(Get-Random)" -Phase 1 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }

        It 'Respects explicit AuditOnly setting' {
            $result = New-Policy -Name "TestPhase1Audit_$(Get-Random)" -Phase 1 -EnforcementMode AuditOnly
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
    }

    Context 'Phase 2 (EXE + Script)' {
        It 'Creates policy with Phase = 2' {
            $result = New-Policy -Name "TestPhase2_$(Get-Random)" -Phase 2
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Success | Should -BeTrue
            $result.Data.Phase | Should -Be 2
        }

        It 'Forces AuditOnly even when Enabled requested' {
            $result = New-Policy -Name "TestPhase2Enforce_$(Get-Random)" -Phase 2 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
    }

    Context 'Phase 3 (EXE + Script + MSI)' {
        It 'Creates policy with Phase = 3' {
            $result = New-Policy -Name "TestPhase3_$(Get-Random)" -Phase 3
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Success | Should -BeTrue
            $result.Data.Phase | Should -Be 3
        }

        It 'Forces AuditOnly even when Enabled requested' {
            $result = New-Policy -Name "TestPhase3Enforce_$(Get-Random)" -Phase 3 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }
    }

    Context 'Phase 4 (Full Enforcement)' {
        It 'Creates policy with Phase = 4' {
            $result = New-Policy -Name "TestPhase4_$(Get-Random)" -Phase 4
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Success | Should -BeTrue
            $result.Data.Phase | Should -Be 4
        }

        It 'Respects Enabled enforcement mode' {
            $result = New-Policy -Name "TestPhase4Enabled_$(Get-Random)" -Phase 4 -EnforcementMode Enabled
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.EnforcementMode | Should -Be 'Enabled'
        }

        It 'Respects AuditOnly enforcement mode' {
            $result = New-Policy -Name "TestPhase4Audit_$(Get-Random)" -Phase 4 -EnforcementMode AuditOnly
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.EnforcementMode | Should -Be 'AuditOnly'
        }

        It 'Respects NotConfigured enforcement mode' {
            $result = New-Policy -Name "TestPhase4NotConfig_$(Get-Random)" -Phase 4 -EnforcementMode NotConfigured
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.EnforcementMode | Should -Be 'NotConfigured'
        }
    }

    Context 'Default Phase Behavior' {
        It 'Defaults to Phase 1 when not specified' {
            $result = New-Policy -Name "TestDefaultPhase_$(Get-Random)"
            $script:testPolicyId = $result.Data.PolicyId
            
            $result.Data.Phase | Should -Be 1
        }
    }

    Context 'Input Validation' {
        It 'Rejects Phase 0' {
            { New-Policy -Name "TestPhase0" -Phase 0 } | Should -Throw
        }

        It 'Rejects Phase 5' {
            { New-Policy -Name "TestPhase5" -Phase 5 } | Should -Throw
        }

        It 'Rejects negative Phase' {
            { New-Policy -Name "TestPhaseNeg" -Phase -1 } | Should -Throw
        }
    }
}

Describe 'Build-PolicyRuleCollectionXml - SourceFileName Extraction (v1.2.15)' -Tag 'Unit', 'Policy', 'Export' {

    AfterEach {
        if ($script:testPolicyId) {
            Remove-Policy -PolicyId $script:testPolicyId -Force -ErrorAction SilentlyContinue | Out-Null
            $script:testPolicyId = $null
        }
    }

    Context 'Export extracts filename from rule Name field' {
        It 'Should write real filename to SourceFileName in XML, not Unknown' {
            # Create a hash rule where Name is "myapp.exe (Hash)" but SourceFileName is Unknown
            $hash = 'AABB' * 16
            $createResult = New-HashRule -Hash $hash -SourceFileName 'Unknown' -SourceFileLength 4096 -Name 'myapp.exe (Hash)' -Action 'Allow' -CollectionType 'Exe' -Status 'Approved' -Save
            $createResult.Success | Should -BeTrue

            # Create policy and add rule
            $policyResult = New-Policy -Name "ExportFilenameTest_$(Get-Random)" -Phase 1
            $policyResult.Success | Should -BeTrue
            $script:testPolicyId = $policyResult.Data.PolicyId

            $addResult = Add-RuleToPolicy -PolicyId $script:testPolicyId -RuleId $createResult.Data.Id
            $addResult.Success | Should -BeTrue

            # Export
            $exportPath = Join-Path $env:TEMP "policy-export-test-$(Get-Random).xml"
            try {
                $exportResult = Export-PolicyToXml -PolicyId $script:testPolicyId -OutputPath $exportPath -SkipValidation
                $exportResult.Success | Should -BeTrue

                # Verify XML contains real filename
                $xmlContent = Get-Content $exportPath -Raw
                $xmlContent | Should -Match 'SourceFileName="myapp.exe"'
                $xmlContent | Should -Not -Match 'SourceFileName="Unknown"'
            }
            finally {
                Remove-Item -Path $exportPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Policy Schema Backward Compatibility' -Tag 'Unit', 'Policy', 'BackwardCompat' {
    
    Context 'Policies without Phase field' {
        It 'Handles legacy policy JSON without Phase field' {
            # Simulate reading a legacy policy that has no Phase field
            $legacyPolicyJson = @{
                PolicyId        = [guid]::NewGuid().ToString()
                Name            = 'LegacyPolicy'
                Description     = 'Created before Phase feature'
                EnforcementMode = 'AuditOnly'
                Status          = 'Draft'
                RuleIds         = @()
                TargetOUs       = @()
                TargetGPO       = $null
                CreatedAt       = (Get-Date).ToString('o')
                ModifiedAt      = (Get-Date).ToString('o')
                CreatedBy       = $env:USERNAME
                Version         = 1
                # NOTE: No Phase field!
            }

            # Save it directly to disk
            $dataPath = Get-AppLockerDataPath
            $policiesPath = Join-Path $dataPath 'Policies'
            if (-not (Test-Path $policiesPath)) {
                New-Item -Path $policiesPath -ItemType Directory -Force | Out-Null
            }
            $policyFile = Join-Path $policiesPath "$($legacyPolicyJson.PolicyId).json"
            $legacyPolicyJson | ConvertTo-Json -Depth 5 | Set-Content -Path $policyFile -Encoding UTF8

            try {
                # Read it back
                $result = Get-Policy -PolicyId $legacyPolicyJson.PolicyId
                
                $result.Success | Should -BeTrue
                # Phase should be null/missing, but export should default to 4
                $result.Data.Phase | Should -BeNullOrEmpty -Because 'Legacy policy has no Phase field'
            }
            finally {
                # Cleanup
                Remove-Item -Path $policyFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
