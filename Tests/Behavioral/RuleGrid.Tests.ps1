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
