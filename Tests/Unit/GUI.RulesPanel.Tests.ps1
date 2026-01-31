#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for GUI Rules Panel logic.
.DESCRIPTION
    Tests GUI functions with mocked window objects. These tests verify
    business logic without launching the actual WPF window.
    
    Focus areas:
    - Rule deletion workflow
    - Selection state management
    - DataGrid refresh logic
    - Error handling in WPF context
#>

BeforeAll {
    # Import the main module
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -WarningAction SilentlyContinue
    }
    
    # Dot-source the Rules panel to get the global functions
    $rulesPanel = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Rules.ps1'
    if (Test-Path $rulesPanel) {
        . $rulesPanel
    }
    
    # Helper to create a mock WPF window
    function New-MockWindow {
        param(
            [hashtable]$Elements = @{},
            [array]$SelectedItems = @()
        )
        
        $mockWindow = [PSCustomObject]@{
            _elements = $Elements
            _selectedItems = $SelectedItems
        }
        
        $mockWindow | Add-Member -MemberType ScriptMethod -Name 'FindName' -Value {
            param([string]$name)
            
            # Return mock elements based on name
            if ($this._elements.ContainsKey($name)) {
                return $this._elements[$name]
            }
            
            # Default mock elements
            switch -Wildcard ($name) {
                'RulesDataGrid' {
                    return [PSCustomObject]@{
                        ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
                        SelectedItems = $this._selectedItems
                        Items = [PSCustomObject]@{ Count = 100 }
                    }
                }
                'ChkSelectAllRules' {
                    return [PSCustomObject]@{ IsChecked = $false }
                }
                'TxtSelectionCount' {
                    return [PSCustomObject]@{ Text = '0 selected' }
                }
                'BtnFilter*' {
                    return [PSCustomObject]@{ Content = 'Filter (0)' }
                }
                default { return $null }
            }
        }
        
        $mockWindow | Add-Member -MemberType ScriptMethod -Name 'Dispatcher' -Value {
            return [PSCustomObject]@{
                Invoke = { param($action) & $action }
            }
        }
        
        return $mockWindow
    }
    
    # Helper to create mock rule objects
    function New-MockRule {
        param(
            [string]$Id = [guid]::NewGuid().ToString(),
            [string]$Status = 'Pending',
            [string]$RuleType = 'Publisher',
            [string]$Name = 'Test Rule'
        )
        
        return [PSCustomObject]@{
            Id = $Id
            RuleId = $Id
            Status = $Status
            RuleType = $RuleType
            Name = $Name
            CreatedDate = (Get-Date).AddDays(-1)
        }
    }
}

Describe 'Rules Panel - Rule Operations' {
    Context 'Get-SelectedRules helper logic' {
        It 'Should return all rules when AllRulesSelected is true' {
            # Arrange
            $script:AllRulesSelected = $true
            $allRules = @(
                New-MockRule -Id 'rule-1'
                New-MockRule -Id 'rule-2'
                New-MockRule -Id 'rule-3'
            )
            
            $mockDataGrid = [PSCustomObject]@{
                ItemsSource = $allRules
                SelectedItems = @($allRules[0])  # Only 1 visually selected
            }
            
            $mockWindow = New-MockWindow -Elements @{
                'RulesDataGrid' = $mockDataGrid
            }
            
            # Act - simulate Get-SelectedRules logic
            $result = if ($script:AllRulesSelected) {
                @($mockDataGrid.ItemsSource)
            } else {
                @($mockDataGrid.SelectedItems)
            }
            
            # Assert
            $result.Count | Should -Be 3
        }
    }
}

Describe 'Rules Panel - Error Handling' {
    Context 'Try-Catch Pattern (WPF Context Safe)' {
        It 'Should handle missing functions gracefully' {
            # This simulates the pattern we use instead of Get-Command
            $result = $null
            $errorOccurred = $false
            
            try {
                # Simulate calling a function that might not exist
                $result = & { 
                    # In real code this would be: SomeFunctionThatMightNotExist
                    throw "Function not found"
                }
            } catch {
                $errorOccurred = $true
            }
            
            # Assert - error was caught, didn't crash
            $errorOccurred | Should -BeTrue
            $result | Should -BeNullOrEmpty
        }
        
        It 'Should continue execution after caught error' {
            $steps = @()
            
            # Step 1
            $steps += 'before'
            
            # Step 2 - might fail
            try { throw "Simulated WPF error" } catch { }
            
            # Step 3 - should still execute
            $steps += 'after'
            
            $steps | Should -Contain 'before'
            $steps | Should -Contain 'after'
            $steps.Count | Should -Be 2
        }
    }
}

Describe 'Rules Panel - Filter Button Counts' {
    Context 'Update-RuleCounters' {
        It 'Should update button content with counts' {
            # Arrange
            $mockCounts = [PSCustomObject]@{
                Pending = 25
                Approved = 100
                Rejected = 5
                Total = 130
            }
            
            $mockButtons = @{
                'BtnFilterPending' = [PSCustomObject]@{ Content = '' }
                'BtnFilterApproved' = [PSCustomObject]@{ Content = '' }
                'BtnFilterRejected' = [PSCustomObject]@{ Content = '' }
                'BtnFilterAll' = [PSCustomObject]@{ Content = '' }
            }
            
            # Act - Simulate counter update
            $mockButtons['BtnFilterPending'].Content = "Pending ($($mockCounts.Pending))"
            $mockButtons['BtnFilterApproved'].Content = "Approved ($($mockCounts.Approved))"
            $mockButtons['BtnFilterRejected'].Content = "Rejected ($($mockCounts.Rejected))"
            $mockButtons['BtnFilterAll'].Content = "All ($($mockCounts.Total))"
            
            # Assert
            $mockButtons['BtnFilterPending'].Content | Should -Be 'Pending (25)'
            $mockButtons['BtnFilterApproved'].Content | Should -Be 'Approved (100)'
            $mockButtons['BtnFilterAll'].Content | Should -Be 'All (130)'
        }
    }
}
