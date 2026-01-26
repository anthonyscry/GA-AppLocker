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
        'BtnGenerateFromArtifacts', 'BtnCreateManualRule', 'BtnExportRulesXml', 'BtnExportRulesCsv',
        'BtnImportRulesXml', 'BtnRefreshRules', 'BtnApproveRule', 'BtnRejectRule', 'BtnReviewRule',
        'BtnDeleteRule', 'BtnViewRuleDetails', 'BtnViewRuleHistory', 'BtnAddRuleToPolicy',
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

    # NOTE: Async disabled due to runspace cmdlet issues - using sync load
    # TODO: Fix async runspace to include core cmdlets properly
    if ($false -and $Async -and (Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction SilentlyContinue)) {
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
    $btnAll = $Window.FindName('BtnFilterAllRules')
    $btnPending = $Window.FindName('BtnFilterRulesPending')
    $btnApproved = $Window.FindName('BtnFilterRulesApproved')
    $btnRejected = $Window.FindName('BtnFilterRulesRejected')

    if ($btnAll) { $btnAll.Content = "All ($total)" }
    if ($btnPending) { $btnPending.Content = "Pending ($pending)" }
    if ($btnApproved) { $btnApproved.Content = "Approved ($approved)" }
    if ($btnRejected) { $btnRejected.Content = "Rejected ($rejected)" }
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
    
    # Suppress selection events during bulk operation
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
        # Re-enable selection events
        $script:SuppressRulesSelectionChanged = $false
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

    # Get publisher granularity level
    $pubLevelCombo = $Window.FindName('CboPublisherLevel')
    $publisherLevel = if ($pubLevelCombo -and $pubLevelCombo.SelectedItem) {
        $pubLevelCombo.SelectedItem.Tag
    }
    else {
        'PublisherProduct'  # Default
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
                    # Respect PublisherLevel when checking existing rules
                    $pubKey = if ($publisherLevel -eq 'PublisherOnly') {
                        $_.Publisher.ToLower()
                    } else {
                        "$($_.Publisher)|$($_.ProductName)".ToLower()
                    }
                    # Use correct index based on PublisherLevel
                    $indexToCheck = if ($publisherLevel -eq 'PublisherOnly') {
                        $ruleIndex.PublishersOnly
                    } else {
                        $ruleIndex.Publishers
                    }
                    if ($indexToCheck -and $indexToCheck.Contains($pubKey)) {
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

    # Deduplicate artifacts by hash (same file in multiple locations = one rule needed)
    $beforeDedupeCount = $artifactsToProcess.Count
    $seenHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenPublishers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $dedupedArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    foreach ($artifact in $artifactsToProcess) {
        $dominated = $false
        
        # For Publisher mode or Smart mode with signed files, dedupe by publisher+product
        if ($mode -in @('Publisher', 'Smart') -and $artifact.IsSigned -and $artifact.Publisher) {
            # Respect PublisherLevel when deduplicating
            $pubKey = if ($publisherLevel -eq 'PublisherOnly') {
                $artifact.Publisher.ToLower()
            } else {
                "$($artifact.Publisher)|$($artifact.ProductName)".ToLower()
            }
            if ($seenPublishers.Contains($pubKey)) {
                $dominated = $true
            }
            else {
                [void]$seenPublishers.Add($pubKey)
            }
        }
        
        # For Hash mode or unsigned files in Smart mode, dedupe by hash
        if (-not $dominated -and $artifact.SHA256Hash) {
            if ($mode -eq 'Hash' -or ($mode -eq 'Smart' -and -not $artifact.IsSigned)) {
                if ($seenHashes.Contains($artifact.SHA256Hash)) {
                    $dominated = $true
                }
                else {
                    [void]$seenHashes.Add($artifact.SHA256Hash)
                }
            }
        }
        
        if (-not $dominated) {
            $dedupedArtifacts.Add($artifact)
        }
    }
    
    $artifactsToProcess = $dedupedArtifacts.ToArray()
    $dedupedCount = $beforeDedupeCount - $artifactsToProcess.Count
    if ($dedupedCount -gt 0) {
        Write-Log -Message "Deduplicated $dedupedCount artifacts (same hash/publisher) - processing $($artifactsToProcess.Count) unique"
    }

    if ($artifactsToProcess.Count -eq 0) {
        Hide-LoadingOverlay
        if ($btnGenerate) { $btnGenerate.IsEnabled = $true }
        Show-Toast -Message "All $originalCount artifacts already have rules. Nothing to generate." -Type 'Info'
        return
    }

    # Show loading overlay with deduplication info
    $skippedCount = $originalCount - $beforeDedupeCount  # Already have rules
    $filterParts = @()
    if ($skippedCount -gt 0) { $filterParts += "$skippedCount already have rules" }
    if ($dedupedCount -gt 0) { $filterParts += "$dedupedCount duplicates" }
    $filterMsg = if ($filterParts.Count -gt 0) { " (skipped: $($filterParts -join ', '))" } else { "" }
    
    Show-LoadingOverlay -Message "Generating Rules..." -SubMessage "Processing $($artifactsToProcess.Count) unique artifacts...$filterMsg"
    
    Show-Toast -Message "Generating rules from $($artifactsToProcess.Count) unique artifacts (of $originalCount total)$filterMsg..." -Type 'Info'

    # Create sync hashtable for async communication
    $script:RuleGenSyncHash = [hashtable]::Synchronized(@{
        Window = $Window
        Artifacts = @($artifactsToProcess)
        Mode = $mode
        Action = $action
        TargetGroupSid = $targetGroupSid
        PublisherLevel = $publisherLevel
        Generated = 0
        Failed = 0
        Progress = 0
        ProgressMessage = ''
        Summary = $null
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

            # Use batch generation for 10x+ performance improvement
            $batchParams = @{
                Artifacts = $SyncHash.Artifacts
                Mode = $SyncHash.Mode
                Action = $SyncHash.Action
                UserOrGroupSid = $SyncHash.TargetGroupSid
                Status = 'Pending'
                DedupeMode = 'Smart'
            }
            
            # Add publisher level if specified
            if ($SyncHash.PublisherLevel) {
                $batchParams['PublisherLevel'] = $SyncHash.PublisherLevel
            }
            
            # Progress callback to update sync hash
            $batchParams['OnProgress'] = {
                param($pct, $msg)
                $SyncHash.Progress = $pct
                $SyncHash.ProgressMessage = $msg
            }.GetNewClosure()
            
            $result = Invoke-BatchRuleGeneration @batchParams
            
            $SyncHash.Generated = $result.RulesCreated
            $SyncHash.Failed = $result.Errors.Count
            $SyncHash.Summary = $result.Summary
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
        
        # Update progress display from batch operation
        if ($syncHash.Progress -gt 0 -and -not $syncHash.IsComplete) {
            $msg = if ($syncHash.ProgressMessage) { $syncHash.ProgressMessage } else { "$($syncHash.Progress)% complete" }
            Update-LoadingText -Message "Generating Rules..." -SubMessage $msg
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
                # Show summary from batch operation
                $summary = $syncHash.Summary
                if ($summary) {
                    $msg = "Created $($syncHash.Generated) rules"
                    $details = @()
                    if ($summary.AlreadyExisted -gt 0) { $details += "$($summary.AlreadyExisted) existed" }
                    if ($summary.Deduplicated -gt 0) { $details += "$($summary.Deduplicated) deduped" }
                    if ($details.Count -gt 0) { $msg += " ($($details -join ', '))" }
                    Show-Toast -Message $msg -Type 'Success'
                } else {
                    Show-Toast -Message "Generated $($syncHash.Generated) rule(s) from $($syncHash.Artifacts.Count) artifacts." -Type 'Success'
                }
            }
            elseif ($syncHash.Summary -and $syncHash.Summary.AlreadyExisted -gt 0) {
                Show-Toast -Message "All $($syncHash.Summary.AlreadyExisted) artifacts already have rules." -Type 'Info'
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
        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Level Warning -Message "Errors updating rules: $($errors -join '; ')" -NoConsole
        }
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
        if (Get-Command -Name 'Remove-RulesBulk' -ErrorAction SilentlyContinue) {
            $deleteResult = Remove-RulesBulk -RuleIds $idsToDelete
            
            if ($deleteResult.Success) {
                $deleted = $deleteResult.RemovedCount
                Show-Toast -Message "Deleted $deleted rule(s)." -Type 'Success'
                # Caches already invalidated by Remove-RulesBulk
            }
            else {
                Show-Toast -Message "Delete failed: $($deleteResult.Error)" -Type 'Error'
            }
        }
        elseif (Get-Command -Name 'Remove-RuleFromDatabase' -ErrorAction SilentlyContinue) {
            # Fallback to single-rule deletion
            $deleteResult = Remove-RuleFromDatabase -Id $idsToDelete
            
            if ($deleteResult.Success) {
                $deleted = $deleteResult.RemovedCount
                Show-Toast -Message "Deleted $deleted rule(s)." -Type 'Success'
                
                # Invalidate caches
                if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
                    Clear-AppLockerCache -Pattern 'GlobalSearch_*' | Out-Null
                    Clear-AppLockerCache -Pattern 'RuleCounts*' | Out-Null
                    Clear-AppLockerCache -Pattern 'RuleQuery*' | Out-Null
                }
            }
            else {
                Show-Toast -Message "Delete failed: $($deleteResult.Error)" -Type 'Error'
            }
        }
        else {
            Show-Toast -Message "Remove-RulesBulk not available. Please update GA-AppLocker.Storage module." -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
    finally {
        Hide-LoadingOverlay
    }
    
    # Refresh the grid
    Update-RulesDataGrid -Window $Window
    Update-RulesSelectionCount -Window $Window
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

    # Use async to prevent UI freeze
    Invoke-AsyncOperation -ScriptBlock {
        Approve-TrustedVendorRules
    } -LoadingMessage 'Approving trusted vendor rules...' -OnComplete {
        param($Result)
        if ($Result.Success) {
            $message = "Approved $($Result.TotalUpdated) rules from trusted vendors."
            Show-Toast -Message $message -Type 'Success'
            Write-Log -Message $message
            Update-RulesDataGrid -Window $Window -Async
        }
        else {
            Show-Toast -Message "Failed to approve rules: $($Result.Error)" -Type 'Error'
        }
    }.GetNewClosure() -OnError {
        param($ErrorMessage)
        Show-Toast -Message "Error: $ErrorMessage" -Type 'Error'
        Write-Log -Level Error -Message "Approve trusted vendors failed: $ErrorMessage"
    }.GetNewClosure()
}

function Invoke-RemoveDuplicateRules {
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
            Update-RulesDataGrid -Window $Window
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

function Invoke-ImportRulesFromXmlFile {
    <#
    .SYNOPSIS
        Opens file dialog and imports rules from AppLocker XML.
    #>
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Import-RulesFromXml' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Import-RulesFromXml function not available.' -Type 'Error'
        return
    }

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

function Invoke-RulesContextAction {
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

function global:Invoke-ViewRuleHistory {
    <#
    .SYNOPSIS
        Shows the version history for the selected rule.
    #>
    param([System.Windows.Window]$Window)
    
    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid -or -not $dataGrid.SelectedItem) {
        Show-Toast -Message 'Please select a rule to view history.' -Type 'Warning'
        return
    }
    
    $selectedItem = $dataGrid.SelectedItem
    $ruleId = $selectedItem.RuleId
    $ruleName = $selectedItem.Name
    
    if (-not (Get-Command -Name 'Get-RuleHistory' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Rule history function not available.' -Type 'Error'
        return
    }
    
    try {
        Show-LoadingOverlay -Message "Loading history for $ruleName..."
        
        $result = Get-RuleHistory -RuleId $ruleId -IncludeContent
        
        Hide-LoadingOverlay
        
        if (-not $result.Success) {
            Show-Toast -Message "Failed to load history: $($result.Error)" -Type 'Error'
            return
        }
        
        if ($result.Data.Count -eq 0) {
            Show-Toast -Message "No version history found for this rule." -Type 'Info'
            return
        }
        
        # Show history dialog
        Show-RuleHistoryDialog -Window $Window -RuleName $ruleName -RuleId $ruleId -Versions $result.Data
    }
    catch {
        Hide-LoadingOverlay
        Show-Toast -Message "Error loading history: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Show-RuleHistoryDialog {
    <#
    .SYNOPSIS
        Shows a dialog with rule version history.
    #>
    param(
        [System.Windows.Window]$Window,
        [string]$RuleName,
        [string]$RuleId,
        [array]$Versions
    )
    
    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Rule History: $([System.Security.SecurityElement]::Escape($RuleName))"
        Width="700" Height="500"
        WindowStartupLocation="CenterOwner"
        Background="#1E1E1E"
        ResizeMode="CanResize">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#3C3C3C"/>
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="ListBoxItem">
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="Padding" Value="8,6"/>
        </Style>
    </Window.Resources>
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="VERSION HISTORY" FontSize="12" FontWeight="SemiBold" 
                   Foreground="#888888" Margin="0,0,0,10"/>
        
        <Border Grid.Row="1" Background="#2D2D2D" CornerRadius="4" Margin="0,0,0,10">
            <ListBox x:Name="VersionsList" Background="Transparent" BorderThickness="0" 
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled">
            </ListBox>
        </Border>
        
        <Border Grid.Row="2" Background="#252526" CornerRadius="4" Padding="10" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="SELECTED VERSION DETAILS" FontSize="10" FontWeight="SemiBold" 
                           Foreground="#888888" Margin="0,0,0,8"/>
                <TextBlock x:Name="TxtVersionDetails" Text="Select a version to view details"
                           Foreground="#E0E0E0" FontSize="12" TextWrapping="Wrap"/>
            </StackPanel>
        </Border>
        
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnRestoreVersion" Content="Restore This Version" Width="150"/>
            <Button x:Name="BtnCompareVersions" Content="Compare Versions" Width="130"/>
            <Button x:Name="BtnClose" Content="Close" Width="80" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@
    
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dialogXaml))
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $Window
    
    $versionsList = $dialog.FindName('VersionsList')
    $txtDetails = $dialog.FindName('TxtVersionDetails')
    $btnRestore = $dialog.FindName('BtnRestoreVersion')
    $btnCompare = $dialog.FindName('BtnCompareVersions')
    $btnClose = $dialog.FindName('BtnClose')
    
    # Populate versions list
    foreach ($version in $Versions) {
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $modifiedDate = if ($version.ModifiedAt) {
            try { [datetime]::Parse($version.ModifiedAt).ToString('yyyy-MM-dd HH:mm') } catch { $version.ModifiedAt }
        } else { 'Unknown' }
        
        $item.Content = "v$($version.Version) | $($version.ChangeType) | $modifiedDate | $($version.ModifiedBy)"
        $item.Tag = $version
        $versionsList.Items.Add($item)
    }
    
    # Selection changed handler
    $versionsList.Add_SelectionChanged({
        $selectedItem = $versionsList.SelectedItem
        if ($selectedItem -and $selectedItem.Tag) {
            $ver = $selectedItem.Tag
            $details = @(
                "Version: $($ver.Version)",
                "Modified: $(if ($ver.ModifiedAt) { try { [datetime]::Parse($ver.ModifiedAt).ToString('yyyy-MM-dd HH:mm:ss') } catch { $ver.ModifiedAt } } else { 'Unknown' })",
                "Modified By: $($ver.ModifiedBy)",
                "Change Type: $($ver.ChangeType)",
                "Summary: $($ver.ChangeSummary)"
            )
            
            if ($ver.RuleContent) {
                $details += ""
                $details += "--- Rule Details ---"
                $details += "Status: $($ver.RuleContent.Status)"
                $details += "Action: $($ver.RuleContent.Action)"
                if ($ver.RuleContent.PublisherName) {
                    $details += "Publisher: $($ver.RuleContent.PublisherName)"
                }
                if ($ver.RuleContent.ProductName) {
                    $details += "Product: $($ver.RuleContent.ProductName)"
                }
            }
            
            $txtDetails.Text = $details -join "`n"
        }
    }.GetNewClosure())
    
    # Restore button handler
    $script:HistoryRuleId = $RuleId
    $btnRestore.Add_Click({
        $selectedItem = $versionsList.SelectedItem
        if (-not $selectedItem -or -not $selectedItem.Tag) {
            [System.Windows.MessageBox]::Show('Please select a version to restore.', 'No Selection', 'OK', 'Warning')
            return
        }
        
        $ver = $selectedItem.Tag
        $confirm = [System.Windows.MessageBox]::Show(
            "Restore rule to version $($ver.Version)?`n`nThis will revert the rule to its state at that version.",
            'Confirm Restore',
            'YesNo',
            'Question'
        )
        
        if ($confirm -eq 'Yes') {
            $restoreResult = Restore-RuleVersion -RuleId $script:HistoryRuleId -Version $ver.Version
            if ($restoreResult.Success) {
                [System.Windows.MessageBox]::Show('Rule restored successfully.', 'Restored', 'OK', 'Information')
                $dialog.Close()
                # Refresh rules grid
                Update-RulesDataGrid -Window $global:GA_MainWindow -Async
            }
            else {
                [System.Windows.MessageBox]::Show("Restore failed: $($restoreResult.Error)", 'Error', 'OK', 'Error')
            }
        }
    }.GetNewClosure())
    
    # Compare button handler
    $btnCompare.Add_Click({
        if ($versionsList.Items.Count -lt 2) {
            [System.Windows.MessageBox]::Show('Need at least 2 versions to compare.', 'Cannot Compare', 'OK', 'Information')
            return
        }
        
        $selectedItem = $versionsList.SelectedItem
        if (-not $selectedItem -or -not $selectedItem.Tag) {
            [System.Windows.MessageBox]::Show('Select a version to compare with the current rule.', 'No Selection', 'OK', 'Warning')
            return
        }
        
        $ver = $selectedItem.Tag
        $compareResult = Compare-RuleVersions -RuleId $script:HistoryRuleId -Version1 $ver.Version
        
        if ($compareResult.Success) {
            if ($compareResult.Differences.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No differences between version $($ver.Version) and current rule.", 'No Differences', 'OK', 'Information')
            }
            else {
                $diffText = "Differences between v$($ver.Version) and Current:`n`n"
                foreach ($diff in $compareResult.Differences) {
                    $diffText += "$($diff.Property):`n"
                    $diffText += "  v$($ver.Version): $($diff.Version1Value)`n"
                    $diffText += "  Current: $($diff.Version2Value)`n`n"
                }
                [System.Windows.MessageBox]::Show($diffText, 'Version Comparison', 'OK', 'Information')
            }
        }
        else {
            [System.Windows.MessageBox]::Show("Compare failed: $($compareResult.Error)", 'Error', 'OK', 'Error')
        }
    }.GetNewClosure())
    
    # Close button
    $btnClose.Add_Click({
        $dialog.Close()
    }.GetNewClosure())
    
    [void]$dialog.ShowDialog()
}

#endregion
