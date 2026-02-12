#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force

    $script:RulesPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Rules.ps1'
    $script:DeployPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Deploy.ps1'
    $script:PolicyPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Policy.ps1'
    $script:DashboardPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Dashboard.ps1'
    $script:MainWindowPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\MainWindow.xaml.ps1'
    $script:ModulePsm1Path = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psm1'
    $script:ScannerPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Scanner.ps1'
    $script:StartScanPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Start-ArtifactScan.ps1'
}

Describe 'Recent regressions: curated guardrails (v1.2.80+)' -Tag @('Behavioral', 'GUI', 'Curated') {
    Context 'Rules dedupe execution' {
        It 'Executes real duplicate removal (not preview only)' {
            $content = Get-Content -Path $script:RulesPath -Raw
            $content -match 'Remove-DuplicateRules\s+-RuleType\s+All\s+-Strategy\s+KeepOldest\s+-WhatIf:\$false' | Should -BeTrue
        }
    }

    Context 'Deploy selected job handling' {
        It 'Backfills JobId from Id for legacy deployment rows' {
            $content = Get-Content -Path $script:DeployPath -Raw
            $content -match '\$props\[''JobId''\]\s*=\s*\[string\]\$props\[''Id''\]' | Should -BeTrue
        }

        It 'Captures a stable selectedJobId before deployment runspace starts' {
            $content = Get-Content -Path $script:DeployPath -Raw
            $content -match '\$selectedJobId\s*=\s*\[string\]\$script:SelectedDeploymentJobId' | Should -BeTrue
            $content -match 'JobId\s*=\s*\$selectedJobId' | Should -BeTrue
        }
    }

    Context 'Policy add/remove rule async flow' {
        It 'Uses Invoke-BackgroundWork for add/remove rules and avoids Invoke-AsyncOperation' {
            $content = Get-Content -Path $script:PolicyPath -Raw

            $addStart = $content.IndexOf('function global:Invoke-AddRulesToPolicy')
            $removeStart = $content.IndexOf('function global:Invoke-RemoveRulesFromPolicy')
            $nextStart = $content.IndexOf('function global:Select-PolicyInGrid')

            $addStart | Should -BeGreaterThan -1
            $removeStart | Should -BeGreaterThan $addStart
            $nextStart | Should -BeGreaterThan $removeStart

            $addBlock = $content.Substring($addStart, $removeStart - $addStart)
            $removeBlock = $content.Substring($removeStart, $nextStart - $removeStart)

            $addBlock.Contains('Invoke-BackgroundWork -ScriptBlock $bgWork') | Should -BeTrue
            $removeBlock.Contains('Invoke-BackgroundWork -ScriptBlock $bgWork') | Should -BeTrue
            $addBlock.Contains('Invoke-AsyncOperation') | Should -BeFalse
            $removeBlock.Contains('Invoke-AsyncOperation') | Should -BeFalse
        }

        It 'Imports only Core + Policy modules inside policy add/remove background work' {
            $content = Get-Content -Path $script:PolicyPath -Raw
            ([regex]::Matches($content, "GA-AppLocker.Core', 'GA-AppLocker.Policy")).Count | Should -BeGreaterThan 1
        }
    }

    Context 'Dashboard stats refresh stability' {
        It 'Uses in-progress guard and clears it on both complete and timeout paths' {
            $content = Get-Content -Path $script:DashboardPath -Raw
            $content.Contains('if ($global:GA_DashboardStatsInProgress) { return }') | Should -BeTrue
            $content.Contains('$global:GA_DashboardStatsInProgress = $true') | Should -BeTrue
            ([regex]::Matches($content, '\$global:GA_DashboardStatsInProgress\s*=\s*\$false')).Count | Should -BeGreaterThan 1
            $content -match 'Invoke-BackgroundWork\s+-ScriptBlock\s+\$bgWork' | Should -BeTrue
        }
    }

    Context 'Write-Log bootstrap hardening' {
        It 'Defines a safe Write-Log wrapper in MainWindow code-behind' {
            $content = Get-Content -Path $script:MainWindowPath -Raw
            $content -match 'function\s+global:Write-Log\s*\{' | Should -BeTrue
            $content.Contains('Emergency fallback (never throw from logger)') | Should -BeTrue
        }

        It 'Registers emergency Write-Log fallback before Initialize-MainWindow' {
            $content = Get-Content -Path $script:ModulePsm1Path -Raw
            $content.Contains("if (-not (Get-Command -Name 'Write-Log' -ErrorAction SilentlyContinue)) {") | Should -BeTrue
            $content -match 'Initialize-MainWindow\s+-Window\s+\$window' | Should -BeTrue
        }
    }

    Context 'Scanner import/export and tier routing guardrails' {
        It 'Coerces imported CSV IsSigned values using robust truthy parsing' {
            $content = Get-Content -Path $script:ScannerPath -Raw
            $content.Contains('$normalized = ([string]$rawValue).Trim().ToLowerInvariant()') | Should -BeTrue
            $content.Contains("`$item.IsSigned = (`$normalized -in @('true', '1', 'yes', 'y'))") | Should -BeTrue
        }

        It 'Normalizes machine type tiers and machine type names before credential selection' {
            $content = Get-Content -Path $script:StartScanPath -Raw
            $content.Contains('$ConvertToTierIndex = {') | Should -BeTrue
            $content.Contains('$ResolveMachineType = {') | Should -BeTrue
            $content.Contains('$type = & $ResolveMachineType $_') | Should -BeTrue
        }

        It 'Wraps export SaveFileDialog.ShowDialog calls in try/catch to prevent UI crashes' {
            $scannerContent = Get-Content -Path $script:ScannerPath -Raw
            $rulesContent = Get-Content -Path $script:RulesPath -Raw

            ([regex]::Matches($scannerContent, '\$dialogResult\s*=\s*\$dialog\.ShowDialog\(\)')).Count | Should -BeGreaterThan 1
            ([regex]::Matches($rulesContent, '\$dialogResult\s*=\s*\$dialog\.ShowDialog\(\)')).Count | Should -BeGreaterThan 1
            $scannerContent.Contains('$dialog.CheckPathExists = $true') | Should -BeTrue
            ([regex]::Matches($rulesContent, '\$dialog\.CheckPathExists\s*=\s*\$true')).Count | Should -BeGreaterThan 1
        }
    }
}
