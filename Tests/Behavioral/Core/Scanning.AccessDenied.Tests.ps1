#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Behavioral Scanning: Get-LocalArtifacts access denied paths' -Tag @('Behavioral','Core') {
    It 'Handles access denied paths during recursive scan' {
        Mock Get-DefaultScanPaths { @('C:\Denied') }
        Mock Test-Path { $true }
        Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('Access denied') }
        Mock Write-ScanLog { }

        $result = Get-LocalArtifacts -Recurse

        $result.Success | Should -BeTrue
        $result.Error | Should -BeNullOrEmpty
        Assert-MockCalled Write-ScanLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning'
        }
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

        $content | Should -Match "\$stats\.Errors\s*=\s*\[Math\]::Max\(\$stats\.Errors,\s*\$totalFiles\s*-\s*\$artifacts\.Count\)"
    }
}
