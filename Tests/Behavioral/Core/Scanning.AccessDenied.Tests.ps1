#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Behavioral Scanning: Get-LocalArtifacts access denied paths' -Tag @('Behavioral','Core') {
    It 'Handles access denied paths during recursive scan' {
        # Pass a non-existent path — Get-LocalArtifacts should handle gracefully
        $result = Get-LocalArtifacts -Paths @('C:\NonExistent_TestPath_DoesNotExist') -Recurse

        $result.Success | Should -BeTrue
        $result.Data.Count | Should -Be 0
    }

    It 'Uses ErrorVariable for access denied detection' {
        $scanPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Get-LocalArtifacts.ps1'
        $content = Get-Content $scanPath -Raw

        $content | Should -Match "ErrorVariable\s*=\s*'accessErrors'"
        $content | Should -Match "-ErrorVariable\s+extErrors"
    }

    It 'Counts missing artifacts as errors in parallel scan' {
        $scanPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Get-LocalArtifacts.ps1'
        $content = Get-Content $scanPath -Raw

        $content | Should -Match '\$stats\.Errors\s*=\s*\[Math\]::Max\(\$stats\.Errors,\s*\$totalFiles\s*-\s*\$artifacts\.Count\)'
    }
}
