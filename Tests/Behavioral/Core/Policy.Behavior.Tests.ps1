#Requires -Modules Pester

Describe 'Behavioral Policy: create and attach rules' -Tag @('Behavioral','Core') {
    BeforeEach {
        # Setup for each test (Pester 3.4 compatible)
        $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop

        $script:hash = (([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))).Substring(0,64).ToUpper()
        $script:ruleId = $null
        $script:policyId = $null
        $script:policyName = "Behavioral Policy $([guid]::NewGuid().ToString('N'))"
        $script:extraRuleIds = [System.Collections.Generic.List[string]]::new()

        $ruleResult = New-HashRule -Hash $script:hash -SourceFileName 'test.exe' -SourceFileLength 1024 -Save -Status 'Approved'
        if ($ruleResult.Success) { $script:ruleId = $ruleResult.Data.Id }

        $policyResult = New-Policy -Name $script:policyName -Phase 1 -EnforcementMode Enabled
        if ($policyResult.Success) { $script:policyId = $policyResult.Data.PolicyId }
    }

    AfterEach {
        # Cleanup for each test (Pester 3.4 compatible)
        if ($script:policyId) { Remove-Policy -PolicyId $script:policyId -Force | Out-Null }
        if ($script:ruleId) { Remove-RulesBulk -RuleIds @($script:ruleId) | Out-Null }
        if ($script:extraRuleIds -and $script:extraRuleIds.Count -gt 0) {
            Remove-RulesBulk -RuleIds @($script:extraRuleIds.ToArray()) | Out-Null
        }
    }

    It 'Phase 1 forces AuditOnly enforcement' {
        $policy = Get-Policy -PolicyId $script:policyId
        $policy.Success | Should -BeTrue
        $policy.Data.EnforcementMode | Should -Be 'AuditOnly'
    }

    It 'Add-RuleToPolicy attaches rule id' {
        $addResult = Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)
        $addResult.Success | Should -BeTrue

        $policy = Get-Policy -PolicyId $script:policyId
        $policy.Success | Should -BeTrue
        $policy.Data.RuleIds | Should -Contain $script:ruleId
    }

    It 'Add-RuleToPolicy does not duplicate an existing rule id' {
        (Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)).Success | Should -BeTrue
        (Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)).Success | Should -BeTrue

        $policy = Get-Policy -PolicyId $script:policyId
        $policy.Success | Should -BeTrue

        $matches = @($policy.Data.RuleIds | Where-Object { $_ -eq $script:ruleId })
        $matches.Count | Should -Be 1
    }

    It 'Add-RuleToPolicy blocks contradictory actions for the same semantic key' {
        $denyRule = New-HashRule -Hash $script:hash -SourceFileName 'test.exe' -SourceFileLength 1024 -Action 'Deny' -Status 'Approved'
        $denyRule.Success | Should -BeTrue
        $script:conflictRuleId = $denyRule.Data.Id
        [void]$script:extraRuleIds.Add($script:conflictRuleId)

        $saveBulk = Save-RulesBulk -Rules @($denyRule.Data) -UpdateIndex
        $saveBulk.Success | Should -BeTrue

        (Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)).Success | Should -BeTrue

        $conflictResult = Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:conflictRuleId)
        $conflictResult.Success | Should -BeFalse
        $conflictResult.Error | Should -Match 'Conflicting rule action'
    }

    It 'Add-RuleToPolicy still allows non-conflicting additions' {
        $newHash = (([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))).Substring(0,64).ToUpper()
        $newRule = New-HashRule -Hash $newHash -SourceFileName 'other.exe' -SourceFileLength 2048 -Save -Status 'Approved'
        $newRule.Success | Should -BeTrue
        $script:extraRuleId = $newRule.Data.Id
        [void]$script:extraRuleIds.Add($script:extraRuleId)

        (Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)).Success | Should -BeTrue

        $addResult = Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:extraRuleId)
        $addResult.Success | Should -BeTrue

        $policy = Get-Policy -PolicyId $script:policyId
        $policy.Success | Should -BeTrue
        $policy.Data.RuleIds | Should -Contain $script:extraRuleId
    }

    It 'Remove-RuleFromPolicy detaches an attached rule id' {
        (Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)).Success | Should -BeTrue

        $removeResult = Remove-RuleFromPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)
        $removeResult.Success | Should -BeTrue

        $policy = Get-Policy -PolicyId $script:policyId
        $policy.Success | Should -BeTrue
        $policy.Data.RuleIds | Should -Not -Contain $script:ruleId
    }
}
