#region Policy Panel Functions
# Policy.ps1 - Policy panel handlers
$script:PolicyCacheResult = $null
$script:PolicyCacheTimestamp = $null
function Initialize-PolicyPanel {
    param($Window)

    # Wire up filter buttons
    $filterButtons = @(
        'BtnFilterAllPolicies', 'BtnFilterDraft', 'BtnFilterActive', 
        'BtnFilterDeployed', 'BtnFilterArchived'
    )

    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Add_Click({
                    param($sender, $e)
                    $tag = $sender.Tag
                    if ($tag -match 'FilterPolicies(.+)') {
                        $filter = $Matches[1]
                        Update-PoliciesFilter -Window $global:GA_MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnCreatePolicy', 'BtnRefreshPolicies', 'BtnActivatePolicy', 
        'BtnArchivePolicy', 'BtnDeletePolicy', 'BtnDeployPolicy',
        'BtnAddRulesToPolicyAction', 'BtnRemoveRulesFromPolicyAction', 'BtnImportRulesToPolicyAction',
        'BtnSavePolicyChanges', 'BtnComparePolicies', 'BtnExportDiffReport'
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

    # Wire up Edit tab GPO dropdown to show/hide custom textbox
    $gpoCombo = $Window.FindName('CboEditTargetGPO')
    if ($gpoCombo) {
        $gpoCombo.Add_SelectionChanged({
                param($sender, $e)
                $selectedItem = $sender.SelectedItem
                $customBox = $global:GA_MainWindow.FindName('TxtEditCustomGPO')
                if ($customBox) {
                    if ($selectedItem -and $selectedItem.Tag -eq 'Custom') {
                        $customBox.Visibility = 'Visible'
                    }
                    else {
                        $customBox.Visibility = 'Collapsed'
                    }
                }
            })
    }

    # Wire up Create tab GPO dropdown to show/hide custom textbox
    $createGpoCombo = $Window.FindName('CboPolicyTargetGPO')
    if ($createGpoCombo) {
        $createGpoCombo.Add_SelectionChanged({
                param($sender, $e)
                $selectedItem = $sender.SelectedItem
                $customBox = $global:GA_MainWindow.FindName('TxtPolicyCustomGPO')
                if ($customBox) {
                    if ($selectedItem -and $selectedItem.Tag -eq 'Custom') {
                        $customBox.Visibility = 'Visible'
                    }
                    else {
                        $customBox.Visibility = 'Collapsed'
                    }
                }
            })
    }

    # Wire up DataGrid selection changed
    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if ($dataGrid) {
        $dataGrid.Add_SelectionChanged({
                param($sender, $e)
                try { Update-SelectedPolicyInfo -Window $global:GA_MainWindow } catch { }
            })
    }

    # Don't load policies at init — they load on first navigation to Policy panel
    # (Set-ActivePanel calls Update-PoliciesDataGrid when PanelPolicy is shown)
    
    # Initialize Compare tab dropdowns
    Initialize-PolicyCompareDropdowns -Window $Window
}

function global:Update-PoliciesDataGrid {
    param(
        $Window,
        [switch]$Async,
        [switch]$Force,
        [switch]$NoOverlay
    )

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if (-not $dataGrid) { return }

    # Capture filter state for use in callback
    $statusFilter = $script:CurrentPoliciesFilter
    $filterBox = $Window.FindName('TxtPolicyFilter')
    $textFilter = if ($filterBox) { $filterBox.Text } else { '' }

    # Define the data processing logic
    $processPoliciesData = {
        param($Result, $StatusFilter, $TextFilter, $DataGrid, $Window)
        
        if (-not $Result.Success) {
            $DataGrid.ItemsSource = $null
            return
        }

        $script:PolicyCacheResult = $Result
        $script:PolicyCacheTimestamp = Get-Date

        $policies = $Result.Data

        # Apply status filter
        if ($StatusFilter -and $StatusFilter -ne 'All') {
            $policies = $policies | Where-Object { $_.Status -eq $StatusFilter }
        }

        # Apply text filter
        if (-not [string]::IsNullOrWhiteSpace($TextFilter)) {
            $filterText = $TextFilter.ToLower()
            $policies = $policies | Where-Object {
                $_.Name.ToLower().Contains($filterText) -or
                ($_.Description -and $_.Description.ToLower().Contains($filterText))
            }
        }

        # Add display properties using List<T> for O(n) performance
        $displayData = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($policies) {
            foreach ($policy in $policies) {
                # Format ModifiedAt for display
                $modifiedDisplay = ''
                if ($policy.ModifiedAt) {
                    try {
                        $dateValue = $policy.ModifiedAt
                        if ($dateValue -is [PSCustomObject] -and $dateValue.DateTime) {
                            $modifiedDisplay = ([datetime]$dateValue.DateTime).ToString('MM/dd HH:mm')
                        }
                        elseif ($dateValue -is [datetime]) {
                            $modifiedDisplay = $dateValue.ToString('MM/dd HH:mm')
                        }
                        elseif ($dateValue -is [string] -and $dateValue.Length -gt 0) {
                            $modifiedDisplay = ([datetime]$dateValue).ToString('MM/dd HH:mm')
                        }
                    } catch { }
                }

                [void]$displayData.Add([PSCustomObject]@{
                    PolicyId        = $policy.PolicyId
                    Name            = $policy.Name
                    Description     = $policy.Description
                    EnforcementMode = $policy.EnforcementMode
                    Phase           = if ($policy.Phase) { $policy.Phase } else { 1 }
                    Status          = $policy.Status
                    RuleIds         = $policy.RuleIds
                    TargetOUs       = $policy.TargetOUs
                    TargetGPO       = $policy.TargetGPO
                    CreatedAt       = $policy.CreatedAt
                    ModifiedAt      = $policy.ModifiedAt
                    ModifiedDisplay = $modifiedDisplay
                    Version         = $policy.Version
                    RuleCount       = if ($policy.RuleIds) { @($policy.RuleIds).Count } else { 0 }
                })
            }
        }

        $DataGrid.ItemsSource = $displayData.ToArray()

        # Update counters using already-fetched data
        Update-PolicyCounters -Window $Window -Policies $Result.Data

        try { Update-SelectedPolicyInfo -Window $Window } catch { }
    }

    # Use async for initial/refresh loads
    if ($Async) {
        if (-not $Force -and $script:PolicyCacheResult -and $script:PolicyCacheResult.Success) {
            & $processPoliciesData $script:PolicyCacheResult $statusFilter $textFilter $dataGrid $Window
            return
        }

        Invoke-AsyncOperation -ScriptBlock { Get-AllPolicies } -LoadingMessage 'Loading policies...' -OnComplete {
            param($Result)
            & $processPoliciesData $Result $statusFilter $textFilter $dataGrid $Window
        }.GetNewClosure() -OnError {
            param($ErrorMessage)
            Write-Log -Level Error -Message "Failed to load policies: $ErrorMessage"
        }.GetNewClosure() -NoLoadingOverlay:$NoOverlay
    }
    else {
        # Synchronous fallback
        try {
            $result = Get-AllPolicies
            & $processPoliciesData $result $statusFilter $textFilter $dataGrid $Window
        }
        catch {
            Write-Log -Level Error -Message "Failed to update policies grid: $($_.Exception.Message)"
        }
    }
}

function global:Update-PolicyCounters {
    param(
        $Window,
        [array]$Policies
    )

    $total = if ($Policies) { @($Policies).Count } else { 0 }
    $draft = if ($Policies) { @($Policies | Where-Object { $_.Status -eq 'Draft' }).Count } else { 0 }
    $active = if ($Policies) { @($Policies | Where-Object { $_.Status -eq 'Active' }).Count } else { 0 }
    $deployed = if ($Policies) { @($Policies | Where-Object { $_.Status -eq 'Deployed' }).Count } else { 0 }

    $ctrl = $Window.FindName('TxtPolicyTotalCount');    if ($ctrl) { $ctrl.Text = "$total" }
    $ctrl = $Window.FindName('TxtPolicyDraftCount');    if ($ctrl) { $ctrl.Text = "$draft" }
    $ctrl = $Window.FindName('TxtPolicyActiveCount');   if ($ctrl) { $ctrl.Text = "$active" }
    $ctrl = $Window.FindName('TxtPolicyDeployedCount'); if ($ctrl) { $ctrl.Text = "$deployed" }
}

function global:Update-PoliciesFilter {
    param(
        $Window,
        [string]$Filter
    )

    $script:CurrentPoliciesFilter = $Filter

    # Grey pill visual toggle for filter buttons
    $activePillBg = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')
    $filterButtons = @(
        'BtnFilterAllPolicies', 'BtnFilterDraft', 'BtnFilterActive',
        'BtnFilterDeployed', 'BtnFilterArchived'
    )
    $colorMap = @{
        'BtnFilterAllPolicies' = [System.Windows.Media.Brushes]::White
        'BtnFilterDraft'       = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF8C00')
        'BtnFilterActive'      = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0078D4')
        'BtnFilterDeployed'    = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#107C10')
        'BtnFilterArchived'    = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E0E0E0')
    }
    $btnNameMap = @{
        'All'      = 'BtnFilterAllPolicies'
        'Draft'    = 'BtnFilterDraft'
        'Active'   = 'BtnFilterActive'
        'Deployed' = 'BtnFilterDeployed'
        'Archived' = 'BtnFilterArchived'
    }

    # Reset all to inactive (transparent bg + original color)
    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
            $btn.Foreground = $colorMap[$btnName]
        }
    }

    # Highlight active filter (grey pill bg + white text)
    $activeBtnName = $btnNameMap[$Filter]
    if ($activeBtnName) {
        $btn = $Window.FindName($activeBtnName)
        if ($btn) {
            $btn.Background = $activePillBg
            $btn.Foreground = [System.Windows.Media.Brushes]::White
        }
    }

    Update-PoliciesDataGrid -Window $Window
}

function global:Update-SelectedPolicyInfo {
    param($Window)

    try {
        $dataGrid = $Window.FindName('PoliciesDataGrid')
        if (-not $dataGrid) { return }

        $selectedItems = @($dataGrid.SelectedItems | Where-Object { $_ -ne $null })
        $selectedCount = $selectedItems.Count
        $selectedCountText = $Window.FindName('TxtPolicySelectedCount')
        if ($selectedCountText) { $selectedCountText.Text = "Selected: $selectedCount" }

        $selectedItem = $dataGrid.SelectedItem

        if ($selectedCount -eq 1 -and $selectedItem) {
            $script:SelectedPolicyId = $selectedItem.PolicyId
            $global:GA_SelectedPolicyId = $selectedItem.PolicyId

            $ruleCount = if ($selectedItem.RuleIds) { $selectedItem.RuleIds.Count } else { 0 }
            $txtRuleCount = $Window.FindName('TxtPolicyRuleCount')
            if ($txtRuleCount) { $txtRuleCount.Text = "$ruleCount rules" }

            $txtName = $Window.FindName('TxtSelectedPolicyName')
            if ($txtName) {
                $txtName.Text = $selectedItem.Name
                $txtName.FontStyle = 'Normal'
                $txtName.Foreground = [System.Windows.Media.Brushes]::White
            }

            $editHint = $Window.FindName('TxtPolicyEditHint')
            if ($editHint) { $editHint.Visibility = 'Collapsed' }

            $txtEditName = $Window.FindName('TxtEditPolicyName')
            if ($txtEditName) { $txtEditName.Text = $selectedItem.Name; $txtEditName.IsEnabled = $true }

            $txtEditDesc = $Window.FindName('TxtEditPolicyDescription')
            if ($txtEditDesc) { $txtEditDesc.Text = if ($selectedItem.Description) { $selectedItem.Description } else { '' }; $txtEditDesc.IsEnabled = $true }

            $cboEnforcement = $Window.FindName('CboEditEnforcement')
            if ($cboEnforcement) {
                $cboEnforcement.IsEnabled = $true
                $enfIndex = switch ($selectedItem.EnforcementMode) {
                    'AuditOnly' { 0 }
                    'Enabled' { 1 }
                    'NotConfigured' { 2 }
                    default { 0 }
                }
                $cboEnforcement.SelectedIndex = $enfIndex
            }

            $cboPhase = $Window.FindName('CboEditPhase')
            if ($cboPhase) {
                $cboPhase.IsEnabled = $true
                $phaseIndex = if ($selectedItem.Phase) { [int]$selectedItem.Phase - 1 } else { 0 }
                if ($phaseIndex -lt 0) { $phaseIndex = 0 }
                if ($phaseIndex -gt 4) { $phaseIndex = 4 }
                $cboPhase.SelectedIndex = $phaseIndex
            }

            $cboGPO = $Window.FindName('CboEditTargetGPO')
            $txtCustomGPO = $Window.FindName('TxtEditCustomGPO')
            if ($cboGPO) {
                $cboGPO.IsEnabled = $true
                $gpoValue = if ($selectedItem.TargetGPO) { $selectedItem.TargetGPO } else { '' }
                $matched = $false
                for ($i = 0; $i -lt $cboGPO.Items.Count; $i++) {
                    $item = $cboGPO.Items[$i]
                    if ($item.Tag -eq $gpoValue) {
                        $cboGPO.SelectedIndex = $i
                        $matched = $true
                        break
                    }
                }
                if (-not $matched -and $gpoValue.Length -gt 0) {
                    for ($i = 0; $i -lt $cboGPO.Items.Count; $i++) {
                        if ($cboGPO.Items[$i].Tag -eq 'Custom') {
                            $cboGPO.SelectedIndex = $i
                            break
                        }
                    }
                    if ($txtCustomGPO) {
                        $txtCustomGPO.Text = $gpoValue
                        $txtCustomGPO.Visibility = 'Visible'
                    }
                }
                elseif ($txtCustomGPO) {
                    $txtCustomGPO.Text = ''
                    $txtCustomGPO.Visibility = 'Collapsed'
                }
            }
            if ($txtCustomGPO) { $txtCustomGPO.IsEnabled = $true }

            $btnSave = $Window.FindName('BtnSavePolicyChanges')
            if ($btnSave) { $btnSave.IsEnabled = $true }
        }
        else {
            $script:SelectedPolicyId = $null
            $global:GA_SelectedPolicyId = $null

            $txtRuleCount = $Window.FindName('TxtPolicyRuleCount')
            if ($txtRuleCount) { $txtRuleCount.Text = '0 rules' }

            $txtName = $Window.FindName('TxtSelectedPolicyName')
            if ($txtName) {
                $txtName.Text = '(Select a policy)'
                $txtName.FontStyle = 'Italic'
                $txtName.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(158, 158, 158))
            }

            $editHint = $Window.FindName('TxtPolicyEditHint')
            if ($editHint) {
                $editHint.Text = if ($selectedCount -gt 1) { 'Multiple policies selected. Edit disabled.' } else { 'Select a policy to edit.' }
                $editHint.Visibility = 'Visible'
            }

            $txtEditName = $Window.FindName('TxtEditPolicyName')
            if ($txtEditName) { $txtEditName.Text = ''; $txtEditName.IsEnabled = $false }
            $txtEditDesc = $Window.FindName('TxtEditPolicyDescription')
            if ($txtEditDesc) { $txtEditDesc.Text = ''; $txtEditDesc.IsEnabled = $false }
            $cboEnforcement = $Window.FindName('CboEditEnforcement')
            if ($cboEnforcement) { $cboEnforcement.IsEnabled = $false }
            $cboPhase = $Window.FindName('CboEditPhase')
            if ($cboPhase) { $cboPhase.IsEnabled = $false }
            $cboGPO = $Window.FindName('CboEditTargetGPO')
            if ($cboGPO) { $cboGPO.IsEnabled = $false; $cboGPO.SelectedIndex = 0 }
            $txtCustomGPO = $Window.FindName('TxtEditCustomGPO')
            if ($txtCustomGPO) { $txtCustomGPO.Text = ''; $txtCustomGPO.Visibility = 'Collapsed'; $txtCustomGPO.IsEnabled = $false }
            $btnSave = $Window.FindName('BtnSavePolicyChanges')
            if ($btnSave) { $btnSave.IsEnabled = $false }
        }
    }
    catch {
        Write-Log -Level Warning -Message "Update-SelectedPolicyInfo failed: $($_.Exception.Message)"
    }
}

function global:Invoke-SavePolicyChanges {
    param($Window)
    
    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy to edit.' -Type 'Warning'
        return
    }
    
    # Get name and description
    $txtEditName = $Window.FindName('TxtEditPolicyName')
    $editName = if ($txtEditName) { $txtEditName.Text.Trim() } else { '' }
    
    if ([string]::IsNullOrWhiteSpace($editName)) {
        Show-Toast -Message 'Policy name cannot be empty.' -Type 'Warning'
        return
    }
    
    $txtEditDesc = $Window.FindName('TxtEditPolicyDescription')
    $editDesc = if ($txtEditDesc) { $txtEditDesc.Text.Trim() } else { '' }
    
    # Get enforcement mode from dropdown
    $cboEnforcement = $Window.FindName('CboEditEnforcement')
    $enforcement = switch ($cboEnforcement.SelectedIndex) {
        0 { 'AuditOnly' }
        1 { 'Enabled' }
        2 { 'NotConfigured' }
        default { 'AuditOnly' }
    }
    
    # Get phase from dropdown
    $cboPhase = $Window.FindName('CboEditPhase')
    $selectedPhaseItem = $cboPhase.SelectedItem
    $phase = if ($selectedPhaseItem -and $selectedPhaseItem.Tag) {
        [int]$selectedPhaseItem.Tag
    } else {
        1
    }
    
    # Get target GPO from dropdown or custom textbox
    $cboGPO = $Window.FindName('CboEditTargetGPO')
    $txtCustomGPO = $Window.FindName('TxtEditCustomGPO')
    $selectedGpoItem = $cboGPO.SelectedItem
    $targetGPO = if ($selectedGpoItem -and $selectedGpoItem.Tag -eq 'Custom') {
        if ($txtCustomGPO) { $txtCustomGPO.Text.Trim() } else { '' }
    }
    elseif ($selectedGpoItem) {
        [string]$selectedGpoItem.Tag
    }
    else {
        ''
    }
    
    try {
        $result = Update-Policy -Id $script:SelectedPolicyId -Name $editName -Description $editDesc -EnforcementMode $enforcement -Phase $phase -TargetGPO $targetGPO
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window -Force
            Select-PolicyInGrid -Window $Window -PolicyId $script:SelectedPolicyId
            Update-SelectedPolicyInfo -Window $Window
            Show-Toast -Message "Policy '$editName' updated successfully." -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to update policy: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Invoke-CreatePolicy {
    param($Window)

    $txtName = $Window.FindName('TxtPolicyName')
    $txtDesc = $Window.FindName('TxtPolicyDescription')
    
    $name = if ($txtName) { $txtName.Text } else { '' }
    $description = if ($txtDesc) { $txtDesc.Text } else { '' }

    if ([string]::IsNullOrWhiteSpace($name)) {
        Show-Toast -Message 'Please enter a policy name.' -Type 'Warning'
        return
    }

    $enforcementCombo = $Window.FindName('CboPolicyEnforcement')
    $enforcement = 'AuditOnly'
    if ($enforcementCombo) {
        $enforcement = switch ($enforcementCombo.SelectedIndex) {
            0 { 'AuditOnly' }
            1 { 'Enabled' }
            2 { 'NotConfigured' }
            default { 'AuditOnly' }
        }
    }

    # Get deployment phase from ComboBox
    $phaseCombo = $Window.FindName('CboPolicyPhase')
    $phase = 1
    if ($phaseCombo) {
        $selectedPhaseItem = $phaseCombo.SelectedItem
        if ($selectedPhaseItem -and $selectedPhaseItem.Tag) {
            $phase = [int]$selectedPhaseItem.Tag
        }
    }

    # Get target GPO from Create tab dropdown
    $cboTargetGPO = $Window.FindName('CboPolicyTargetGPO')
    $txtCustomGPO = $Window.FindName('TxtPolicyCustomGPO')
    $targetGPO = ''
    if ($cboTargetGPO -and $cboTargetGPO.SelectedItem) {
        $selectedGpoItem = $cboTargetGPO.SelectedItem
        if ($selectedGpoItem.Tag -eq 'Custom') {
            $targetGPO = if ($txtCustomGPO) { $txtCustomGPO.Text.Trim() } else { '' }
        }
        else {
            $targetGPO = [string]$selectedGpoItem.Tag
        }
    }

    try {
        $result = New-Policy -Name $name -Description $description -EnforcementMode $enforcement -Phase $phase
        
        if ($result.Success) {
            # Set target GPO on the newly created policy
            if (-not [string]::IsNullOrWhiteSpace($targetGPO) -and $result.Data -and $result.Data.PolicyId) {
                try { $null = Update-Policy -Id $result.Data.PolicyId -TargetGPO $targetGPO } catch { }
            }

            if ($txtName) { $txtName.Text = '' }
            if ($txtDesc) { $txtDesc.Text = '' }
            if ($phaseCombo) { $phaseCombo.SelectedIndex = 0 } # Reset to Phase 1
            if ($cboTargetGPO) { $cboTargetGPO.SelectedIndex = 0 } # Reset to (None)
            
            Update-PoliciesDataGrid -Window $Window -Force
            $script:SelectedPolicyId = $result.Data.PolicyId
            $global:GA_SelectedPolicyId = $result.Data.PolicyId
            Select-PolicyInGrid -Window $Window -PolicyId $result.Data.PolicyId
            Update-SelectedPolicyInfo -Window $Window
            $tab = $Window.FindName('PolicyTabControl')
            if ($tab) { $tab.SelectedIndex = 1 }
            Update-WorkflowBreadcrumb -Window $Window
            Show-Toast -Message "Policy '$name' created successfully (Phase $phase)." -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to create policy: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Set-SelectedPolicyStatus {
    param(
        $Window,
        [string]$Status
    )

    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy.' -Type 'Warning'
        return
    }

    try {
        $result = Set-PolicyStatus -PolicyId $script:SelectedPolicyId -Status $Status
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window -Force
            Show-Toast -Message "Policy status updated to '$Status'." -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Invoke-DeleteSelectedPolicy {
    param($Window)

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    $selected = if ($dataGrid) { @($dataGrid.SelectedItems | Where-Object { $_ -ne $null }) } else { @() }

    if (-not $selected -or $selected.Count -eq 0) {
        Show-Toast -Message 'Please select one or more policies to delete.' -Type 'Warning'
        return
    }

    $confirmMsg = if ($selected.Count -eq 1) {
        'Are you sure you want to delete this policy?'
    } else {
        "Are you sure you want to delete $($selected.Count) policies?"
    }

    $confirm = Show-AppLockerMessageBox $confirmMsg 'Confirm Delete' 'YesNo' 'Warning'
    if ($confirm -ne 'Yes') { return }

    $policySummaries = $selected | ForEach-Object {
        [PSCustomObject]@{ PolicyId = $_.PolicyId; Name = $_.Name }
    }

    Invoke-AsyncOperation -ScriptBlock {
        param($Policies)

        $summary = [PSCustomObject]@{
            Deleted = 0
            Errors  = [System.Collections.Generic.List[string]]::new()
        }

        foreach ($policy in $Policies) {
            try {
                $result = Remove-Policy -PolicyId $policy.PolicyId -Force
                if ($result.Success) {
                    $summary.Deleted++
                }
                else {
                    [void]$summary.Errors.Add("$($policy.Name): $($result.Error)")
                }
            }
            catch {
                [void]$summary.Errors.Add("$($policy.Name): $($_.Exception.Message)")
            }
        }

        return $summary
    } -Arguments @{ Policies = $policySummaries } -LoadingMessage 'Deleting policies...' -OnComplete {
        param($summary)

        $script:SelectedPolicyId = $null
        $global:GA_SelectedPolicyId = $null
        Update-PoliciesDataGrid -Window $Window -Force
        Update-SelectedPolicyInfo -Window $Window

        if ($summary -and $summary.Errors.Count -eq 0) {
            Show-Toast -Message "Deleted $($summary.Deleted) policy(s)." -Type 'Success'
        }
        elseif ($summary) {
            $errorText = ($summary.Errors -join "`n")
            Show-Toast -Message "Deleted $($summary.Deleted) policy(s).`nFailed:`n$errorText" -Type 'Warning'
        }
        else {
            Show-Toast -Message 'Delete operation completed with unknown result.' -Type 'Warning'
        }
    }.GetNewClosure() -OnError {
        param($ErrorMessage)
        Show-Toast -Message "Failed to delete policies: $ErrorMessage" -Type 'Error'
    }.GetNewClosure()
}

function global:Invoke-ExportSelectedPolicy {
    param($Window)

    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy to export.' -Type 'Warning'
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Policy to XML'
    $dialog.Filter = 'XML Files (*.xml)|*.xml'
    $dialog.FileName = "AppLockerPolicy_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"

    if ($dialog.ShowDialog() -eq 'OK') {
        $exportPath = $dialog.FileName

        Invoke-AsyncOperation -ScriptBlock {
            param($PolicyId, $OutputPath)
            Export-PolicyToXml -PolicyId $PolicyId -OutputPath $OutputPath
        } -Arguments @{ PolicyId = $script:SelectedPolicyId; OutputPath = $exportPath } -LoadingMessage 'Exporting policy...' -OnComplete {
            param($exportResult)

            if ($exportResult -and $exportResult.Success) {
                $ruleCount = if ($exportResult.Data -and $exportResult.Data.RuleCount) { $exportResult.Data.RuleCount } else { 0 }
                Show-Toast -Message "Exported policy to:`n$exportPath`nRules: $ruleCount" -Type 'Success'
            }
            elseif ($exportResult) {
                Show-Toast -Message "Failed to export policy: $($exportResult.Error)" -Type 'Error'
            }
            else {
                Show-Toast -Message 'Export operation returned no result.' -Type 'Error'
            }
        }.GetNewClosure() -OnError {
            param($ErrorMessage)
            Show-Toast -Message "Failed to export policy: $ErrorMessage" -Type 'Error'
        }.GetNewClosure()
    }
}

function global:Invoke-DeploySelectedPolicy {
    param($Window)

    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy to deploy.' -Type 'Warning'
        return
    }

    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) {
        Show-Toast -Message "Could not load policy: $($policyResult.Error)" -Type 'Error'
        return
    }

    $policy = $policyResult.Data
    $gpoInfo = if ($policy.TargetGPO) { " to GPO '$($policy.TargetGPO)'" } else { '' }

    Set-ActivePanel -PanelName 'PanelDeploy'
    Show-Toast -Message "Opening Deployment panel for '$($policy.Name)'$gpoInfo" -Type 'Info'
}

function script:Get-PhaseCollectionTypes {
    <#
    .SYNOPSIS
        Returns the allowed collection types for a deployment phase.
    .DESCRIPTION
        Phase controls which AppLocker collection types are included in a policy:
        Phase 1: Exe only
        Phase 2: Exe + Script
        Phase 3: Exe + Script + Msi
        Phase 4: Exe + Script + Msi + Appx
        Phase 5: All (Exe + Script + Msi + Appx + Dll)
    #>
    param([int]$Phase)

    switch ($Phase) {
        1 { @('Exe') }
        2 { @('Exe', 'Script') }
        3 { @('Exe', 'Script', 'Msi') }
        4 { @('Exe', 'Script', 'Msi', 'Appx') }
        5 { @('Exe', 'Script', 'Msi', 'Appx', 'Dll') }
        default { @('Exe', 'Script', 'Msi', 'Appx', 'Dll') }
    }
}

function global:Invoke-AddRulesToPolicy {
    param($Window)

    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy first.' -Type 'Warning'
        return
    }

    # Get all approved rules not in this policy
    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) { return }
    
    $policy = $policyResult.Data
    $currentRuleIds = @($policy.RuleIds)

    # Determine allowed collection types from the policy phase
    $phase = if ($policy.Phase) { [int]$policy.Phase } else { 5 }
    $allowedCollections = Get-PhaseCollectionTypes -Phase $phase

    $rulesResult = Get-AllRules -Take 100000
    if (-not $rulesResult.Success) { return }

    # Filter by approved status, not already in policy, AND matching collection types for this phase
    $availableRules = $rulesResult.Data | Where-Object { 
        $_.Status -eq 'Approved' -and $_.Id -notin $currentRuleIds -and $_.CollectionType -in $allowedCollections
    }

    # Also count how many approved rules were excluded by the phase filter, grouped by type
    $excludedRules = @($rulesResult.Data | Where-Object {
        $_.Status -eq 'Approved' -and $_.Id -notin $currentRuleIds -and $_.CollectionType -notin $allowedCollections
    })
    $excludedByPhase = $excludedRules.Count

    # Build a helper that maps excluded collection types to which phase includes them
    $phaseMap = @{ 'Exe' = 1; 'Script' = 2; 'Msi' = 3; 'Appx' = 4; 'Dll' = 5 }
    $excludedDetail = ''
    if ($excludedByPhase -gt 0) {
        $excludedGroups = $excludedRules | Group-Object CollectionType
        $details = foreach ($g in $excludedGroups) {
            $includedAtPhase = $phaseMap[$g.Name]
            "$($g.Name): $($g.Count) rule(s) (included at Phase $includedAtPhase)"
        }
        $excludedDetail = $details -join "`n"
    }

    if ($availableRules.Count -eq 0) {
        $msg = 'No approved rules available to add.'
        if ($excludedByPhase -gt 0) {
            $msg += "`n$excludedByPhase rule(s) excluded by Phase $phase filter:`n$excludedDetail"
        }
        Show-Toast -Message $msg -Type 'Info'
        return
    }

    $ruleIds = $availableRules | Select-Object -ExpandProperty Id
    $policyName = $policy.Name

    $moduleInfo = Get-Module GA-AppLocker
    if (-not $moduleInfo -or -not $moduleInfo.ModuleBase) {
        Show-Toast -Message 'GA-AppLocker module is not loaded. Please restart the dashboard and try again.' -Type 'Error'
        return
    }

    $modulePath = $moduleInfo.ModuleBase
    $windowRef = $Window
    $policyNameValue = $policyName

    $bgWork = {
        param($ModulePath, $PolicyId, $RuleIds)

        try {
            $modulesDir = Join-Path $ModulePath 'Modules'
            foreach ($mod in @('GA-AppLocker.Core', 'GA-AppLocker.Policy')) {
                $modPath = Join-Path $modulesDir "$mod\$mod.psd1"
                if (-not (Test-Path $modPath)) {
                    throw "Required module missing: $modPath"
                }

                Import-Module $modPath -Force -ErrorAction Stop
            }

            $result = Add-RuleToPolicy -PolicyId $PolicyId -RuleId $RuleIds
            if ($null -eq $result) {
                return @{ Success = $false; Data = $null; Error = 'Add-RuleToPolicy returned no result.' }
            }

            return $result
        }
        catch {
            return @{ Success = $false; Data = $null; Error = $_.Exception.Message }
        }
    }

    $onComplete = {
        param($addResult)

        if ($windowRef) {
            Update-PoliciesDataGrid -Window $windowRef -Force
            Update-SelectedPolicyInfo -Window $windowRef
        }

        if ($addResult -and $addResult.Success) {
            $message = if ($addResult.Message) { $addResult.Message } else { "Added rules to '$policyNameValue'." }
            Show-Toast -Message $message -Type 'Success'
        }
        elseif ($addResult) {
            Show-Toast -Message "Failed to add rules: $($addResult.Error)" -Type 'Error'
        }
        else {
            Show-Toast -Message "Add rules operation returned no result for '$policyNameValue'." -Type 'Error'
        }
    }.GetNewClosure()

    $onTimeout = {
        param($TimeoutMessage)
        Show-Toast -Message "Failed to add rules to '$policyNameValue': $TimeoutMessage" -Type 'Error'
    }.GetNewClosure()

    Invoke-BackgroundWork -ScriptBlock $bgWork `
        -ArgumentList @($modulePath, $script:SelectedPolicyId, @($ruleIds)) `
        -OnComplete $onComplete `
        -OnTimeout $onTimeout `
        -NoLoadingOverlay `
        -TimeoutSeconds 180
}

function global:Invoke-RemoveRulesFromPolicy {
    param($Window)

    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy first.' -Type 'Warning'
        return
    }

    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) { return }
    
    $policy = $policyResult.Data
    $ruleCount = if ($policy.RuleIds) { $policy.RuleIds.Count } else { 0 }

    if ($ruleCount -eq 0) {
        Show-Toast -Message 'This policy has no rules to remove.' -Type 'Info'
        return
    }

    $confirm = Show-AppLockerMessageBox "Remove all $ruleCount rule(s) from this policy?" 'Remove Rules' 'YesNo' 'Warning'

    if ($confirm -eq 'Yes') {
        $ruleIds = @($policy.RuleIds)
        $policyName = $policy.Name

        $moduleInfo = Get-Module GA-AppLocker
        if (-not $moduleInfo -or -not $moduleInfo.ModuleBase) {
            Show-Toast -Message 'GA-AppLocker module is not loaded. Please restart the dashboard and try again.' -Type 'Error'
            return
        }

        $modulePath = $moduleInfo.ModuleBase
        $windowRef = $Window
        $policyNameValue = $policyName

        $bgWork = {
            param($ModulePath, $PolicyId, $RuleIds)

            try {
                $modulesDir = Join-Path $ModulePath 'Modules'
                foreach ($mod in @('GA-AppLocker.Core', 'GA-AppLocker.Policy')) {
                    $modPath = Join-Path $modulesDir "$mod\$mod.psd1"
                    if (-not (Test-Path $modPath)) {
                        throw "Required module missing: $modPath"
                    }

                    Import-Module $modPath -Force -ErrorAction Stop
                }

                $result = Remove-RuleFromPolicy -PolicyId $PolicyId -RuleId $RuleIds
                if ($null -eq $result) {
                    return @{ Success = $false; Data = $null; Error = 'Remove-RuleFromPolicy returned no result.' }
                }

                return $result
            }
            catch {
                return @{ Success = $false; Data = $null; Error = $_.Exception.Message }
            }
        }

        $onComplete = {
            param($removeResult)

            if ($windowRef) {
                Update-PoliciesDataGrid -Window $windowRef -Force
                Update-SelectedPolicyInfo -Window $windowRef
            }

            if ($removeResult -and $removeResult.Success) {
                $message = if ($removeResult.Message) { $removeResult.Message } else { "Removed rules from '$policyNameValue'." }
                Show-Toast -Message $message -Type 'Success'
            }
            elseif ($removeResult) {
                Show-Toast -Message "Failed to remove rules: $($removeResult.Error)" -Type 'Error'
            }
            else {
                Show-Toast -Message "Remove rules operation returned no result for '$policyNameValue'." -Type 'Error'
            }
        }.GetNewClosure()

        $onTimeout = {
            param($TimeoutMessage)
            Show-Toast -Message "Failed to remove rules from '$policyNameValue': $TimeoutMessage" -Type 'Error'
        }.GetNewClosure()

        Invoke-BackgroundWork -ScriptBlock $bgWork `
            -ArgumentList @($modulePath, $script:SelectedPolicyId, @($ruleIds)) `
            -OnComplete $onComplete `
            -OnTimeout $onTimeout `
            -NoLoadingOverlay `
            -TimeoutSeconds 180
    }
}

function global:Select-PolicyInGrid {
    param(
        $Window,
        [string]$PolicyId
    )

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if (-not $dataGrid -or -not $dataGrid.ItemsSource) { return }

    foreach ($item in $dataGrid.ItemsSource) {
        if ($item.PolicyId -eq $PolicyId) {
            $dataGrid.SelectedItem = $item
            $dataGrid.ScrollIntoView($item)
            break
        }
    }
}

function global:Invoke-ShowPolicyRules {
    param($Window)

    $tab = $Window.FindName('PolicyTabControl')
    if ($tab) { $tab.SelectedIndex = 1 }

    $rulesSection = $Window.FindName('PolicyRulesSection')
    if ($rulesSection) { $rulesSection.BringIntoView() }
}

function global:Invoke-ShowPolicyTargetGpo {
    param($Window)

    if (-not $global:GA_DeploySelectedPolicyId) {
        Show-Toast -Message 'Select a policy in Deployment first.' -Type 'Warning'
        return
    }

    Set-ActivePanel -PanelName 'PanelPolicy'

    Update-PoliciesDataGrid -Window $Window
    Select-PolicyInGrid -Window $Window -PolicyId $global:GA_DeploySelectedPolicyId
    Update-SelectedPolicyInfo -Window $Window

    $tab = $Window.FindName('PolicyTabControl')
    if ($tab) { $tab.SelectedIndex = 1 }

    $cbo = $Window.FindName('CboEditTargetGPO')
    if ($cbo) { $cbo.Focus() }
}

function global:Invoke-ImportRulesToPolicy {
    param($Window)

    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy first.' -Type 'Warning'
        return
    }

    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Filter = 'XML Files (*.xml)|*.xml'
    $dialog.Title = 'Import AppLocker Rules (XML)'

    if (-not $dialog.ShowDialog()) { return }

    try {
        $importResult = Import-RulesFromXml -Path $dialog.FileName -Status 'Approved' -SkipDuplicates
        if (-not $importResult.Success) {
            Show-Toast -Message "Import failed: $($importResult.Error)" -Type 'Error'
            return
        }

        $ruleIds = @($importResult.Data | ForEach-Object { $_.Id } | Where-Object { $_ })
        if ($ruleIds.Count -eq 0) {
            Show-Toast -Message 'No new rules were imported (all duplicates or empty).' -Type 'Info'
            return
        }

        $addResult = Add-RuleToPolicy -PolicyId $script:SelectedPolicyId -RuleId $ruleIds
        if ($addResult.Success) {
            Update-PoliciesDataGrid -Window $Window -Force
            Update-SelectedPolicyInfo -Window $Window
            $msg = "Imported $($ruleIds.Count) rule(s) and added to policy."
            if ($importResult.SkippedCount -gt 0) { $msg += " $($importResult.SkippedCount) duplicate(s) skipped." }
            Show-Toast -Message $msg -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to add imported rules: $($addResult.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
}

#endregion

#region ===== POLICY COMPARISON HANDLERS =====

function Initialize-PolicyCompareDropdowns {
    param($Window)
    
    $cboSource = $Window.FindName('CboCompareSource')
    $cboTarget = $Window.FindName('CboCompareTarget')
    
    if (-not $cboSource -or -not $cboTarget) { return }
    
    # Get all policies
    $result = Get-AllPolicies
    if ($result.Success -and $result.Data) {
        $policies = $result.Data | Sort-Object Name
        $cboSource.ItemsSource = $policies
        $cboTarget.ItemsSource = $policies
    }
}

function global:Invoke-ComparePolicies {
    param($Window)
    
    $cboSource = $Window.FindName('CboCompareSource')
    $cboTarget = $Window.FindName('CboCompareTarget')
    
    if (-not $cboSource.SelectedItem -or -not $cboTarget.SelectedItem) {
        Show-Toast -Message 'Please select both source and target policies.' -Type 'Warning'
        return
    }
    
    $sourcePolicy = $cboSource.SelectedItem
    $targetPolicy = $cboTarget.SelectedItem
    
    if ($sourcePolicy.PolicyId -eq $targetPolicy.PolicyId) {
        Show-Toast -Message 'Source and target policies are the same. Select different policies.' -Type 'Warning'
        return
    }
    
    try {
        Show-LoadingOverlay -Message 'Comparing policies...'
        
        $result = Compare-Policies -SourcePolicyId $sourcePolicy.PolicyId -TargetPolicyId $targetPolicy.PolicyId
        
        Hide-LoadingOverlay
        
        if ($result.Success) {
            $data = $result.Data
            $summary = $data.Summary
            
            # Build result message
            $msg = "Comparison complete: Added $($summary.AddedCount), Removed $($summary.RemovedCount), Modified $($summary.ModifiedCount), Unchanged $($summary.UnchangedCount)."
            
            # Store comparison result for export
            $script:LastPolicyComparison = @{
                SourcePolicy = $sourcePolicy
                TargetPolicy = $targetPolicy
                Result = $result
            }
            
            # Enable export button
            $btnExport = $Window.FindName('BtnExportDiffReport')
            if ($btnExport) { $btnExport.IsEnabled = $true }
            
            Show-Toast -Message $msg -Type 'Info'
        }
        else {
            Show-Toast -Message "Comparison failed: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Invoke-ExportDiffReport {
    param($Window)
    
    if (-not $script:LastPolicyComparison) {
        Show-Toast -Message 'No comparison results available. Compare policies first.' -Type 'Warning'
        return
    }
    
    Add-Type -AssemblyName System.Windows.Forms
    
    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Policy Diff Report'
    $dialog.Filter = 'Markdown Files (*.md)|*.md|HTML Files (*.html)|*.html|Text Files (*.txt)|*.txt'
    $dialog.FileName = "PolicyDiff_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
    
    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $format = switch ([System.IO.Path]::GetExtension($dialog.FileName).ToLower()) {
                '.html' { 'Html' }
                '.md' { 'Markdown' }
                default { 'Text' }
            }
            
            $sourceId = $script:LastPolicyComparison.SourcePolicy.PolicyId
            $targetId = $script:LastPolicyComparison.TargetPolicy.PolicyId
            
            $report = Get-PolicyDiffReport -SourcePolicyId $sourceId -TargetPolicyId $targetId -Format $format
            
            if ($report.Success) {
                $report.Data | Set-Content -Path $dialog.FileName -Encoding UTF8
                Show-Toast -Message "Report exported to: $($dialog.FileName)" -Type 'Success'
            }
            else {
                Show-Toast -Message "Export failed: $($report.Error)" -Type 'Error'
            }
        }
        catch {
            Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

#endregion

#region ===== DEPLOYMENT PANEL HANDLERS =====

#endregion
