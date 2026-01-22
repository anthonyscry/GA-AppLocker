#region Rules Panel Functions
# Rules.ps1 - Rules panel handlers
function Initialize-RulesPanel {
    param([System.Windows.Window]$Window)

    # Wire up filter buttons
    $filterButtons = @(
        'BtnFilterAllRules', 'BtnFilterPublisher', 'BtnFilterHash', 'BtnFilterPath',
        'BtnFilterPending', 'BtnFilterApproved', 'BtnFilterRejected'
    )

    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Add_Click({
                    param($sender, $e)
                    $tag = $sender.Tag
                    if ($tag -match 'FilterRules(.+)') {
                        $filter = $Matches[1]
                        Update-RulesFilter -Window $script:MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnGenerateFromArtifacts', 'BtnCreateManualRule', 'BtnExportRulesXml', 'BtnExportRulesCsv',
        'BtnRefreshRules', 'BtnApproveRule', 'BtnRejectRule', 'BtnReviewRule',
        'BtnDeleteRule', 'BtnViewRuleDetails', 'BtnAddRuleToPolicy',
        'BtnApproveTrustedRules', 'BtnRemoveDuplicateRules'
    )

    foreach ($btnName in $actionButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $btn.Add_Click({
                    param($sender, $e)
                    Invoke-ButtonAction -Action $sender.Tag
                }.GetNewClosure())
        }
    }

    # Wire up text filter
    $filterBox = $Window.FindName('TxtRuleFilter')
    if ($filterBox) {
        $filterBox.Add_TextChanged({
                Update-RulesDataGrid -Window $script:MainWindow
            })
    }

    # Wire up Select All checkbox
    $selectAllChk = $Window.FindName('ChkSelectAllRules')
    if ($selectAllChk) {
        $selectAllChk.Add_Checked({
                Invoke-SelectAllRules -Window $script:MainWindow -SelectAll $true
            })
        $selectAllChk.Add_Unchecked({
                Invoke-SelectAllRules -Window $script:MainWindow -SelectAll $false
            })
    }

    # Wire up DataGrid selection changed for count update
    $rulesGrid = $Window.FindName('RulesDataGrid')
    if ($rulesGrid) {
        $rulesGrid.Add_SelectionChanged({
                Update-RulesSelectionCount -Window $script:MainWindow
            })
    }

    # Set initial filter button state (All is active by default)
    $btnAll = $Window.FindName('BtnFilterAllRules')
    if ($btnAll) {
        $btnAll.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 122, 204))
    }
    
    # Set initial opacity for status buttons (dimmed until selected)
    foreach ($btnName in @('BtnFilterPending', 'BtnFilterApproved', 'BtnFilterRejected')) {
        $btn = $Window.FindName($btnName)
        if ($btn) { $btn.Opacity = 0.6 }
    }

    # Initial load - use async to keep UI responsive
    Update-RulesDataGrid -Window $Window -Async
}

function script:Update-RulesDataGrid {
    param(
        [System.Windows.Window]$Window,
        [switch]$Async
    )

    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid) { return }

    # Check if module function is available
    if (-not (Get-Command -Name 'Get-AllRules' -ErrorAction SilentlyContinue)) {
        $dataGrid.ItemsSource = $null
        return
    }

    # Capture filter state for use in async callback
    $typeFilter = $script:CurrentRulesTypeFilter
    $statusFilter = $script:CurrentRulesFilter
    $filterBox = $Window.FindName('TxtRuleFilter')
    $textFilter = if ($filterBox) { $filterBox.Text } else { '' }

    # Define the data processing logic
    $processRulesData = {
        param($Result, $TypeFilter, $StatusFilter, $TextFilter, $DataGrid, $Window)
        
        if (-not $Result.Success) {
            $DataGrid.ItemsSource = $null
            return
        }

        $rules = $Result.Data

        # Apply type filter
        if ($TypeFilter -and $TypeFilter -ne 'All') {
            $rules = $rules | Where-Object { $_.RuleType -eq $TypeFilter }
        }

        # Apply status filter
        if ($StatusFilter -and $StatusFilter -notin @('All', 'Publisher', 'Hash', 'Path')) {
            $rules = $rules | Where-Object { $_.Status -eq $StatusFilter }
        }

        # Apply text filter
        if (-not [string]::IsNullOrWhiteSpace($TextFilter)) {
            $filterText = $TextFilter.ToLower()
            $rules = $rules | Where-Object {
                $_.Name.ToLower().Contains($filterText) -or
                $_.CollectionType.ToLower().Contains($filterText) -or
                ($_.Description -and $_.Description.ToLower().Contains($filterText)) -or
                ($_.GroupName -and $_.GroupName.ToLower().Contains($filterText)) -or
                ($_.GroupVendor -and $_.GroupVendor.ToLower().Contains($filterText))
            }
        }

        # Add display properties and map rule properties for UI
        $displayData = $rules | ForEach-Object {
            $rule = $_
            $props = @{}
            $_.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            # Map properties for XAML bindings and UI compatibility
            $props['RuleId'] = $_.Id
            $props['Collection'] = $_.CollectionType
            $props['CreatedAt'] = $_.CreatedDate
            $props['ModifiedAt'] = $_.ModifiedDate
            $props['CreatedDisplay'] = if ($_.CreatedDate) { ([datetime]$_.CreatedDate).ToString('MM/dd HH:mm') } else { '' }
            [PSCustomObject]$props
        }

        $DataGrid.ItemsSource = @($displayData)

        # Update counters from the original result data
        Update-RuleCounters -Window $Window -Rules $Result.Data
    }

    # Use async for initial/refresh loads, sync for filter changes (already have data)
    if ($Async -and (Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction SilentlyContinue)) {
        Invoke-AsyncOperation -ScriptBlock { Get-AllRules } -LoadingMessage 'Loading rules...' -OnComplete {
            param($Result)
            & $processRulesData $Result $typeFilter $statusFilter $textFilter $dataGrid $Window
        }.GetNewClosure() -OnError {
            param($ErrorMessage)
            Write-Log -Level Error -Message "Failed to load rules: $ErrorMessage"
            $dataGrid.ItemsSource = $null
        }.GetNewClosure()
    }
    else {
        # Synchronous fallback
        try {
            $result = Get-AllRules
            & $processRulesData $result $typeFilter $statusFilter $textFilter $dataGrid $Window
        }
        catch {
            Write-Log -Level Error -Message "Failed to update rules grid: $($_.Exception.Message)"
            $dataGrid.ItemsSource = $null
        }
    }
}

function Update-RuleCounters {
    param(
        [System.Windows.Window]$Window,
        [array]$Rules
    )

    $total = if ($Rules) { $Rules.Count } else { 0 }
    $pending = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Pending' }).Count } else { 0 }
    $approved = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Approved' }).Count } else { 0 }
    $rejected = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Rejected' }).Count } else { 0 }

    $Window.FindName('TxtRuleTotalCount').Text = "$total"
    $Window.FindName('TxtRulePendingCount').Text = "$pending"
    $Window.FindName('TxtRuleApprovedCount').Text = "$approved"
    $Window.FindName('TxtRuleRejectedCount').Text = "$rejected"
}

function Update-RulesSelectionCount {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $countText = $Window.FindName('TxtSelectedRuleCount')
    $selectAllChk = $Window.FindName('ChkSelectAllRules')
    
    if (-not $dataGrid -or -not $countText) { return }
    
    $selectedCount = $dataGrid.SelectedItems.Count
    $totalCount = if ($dataGrid.ItemsSource) { @($dataGrid.ItemsSource).Count } else { 0 }
    
    $countText.Text = "$selectedCount"
    
    # Update Select All checkbox state (without triggering events)
    if ($selectAllChk) {
        $selectAllChk.IsChecked = ($selectedCount -gt 0 -and $selectedCount -eq $totalCount)
    }
}

function Invoke-SelectAllRules {
    param(
        [System.Windows.Window]$Window,
        [bool]$SelectAll = $true
    )

    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid) { return }
    
    if ($SelectAll) {
        $dataGrid.SelectAll()
    }
    else {
        $dataGrid.UnselectAll()
    }
    
    Update-RulesSelectionCount -Window $Window
}

function Invoke-AddSelectedRulesToPolicy {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItems = @($dataGrid.SelectedItems)

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules to add to a policy.' -Type 'Warning'
        return
    }

    # Get available policies
    if (-not (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Policy functions not available.' -Type 'Error'
        return
    }

    $policiesResult = Get-AllPolicies
    if (-not $policiesResult.Success -or $policiesResult.Data.Count -eq 0) {
        Show-Toast -Message 'No policies available. Create a policy first.' -Type 'Warning'
        return
    }

    # Create selection dialog
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = "Add $($selectedItems.Count) Rule(s) to Policy"
    $dialog.Width = 400
    $dialog.Height = 300
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.Owner = $Window
    $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1E1E1E')
    $dialog.ResizeMode = 'NoResize'

    $stack = [System.Windows.Controls.StackPanel]::new()
    $stack.Margin = [System.Windows.Thickness]::new(20)

    # Label
    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = "Select a policy to add the selected rules:"
    $label.Foreground = [System.Windows.Media.Brushes]::White
    $label.Margin = [System.Windows.Thickness]::new(0, 0, 0, 15)
    $stack.Children.Add($label)

    # Policy ListBox
    $listBox = [System.Windows.Controls.ListBox]::new()
    $listBox.Height = 150
    $listBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2D2D30')
    $listBox.Foreground = [System.Windows.Media.Brushes]::White
    $listBox.BorderThickness = [System.Windows.Thickness]::new(1)
    $listBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')

    foreach ($policy in $policiesResult.Data) {
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $item.Content = "$($policy.Name) (Phase $($policy.Phase)) - $($policy.Status)"
        $item.Tag = $policy.Id
        $item.Foreground = [System.Windows.Media.Brushes]::White
        $listBox.Items.Add($item)
    }
    $stack.Children.Add($listBox)

    # Buttons
    $btnPanel = [System.Windows.Controls.StackPanel]::new()
    $btnPanel.Orientation = 'Horizontal'
    $btnPanel.HorizontalAlignment = 'Right'
    $btnPanel.Margin = [System.Windows.Thickness]::new(0, 20, 0, 0)

    $btnAdd = [System.Windows.Controls.Button]::new()
    $btnAdd.Content = "Add Rules"
    $btnAdd.Width = 100
    $btnAdd.Height = 32
    $btnAdd.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
    $btnAdd.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0078D4')
    $btnAdd.Foreground = [System.Windows.Media.Brushes]::White
    $btnAdd.BorderThickness = [System.Windows.Thickness]::new(0)

    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Content = "Cancel"
    $btnCancel.Width = 80
    $btnCancel.Height = 32
    $btnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')
    $btnCancel.Foreground = [System.Windows.Media.Brushes]::White
    $btnCancel.BorderThickness = [System.Windows.Thickness]::new(0)

    $btnPanel.Children.Add($btnAdd)
    $btnPanel.Children.Add($btnCancel)
    $stack.Children.Add($btnPanel)

    $dialog.Content = $stack

    # Store references for closures
    $listBoxRef = $listBox
    $selectedRules = $selectedItems
    $dialogRef = $dialog
    $windowRef = $Window

    $btnAdd.Add_Click({
        if ($listBoxRef.SelectedItem) {
            $policyId = $listBoxRef.SelectedItem.Tag
            $addedCount = 0
            $errors = @()
            
            foreach ($rule in $selectedRules) {
                try {
                    $result = Add-RuleToPolicy -PolicyId $policyId -RuleId $rule.Id
                    if ($result.Success) { $addedCount++ }
                    else { $errors += $result.Error }
                }
                catch {
                    $errors += "Rule $($rule.Id): $($_.Exception.Message)"
                }
            }
            
            $dialogRef.DialogResult = $true
            $dialogRef.Close()
            
            if ($addedCount -gt 0) {
                Show-Toast -Message "Added $addedCount rule(s) to policy." -Type 'Success'
            }
            if ($errors.Count -gt 0) {
                Show-Toast -Message "Some rules could not be added: $($errors.Count) error(s)" -Type 'Warning'
                Write-Log -Level Warning -Message "Errors adding rules: $($errors -join '; ')"
            }
        }
        else {
            Show-Toast -Message 'Please select a policy.' -Type 'Warning'
        }
    }.GetNewClosure())

    $btnCancel.Add_Click({
        $dialogRef.DialogResult = $false
        $dialogRef.Close()
    }.GetNewClosure())

    $dialog.ShowDialog()
}

function global:Update-RulesFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    # Reset all filter button styles
    $typeButtons = @('BtnFilterAllRules', 'BtnFilterPublisher', 'BtnFilterHash', 'BtnFilterPath')
    $statusButtons = @('BtnFilterPending', 'BtnFilterApproved', 'BtnFilterRejected')
    
    $defaultBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(45, 45, 48))
    $activeBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 122, 204))
    
    # Type filters (Publisher, Hash, Path, All)
    if ($Filter -in @('All', 'Publisher', 'Hash', 'Path')) {
        $script:CurrentRulesTypeFilter = $Filter
        # Reset status filter when changing type filter to 'All'
        if ($Filter -eq 'All') { 
            $script:CurrentRulesFilter = 'All' 
            # Reset status button styles
            foreach ($btnName in $statusButtons) {
                $btn = $Window.FindName($btnName)
                if ($btn) {
                    # Keep original colors for status buttons
                    $btn.Opacity = 0.6
                }
            }
        }
        
        # Update type button styles
        foreach ($btnName in $typeButtons) {
            $btn = $Window.FindName($btnName)
            if ($btn) {
                $btn.Background = $defaultBg
            }
        }
        
        # Highlight active type filter
        $activeBtn = switch ($Filter) {
            'All' { 'BtnFilterAllRules' }
            'Publisher' { 'BtnFilterPublisher' }
            'Hash' { 'BtnFilterHash' }
            'Path' { 'BtnFilterPath' }
        }
        $btn = $Window.FindName($activeBtn)
        if ($btn) { $btn.Background = $activeBg }
    }
    # Status filters (Pending, Approved, Rejected, Review)
    elseif ($Filter -in @('Pending', 'Approved', 'Rejected', 'Review')) {
        $script:CurrentRulesFilter = $Filter
        
        # Update status button opacity to show active
        foreach ($btnName in $statusButtons) {
            $btn = $Window.FindName($btnName)
            if ($btn) {
                $btn.Opacity = 0.6
            }
        }
        
        # Highlight active status filter
        $activeBtn = switch ($Filter) {
            'Pending' { 'BtnFilterPending' }
            'Approved' { 'BtnFilterApproved' }
            'Rejected' { 'BtnFilterRejected' }
        }
        $btn = $Window.FindName($activeBtn)
        if ($btn) { $btn.Opacity = 1.0 }
    }

    Update-RulesDataGrid -Window $Window
}

function Invoke-GenerateRulesFromArtifacts {
    param([System.Windows.Window]$Window)

    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        Show-Toast -Message 'No artifacts loaded. Please run a scan or load saved scan results first.' -Type 'Warning'
        return
    }

    if (-not (Get-Command -Name 'ConvertFrom-Artifact' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Rules module not loaded.' -Type 'Error'
        return
    }

    # Get options from UI before async
    $collection = $Window.FindName('TxtRuleCollectionName').Text
    if ([string]::IsNullOrWhiteSpace($collection)) { $collection = 'Default' }

    $modeCombo = $Window.FindName('CboRuleGenMode')
    $modeIndex = if ($modeCombo) { $modeCombo.SelectedIndex } else { 0 }

    $mode = switch ($modeIndex) {
        0 { 'Smart' }
        1 { 'Publisher' }
        2 { 'Hash' }
        3 { 'Path' }
        default { 'Smart' }
    }

    $rbAllow = $Window.FindName('RbRuleAllow')
    $action = if ($rbAllow -and $rbAllow.IsChecked) { 'Allow' } else { 'Deny' }

    # Get target group SID
    $targetGroupCombo = $Window.FindName('CboRuleTargetGroup')
    $targetGroupSid = if ($targetGroupCombo -and $targetGroupCombo.SelectedItem) {
        $targetGroupCombo.SelectedItem.Tag
    }
    else {
        'S-1-1-0'  # Everyone
    }

    # Disable generate button during processing
    $btnGenerate = $Window.FindName('BtnGenerateFromArtifacts')
    if ($btnGenerate) { $btnGenerate.IsEnabled = $false }

    # Filter out artifacts that already have rules (performance optimization)
    Show-LoadingOverlay -Message "Checking existing rules..." -SubMessage "Building rule index..."
    
    $originalCount = $script:CurrentScanArtifacts.Count
    $artifactsToProcess = @($script:CurrentScanArtifacts)
    
    try {
        $ruleIndex = Get-ExistingRuleIndex
        if ($ruleIndex.HashCount -gt 0 -or $ruleIndex.PublisherCount -gt 0) {
            $artifactsToProcess = @($script:CurrentScanArtifacts | Where-Object {
                $dominated = $false
                # Check hash rules
                if ($_.SHA256Hash -and $ruleIndex.Hashes.Contains($_.SHA256Hash)) {
                    $dominated = $true
                }
                # Check publisher rules (for signed files)
                if (-not $dominated -and $_.IsSigned -and $_.Publisher) {
                    $pubKey = "$($_.Publisher)|$($_.ProductName)".ToLower()
                    if ($ruleIndex.Publishers.Contains($pubKey)) {
                        $dominated = $true
                    }
                }
                -not $dominated
            })
            
            $skipped = $originalCount - $artifactsToProcess.Count
            if ($skipped -gt 0) {
                Write-Log -Message "Filtered $skipped artifacts that already have rules"
            }
        }
    }
    catch {
        Write-Log -Level Warning -Message "Could not filter existing rules: $($_.Exception.Message)"
    }

    if ($artifactsToProcess.Count -eq 0) {
        Hide-LoadingOverlay
        if ($btnGenerate) { $btnGenerate.IsEnabled = $true }
        Show-Toast -Message "All $originalCount artifacts already have rules. Nothing to generate." -Type 'Info'
        return
    }

    # Show loading overlay
    $filterMsg = if ($originalCount -ne $artifactsToProcess.Count) { " ($($originalCount - $artifactsToProcess.Count) already have rules)" } else { "" }
    Show-LoadingOverlay -Message "Generating Rules..." -SubMessage "Processing $($artifactsToProcess.Count) artifacts...$filterMsg"
    
    Show-Toast -Message "Generating rules from $($artifactsToProcess.Count) of $originalCount artifacts$filterMsg..." -Type 'Info'

    # Create sync hashtable for async communication
    $script:RuleGenSyncHash = [hashtable]::Synchronized(@{
        Window = $Window
        Artifacts = @($artifactsToProcess)
        Mode = $mode
        Action = $action
        TargetGroupSid = $targetGroupSid
        Generated = 0
        Failed = 0
        IsComplete = $false
        Error = $null
    })

    # Create runspace for background processing
    $script:RuleGenRunspace = [runspacefactory]::CreateRunspace()
    $script:RuleGenRunspace.ApartmentState = 'STA'
    $script:RuleGenRunspace.ThreadOptions = 'ReuseThread'
    $script:RuleGenRunspace.Open()
    $script:RuleGenRunspace.SessionStateProxy.SetVariable('SyncHash', $script:RuleGenSyncHash)

    # Get module path - try multiple methods
    $modulePath = $null
    $gaModule = Get-Module GA-AppLocker -ErrorAction SilentlyContinue
    if ($gaModule) {
        $modulePath = $gaModule.ModuleBase
    }
    if (-not $modulePath) {
        # Fallback: look relative to GUI folder
        $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        if (-not (Test-Path (Join-Path $modulePath "GA-AppLocker.psd1"))) {
            $modulePath = Join-Path $PSScriptRoot "..\..\"
        }
    }
    $script:RuleGenRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:RuleGenPowerShell = [powershell]::Create()
    $script:RuleGenPowerShell.Runspace = $script:RuleGenRunspace

    [void]$script:RuleGenPowerShell.AddScript({
        param($SyncHash, $ModulePath)
        
        try {
            # Import module in runspace
            $manifestPath = Join-Path $ModulePath "GA-AppLocker.psd1"
            if (-not (Test-Path $manifestPath)) {
                throw "Module not found at: $manifestPath"
            }
            Import-Module $manifestPath -Force -ErrorAction Stop

            $generated = 0
            $failed = 0

            foreach ($artifact in $SyncHash.Artifacts) {
                try {
                    $ruleType = switch ($SyncHash.Mode) {
                        'Smart' { if ($artifact.IsSigned) { 'Publisher' } else { 'Hash' } }
                        'Publisher' { if ($artifact.IsSigned) { 'Publisher' } else { $null } }
                        'Hash' { 'Hash' }
                        'Path' { 'Path' }
                    }

                    if (-not $ruleType) { continue }

                    $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType $ruleType -Action $SyncHash.Action -UserOrGroupSid $SyncHash.TargetGroupSid -Save
                    if ($result.Success) { $generated++ } else { $failed++ }
                }
                catch {
                    $failed++
                }
            }

            $SyncHash.Generated = $generated
            $SyncHash.Failed = $failed
        }
        catch {
            $SyncHash.Error = $_.Exception.Message
        }
        finally {
            $SyncHash.IsComplete = $true
        }
    })

    [void]$script:RuleGenPowerShell.AddArgument($script:RuleGenSyncHash)
    [void]$script:RuleGenPowerShell.AddArgument($modulePath)

    # Start async
    $script:RuleGenAsyncResult = $script:RuleGenPowerShell.BeginInvoke()

    # Timer to check completion
    $script:RuleGenTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:RuleGenTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:RuleGenTimer.Add_Tick({
        $syncHash = $script:RuleGenSyncHash
        
        # Update progress display
        $total = $syncHash.Artifacts.Count
        $processed = $syncHash.Generated + $syncHash.Failed
        if ($processed -gt 0 -and -not $syncHash.IsComplete) {
            Update-LoadingText -Message "Generating Rules..." -SubMessage "Processed $processed of $total artifacts..."
        }
        
        if ($syncHash.IsComplete) {
            $script:RuleGenTimer.Stop()
            
            # Hide loading overlay
            Hide-LoadingOverlay
            
            # Cleanup
            try { $script:RuleGenPowerShell.EndInvoke($script:RuleGenAsyncResult) } catch {}
            if ($script:RuleGenPowerShell) { $script:RuleGenPowerShell.Dispose() }
            if ($script:RuleGenRunspace) { 
                $script:RuleGenRunspace.Close()
                $script:RuleGenRunspace.Dispose()
            }

            # Re-enable button
            $win = $syncHash.Window
            $btnGenerate = $win.FindName('BtnGenerateFromArtifacts')
            if ($btnGenerate) { $btnGenerate.IsEnabled = $true }

            # Update UI
            Update-RulesDataGrid -Window $win
            Update-WorkflowBreadcrumb -Window $win

            if ($syncHash.Error) {
                Show-Toast -Message "Error: $($syncHash.Error)" -Type 'Error'
            }
            elseif ($syncHash.Generated -gt 0) {
                Show-Toast -Message "Generated $($syncHash.Generated) rule(s) from $($syncHash.Artifacts.Count) artifacts." -Type 'Success'
            }
            if ($syncHash.Failed -gt 0) {
                Show-Toast -Message "$($syncHash.Failed) artifact(s) failed to generate rules." -Type 'Warning'
            }
        }
    })

    $script:RuleGenTimer.Start()
}

function Invoke-CreateManualRule {
    param([System.Windows.Window]$Window)

    $typeCombo = $Window.FindName('CboManualRuleType')
    $value = $Window.FindName('TxtManualRuleValue').Text
    $desc = $Window.FindName('TxtManualRuleDesc').Text
    $action = if ($Window.FindName('RbRuleAllow').IsChecked) { 'Allow' } else { 'Deny' }

    # Get target group SID
    $targetGroupCombo = $Window.FindName('CboManualRuleTargetGroup')
    $targetGroupSid = if ($targetGroupCombo -and $targetGroupCombo.SelectedItem) {
        $targetGroupCombo.SelectedItem.Tag
    }
    else {
        'S-1-1-0'  # Everyone
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        Show-Toast -Message 'Please enter a path, hash, or publisher value.' -Type 'Warning'
        return
    }

    $ruleType = switch ($typeCombo.SelectedIndex) {
        0 { 'Path' }
        1 { 'Hash' }
        2 { 'Publisher' }
        default { 'Path' }
    }

    try {
        $result = switch ($ruleType) {
            'Path' {
                if (-not (Get-Command -Name 'New-PathRule' -ErrorAction SilentlyContinue)) { throw 'New-PathRule not available' }
                New-PathRule -Path $value -Action $action -Description $desc -CollectionType 'Exe' -UserOrGroupSid $targetGroupSid -Save
            }
            'Hash' {
                if (-not (Get-Command -Name 'New-HashRule' -ErrorAction SilentlyContinue)) { throw 'New-HashRule not available' }
                New-HashRule -Hash $value -SourceFileName 'Manual' -Action $action -Description $desc -CollectionType 'Exe' -UserOrGroupSid $targetGroupSid -Save
            }
            'Publisher' {
                if (-not (Get-Command -Name 'New-PublisherRule' -ErrorAction SilentlyContinue)) { throw 'New-PublisherRule not available' }
                $parts = $value -split ','
                $pubName = $parts[0].Trim()
                $prodName = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '*' }
                New-PublisherRule -PublisherName $pubName -ProductName $prodName -Action $action -Description $desc -CollectionType 'Exe' -UserOrGroupSid $targetGroupSid -Save
            }
        }

        if ($result.Success) {
            $Window.FindName('TxtManualRuleValue').Text = ''
            $Window.FindName('TxtManualRuleDesc').Text = ''
            Update-RulesDataGrid -Window $Window
            Show-Toast -Message "$ruleType rule created successfully." -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to create rule: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error creating rule: $($_.Exception.Message)" -Type 'Error'
    }
}

function Set-SelectedRuleStatus {
    param(
        [System.Windows.Window]$Window,
        [string]$Status
    )

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItems = $dataGrid.SelectedItems

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules.' -Type 'Warning'
        return
    }

    if (-not (Get-Command -Name 'Set-RuleStatus' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Set-RuleStatus function not available.' -Type 'Error'
        return
    }

    $updated = 0
    $errors = @()
    foreach ($item in $selectedItems) {
        try {
            $result = Set-RuleStatus -Id $item.Id -Status $Status
            if ($result.Success) { $updated++ }
        }
        catch { 
            $errors += "Rule $($item.Id): $($_.Exception.Message)"
        }
    }
    if ($errors.Count -gt 0) {
        Write-AppLockerLog -Level Warning -Message "Errors updating rules: $($errors -join '; ')" -NoConsole
    }

    Update-RulesDataGrid -Window $Window
    Update-RulesSelectionCount -Window $Window
    
    if ($updated -gt 0) {
        Show-Toast -Message "Updated $updated rule(s) to '$Status'." -Type 'Success'
    }
    if ($errors.Count -gt 0) {
        Show-Toast -Message "$($errors.Count) rule(s) failed to update." -Type 'Warning'
    }
}

function Invoke-DeleteSelectedRules {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItems = $dataGrid.SelectedItems

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules to delete.' -Type 'Warning'
        return
    }

    # Use MessageBox for confirmation (requires blocking user interaction)
    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete $($selectedItems.Count) rule(s)?`n`nThis action cannot be undone.",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne 'Yes') { return }

    if (-not (Get-Command -Name 'Remove-Rule' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Remove-Rule function not available.' -Type 'Error'
        return
    }

    $deleted = 0
    $errors = @()
    foreach ($item in $selectedItems) {
        try {
            $result = Remove-Rule -Id $item.Id
            if ($result.Success) { $deleted++ }
        }
        catch { 
            $errors += "Rule $($item.Id): $($_.Exception.Message)"
        }
    }
    if ($errors.Count -gt 0) {
        Write-AppLockerLog -Level Warning -Message "Errors deleting rules: $($errors -join '; ')" -NoConsole
    }

    Update-RulesDataGrid -Window $Window
    Update-RulesSelectionCount -Window $Window
    
    if ($deleted -gt 0) {
        Show-Toast -Message "Deleted $deleted rule(s)." -Type 'Success'
    }
    if ($errors.Count -gt 0) {
        Show-Toast -Message "$($errors.Count) rule(s) failed to delete." -Type 'Warning'
    }
}

function Invoke-ApproveTrustedVendors {
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Approve-TrustedVendorRules' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Approve-TrustedVendorRules function not available. Please update GA-AppLocker.Rules module.' -Type 'Error'
        return
    }

    # Confirm action
    $confirm = [System.Windows.MessageBox]::Show(
        "This will approve all pending rules from trusted vendors (Microsoft, Adobe, Oracle, Google, etc.).`n`nDo you want to continue?",
        'Approve Trusted Vendor Rules',
        'YesNo',
        'Question'
    )

    if ($confirm -ne 'Yes') { return }

    Show-LoadingOverlay -Message 'Approving trusted vendor rules...' -SubMessage 'This may take a moment'

    try {
        $result = Approve-TrustedVendorRules
        
        Hide-LoadingOverlay
        
        if ($result.Success) {
            $message = "Approved $($result.TotalUpdated) rules from trusted vendors."
            Show-Toast -Message $message -Type 'Success'
            Write-Log -Message $message
            
            # Refresh dashboard stats
            Update-DashboardStats -Window $Window
        }
        else {
            Show-Toast -Message "Failed to approve rules: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
        Write-Log -Level Error -Message "Approve trusted vendors failed: $($_.Exception.Message)"
    }
}

function Invoke-RemoveDuplicateRules {
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Remove-DuplicateRules' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Remove-DuplicateRules function not available. Please update GA-AppLocker.Rules module.' -Type 'Error'
        return
    }

    # First, do a preview
    Show-LoadingOverlay -Message 'Analyzing duplicate rules...' -SubMessage 'Scanning rule database'

    try {
        $preview = Remove-DuplicateRules -RuleType All -WhatIf
        
        Hide-LoadingOverlay

        if ($preview.DuplicateCount -eq 0) {
            Show-Toast -Message 'No duplicate rules found.' -Type 'Info'
            return
        }

        # Show confirmation with counts
        $message = "Found $($preview.DuplicateCount) duplicate rules:`n`n"
        $message += "- Hash rules: $($preview.HashDuplicates)`n"
        $message += "- Publisher rules: $($preview.PublisherDuplicates)`n`n"
        $message += "Do you want to remove these duplicates?`n(Oldest rule of each duplicate set will be kept)"

        $confirm = [System.Windows.MessageBox]::Show(
            $message,
            'Remove Duplicate Rules',
            'YesNo',
            'Question'
        )

        if ($confirm -ne 'Yes') { return }

        Show-LoadingOverlay -Message 'Removing duplicate rules...' -SubMessage 'Please wait'

        $result = Remove-DuplicateRules -RuleType All -Strategy KeepOldest
        
        Hide-LoadingOverlay

        if ($result.Success) {
            $msg = "Removed $($result.RemovedCount) duplicate rules."
            Show-Toast -Message $msg -Type 'Success'
            Write-Log -Message $msg
            
            # Refresh dashboard stats
            Update-DashboardStats -Window $Window
        }
        else {
            Show-Toast -Message "Failed to remove duplicates: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
        Write-Log -Level Error -Message "Remove duplicates failed: $($_.Exception.Message)"
    }
}

function Invoke-ExportRulesToXml {
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Export-RulesToXml' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Export-RulesToXml function not available.' -Type 'Error'
        return
    }

    $approvedOnly = $Window.FindName('ChkExportApprovedOnly').IsChecked

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export AppLocker Rules'
    $dialog.Filter = 'XML Files (*.xml)|*.xml'
    $dialog.FileName = "AppLockerRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            # IncludeAllStatuses is the inverse of "approved only"
            # If checkbox is checked (approved only), don't include all statuses
            # If checkbox is unchecked, include all statuses
            if ($approvedOnly) {
                $result = Export-RulesToXml -OutputPath $dialog.FileName
            }
            else {
                $result = Export-RulesToXml -OutputPath $dialog.FileName -IncludeAllStatuses
            }
            
            if ($result.Success) {
                Show-Toast -Message "Exported $($result.Data.RuleCount) rule(s) to XML." -Type 'Success'
            }
            else {
                Show-Toast -Message "Export failed: $($result.Error)" -Type 'Error'
            }
        }
        catch {
            Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

function Invoke-ExportRulesToCsv {
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Get-AllRules' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Get-AllRules function not available.' -Type 'Error'
        return
    }

    $approvedOnly = $Window.FindName('ChkExportApprovedOnly').IsChecked

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Rules to CSV'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv'
    $dialog.FileName = "AppLockerRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $result = Get-AllRules
            
            if ($result.Success) {
                $rules = $result.Data
                if ($approvedOnly) {
                    $rules = $rules | Where-Object { $_.Status -eq 'Approved' }
                }
                
                $rules | Select-Object Id, Name, RuleType, CollectionType, Action, Status, CreatedDate | 
                Export-Csv -Path $dialog.FileName -NoTypeInformation
                
                Show-Toast -Message "Exported $($rules.Count) rule(s) to CSV." -Type 'Success'
            }
            else {
                Show-Toast -Message "Export failed: $($result.Error)" -Type 'Error'
            }
        }
        catch {
            Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

function Show-RuleDetails {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItem = $dataGrid.SelectedItem

    if (-not $selectedItem) {
        Show-Toast -Message 'Please select a rule to view details.' -Type 'Warning'
        return
    }

    $details = @"
Rule Details
============

ID: $($selectedItem.RuleId)
Name: $($selectedItem.Name)
Type: $($selectedItem.RuleType)
Action: $($selectedItem.Action)
Status: $($selectedItem.Status)
Collection: $($selectedItem.Collection)
Rule Collection: $($selectedItem.RuleCollection)

Description:
$($selectedItem.Description)

Created: $($selectedItem.CreatedAt)
Modified: $($selectedItem.ModifiedAt)

Condition Data:
$($selectedItem | Select-Object -Property Publisher*, Hash*, Path* | Format-List | Out-String)
"@

    [System.Windows.MessageBox]::Show($details.Trim(), 'Rule Details', 'OK', 'Information')
}

#endregion
