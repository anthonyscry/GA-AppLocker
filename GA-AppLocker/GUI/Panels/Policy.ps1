#region Policy Panel Functions
# Policy.ps1 - Policy panel handlers
function Initialize-PolicyPanel {
    param([System.Windows.Window]$Window)

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
        'BtnArchivePolicy', 'BtnExportPolicy', 'BtnDeletePolicy', 'BtnDeployPolicy',
        'BtnAddRulesToPolicy', 'BtnRemoveRulesFromPolicy',
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

    # Wire up GPO dropdown to show/hide custom textbox
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

    # Wire up DataGrid selection changed
    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if ($dataGrid) {
        $dataGrid.Add_SelectionChanged({
                param($sender, $e)
                Update-SelectedPolicyInfo -Window $global:GA_MainWindow
            })
    }

    # Initial load - use async to keep UI responsive
    Update-PoliciesDataGrid -Window $Window -Async
    
    # Initialize Compare tab dropdowns
    Initialize-PolicyCompareDropdowns -Window $Window
}

function global:Update-PoliciesDataGrid {
    param(
        [System.Windows.Window]$Window,
        [switch]$Async
    )

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if (-not $dataGrid) { return }

    if (-not (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
        $dataGrid.ItemsSource = $null
        return
    }

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

                $displayData.Add([PSCustomObject]@{
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
    }

    # Use async for initial/refresh loads
    if ($Async -and (Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction SilentlyContinue)) {
        Invoke-AsyncOperation -ScriptBlock { Get-AllPolicies } -LoadingMessage 'Loading policies...' -OnComplete {
            param($Result)
            & $processPoliciesData $Result $statusFilter $textFilter $dataGrid $Window
        }.GetNewClosure() -OnError {
            param($ErrorMessage)
            Write-Log -Level Error -Message "Failed to load policies: $ErrorMessage"
        }.GetNewClosure()
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
        [System.Windows.Window]$Window,
        [array]$Policies
    )

    $total = if ($Policies) { $Policies.Count } else { 0 }
    $draft = if ($Policies) { ($Policies | Where-Object { $_.Status -eq 'Draft' }).Count } else { 0 }
    $active = if ($Policies) { ($Policies | Where-Object { $_.Status -eq 'Active' }).Count } else { 0 }
    $deployed = if ($Policies) { ($Policies | Where-Object { $_.Status -eq 'Deployed' }).Count } else { 0 }

    $Window.FindName('TxtPolicyTotalCount').Text = "$total"
    $Window.FindName('TxtPolicyDraftCount').Text = "$draft"
    $Window.FindName('TxtPolicyActiveCount').Text = "$active"
    $Window.FindName('TxtPolicyDeployedCount').Text = "$deployed"
}

function global:Update-PoliciesFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    $script:CurrentPoliciesFilter = $Filter
    Update-PoliciesDataGrid -Window $Window
}

function global:Update-SelectedPolicyInfo {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if (-not $dataGrid) { return }
    $selectedItem = $dataGrid.SelectedItem

    if ($selectedItem) {
        $script:SelectedPolicyId = $selectedItem.PolicyId
        
        $txtName = $Window.FindName('TxtSelectedPolicyName')
        if ($txtName) {
            $txtName.Text = $selectedItem.Name
            $txtName.FontStyle = 'Normal'
            $txtName.Foreground = [System.Windows.Media.Brushes]::White
        }
        
        $ruleCount = if ($selectedItem.RuleIds) { $selectedItem.RuleIds.Count } else { 0 }
        $txtRuleCount = $Window.FindName('TxtPolicyRuleCount')
        if ($txtRuleCount) { $txtRuleCount.Text = "$ruleCount rules" }
        
        # Update Edit tab - Name and Description
        $txtEditName = $Window.FindName('TxtEditPolicyName')
        if ($txtEditName) { $txtEditName.Text = $selectedItem.Name }
        
        $txtEditDesc = $Window.FindName('TxtEditPolicyDescription')
        if ($txtEditDesc) { $txtEditDesc.Text = if ($selectedItem.Description) { $selectedItem.Description } else { '' } }
        
        # Set enforcement mode dropdown
        $cboEnforcement = $Window.FindName('CboEditEnforcement')
        if ($cboEnforcement) {
            $enfIndex = switch ($selectedItem.EnforcementMode) {
                'AuditOnly' { 0 }
                'Enabled' { 1 }
                'NotConfigured' { 2 }
                default { 0 }
            }
            $cboEnforcement.SelectedIndex = $enfIndex
        }
        
        # Set phase dropdown
        $cboPhase = $Window.FindName('CboEditPhase')
        if ($cboPhase) {
            $phaseIndex = if ($selectedItem.Phase) { [int]$selectedItem.Phase - 1 } else { 0 }
            if ($phaseIndex -lt 0) { $phaseIndex = 0 }
            if ($phaseIndex -gt 3) { $phaseIndex = 3 }
            $cboPhase.SelectedIndex = $phaseIndex
        }
        
        # Set Target GPO dropdown
        $cboGPO = $Window.FindName('CboEditTargetGPO')
        $txtCustomGPO = $Window.FindName('TxtEditCustomGPO')
        if ($cboGPO) {
            $gpoValue = if ($selectedItem.TargetGPO) { $selectedItem.TargetGPO } else { '' }
            # Match against known GPO names
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
                # Custom GPO name — select "Custom..." and fill textbox
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
    }
    else {
        $script:SelectedPolicyId = $null
        
        $txtName = $Window.FindName('TxtSelectedPolicyName')
        if ($txtName) {
            $txtName.Text = '(Select a policy)'
            $txtName.FontStyle = 'Italic'
            $txtName.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(158, 158, 158))
        }
        
        $txtRuleCount = $Window.FindName('TxtPolicyRuleCount')
        if ($txtRuleCount) { $txtRuleCount.Text = '0 rules' }
        
        # Reset Edit tab
        $txtEditName = $Window.FindName('TxtEditPolicyName')
        if ($txtEditName) { $txtEditName.Text = '' }
        
        $txtEditDesc = $Window.FindName('TxtEditPolicyDescription')
        if ($txtEditDesc) { $txtEditDesc.Text = '' }
        
        $cboGPO = $Window.FindName('CboEditTargetGPO')
        if ($cboGPO) { $cboGPO.SelectedIndex = 0 }
        
        $txtCustomGPO = $Window.FindName('TxtEditCustomGPO')
        if ($txtCustomGPO) { $txtCustomGPO.Text = ''; $txtCustomGPO.Visibility = 'Collapsed' }
    }
}

function global:Invoke-SavePolicyChanges {
    param([System.Windows.Window]$Window)
    
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
            Update-PoliciesDataGrid -Window $Window
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
    param([System.Windows.Window]$Window)

    $name = $Window.FindName('TxtPolicyName').Text
    $description = $Window.FindName('TxtPolicyDescription').Text

    if ([string]::IsNullOrWhiteSpace($name)) {
        Show-Toast -Message 'Please enter a policy name.' -Type 'Warning'
        return
    }

    $enforcementCombo = $Window.FindName('CboPolicyEnforcement')
    $enforcement = switch ($enforcementCombo.SelectedIndex) {
        0 { 'AuditOnly' }
        1 { 'Enabled' }
        2 { 'NotConfigured' }
        default { 'AuditOnly' }
    }

    # Get deployment phase from ComboBox
    $phaseCombo = $Window.FindName('CboPolicyPhase')
    $selectedPhaseItem = $phaseCombo.SelectedItem
    $phase = if ($selectedPhaseItem -and $selectedPhaseItem.Tag) {
        [int]$selectedPhaseItem.Tag
    } else {
        1  # Default to Phase 1
    }

    try {
        $result = New-Policy -Name $name -Description $description -EnforcementMode $enforcement -Phase $phase
        
        if ($result.Success) {
            $Window.FindName('TxtPolicyName').Text = ''
            $Window.FindName('TxtPolicyDescription').Text = ''
            $Window.FindName('CboPolicyPhase').SelectedIndex = 0  # Reset to Phase 1
            Update-PoliciesDataGrid -Window $Window
            Update-WorkflowBreadcrumb -Window $Window
            Show-Toast -Message "Policy '$name' created successfully (Phase $phase)." -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to create policy: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Set-SelectedPolicyStatus {
    param(
        [System.Windows.Window]$Window,
        [string]$Status
    )

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy.', 'No Selection', 'OK', 'Information')
        return
    }

    try {
        $result = Set-PolicyStatus -PolicyId $script:SelectedPolicyId -Status $Status
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            [System.Windows.MessageBox]::Show("Policy status updated to '$Status'.", 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-DeleteSelectedPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        'Are you sure you want to delete this policy?',
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne 'Yes') { return }

    try {
        $result = Remove-Policy -PolicyId $script:SelectedPolicyId -Force
        
        if ($result.Success) {
            $script:SelectedPolicyId = $null
            Update-PoliciesDataGrid -Window $Window
            Update-SelectedPolicyInfo -Window $Window
            [System.Windows.MessageBox]::Show('Policy deleted.', 'Deleted', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-ExportSelectedPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy to export.', 'No Selection', 'OK', 'Information')
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Policy to XML'
    $dialog.Filter = 'XML Files (*.xml)|*.xml'
    $dialog.FileName = "AppLockerPolicy_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $result = Export-PolicyToXml -PolicyId $script:SelectedPolicyId -OutputPath $dialog.FileName
            
            if ($result.Success) {
                [System.Windows.MessageBox]::Show(
                    "Exported policy to:`n$($dialog.FileName)`n`nRules: $($result.Data.RuleCount)",
                    'Export Complete',
                    'OK',
                    'Information'
                )
            }
            else {
                [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
        }
    }
}

function global:Invoke-DeploySelectedPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy to deploy.', 'No Selection', 'OK', 'Information')
        return
    }

    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) {
        [System.Windows.MessageBox]::Show("Could not load policy: $($policyResult.Error)", 'Error', 'OK', 'Error')
        return
    }

    $policy = $policyResult.Data
    $gpoInfo = if ($policy.TargetGPO) { " to GPO '$($policy.TargetGPO)'" } else { '' }

    $confirm = [System.Windows.MessageBox]::Show(
        "Navigate to Deployment panel to deploy policy '$($policy.Name)'$gpoInfo?",
        'Deploy Policy',
        'YesNo',
        'Question'
    )

    if ($confirm -eq 'Yes') {
        Set-ActivePanel -PanelName 'PanelDeploy'
    }
}

function global:Invoke-AddRulesToPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    # Get all approved rules not in this policy
    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) { return }
    
    $policy = $policyResult.Data
    $currentRuleIds = @($policy.RuleIds)

    $rulesResult = Get-AllRules -Take 100000
    if (-not $rulesResult.Success) { return }

    $availableRules = $rulesResult.Data | Where-Object { 
        $_.Status -eq 'Approved' -and $_.Id -notin $currentRuleIds 
    }

    if ($availableRules.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No approved rules available to add.', 'No Rules', 'OK', 'Information')
        return
    }

    # For now, add all approved rules
    $confirm = [System.Windows.MessageBox]::Show(
        "Add $($availableRules.Count) approved rule(s) to this policy?",
        'Add Rules',
        'YesNo',
        'Question'
    )

    if ($confirm -eq 'Yes') {
        $ruleIds = $availableRules | Select-Object -ExpandProperty Id
        $result = Add-RuleToPolicy -PolicyId $script:SelectedPolicyId -RuleId $ruleIds
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            Update-SelectedPolicyInfo -Window $Window
            [System.Windows.MessageBox]::Show($result.Message, 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
}

function global:Invoke-RemoveRulesFromPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) { return }
    
    $policy = $policyResult.Data
    $ruleCount = if ($policy.RuleIds) { $policy.RuleIds.Count } else { 0 }

    if ($ruleCount -eq 0) {
        [System.Windows.MessageBox]::Show('This policy has no rules to remove.', 'No Rules', 'OK', 'Information')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Remove all $ruleCount rule(s) from this policy?",
        'Remove Rules',
        'YesNo',
        'Warning'
    )

    if ($confirm -eq 'Yes') {
        $result = Remove-RuleFromPolicy -PolicyId $script:SelectedPolicyId -RuleId $policy.RuleIds
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            Update-SelectedPolicyInfo -Window $Window
            [System.Windows.MessageBox]::Show($result.Message, 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
}

#endregion

#region ===== POLICY COMPARISON HANDLERS =====

function Initialize-PolicyCompareDropdowns {
    param([System.Windows.Window]$Window)
    
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
    param([System.Windows.Window]$Window)
    
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
            $msg = @"
Policy Comparison Results
========================

Source: $($sourcePolicy.Name)
Target: $($targetPolicy.Name)

Summary:
- Added (in target only): $($summary.AddedCount) rule(s)
- Removed (in source only): $($summary.RemovedCount) rule(s)
- Modified: $($summary.ModifiedCount) rule(s)
- Unchanged: $($summary.UnchangedCount) rule(s)
"@
            
            # Store comparison result for export
            $script:LastPolicyComparison = @{
                SourcePolicy = $sourcePolicy
                TargetPolicy = $targetPolicy
                Result = $result
            }
            
            # Enable export button
            $btnExport = $Window.FindName('BtnExportDiffReport')
            if ($btnExport) { $btnExport.IsEnabled = $true }
            
            [System.Windows.MessageBox]::Show($msg, 'Comparison Results', 'OK', 'Information')
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
    param([System.Windows.Window]$Window)
    
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
