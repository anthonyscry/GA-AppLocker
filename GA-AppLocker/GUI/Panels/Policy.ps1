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
                        Update-PoliciesFilter -Window $script:MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnCreatePolicy', 'BtnRefreshPolicies', 'BtnActivatePolicy', 
        'BtnArchivePolicy', 'BtnExportPolicy', 'BtnDeletePolicy', 'BtnDeployPolicy',
        'BtnAddRulesToPolicy', 'BtnRemoveRulesFromPolicy', 'BtnSelectTargetOUs', 'BtnSaveTargets',
        'BtnSavePolicyChanges'
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

    # Wire up DataGrid selection changed
    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if ($dataGrid) {
        $dataGrid.Add_SelectionChanged({
                param($sender, $e)
                Update-SelectedPolicyInfo -Window $script:MainWindow
            })
    }

    # Initial load - use async to keep UI responsive
    Update-PoliciesDataGrid -Window $Window -Async
}

function script:Update-PoliciesDataGrid {
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

function Update-PolicyCounters {
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

function Update-SelectedPolicyInfo {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    $selectedItem = $dataGrid.SelectedItem

    if ($selectedItem) {
        $script:SelectedPolicyId = $selectedItem.PolicyId
        $Window.FindName('TxtSelectedPolicyName').Text = $selectedItem.Name
        $Window.FindName('TxtSelectedPolicyName').FontStyle = 'Normal'
        $Window.FindName('TxtSelectedPolicyName').Foreground = [System.Windows.Media.Brushes]::White
        $ruleCount = if ($selectedItem.RuleIds) { $selectedItem.RuleIds.Count } else { 0 }
        $Window.FindName('TxtPolicyRuleCount').Text = "$ruleCount rules"

        # Update target fields
        $Window.FindName('TxtTargetGPO').Text = if ($selectedItem.TargetGPO) { $selectedItem.TargetGPO } else { '' }
        $Window.FindName('PolicyTargetOUsList').ItemsSource = if ($selectedItem.TargetOUs) { $selectedItem.TargetOUs } else { @() }
        
        # Update Export tab
        $txtExportName = $Window.FindName('TxtExportPolicyName')
        if ($txtExportName) {
            $txtExportName.Text = $selectedItem.Name
            $txtExportName.FontStyle = 'Normal'
            $txtExportName.Foreground = [System.Windows.Media.Brushes]::White
        }
        
        # Update Edit tab
        $txtEditName = $Window.FindName('TxtEditPolicyName')
        if ($txtEditName) {
            $txtEditName.Text = $selectedItem.Name
            $txtEditName.FontStyle = 'Normal'
            $txtEditName.Foreground = [System.Windows.Media.Brushes]::White
        }
        
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
    }
    else {
        $script:SelectedPolicyId = $null
        $Window.FindName('TxtSelectedPolicyName').Text = '(Select a policy)'
        $Window.FindName('TxtSelectedPolicyName').FontStyle = 'Italic'
        $Window.FindName('TxtSelectedPolicyName').Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(158, 158, 158))
        $Window.FindName('TxtPolicyRuleCount').Text = '0 rules'
        $Window.FindName('TxtTargetGPO').Text = ''
        $Window.FindName('PolicyTargetOUsList').ItemsSource = $null
        
        # Reset Export tab
        $txtExportName = $Window.FindName('TxtExportPolicyName')
        if ($txtExportName) {
            $txtExportName.Text = '(Select a policy)'
            $txtExportName.FontStyle = 'Italic'
            $txtExportName.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(158, 158, 158))
        }
        
        # Reset Edit tab
        $txtEditName = $Window.FindName('TxtEditPolicyName')
        if ($txtEditName) {
            $txtEditName.Text = '(Select a policy)'
            $txtEditName.FontStyle = 'Italic'
            $txtEditName.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(158, 158, 158))
        }
    }
}

function Invoke-SavePolicyChanges {
    param([System.Windows.Window]$Window)
    
    if (-not $script:SelectedPolicyId) {
        Show-Toast -Message 'Please select a policy to edit.' -Type 'Warning'
        return
    }
    
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
    
    try {
        $result = Update-Policy -Id $script:SelectedPolicyId -EnforcementMode $enforcement -Phase $phase
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            Show-Toast -Message "Policy updated: Mode=$enforcement, Phase=$phase" -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to update policy: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
}

function Invoke-CreatePolicy {
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

function Set-SelectedPolicyStatus {
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

function Invoke-DeleteSelectedPolicy {
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

function Invoke-ExportSelectedPolicy {
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

function Invoke-DeploySelectedPolicy {
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

    if (-not $policy.TargetGPO) {
        [System.Windows.MessageBox]::Show('Please set a Target GPO before deploying.', 'Missing Target', 'OK', 'Warning')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Deploy policy '$($policy.Name)' to GPO '$($policy.TargetGPO)'?`n`nThis will navigate to the Deployment panel.",
        'Confirm Deploy',
        'YesNo',
        'Question'
    )

    if ($confirm -eq 'Yes') {
        # Set status to deployed and navigate to deploy panel
        Set-PolicyStatus -PolicyId $script:SelectedPolicyId -Status 'Deployed' | Out-Null
        Update-PoliciesDataGrid -Window $Window
        Set-ActivePanel -PanelName 'PanelDeploy'
    }
}

function Invoke-AddRulesToPolicy {
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

    $rulesResult = Get-AllRules
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

function Invoke-RemoveRulesFromPolicy {
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

function Invoke-SelectTargetOUs {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    # Use discovered OUs from Discovery panel
    if ($script:DiscoveredOUs.Count -eq 0) {
        $confirm = [System.Windows.MessageBox]::Show(
            "No OUs discovered. Navigate to AD Discovery to scan for OUs?",
            'No OUs',
            'YesNo',
            'Question'
        )

        if ($confirm -eq 'Yes') {
            Set-ActivePanel -PanelName 'PanelDiscovery'
        }
        return
    }

    # For now, use all discovered OUs
    $ouList = $Window.FindName('PolicyTargetOUsList')
    $ouList.ItemsSource = $script:DiscoveredOUs | Select-Object -ExpandProperty DistinguishedName

    [System.Windows.MessageBox]::Show(
        "Added $($script:DiscoveredOUs.Count) OUs to target list.`nClick 'Save Targets' to apply.",
        'OUs Selected',
        'OK',
        'Information'
    )
}

function Invoke-SavePolicyTargets {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    $targetGPO = $Window.FindName('TxtTargetGPO').Text
    $targetOUs = @($Window.FindName('PolicyTargetOUsList').ItemsSource)

    try {
        $result = Set-PolicyTarget -PolicyId $script:SelectedPolicyId -TargetOUs $targetOUs -TargetGPO $targetGPO
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            [System.Windows.MessageBox]::Show('Policy targets saved.', 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

#endregion

#region ===== DEPLOYMENT PANEL HANDLERS =====

#endregion
