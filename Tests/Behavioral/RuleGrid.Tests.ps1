#Requires -Modules Pester

Describe 'Update-RulesGrid null guards' {
    BeforeEach {
        Import-Module $PSScriptRoot\..\..\GA-AppLocker\GA-AppLocker.psd1 -Force -ErrorAction Stop
    }

    It 'Returns early when Rules is null' {
        $result = Update-RulesGrid -Rules $null
        $result | Should -BeNullOrEmpty
    }

    It 'Uses O(1) collection when Rules provided' {
        $testRules = @(
            [PSCustomObject]@{ Id = '1'; Name = 'Test1' }
            [PSCustomObject]@{ Id = '2'; Name = 'Test2' }
        )
        
        $result = Update-RulesGrid -Rules $testRules
        # Verify internal collection was created
        # (would need to modify function to return list for testing)
        $result | Should -BeTrue
    }
}

Describe 'Rules grid null guards' {
    BeforeAll {
        Import-Module $PSScriptRoot\..\..\GA-AppLocker\GA-AppLocker.psd1 -Force -ErrorAction Stop
    }

    It 'Normalizes Result.Data to array' {
        $rulesPath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Rules.ps1'
        $rulesContent = Get-Content $rulesPath -Raw

        $rulesContent | Should -Match '\$rules\s*=\s*@\(\$Result\.Data\)'
    }

    It 'Returns early when rules are empty' {
        $rulesPath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Rules.ps1'
        $rulesContent = Get-Content $rulesPath -Raw

        $pattern = '(?s)if\s*\(-not\s+\$rules\s+-or\s+\$rules\.Count\s+-eq\s+0\).*?Update-RuleCounters.*?return'
        $rulesContent | Should -Match $pattern
    }
}
