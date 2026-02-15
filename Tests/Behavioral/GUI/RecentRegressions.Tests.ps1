#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    if (-not $env:LOCALAPPDATA) {
        $env:LOCALAPPDATA = Join-Path ([System.IO.Path]::GetTempPath()) 'GA-AppLocker'
    }
    if (-not (Test-Path -Path $env:LOCALAPPDATA)) {
        [void](New-Item -Path $env:LOCALAPPDATA -ItemType Directory -Force)
    }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')

    $script:RulesPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Rules.ps1'
    $script:DeployPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Deploy.ps1'
    $script:PolicyPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Policy.ps1'
    $script:DashboardPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Dashboard.ps1'

    . $script:RulesPath
    . $script:DeployPath
    . $script:PolicyPath
    . $script:DashboardPath

    $script:MockModuleBase = Join-Path ([System.IO.Path]::GetTempPath()) ('ga-module-' + [guid]::NewGuid().ToString('N'))
    $script:MissingModuleBase = Join-Path ([System.IO.Path]::GetTempPath()) ('ga-missing-' + [guid]::NewGuid().ToString('N'))

    if (-not $global:GA_TestToastEvents) {
        $global:GA_TestToastEvents = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    function global:Show-AppLockerMessageBox {
        param($Message, $Title, $Button, $Icon)
        return 'Yes'
    }

    function global:Show-Toast {
        param($Message, $Type = 'Info')
        if (-not $global:GA_TestToastEvents) {
            $global:GA_TestToastEvents = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        [void]$global:GA_TestToastEvents.Add([PSCustomObject]@{ Message = $Message; Type = $Type })
    }

    function global:Invoke-BackgroundWork {
        param(
            [scriptblock]$ScriptBlock,
            [object[]]$ArgumentList,
            [scriptblock]$OnComplete,
            [scriptblock]$OnTimeout
        )

        $result = if ($ScriptBlock) { & $ScriptBlock @($ArgumentList) } else { $null }
        if ($OnComplete) { & $OnComplete $result }
        return 'bg-fallback'
    }

    function global:Invoke-UIUpdate {
        param([scriptblock]$ScriptBlock)
        if ($ScriptBlock) { & $ScriptBlock }
    }

    function global:Write-Log {
        param([string]$Message, [string]$Level = 'Info')
    }
}

Describe 'Recent regressions: curated guardrails (v1.2.80+)' -Tag @('Behavioral', 'GUI', 'Curated') {
    AfterEach {
        $script:SelectedDeploymentJobId = $null
        $script:DeploymentInProgress = $false
        $script:DeploymentCancelled = $false
        $script:DeployPrevFilter = $null
        $script:CurrentDeploymentFilter = 'All'
        $script:DeploySyncHash = $null
        $script:DeployAsyncResult = $null

        if ($script:DeployPowerShell) {
            try { $script:DeployPowerShell.Stop() } catch { }
            try { $script:DeployPowerShell.Dispose() } catch { }
        }
        if ($script:DeployRunspace) {
            try { $script:DeployRunspace.Close() } catch { }
            try { $script:DeployRunspace.Dispose() } catch { }
        }
        $script:DeployPowerShell = $null
        $script:DeployRunspace = $null
        $script:DeployTimer = $null

        $script:SelectedPolicyId = $null

        $global:GA_DashboardStatsInProgress = $false
        $global:GA_DashboardStats_Window = $null

        foreach ($name in @(
            'GA_PolicyAdd_Window',
            'GA_PolicyAdd_PolicyId',
            'GA_PolicyAdd_PolicyName',
            'GA_PolicyRemove_Window',
            'GA_PolicyRemove_PolicyId',
            'GA_PolicyRemove_PolicyName'
        )) {
            Remove-Variable -Scope Global -Name $name -ErrorAction SilentlyContinue
        }

        if ($global:GA_TestToastEvents) {
            $global:GA_TestToastEvents.Clear()
        }
    }

    Context 'Rules dedupe execution' {
        It 'Executes preview first, then confirmed duplicate removal' {
            $win = New-MockWpfWindow

            Mock Show-AppLockerMessageBox { 'Yes' }
            Mock Show-Toast { }
            Mock Write-Log { }
            Mock Reset-RulesSelectionState { }
            Mock Update-RulesDataGrid { }
            Mock Update-DashboardStats { }
            Mock Get-Module { [PSCustomObject]@{ ModuleBase = $script:MockModuleBase } } -ParameterFilter { $Name -eq 'GA-AppLocker' }
            Mock Test-Path { $true }
            Mock Import-Module { }
            Mock Remove-DuplicateRules {
                param($RuleType, $Strategy, [switch]$WhatIf)
                if ($WhatIf) {
                    return [PSCustomObject]@{
                        DuplicateCount     = 2
                        HashDuplicates     = 1
                        PublisherDuplicates = 1
                    }
                }
                return @{ Success = $true; RemovedCount = 2 }
            }
            Mock Invoke-BackgroundWork {
                param($ScriptBlock, $ArgumentList, $OnComplete, $OnTimeout)
                $result = & $ScriptBlock $ArgumentList[0]
                & $OnComplete $result
                return 'bg-dedupe-1'
            }

            Invoke-RemoveDuplicateRules -Window $win

            Assert-MockCalled Remove-DuplicateRules -Times 1 -Exactly -ParameterFilter { $WhatIf }
            Assert-MockCalled Remove-DuplicateRules -Times 1 -Exactly -ParameterFilter {
                (-not $WhatIf) -and $RuleType -eq 'All' -and $Strategy -eq 'KeepOldest'
            }
            Assert-MockCalled Invoke-BackgroundWork -Times 1 -Exactly
        }
    }

    Context 'Deploy selected job handling' {
        It 'Backfills selected job id from legacy Id when JobId is missing' {
            $selected = [PSCustomObject]@{
                Id       = 'legacy-001'
                Progress = 40
                Message  = 'Legacy row'
            }

            $dataGrid = New-MockDataGrid -Data @($selected) -SelectedItem $selected
            $msg = New-MockTextBlock
            $bar = New-MockProgressBar
            $win = New-MockWpfWindow -Elements @{
                DeploymentJobsDataGrid = $dataGrid
                TxtDeploymentMessage   = $msg
                DeploymentProgressBar  = $bar
            }

            Update-SelectedJobInfo -Window $win

            $script:SelectedDeploymentJobId | Should -Be 'legacy-001'
            $msg.Text | Should -Be 'Legacy row'
            $bar.Value | Should -Be 40
        }

        It 'Uses captured JobId even if selection state mutates later in the flow' {
            $fakeTimer = [PSCustomObject]@{
                Interval = [TimeSpan]::FromMilliseconds(0)
                IsEnabled = $false
                TickHandler = $null
            }
            $fakeTimer | Add-Member -MemberType ScriptMethod -Name Add_Tick -Value {
                param($handler)
                $this.TickHandler = $handler
            }
            $fakeTimer | Add-Member -MemberType ScriptMethod -Name Start -Value { $this.IsEnabled = $true }
            $fakeTimer | Add-Member -MemberType ScriptMethod -Name Stop -Value { $this.IsEnabled = $false }

            $script:CurrentDeploymentFilter = 'Running'

            Mock Update-SelectedJobInfo { $script:SelectedDeploymentJobId = '  job-initial  ' }
            Mock Show-AppLockerMessageBox { 'Yes' }
            Mock Update-DeploymentUIState { }
            Mock Update-DeploymentProgress {
                param($Window, $Text, $Percent)
                $script:SelectedDeploymentJobId = 'job-mutated'
            }
            Mock Update-DeploymentFilter { }
            Mock Show-Toast { }
            Mock Get-Module { [PSCustomObject]@{ ModuleBase = $script:MissingModuleBase } } -ParameterFilter { $Name -eq 'GA-AppLocker' }
            Mock New-Object {
                param($TypeName)
                if ($TypeName -eq 'System.Windows.Threading.DispatcherTimer') {
                    return $fakeTimer
                }
            } -ParameterFilter { $TypeName -eq 'System.Windows.Threading.DispatcherTimer' }

            $win = New-MockWpfWindow

            Invoke-DeploySelectedJob -Window $win

            $script:SelectedDeploymentJobId | Should -Be 'job-mutated'
            $script:DeploySyncHash | Should -Not -BeNullOrEmpty
            $script:DeploySyncHash.JobId | Should -Be 'job-initial'
        }
    }

    Context 'Policy add/remove rule async flow' {
        It 'Returns structured errors for add-rules module load failures and avoids global singleton context' {
            $script:SelectedPolicyId = 'policy-add-1'
            $win = New-MockWpfWindow

            Mock Get-Policy {
                return @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'policy-add-1'; Name = 'Policy Add'; Phase = 5; RuleIds = @() } }
            }
            Mock Get-PhaseCollectionTypes { @('Exe') }
            Mock Get-AllRules {
                return @{ Success = $true; Data = @([PSCustomObject]@{ Id = 'rule-1'; Status = 'Approved'; CollectionType = 'Exe' }) }
            }
            Mock Get-Module { [PSCustomObject]@{ ModuleBase = $script:MissingModuleBase } } -ParameterFilter { $Name -eq 'GA-AppLocker' }
            Mock Update-PoliciesDataGrid { }
            Mock Update-SelectedPolicyInfo { }
            Mock Invoke-BackgroundWork {
                param($ScriptBlock, $ArgumentList, $OnComplete, $OnTimeout)
                $result = & $ScriptBlock $ArgumentList[0] $ArgumentList[1] $ArgumentList[2]
                & $OnComplete $result
                return 'bg-policy-add-1'
            }

            Invoke-AddRulesToPolicy -Window $win

            Assert-MockCalled Invoke-BackgroundWork -Times 1 -Exactly
            $addToast = if ($global:GA_TestToastEvents.Count -gt 0) { $global:GA_TestToastEvents[$global:GA_TestToastEvents.Count - 1] } else { $null }
            $addToast | Should -Not -BeNullOrEmpty
            $addToast.Type | Should -Be 'Error'
            $addToast.Message | Should -Match 'Required module missing'
            (Get-Variable -Scope Global -Name 'GA_PolicyAdd_Window' -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }

        It 'Keeps add callback context isolated across overlapping invocations' {
            $winOne = New-MockWpfWindow
            $winTwo = New-MockWpfWindow
            $winOne | Add-Member -MemberType NoteProperty -Name 'TestId' -Value 'win-one' -Force
            $winTwo | Add-Member -MemberType NoteProperty -Name 'TestId' -Value 'win-two' -Force

            $script:capturedAddCallbacks = [System.Collections.ArrayList]::new()
            $script:updateOrder = [System.Collections.Generic.List[string]]::new()

            $originalUpdateGrid = (Get-Command -Name 'Update-PoliciesDataGrid' -ErrorAction Stop).ScriptBlock
            $originalUpdateSelected = (Get-Command -Name 'Update-SelectedPolicyInfo' -ErrorAction Stop).ScriptBlock

            Mock Get-Policy {
                param($PolicyId)
                if ($PolicyId -eq 'policy-one') {
                    return @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'policy-one'; Name = 'Policy One'; Phase = 5; RuleIds = @() } }
                }

                return @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'policy-two'; Name = 'Policy Two'; Phase = 5; RuleIds = @() } }
            }
            Mock Get-PhaseCollectionTypes { @('Exe') }
            Mock Get-AllRules {
                return @{ Success = $true; Data = @([PSCustomObject]@{ Id = 'rule-ctx-1'; Status = 'Approved'; CollectionType = 'Exe' }) }
            }
            Mock Get-Module { [PSCustomObject]@{ ModuleBase = $script:MockModuleBase } } -ParameterFilter { $Name -eq 'GA-AppLocker' }
            Mock Invoke-BackgroundWork {
                param($ScriptBlock, $ArgumentList, $OnComplete, $OnTimeout)
                [void]$script:capturedAddCallbacks.Add($OnComplete)
                return "bg-policy-add-$($script:capturedAddCallbacks.Count)"
            }

            function global:Update-PoliciesDataGrid {
                param($Window, [switch]$Force)
                [void]$script:updateOrder.Add($Window.TestId)
            }

            function global:Update-SelectedPolicyInfo {
                param($Window)
            }

            try {
                $script:SelectedPolicyId = 'policy-one'
                Invoke-AddRulesToPolicy -Window $winOne

                $script:SelectedPolicyId = 'policy-two'
                Invoke-AddRulesToPolicy -Window $winTwo

                $script:capturedAddCallbacks.Count | Should -Be 2

                & $script:capturedAddCallbacks[1] @{ Success = $true }
                & $script:capturedAddCallbacks[0] @{ Success = $true }

                $script:updateOrder.Count | Should -Be 2
                $script:updateOrder[0] | Should -Be 'win-two'
                $script:updateOrder[1] | Should -Be 'win-one'

                $global:GA_TestToastEvents.Count | Should -Be 2
                $global:GA_TestToastEvents[0].Message | Should -Match 'Policy Two'
                $global:GA_TestToastEvents[1].Message | Should -Match 'Policy One'
            }
            finally {
                Set-Item -Path 'Function:\global:Update-PoliciesDataGrid' -Value $originalUpdateGrid
                Set-Item -Path 'Function:\global:Update-SelectedPolicyInfo' -Value $originalUpdateSelected
            }
        }

        It 'Returns structured errors for remove-rules module load failures and avoids global singleton context' {
            $script:SelectedPolicyId = 'policy-remove-1'
            $win = New-MockWpfWindow

            Mock Get-Policy {
                return @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'policy-remove-1'; Name = 'Policy Remove'; RuleIds = @('rule-1') } }
            }
            Mock Show-AppLockerMessageBox { 'Yes' }
            Mock Get-Module { [PSCustomObject]@{ ModuleBase = $script:MissingModuleBase } } -ParameterFilter { $Name -eq 'GA-AppLocker' }
            Mock Update-PoliciesDataGrid { }
            Mock Update-SelectedPolicyInfo { }
            Mock Invoke-BackgroundWork {
                param($ScriptBlock, $ArgumentList, $OnComplete, $OnTimeout)
                $result = & $ScriptBlock $ArgumentList[0] $ArgumentList[1] $ArgumentList[2]
                & $OnComplete $result
                return 'bg-policy-remove-1'
            }

            Invoke-RemoveRulesFromPolicy -Window $win

            Assert-MockCalled Invoke-BackgroundWork -Times 1 -Exactly
            $removeToast = if ($global:GA_TestToastEvents.Count -gt 0) { $global:GA_TestToastEvents[$global:GA_TestToastEvents.Count - 1] } else { $null }
            $removeToast | Should -Not -BeNullOrEmpty
            $removeToast.Type | Should -Be 'Error'
            $removeToast.Message | Should -Match 'Required module missing'
            (Get-Variable -Scope Global -Name 'GA_PolicyRemove_Window' -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }

    Context 'Dashboard stats refresh stability' {
        It 'Guards against overlap and clears in-progress state on both complete and timeout callbacks' {
            $win = New-MockWpfWindow
            $script:dashboardOnComplete = $null
            $script:dashboardOnTimeout = $null
            $script:appliedStats = $null

            Mock Get-Module { [PSCustomObject]@{ ModuleBase = $script:MockModuleBase } } -ParameterFilter { $Name -eq 'GA-AppLocker' }
            Mock Invoke-BackgroundWork {
                param($ScriptBlock, $ArgumentList, $OnComplete, $OnTimeout)
                $script:dashboardOnComplete = $OnComplete
                $script:dashboardOnTimeout = $OnTimeout
                return 'bg-dashboard-1'
            }
            Mock Invoke-UIUpdate {
                param($ScriptBlock)
                & $ScriptBlock
            }
            Mock Apply-DashboardStats {
                param($Window, $Stats)
                $script:appliedStats = $Stats
            }
            Mock Write-Log { }

            Invoke-DashboardStatsRefresh -Window $win
            $global:GA_DashboardStatsInProgress | Should -BeTrue

            Invoke-DashboardStatsRefresh -Window $win
            Assert-MockCalled Invoke-BackgroundWork -Times 1 -Exactly

            & $script:dashboardOnComplete ([PSCustomObject]@{
                MachineCount = 1
                ArtifactCount = 2
                RuleCounts = $null
                PendingRules = @()
                PolicyCount = 3
                RecentScans = @()
            })

            $global:GA_DashboardStatsInProgress | Should -BeFalse
            $script:appliedStats | Should -Not -BeNullOrEmpty
            $script:appliedStats.MachineCount | Should -Be 1

            Invoke-DashboardStatsRefresh -Window $win
            Assert-MockCalled Invoke-BackgroundWork -Times 2 -Exactly

            & $script:dashboardOnTimeout 'timed out'
            $global:GA_DashboardStatsInProgress | Should -BeFalse
        }
    }
}
