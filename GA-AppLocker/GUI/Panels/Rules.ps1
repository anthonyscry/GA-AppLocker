# Suppress flag for bulk selection operations
$script:SuppressRulesSelectionChanged = $false

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
                        Update-RulesFilter -Window $global:GA_MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnLaunchRuleWizard', 'BtnCreateManualRule', 'BtnExportRulesXml', 'BtnExportRulesCsv',
        'BtnImportRulesXml', 'BtnRefreshRules', 'BtnApproveRule', 'BtnRejectRule', 'BtnReviewRule',
        'BtnDeleteRule', 'BtnViewRuleDetails', 'BtnViewRuleHistory', 'BtnAddRuleToPolicy',
        'BtnApproveTrustedRules', 'BtnRemoveDuplicateRules', 'BtnAddCommonDenyRules'
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
                Update-RulesDataGrid -Window $global:GA_MainWindow
            })
    }

    # Wire up Select All checkbox
    $selectAllChk = $Window.FindName('ChkSelectAllRules')
    if ($selectAllChk) {
        $selectAllChk.Add_Checked({
                Invoke-SelectAllRules -Window $global:GA_MainWindow -SelectAll $true
            })
        $selectAllChk.Add_Unchecked({
                Invoke-SelectAllRules -Window $global:GA_MainWindow -SelectAll $false
            })
    }

    # Wire up DataGrid selection changed for count update
    $rulesGrid = $Window.FindName('RulesDataGrid')
    if ($rulesGrid) {
        $rulesGrid.Add_SelectionChanged({
                if ($script:SuppressRulesSelectionChanged) { return }
                Update-RulesSelectionCount -Window $global:GA_MainWindow
            })
        
        # Wire up context menu items
        $contextMenu = $rulesGrid.ContextMenu
        if ($contextMenu) {
            foreach ($item in $contextMenu.Items) {
                if ($item -is [System.Windows.Controls.MenuItem] -and $item.Tag) {
                    $item.Add_Click({
                        param($sender, $e)
                        Invoke-RulesContextAction -Action $sender.Tag -Window $global:GA_MainWindow
                    }.GetNewClosure())
                }
            }
        }
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

function global:Update-RulesDataGrid {
    param(
        [System.Windows.Window]$Window,
        [switch]$Async
    )

    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid) { return }

    # Note: Get-AllRules is always available when module is loaded
    # Removed Get-Command check that caused WPF crash in certain dispatcher contexts

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
            # Safely parse CreatedDate (may be DateTime, string, or PSCustomObject from JSON)
            $createdDisplay = ''
            if ($_.CreatedDate) {
                try {
                    $dateValue = $_.CreatedDate
                    # Handle PSCustomObject from JSON serialization (has DateTime property)
                    if ($dateValue -is [PSCustomObject] -and $dateValue.DateTime) {
                        $createdDisplay = ([datetime]$dateValue.DateTime).ToString('MM/dd HH:mm')
                    }
                    elseif ($dateValue -is [datetime]) {
                        $createdDisplay = $dateValue.ToString('MM/dd HH:mm')
                    }
                    elseif ($dateValue -is [string]) {
                        $createdDisplay = ([datetime]$dateValue).ToString('MM/dd HH:mm')
                    }
                } catch { }
            }
            $props['CreatedDisplay'] = $createdDisplay
            [PSCustomObject]$props
        }

        # Force WPF to refresh by clearing first (prevents stale binding)
        $DataGrid.ItemsSource = $null
        $DataGrid.ItemsSource = @($displayData)

        # Update counters from the original result data
        Update-RuleCounters -Window $Window -Rules $Result.Data
        
        # Update row count display (filtered vs total)
        $totalCount = if ($Result.Data) { $Result.Data.Count } else { 0 }
        $filteredCount = @($displayData).Count
        
        $txtTotal = $Window.FindName('TxtRuleTotalDisplayCount')
        $txtFiltered = $Window.FindName('TxtRuleFilteredCount')
        if ($txtTotal) { $txtTotal.Text = "$totalCount" }
        if ($txtFiltered) { $txtFiltered.Text = "$filteredCount" }
    }

    # Synchronous load - fast enough for typical deployments (100s-1000s of rules)
    # For extremely large rule sets (10K+), the JSON index with O(1) lookups keeps this performant
    try {
        # Use high Take value to load all rules (default is 1000)
        $result = Get-AllRules -Take 100000
        & $processRulesData $result $typeFilter $statusFilter $textFilter $dataGrid $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to update rules grid: $($_.Exception.Message)"
        $dataGrid.ItemsSource = $null
    }
}

function global:Update-RuleCounters {
    param(
        [System.Windows.Window]$Window,
        [array]$Rules
    )

    $total = if ($Rules) { $Rules.Count } else { 0 }
    $pending = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Pending' }).Count } else { 0 }
    $approved = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Approved' }).Count } else { 0 }
    $rejected = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Rejected' }).Count } else { 0 }

    # Update counter elements if they exist (graceful fallback if XAML doesn't have them)
    $txtTotal = $Window.FindName('TxtRuleTotalCount')
    $txtPending = $Window.FindName('TxtRulePendingCount')
    $txtApproved = $Window.FindName('TxtRuleApprovedCount')
    $txtRejected = $Window.FindName('TxtRuleRejectedCount')

    if ($txtTotal) { $txtTotal.Text = "$total" }
    if ($txtPending) { $txtPending.Text = "$pending" }
    if ($txtApproved) { $txtApproved.Text = "$approved" }
    if ($txtRejected) { $txtRejected.Text = "$rejected" }

    # Also update filter button content to show counts
    # Note: Button names match XAML: BtnFilterPending, BtnFilterApproved, BtnFilterRejected
    $btnAll = $Window.FindName('BtnFilterAllRules')
    $btnPending = $Window.FindName('BtnFilterPending')
    $btnApproved = $Window.FindName('BtnFilterApproved')
    $btnRejected = $Window.FindName('BtnFilterRejected')

    if ($btnAll) { $btnAll.Content = "All ($total)" }
    if ($btnPending) { $btnPending.Content = "Pending ($pending)" }
    if ($btnApproved) { $btnApproved.Content = "Approved ($approved)" }
    if ($btnRejected) { $btnRejected.Content = "Rejected ($rejected)" }
}

function global:Update-RulesSelectionCount {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $countText = $Window.FindName('TxtSelectedRuleCount')
    $selectAllChk = $Window.FindName('ChkSelectAllRules')
    
    if (-not $dataGrid -or -not $countText) { return }
    
    $totalCount = if ($dataGrid.ItemsSource) { @($dataGrid.ItemsSource).Count } else { 0 }
    
    # Respect virtual "all selected" flag for large datasets
    $selectedCount = if ($script:AllRulesSelected) { 
        $totalCount 
    } else { 
        $dataGrid.SelectedItems.Count 
    }
    
    $countText.Text = "$selectedCount"
    
    # Update Select All checkbox state (without triggering events)
    if ($selectAllChk) {
        $selectAllChk.IsChecked = ($selectedCount -gt 0 -and $selectedCount -eq $totalCount)
    }
}

function global:Invoke-SelectAllRules {
    param(
        [System.Windows.Window]$Window,
        [bool]$SelectAll = $true
    )

    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid) { return }
    
    $itemCount = $dataGrid.Items.Count
    if ($itemCount -eq 0) { return }
    
    # For large datasets, use virtual selection (track state without actually selecting in DataGrid)
    if ($itemCount -gt 500) {
        # Set virtual selection flag
        $script:AllRulesSelected = $SelectAll
        
        # Update the count display directly without actual DataGrid selection
        $countLabel = $Window.FindName('SelectedRulesCount')
        if ($countLabel) {
            $countLabel.Text = if ($SelectAll) { "$itemCount selected" } else { "0 selected" }
        }
        
        # Visual feedback - highlight the checkbox but skip slow DataGrid.SelectAll()
        Write-Log -Level Info -Message "Virtual select all: $SelectAll for $itemCount items"
        Update-RulesSelectionCount -Window $Window
        return
    }
    
    # For smaller datasets, use normal selection
    $script:AllRulesSelected = $false
    $script:SuppressRulesSelectionChanged = $true
    
    try {
        if ($SelectAll) {
            $dataGrid.SelectAll()
        }
        else {
            $dataGrid.UnselectAll()
        }
    }
    finally {
        $script:SuppressRulesSelectionChanged = $false
    }
    
    Update-RulesSelectionCount -Window $Window
}

# Helper to get selected rules (respects virtual selection)
function global:Get-SelectedRules {
    param([System.Windows.Window]$Window)
    
    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid) { return @() }
    
    # If virtual "all selected" is active, return all items
    if ($script:AllRulesSelected) {
        return @($dataGrid.ItemsSource)
    }
    
    # Otherwise return actual selection
    return @($dataGrid.SelectedItems)
}

# Helper to reset selection state after grid-modifying operations
function global:Reset-RulesSelectionState {
    param([System.Windows.Window]$Window)
    
    # Reset virtual selection flag
    $script:AllRulesSelected = $false
    
    # Uncheck the Select All checkbox
    $selectAllChk = $Window.FindName('ChkSelectAllRules')
    if ($selectAllChk) {
        $selectAllChk.IsChecked = $false
    }
    
    # Clear DataGrid selection
    $dataGrid = $Window.FindName('RulesDataGrid')
    if ($dataGrid) {
        $dataGrid.UnselectAll()
    }
    
    # Update selection count display
    Update-RulesSelectionCount -Window $Window
}

function global:Invoke-AddSelectedRulesToPolicy {
    param([System.Windows.Window]$Window)

    $selectedItems = Get-SelectedRules -Window $Window

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules to add to a policy.' -Type 'Warning'
        return
    }

    # Get available policies (use try-catch - Get-Command fails in WPF context)
    $policiesResult = $null
    try { $policiesResult = Get-AllPolicies } catch {
        Show-Toast -Message 'Policy functions not available.' -Type 'Error'
        return
    }
    if (-not $policiesResult.Success -or $policiesResult.Data.Count -eq 0) {
        Show-Toast -Message 'No policies available. Create a policy first.' -Type 'Warning'
        return
    }

    # Show dialog and get selected policy ID (dialog is in RulesDialogs.ps1)
    $policyId = Show-AddRulesToPolicyDialog -Window $Window -SelectedRules $selectedItems -Policies $policiesResult.Data
    
    if (-not $policyId) { return }  # User cancelled
    
    # Collect all rule IDs and call Add-RuleToPolicy
    $ruleIds = @($selectedItems | ForEach-Object { $_.Id } | Where-Object { $_ })
    
    if ($ruleIds.Count -eq 0) {
        Show-Toast -Message 'No valid rule IDs found.' -Type 'Warning'
        return
    }
    
    try {
        Write-Log -Level Info -Message "Adding $($ruleIds.Count) rules to policy $policyId"
        $result = Add-RuleToPolicy -PolicyId $policyId -RuleId $ruleIds
        
        if ($result.Success) {
            $msg = if ($result.Message) { $result.Message } else { "Added $($ruleIds.Count) rule(s) to policy" }
            Show-Toast -Message $msg -Type 'Success'
            # Reset virtual selection after successful operation
            $script:AllRulesSelected = $false
        }
        else {
            $errMsg = if ($result.Error) { $result.Error } else { "Unknown error" }
            Show-Toast -Message "Failed to add rules: $errMsg" -Type 'Error'
            Write-Log -Level Error -Message "Add to policy failed: $errMsg"
        }
    }
    catch {
        Show-Toast -Message "Error adding rules: $($_.Exception.Message)" -Type 'Error'
        Write-Log -Level Error -Message "Add to policy exception: $($_.Exception.Message)"
    }
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

# Legacy function - redirects to the Rule Generation Wizard
# The wizard provides a better UX with preview, progress, and all options in one place
function Invoke-GenerateRulesFromArtifacts {
    param([System.Windows.Window]$Window)

    # Redirect to the wizard - it handles everything including validation
    Invoke-LaunchRuleWizard -Window $Window
}

function global:Invoke-CreateManualRule {
    param([System.Windows.Window]$Window)

    $typeCombo = $Window.FindName('CboManualRuleType')
    $value = $Window.FindName('TxtManualRuleValue').Text
    $desc = $Window.FindName('TxtManualRuleDesc').Text
    $action = if ($Window.FindName('RbManualRuleAllow').IsChecked) { 'Allow' } else { 'Deny' }

    # Get target group SID (resolve AD group names if needed)
    $targetGroupCombo = $Window.FindName('CboManualRuleTargetGroup')
    $targetGroupSid = if ($targetGroupCombo -and $targetGroupCombo.SelectedItem) {
        $rawTag = $targetGroupCombo.SelectedItem.Tag
        if ($rawTag -and $rawTag.ToString().StartsWith('RESOLVE:')) {
            try { Resolve-GroupSid -GroupName $rawTag } catch { $rawTag }
        } else {
            $rawTag
        }
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
            # Refresh dashboard stats and sidebar counts
            Update-DashboardStats -Window $Window
            Update-WorkflowBreadcrumb -Window $Window
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

function global:Set-SelectedRuleStatus {
    param(
        [System.Windows.Window]$Window,
        [string]$Status
    )

    $selectedItems = Get-SelectedRules -Window $Window

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules.' -Type 'Warning'
        return
    }
    
    # Reset virtual selection after operation
    $script:AllRulesSelected = $false
    
    $count = $selectedItems.Count
    
    # For large selections, use batch processing with loading overlay
    if ($count -gt 50) {
        Show-LoadingOverlay -Message "Updating $count rules to '$Status'..." -SubMessage 'Please wait'
        # Pump the message queue so overlay actually renders before we start
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [Action]{}
        )
    }

    try {
        # Get rule storage path (construct from exported function)
        $dataPath = Get-AppLockerDataPath
        $rulePath = Join-Path $dataPath 'Rules'
        $updated = 0
        $errors = @()
        $updatedIds = [System.Collections.Generic.List[string]]::new()
        $processedCount = 0
        
        foreach ($item in $selectedItems) {
            $processedCount++
            
            # Update loading overlay progress and pump UI events for large batches
            if ($count -gt 50 -and $processedCount % 100 -eq 0) {
                $pct = [math]::Round(($processedCount / $count) * 100)
                Show-LoadingOverlay -Message "Updating $count rules to '$Status'..." -SubMessage "$processedCount of $count ($pct%)"
                # Pump the message queue to keep UI responsive
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [Action]{}
                )
            }
            
            try {
                $ruleFile = Join-Path $rulePath "$($item.Id).json"
                if (Test-Path $ruleFile) {
                    $rule = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json
                    $rule.Status = $Status
                    $rule.ModifiedDate = Get-Date
                    $rule | ConvertTo-Json -Depth 10 | Set-Content -Path $ruleFile -Encoding UTF8
                    $updatedIds.Add($item.Id)
                    $updated++
                }
            }
            catch { 
                $errors += "Rule $($item.Id): $($_.Exception.Message)"
            }
        }
        
        # Batch update the index once (much faster than individual calls)
        # Use try-catch - Get-Command fails in WPF context
        if ($updatedIds.Count -gt 0) {
            try { Update-RuleStatusInIndex -RuleIds $updatedIds.ToArray() -Status $Status | Out-Null } catch { }
        }
        
        if ($errors.Count -gt 0) {
            Write-Log -Level Warning -Message "Errors updating rules: $($errors.Count) failures"
        }
    }
    finally {
        if ($count -gt 50) {
            Hide-LoadingOverlay
        }
    }

    # Reset selection state and refresh the grid
    Reset-RulesSelectionState -Window $Window
    Update-RulesDataGrid -Window $Window
    
    # Refresh dashboard stats and sidebar counts
    Update-DashboardStats -Window $Window
    Update-WorkflowBreadcrumb -Window $Window
    
    if ($updated -gt 0) {
        Show-Toast -Message "Updated $updated rule(s) to '$Status'." -Type 'Success'
    }
    if ($errors.Count -gt 0) {
        Show-Toast -Message "$($errors.Count) rule(s) failed to update." -Type 'Warning'
    }
}

function global:Invoke-DeleteSelectedRules {
    param([System.Windows.Window]$Window)

    $selectedItems = Get-SelectedRules -Window $Window

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules to delete.' -Type 'Warning'
        return
    }
    
    $count = $selectedItems.Count
    
    # Use MessageBox for confirmation
    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete $count rule(s)?`n`nThis action cannot be undone.",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne 'Yes') { return }

    Show-LoadingOverlay -Message "Deleting $count rules..." -SubMessage 'Please wait'
    
    try {
        # Collect IDs to delete
        $idsToDelete = @($selectedItems | ForEach-Object { $_.Id })
        
        # Use bulk delete for efficiency (uses transaction)
        # Note: Using try-catch instead of Get-Command which can fail in WPF context
        $deleteResult = $null
        try {
            $deleteResult = Remove-RulesBulk -RuleIds $idsToDelete
        }
        catch {
            # Remove-RulesBulk not available, try fallback
            $deleteResult = $null
        }
        
        if ($deleteResult) {
            if ($deleteResult.Success) {
                $deleted = $deleteResult.RemovedCount
                Show-Toast -Message "Deleted $deleted rule(s)." -Type 'Success'
            }
            else {
                Show-Toast -Message "Delete failed: $($deleteResult.Error)" -Type 'Error'
            }
        }
        else {
            # Fallback to single-rule deletion
            try {
                $deleteResult = Remove-RuleFromDatabase -Id $idsToDelete
                if ($deleteResult.Success) {
                    $deleted = $deleteResult.RemovedCount
                    Show-Toast -Message "Deleted $deleted rule(s)." -Type 'Success'
                    
                    # Invalidate caches
                    try {
                        Clear-AppLockerCache -Pattern 'GlobalSearch_*' | Out-Null
                        Clear-AppLockerCache -Pattern 'RuleCounts*' | Out-Null
                        Clear-AppLockerCache -Pattern 'RuleQuery*' | Out-Null
                    } catch { }
                }
                else {
                    Show-Toast -Message "Delete failed: $($deleteResult.Error)" -Type 'Error'
                }
            }
            catch {
                Show-Toast -Message "Delete function not available. Please update GA-AppLocker.Storage module." -Type 'Error'
            }
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
    finally {
        Hide-LoadingOverlay
    }
    
    # Reset selection state and refresh the grid
    Reset-RulesSelectionState -Window $Window
    Update-RulesDataGrid -Window $Window
    
    # Refresh dashboard stats and sidebar counts
    Update-DashboardStats -Window $Window
    Update-WorkflowBreadcrumb -Window $Window
}

function global:Invoke-ApproveTrustedVendors {
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

    # Use async to prevent UI freeze
    Invoke-AsyncOperation -ScriptBlock {
        Approve-TrustedVendorRules
    } -LoadingMessage 'Approving trusted vendor rules...' -OnComplete {
        param($Result)
        if ($Result.Success) {
            $message = "Approved $($Result.TotalUpdated) rules from trusted vendors."
            Show-Toast -Message $message -Type 'Success'
            Write-Log -Message $message
            # Reset selection state before refreshing grid
            Reset-RulesSelectionState -Window $Window
            Update-RulesDataGrid -Window $Window -Async
            # Refresh dashboard stats and sidebar counts
            Update-DashboardStats -Window $Window
            try { Update-WorkflowBreadcrumb -Window $Window } catch { }
        }
        else {
            Show-Toast -Message "Failed to approve rules: $($Result.Error)" -Type 'Error'
        }
    }.GetNewClosure()
}

function global:Invoke-RemoveDuplicateRules {
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Remove-DuplicateRules' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Remove-DuplicateRules function not available. Please update GA-AppLocker.Rules module.' -Type 'Error'
        return
    }

    # Synchronous - duplicate detection is now O(n) and takes <1 second
    try {
        $Preview = Remove-DuplicateRules -RuleType All -WhatIf
        
        if ($Preview.DuplicateCount -eq 0) {
            Show-Toast -Message 'No duplicate rules found.' -Type 'Info'
            return
        }

        # Show confirmation with counts
        $message = "Found $($Preview.DuplicateCount) duplicate rules:`n`n"
        $message += "- Hash rules: $($Preview.HashDuplicates)`n"
        $message += "- Publisher rules: $($Preview.PublisherDuplicates)`n`n"
        $message += "Do you want to remove these duplicates?`n(Oldest rule of each duplicate set will be kept)"

        $confirm = [System.Windows.MessageBox]::Show(
            $message,
            'Remove Duplicate Rules',
            'YesNo',
            'Question'
        )

        if ($confirm -ne 'Yes') { return }

        # Actual removal
        $Result = Remove-DuplicateRules -RuleType All -Strategy KeepOldest
        
        if ($Result.Success) {
            $msg = "Removed $($Result.RemovedCount) duplicate rules."
            Show-Toast -Message $msg -Type 'Success'
            Write-Log -Message $msg
            # Reset selection state before refreshing grid
            Reset-RulesSelectionState -Window $Window
            Update-RulesDataGrid -Window $Window
            # Refresh dashboard stats and sidebar counts
            Update-DashboardStats -Window $Window
            Update-WorkflowBreadcrumb -Window $Window
        }
        else {
            Show-Toast -Message "Failed to remove duplicates: $($Result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
        Write-Log -Level Error -Message "Duplicate analysis failed: $($_.Exception.Message)"
    }
}

function global:Invoke-ExportRulesToXml {
    param([System.Windows.Window]$Window)

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

function global:Invoke-ExportRulesToCsv {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $approvedOnly = $Window.FindName('ChkExportApprovedOnly').IsChecked
    
    # Get data from DataGrid (respects current filters)
    $rules = if ($dataGrid -and $dataGrid.ItemsSource) {
        @($dataGrid.ItemsSource)
    } else {
        @()
    }
    
    if ($rules.Count -eq 0) {
        Show-Toast -Message 'No rules to export. Check your filters.' -Type 'Warning'
        return
    }
    
    # Apply approved-only filter if checkbox is checked
    if ($approvedOnly) {
        $rules = $rules | Where-Object { $_.Status -eq 'Approved' }
        if ($rules.Count -eq 0) {
            Show-Toast -Message 'No approved rules in current view.' -Type 'Warning'
            return
        }
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Rules to CSV'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv'
    $dialog.FileName = "AppLockerRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $rules | Select-Object Id, Name, RuleType, CollectionType, Action, Status, CreatedDate, Description | 
            Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8
            
            Show-Toast -Message "Exported $($rules.Count) rule(s) to CSV (current filtered view)." -Type 'Success'
        }
        catch {
            Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

function global:Invoke-ImportRulesFromXmlFile {
    <#
    .SYNOPSIS
        Opens file dialog and imports rules from AppLocker XML.
    #>
    param([System.Windows.Window]$Window)

    # Get import options from UI
    $skipDuplicates = $Window.FindName('ChkImportSkipDuplicates').IsChecked
    $statusCombo = $Window.FindName('CboImportStatus')
    $status = if ($statusCombo -and $statusCombo.SelectedItem) {
        $statusCombo.SelectedItem.Tag
    } else {
        'Pending'
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = 'Import AppLocker XML Policy'
    $dialog.Filter = 'XML Files (*.xml)|*.xml|All Files (*.*)|*.*'
    $dialog.Multiselect = $true

    if ($dialog.ShowDialog() -eq 'OK') {
        Show-LoadingOverlay -Message "Importing rules..." -SubMessage "Processing XML files..."
        
        $totalImported = 0
        $totalSkipped = 0
        $errors = @()

        foreach ($filePath in $dialog.FileNames) {
            try {
                $importParams = @{
                    Path = $filePath
                    Status = $status
                }
                if ($skipDuplicates) {
                    $importParams.SkipDuplicates = $true
                }
                
                $result = Import-RulesFromXml @importParams
                
                if ($result.Success) {
                    $totalImported += $result.Data.Count
                    $totalSkipped += $result.SkippedCount
                }
                else {
                    $errors += "$([System.IO.Path]::GetFileName($filePath)): $($result.Error)"
                }
            }
            catch {
                $errors += "$([System.IO.Path]::GetFileName($filePath)): $($_.Exception.Message)"
            }
        }
        
        Hide-LoadingOverlay
        Update-RulesDataGrid -Window $Window
        
        $message = "Imported $totalImported rule(s)"
        if ($totalSkipped -gt 0) {
            $message += " ($totalSkipped duplicates skipped)"
        }
        
        if ($totalImported -gt 0) {
            Show-Toast -Message $message -Type 'Success'
        }
        elseif ($totalSkipped -gt 0) {
            Show-Toast -Message "No new rules imported ($totalSkipped duplicates skipped)" -Type 'Info'
        }
        else {
            Show-Toast -Message 'No rules imported' -Type 'Warning'
        }
        
        if ($errors.Count -gt 0) {
            Write-Log -Level Warning -Message "Import errors: $($errors -join '; ')"
            Show-Toast -Message "$($errors.Count) file(s) had errors" -Type 'Warning'
        }
    }
}

function global:Show-RuleDetails {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    # Use extracted dialog function from RulesDialogs.ps1
    Show-RuleDetailsDialog -Window $Window -Rule $dataGrid.SelectedItem
}

function global:Invoke-RulesContextAction {
    <#
    .SYNOPSIS
        Handles context menu actions for the Rules DataGrid.
    #>
    param(
        [string]$Action,
        [System.Windows.Window]$Window
    )
    
    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItem = $dataGrid.SelectedItem
    $selectedItems = $dataGrid.SelectedItems
    
    switch ($Action) {
        'ApproveRule' {
            Set-SelectedRuleStatus -Window $Window -Status 'Approved'
        }
        'RejectRule' {
            Set-SelectedRuleStatus -Window $Window -Status 'Rejected'
        }
        'ReviewRule' {
            Set-SelectedRuleStatus -Window $Window -Status 'Review'
        }
        'AddRuleToPolicy' {
            Invoke-AddRulesToPolicy -Window $Window
        }
        'ViewRuleDetails' {
            Show-RuleDetails -Window $Window
        }
        'CopyRuleHash' {
            if ($selectedItem -and $selectedItem.SHA256Hash) {
                [System.Windows.Clipboard]::SetText($selectedItem.SHA256Hash)
                Show-Toast -Message 'Hash copied to clipboard.' -Type 'Info'
            }
            elseif ($selectedItem -and $selectedItem.HashValue) {
                [System.Windows.Clipboard]::SetText($selectedItem.HashValue)
                Show-Toast -Message 'Hash copied to clipboard.' -Type 'Info'
            }
            else {
                Show-Toast -Message 'No hash available for this rule.' -Type 'Warning'
            }
        }
        'CopyRulePublisher' {
            if ($selectedItem -and $selectedItem.PublisherName) {
                $pubInfo = $selectedItem.PublisherName
                if ($selectedItem.ProductName) { $pubInfo += " - $($selectedItem.ProductName)" }
                [System.Windows.Clipboard]::SetText($pubInfo)
                Show-Toast -Message 'Publisher info copied to clipboard.' -Type 'Info'
            }
            elseif ($selectedItem -and $selectedItem.Publisher) {
                [System.Windows.Clipboard]::SetText($selectedItem.Publisher)
                Show-Toast -Message 'Publisher info copied to clipboard.' -Type 'Info'
            }
            else {
                Show-Toast -Message 'No publisher info available for this rule.' -Type 'Warning'
            }
        }
        'CopyRuleDetails' {
            if ($selectedItem) {
                $details = @(
                    "Rule ID: $($selectedItem.RuleId)",
                    "Name: $($selectedItem.Name)",
                    "Type: $($selectedItem.RuleType)",
                    "Action: $($selectedItem.Action)",
                    "Status: $($selectedItem.Status)",
                    "Collection: $($selectedItem.Collection)"
                )
                
                # Add type-specific details
                if ($selectedItem.PublisherName -or $selectedItem.Publisher) {
                    $details += "Publisher: $(if ($selectedItem.PublisherName) { $selectedItem.PublisherName } else { $selectedItem.Publisher })"
                }
                if ($selectedItem.ProductName) {
                    $details += "Product: $($selectedItem.ProductName)"
                }
                if ($selectedItem.SHA256Hash -or $selectedItem.HashValue) {
                    $details += "Hash: $(if ($selectedItem.SHA256Hash) { $selectedItem.SHA256Hash } else { $selectedItem.HashValue })"
                }
                if ($selectedItem.PathCondition -or $selectedItem.Path) {
                    $details += "Path: $(if ($selectedItem.PathCondition) { $selectedItem.PathCondition } else { $selectedItem.Path })"
                }
                if ($selectedItem.Description) {
                    $details += "Description: $($selectedItem.Description)"
                }
                if ($selectedItem.CreatedDisplay -or $selectedItem.CreatedAt) {
                    $details += "Created: $(if ($selectedItem.CreatedDisplay) { $selectedItem.CreatedDisplay } else { $selectedItem.CreatedAt })"
                }
                
                $clipboardText = $details -join "`n"
                [System.Windows.Clipboard]::SetText($clipboardText)
                Show-Toast -Message 'Rule details copied to clipboard.' -Type 'Info'
            }
            else {
                Show-Toast -Message 'No rule selected.' -Type 'Warning'
            }
        }
        'DeleteRule' {
            Invoke-DeleteSelectedRules -Window $Window
        }
        'ViewRuleHistory' {
            Invoke-ViewRuleHistory -Window $Window
        }
        default {
            Write-Log -Level Warning -Message "Unknown context menu action: $Action"
        }
    }
}

function global:Invoke-AddCommonDenyRules {
    <#
    .SYNOPSIS
        Creates deny path rules for common user-writable directories.
    .DESCRIPTION
        Generates deny rules for 7 user-writable paths across Exe, Msi, and Script
        collection types. These paths are commonly exploited for malware execution.
    #>
    param([System.Windows.Window]$Window)

    # Confirm action with the user
    $confirm = [System.Windows.MessageBox]::Show(
        "This will create Deny rules for 7 user-writable paths:`n`n" +
        "  - %OSDRIVE%\Users\*\AppData\Local\Temp\*`n" +
        "  - %OSDRIVE%\Users\*\Downloads\*`n" +
        "  - %OSDRIVE%\Users\*\Desktop\*`n" +
        "  - %OSDRIVE%\Users\*\Documents\*`n" +
        "  - %OSDRIVE%\Users\Public\*`n" +
        "  - %OSDRIVE%\Windows\Temp\*`n" +
        "  - %OSDRIVE%\PerfLogs\*`n`n" +
        "Rules will be created for Exe, Msi, and Script collections.`n" +
        "Status: Approved | Action: Deny | Target: Everyone`n`n" +
        "Do you want to continue?",
        'Create Common Deny Rules',
        'YesNo',
        'Question'
    )

    if ($confirm -ne 'Yes') { return }

    Show-LoadingOverlay -Message 'Creating common deny rules...' -SubMessage 'Please wait'

    try {
        $denyPaths = @(
            @{ Path = '%OSDRIVE%\Users\*\AppData\Local\Temp\*'; Desc = 'User AppData Temp folder' }
            @{ Path = '%OSDRIVE%\Users\*\Downloads\*';          Desc = 'User Downloads folder' }
            @{ Path = '%OSDRIVE%\Users\*\Desktop\*';            Desc = 'User Desktop folder' }
            @{ Path = '%OSDRIVE%\Users\*\Documents\*';          Desc = 'User Documents folder' }
            @{ Path = '%OSDRIVE%\Users\Public\*';               Desc = 'Public user folder' }
            @{ Path = '%OSDRIVE%\Windows\Temp\*';               Desc = 'Windows Temp folder' }
            @{ Path = '%OSDRIVE%\PerfLogs\*';                   Desc = 'PerfLogs folder' }
        )

        $collectionTypes = @('Exe', 'Msi', 'Script')
        $created = 0
        $errors = @()

        foreach ($entry in $denyPaths) {
            foreach ($collection in $collectionTypes) {
                try {
                    $ruleName = "Deny: $($entry.Desc) ($collection)"
                    $ruleDesc = "Deny execution from user-writable path: $($entry.Path) [$collection]"

                    $result = New-PathRule `
                        -Path $entry.Path `
                        -Action 'Deny' `
                        -CollectionType $collection `
                        -Name $ruleName `
                        -Description $ruleDesc `
                        -UserOrGroupSid 'S-1-1-0' `
                        -Status 'Approved' `
                        -Save

                    if ($result.Success) {
                        $created++
                    }
                    else {
                        $errors += "$ruleName`: $($result.Error)"
                    }
                }
                catch {
                    $errors += "$($entry.Path) ($collection): $($_.Exception.Message)"
                }
            }
        }
    }
    finally {
        Hide-LoadingOverlay
    }

    # Refresh rules grid and counters
    Reset-RulesSelectionState -Window $Window
    Update-RulesDataGrid -Window $Window
    Update-DashboardStats -Window $Window
    Update-WorkflowBreadcrumb -Window $Window

    if ($created -gt 0) {
        Show-Toast -Message "Created $created common deny rules ($($denyPaths.Count) paths x $($collectionTypes.Count) collections)." -Type 'Success'
    }
    if ($errors.Count -gt 0) {
        Write-Log -Level Warning -Message "Errors creating deny rules: $($errors -join '; ')"
        Show-Toast -Message "$($errors.Count) rule(s) failed to create." -Type 'Warning'
    }
}

# Note: Invoke-ViewRuleHistory and Show-RuleHistoryDialog are now in GUI/Dialogs/RulesDialogs.ps1

#endregion
