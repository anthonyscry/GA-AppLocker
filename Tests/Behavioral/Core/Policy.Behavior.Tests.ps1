#Requires -Modules Pester

Describe 'Behavioral Policy: create and attach rules' -Tag @('Behavioral','Core') {
    BeforeEach {
        # Setup for each test (Pester 3.4 compatible)
        $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop

        $hash = (([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))).Substring(0,64).ToUpper()
        $script:ruleId = $null
        $script:policyId = $null
        $script:policyName = "Behavioral Policy $([guid]::NewGuid().ToString('N'))"

        $ruleResult = New-HashRule -Hash $hash -SourceFileName 'test.exe' -SourceFileLength 1024 -Save -Status 'Approved'
        if ($ruleResult.Success) { $script:ruleId = $ruleResult.Data.Id }

        $policyResult = New-Policy -Name $script:policyName -Phase 1 -EnforcementMode Enabled
        if ($policyResult.Success) { $script:policyId = $policyResult.Data.PolicyId }
    }

    AfterEach {
        # Cleanup for each test (Pester 3.4 compatible)
        if ($script:policyId) { Remove-Policy -PolicyId $script:policyId -Force | Out-Null }
        if ($script:ruleId) { Remove-RulesBulk -RuleIds @($script:ruleId) | Out-Null }
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

    It 'Remove-RuleFromPolicy detaches an attached rule id' {
        (Add-RuleToPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)).Success | Should -BeTrue

        $removeResult = Remove-RuleFromPolicy -PolicyId $script:policyId -RuleId @($script:ruleId)
        $removeResult.Success | Should -BeTrue

        $policy = Get-Policy -PolicyId $script:policyId
        $policy.Success | Should -BeTrue
        $policy.Data.RuleIds | Should -Not -Contain $script:ruleId
    }
}
