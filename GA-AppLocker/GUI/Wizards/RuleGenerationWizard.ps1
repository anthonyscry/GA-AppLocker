<#
.SYNOPSIS
    3-Step Rule Generation Wizard

.DESCRIPTION
    A streamlined wizard UI for converting artifacts to rules.
    Step 1: Configure - Set mode, action, exclusions
    Step 2: Preview - See what will be created
    Step 3: Generate - Execute batch generation with progress

.NOTES
    Uses Invoke-BatchRuleGeneration for 10x faster rule creation.
#>

#region ===== WIZARD STATE =====
$script:WizardState = @{
    CurrentStep     = 1
    Artifacts       = @()
    ArtifactSummary = $null
    Preview         = $null
    Settings        = @{
        Mode           = 'Smart'
        Action         = 'Allow'
        Status         = 'Pending'
        PublisherLevel = 'PublisherProduct'
        SkipDlls         = $true
        SkipUnsigned     = $false
        SkipWshScripts   = $true
        SkipShellScripts = $false
        DedupeMode     = 'Smart'
    }
    IsGenerating    = $false
    GenerationResult = $null
}
#endregion

#region ===== INITIALIZATION =====
function global:Initialize-RuleGenerationWizard {
    <#
    .SYNOPSIS
        Initializes the wizard with artifacts from the scanner.
    #>
    param([array]$Artifacts)
    
    $script:WizardState.Artifacts = $Artifacts
    $script:WizardState.CurrentStep = 1
    $script:WizardState.Preview = $null
    $script:WizardState.GenerationResult = $null
    $script:WizardState.IsGenerating = $false
    
    # Calculate artifact summary
    $script:WizardState.ArtifactSummary = Get-ArtifactSummary -Artifacts $Artifacts
    
    # Show wizard overlay
    Show-WizardStep1
    
    global:Write-Log "Wizard initialized with $($Artifacts.Count) artifacts"
}

function global:Get-ArtifactSummary {
    param([array]$Artifacts)
    
    $summary = [PSCustomObject]@{
        Total     = $Artifacts.Count
        Signed    = 0
        Unsigned  = 0
        ByType    = @{}
    }
    
    foreach ($art in $Artifacts) {
        if ($art.IsSigned) { $summary.Signed++ } else { $summary.Unsigned++ }
        
        $type = if ($art.ArtifactType) { $art.ArtifactType } else { 'Other' }
        if (-not $summary.ByType.ContainsKey($type)) {
            $summary.ByType[$type] = 0
        }
        $summary.ByType[$type]++
    }
    
    return $summary
}
#endregion

#region ===== STEP 1: CONFIGURE =====
function global:Show-WizardStep1 {
    <#
    .SYNOPSIS
        Shows the configuration step of the wizard.
    #>
    $script:WizardState.CurrentStep = 1
    
    # Get UI elements
    $wizard = $global:GA_MainWindow.FindName('RuleWizardOverlay')
    $step1 = $global:GA_MainWindow.FindName('WizardStep1')
    $step2 = $global:GA_MainWindow.FindName('WizardStep2')
    $step3 = $global:GA_MainWindow.FindName('WizardStep3')
    
    # Update step indicators
    Update-WizardStepIndicators -Step 1
    
    # Show step 1, hide others
    $step1.Visibility = 'Visible'
    $step2.Visibility = 'Collapsed'
    $step3.Visibility = 'Collapsed'
    
    # Populate artifact summary
    $summary = $script:WizardState.ArtifactSummary
    $txtTotal = $global:GA_MainWindow.FindName('WizardTxtTotalArtifacts')
    $txtSigned = $global:GA_MainWindow.FindName('WizardTxtSignedArtifacts')
    $txtUnsigned = $global:GA_MainWindow.FindName('WizardTxtUnsignedArtifacts')
    
    if ($txtTotal) { $txtTotal.Text = $summary.Total }
    if ($txtSigned) { $txtSigned.Text = $summary.Signed }
    if ($txtUnsigned) { $txtUnsigned.Text = $summary.Unsigned }
    
    # Update type counts with DLL, EXE, Script counts
    $txtExe = $global:GA_MainWindow.FindName('WizardTxtExeCount')
    $txtDll = $global:GA_MainWindow.FindName('WizardTxtDllCount')
    $txtScript = $global:GA_MainWindow.FindName('WizardTxtScriptCount')
    
    if ($txtExe) { $txtExe.Text = if ($summary.ByType.ContainsKey('EXE')) { $summary.ByType['EXE'] } else { 0 } }
    if ($txtDll) { $txtDll.Text = if ($summary.ByType.ContainsKey('DLL')) { $summary.ByType['DLL'] } else { 0 } }
    
    $scriptCount = 0
    foreach ($type in @('PS1', 'BAT', 'CMD', 'VBS', 'JS', 'WSF')) {
        if ($summary.ByType.ContainsKey($type)) { $scriptCount += $summary.ByType[$type] }
    }
    if ($txtScript) { $txtScript.Text = $scriptCount }
    
    # Load saved settings into UI
    $cboMode = $global:GA_MainWindow.FindName('WizardCboMode')
    $cboAction = $global:GA_MainWindow.FindName('WizardCboAction')
    $cboStatus = $global:GA_MainWindow.FindName('WizardCboStatus')
    $chkSkipDlls = $global:GA_MainWindow.FindName('WizardChkSkipDlls')
    $chkSkipUnsigned = $global:GA_MainWindow.FindName('WizardChkSkipUnsigned')
    $chkSkipWshScripts = $global:GA_MainWindow.FindName('WizardChkSkipWshScripts')
    $chkSkipShellScripts = $global:GA_MainWindow.FindName('WizardChkSkipShellScripts')
    $cboPubLevel = $global:GA_MainWindow.FindName('WizardCboPubLevel')
    $cboDedupeMode = $global:GA_MainWindow.FindName('WizardCboDedupeMode')
    
    if ($cboMode) { $cboMode.SelectedValue = $script:WizardState.Settings.Mode }
    if ($cboAction) { $cboAction.SelectedValue = $script:WizardState.Settings.Action }
    if ($cboStatus) { $cboStatus.SelectedValue = $script:WizardState.Settings.Status }
    if ($chkSkipDlls) { $chkSkipDlls.IsChecked = $script:WizardState.Settings.SkipDlls }
    if ($chkSkipUnsigned) { $chkSkipUnsigned.IsChecked = $script:WizardState.Settings.SkipUnsigned }
    if ($chkSkipWshScripts) { $chkSkipWshScripts.IsChecked = $script:WizardState.Settings.SkipWshScripts }
    if ($chkSkipShellScripts) { $chkSkipShellScripts.IsChecked = $script:WizardState.Settings.SkipShellScripts }
    if ($cboPubLevel) { $cboPubLevel.SelectedValue = $script:WizardState.Settings.PublisherLevel }
    if ($cboDedupeMode) { $cboDedupeMode.SelectedValue = $script:WizardState.Settings.DedupeMode }
    
    # Show wizard overlay
    $wizard.Visibility = 'Visible'
    
    # Update button states
    Update-WizardButtons
}

function global:Save-WizardStep1Settings {
    <#
    .SYNOPSIS
        Saves settings from Step 1 UI to wizard state.
    #>
    $cboMode = $global:GA_MainWindow.FindName('WizardCboMode')
    $cboAction = $global:GA_MainWindow.FindName('WizardCboAction')
    $cboStatus = $global:GA_MainWindow.FindName('WizardCboStatus')
    $chkSkipDlls = $global:GA_MainWindow.FindName('WizardChkSkipDlls')
    $chkSkipUnsigned = $global:GA_MainWindow.FindName('WizardChkSkipUnsigned')
    $chkSkipWshScripts = $global:GA_MainWindow.FindName('WizardChkSkipWshScripts')
    $chkSkipShellScripts = $global:GA_MainWindow.FindName('WizardChkSkipShellScripts')
    $cboPubLevel = $global:GA_MainWindow.FindName('WizardCboPubLevel')
    $cboDedupeMode = $global:GA_MainWindow.FindName('WizardCboDedupeMode')
    
    if ($cboMode) { $script:WizardState.Settings.Mode = $cboMode.SelectedValue }
    if ($cboAction) { $script:WizardState.Settings.Action = $cboAction.SelectedValue }
    if ($cboStatus) { $script:WizardState.Settings.Status = $cboStatus.SelectedValue }
    if ($chkSkipDlls) { $script:WizardState.Settings.SkipDlls = $chkSkipDlls.IsChecked }
    if ($chkSkipUnsigned) { $script:WizardState.Settings.SkipUnsigned = $chkSkipUnsigned.IsChecked }
    if ($chkSkipWshScripts) { $script:WizardState.Settings.SkipWshScripts = $chkSkipWshScripts.IsChecked }
    if ($chkSkipShellScripts) { $script:WizardState.Settings.SkipShellScripts = $chkSkipShellScripts.IsChecked }
    if ($cboPubLevel) { $script:WizardState.Settings.PublisherLevel = $cboPubLevel.SelectedValue }
    if ($cboDedupeMode) { $script:WizardState.Settings.DedupeMode = $cboDedupeMode.SelectedValue }
}
#endregion

#region ===== STEP 2: PREVIEW =====
function global:Show-WizardStep2 {
    <#
    .SYNOPSIS
        Shows the preview step with estimated rule counts.
    #>
    
    # Save Step 1 settings first
    Save-WizardStep1Settings
    
    $script:WizardState.CurrentStep = 2
    
    # Get UI elements
    $step1 = $global:GA_MainWindow.FindName('WizardStep1')
    $step2 = $global:GA_MainWindow.FindName('WizardStep2')
    $step3 = $global:GA_MainWindow.FindName('WizardStep3')
    
    # Update step indicators
    Update-WizardStepIndicators -Step 2
    
    # Show step 2, hide others
    $step1.Visibility = 'Collapsed'
    $step2.Visibility = 'Visible'
    $step3.Visibility = 'Collapsed'
    
    # Show loading state
    $previewLoading = $global:GA_MainWindow.FindName('WizardPreviewLoading')
    $previewContent = $global:GA_MainWindow.FindName('WizardPreviewContent')
    if ($previewLoading) { $previewLoading.Visibility = 'Visible' }
    if ($previewContent) { $previewContent.Visibility = 'Collapsed' }
    
    # Calculate preview asynchronously
    $settings = $script:WizardState.Settings
    $artifacts = $script:WizardState.Artifacts
    
    # Use Invoke-AsyncOperation if available, otherwise calculate synchronously
    # Try-catch used since Get-Command fails in WPF context
    $asyncAvailable = $false
    try { $asyncAvailable = [bool](Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction Stop) } catch { }
    
    if ($asyncAvailable) {
        Invoke-AsyncOperation -ScriptBlock {
            param($Artifacts, $Settings)
            Get-BatchPreview `
                -Artifacts $Artifacts `
                -Mode $Settings.Mode `
                -SkipDlls:$Settings.SkipDlls `
                -SkipUnsigned:$Settings.SkipUnsigned `
                -SkipWshScripts:$Settings.SkipWshScripts `
                -SkipShellScripts:$Settings.SkipShellScripts `
                -DedupeMode $Settings.DedupeMode `
                -PublisherLevel $Settings.PublisherLevel
        } -ArgumentList @($artifacts, $settings) -OnComplete {
            param($Result)
            $script:WizardState.Preview = $Result
            Update-WizardPreviewUI -Preview $Result
        }
    } else {
        # Synchronous fallback
        $preview = Get-BatchPreview `
            -Artifacts $artifacts `
            -Mode $settings.Mode `
            -SkipDlls:$settings.SkipDlls `
            -SkipUnsigned:$settings.SkipUnsigned `
            -SkipWshScripts:$settings.SkipWshScripts `
            -SkipShellScripts:$settings.SkipShellScripts `
            -DedupeMode $settings.DedupeMode `
            -PublisherLevel $settings.PublisherLevel
        
        $script:WizardState.Preview = $preview
        Update-WizardPreviewUI -Preview $preview
    }
    
    # Update button states
    Update-WizardButtons
}

function global:Update-WizardPreviewUI {
    param([PSCustomObject]$Preview)
    
    # Hide loading, show content
    $previewLoading = $global:GA_MainWindow.FindName('WizardPreviewLoading')
    $previewContent = $global:GA_MainWindow.FindName('WizardPreviewContent')
    if ($previewLoading) { $previewLoading.Visibility = 'Collapsed' }
    if ($previewContent) { $previewContent.Visibility = 'Visible' }
    
    # Update statistics
    $txtToProcess = $global:GA_MainWindow.FindName('WizardTxtToProcess')
    $txtSkipped = $global:GA_MainWindow.FindName('WizardTxtSkipped')
    $txtDeduped = $global:GA_MainWindow.FindName('WizardTxtDeduped')
    $txtNewRules = $global:GA_MainWindow.FindName('WizardTxtNewRules')
    $txtExisting = $global:GA_MainWindow.FindName('WizardTxtExistingRules')
    $txtPubRules = $global:GA_MainWindow.FindName('WizardTxtPublisherRules')
    $txtHashRules = $global:GA_MainWindow.FindName('WizardTxtHashRules')
    
    if ($txtToProcess) { $txtToProcess.Text = $Preview.AfterExclusions }
    if ($txtSkipped) { $txtSkipped.Text = ($Preview.TotalArtifacts - $Preview.AfterExclusions) }
    if ($txtDeduped) { $txtDeduped.Text = ($Preview.AfterExclusions - $Preview.AfterDedup) }
    if ($txtNewRules) { $txtNewRules.Text = $Preview.NewRulesToCreate }
    if ($txtExisting) { $txtExisting.Text = $Preview.ExistingRules }
    if ($txtPubRules) { $txtPubRules.Text = $Preview.EstimatedPublisher }
    if ($txtHashRules) { $txtHashRules.Text = $Preview.EstimatedHash }
    
    # Update sample rules DataGrid
    $dgSample = $global:GA_MainWindow.FindName('WizardDgSampleRules')
    if ($dgSample -and $Preview.SampleRules) {
        $dgSample.ItemsSource = $Preview.SampleRules
    }
    
    # Update generate button text
    $btnGenerate = $global:GA_MainWindow.FindName('WizardBtnGenerate')
    if ($btnGenerate) {
        $btnGenerate.Content = "Generate $($Preview.NewRulesToCreate) Rules"
        $btnGenerate.IsEnabled = $Preview.NewRulesToCreate -gt 0
    }
}
#endregion

#region ===== STEP 3: GENERATE =====
function global:Show-WizardStep3 {
    <#
    .SYNOPSIS
        Shows the generation step with progress.
    #>
    $script:WizardState.CurrentStep = 3
    $script:WizardState.IsGenerating = $true
    
    # Get UI elements
    $step1 = $global:GA_MainWindow.FindName('WizardStep1')
    $step2 = $global:GA_MainWindow.FindName('WizardStep2')
    $step3 = $global:GA_MainWindow.FindName('WizardStep3')
    
    # Update step indicators
    Update-WizardStepIndicators -Step 3
    
    # Show step 3, hide others
    $step1.Visibility = 'Collapsed'
    $step2.Visibility = 'Collapsed'
    $step3.Visibility = 'Visible'
    
    # Reset progress UI
    $progressBar = $global:GA_MainWindow.FindName('WizardProgressBar')
    $txtProgress = $global:GA_MainWindow.FindName('WizardTxtProgress')
    $txtStatus = $global:GA_MainWindow.FindName('WizardTxtStatus')
    $panelComplete = $global:GA_MainWindow.FindName('WizardPanelComplete')
    $panelProgress = $global:GA_MainWindow.FindName('WizardPanelProgress')
    
    if ($progressBar) { $progressBar.Value = 0 }
    if ($txtProgress) { $txtProgress.Text = "0 / $($script:WizardState.Preview.NewRulesToCreate)" }
    if ($txtStatus) { $txtStatus.Text = "Starting batch generation..." }
    if ($panelComplete) { $panelComplete.Visibility = 'Collapsed' }
    if ($panelProgress) { $panelProgress.Visibility = 'Visible' }
    
    # Update button states (disable back, show cancel)
    Update-WizardButtons
    
    # Start batch generation
    Start-WizardBatchGeneration
}

function global:Start-WizardBatchGeneration {
    <#
    .SYNOPSIS
        Executes the batch rule generation with progress updates.
    #>
    $settings = $script:WizardState.Settings
    $artifacts = $script:WizardState.Artifacts
    
    # Progress callback for UI updates
    $progressCallback = {
        param($Percent, $Message)
        
        $global:GA_MainWindow.Dispatcher.Invoke([Action]{
            $progressBar = $global:GA_MainWindow.FindName('WizardProgressBar')
            $txtStatus = $global:GA_MainWindow.FindName('WizardTxtStatus')
            
            if ($progressBar) { $progressBar.Value = $Percent }
            if ($txtStatus) { $txtStatus.Text = $Message }
        })
    }
    
    # Use async operation if available (try-catch since Get-Command fails in WPF context)
    $asyncAvailable = $false
    try { $asyncAvailable = [bool](Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction Stop) } catch { }
    
    if ($asyncAvailable) {
        Invoke-AsyncOperation -ScriptBlock {
            param($Artifacts, $Settings)
            
            Invoke-BatchRuleGeneration `
                -Artifacts $Artifacts `
                -Mode $Settings.Mode `
                -Action $Settings.Action `
                -Status $Settings.Status `
                -PublisherLevel $Settings.PublisherLevel `
                -SkipDlls:$Settings.SkipDlls `
                -SkipUnsigned:$Settings.SkipUnsigned `
                -SkipWshScripts:$Settings.SkipWshScripts `
                -SkipShellScripts:$Settings.SkipShellScripts `
                -DedupeMode $Settings.DedupeMode
            
        } -ArgumentList @($artifacts, $settings) -OnComplete {
            param($Result)
            Complete-WizardGeneration -Result $Result
        }
    } else {
        # Synchronous fallback with inline progress
        try {
            $result = Invoke-BatchRuleGeneration `
                -Artifacts $artifacts `
                -Mode $settings.Mode `
                -Action $settings.Action `
                -Status $settings.Status `
                -PublisherLevel $settings.PublisherLevel `
                -SkipDlls:$settings.SkipDlls `
                -SkipUnsigned:$settings.SkipUnsigned `
                -SkipWshScripts:$settings.SkipWshScripts `
                -SkipShellScripts:$settings.SkipShellScripts `
                -DedupeMode $settings.DedupeMode `
                -OnProgress {
                    param($Pct, $Msg)
                    $progressBar = $global:GA_MainWindow.FindName('WizardProgressBar')
                    $txtStatus = $global:GA_MainWindow.FindName('WizardTxtStatus')
                    if ($progressBar) { $progressBar.Value = $Pct }
                    if ($txtStatus) { $txtStatus.Text = $Msg }
                    [System.Windows.Forms.Application]::DoEvents()
                }
            
            Complete-WizardGeneration -Result $result
        }
        catch {
            Complete-WizardGeneration -Result @{
                Success = $false
                Errors = @($_.Exception.Message)
            }
        }
    }
}

function global:Complete-WizardGeneration {
    param([PSCustomObject]$Result)
    
    $script:WizardState.IsGenerating = $false
    $script:WizardState.GenerationResult = $Result
    
    # Update UI on main thread
    $global:GA_MainWindow.Dispatcher.Invoke([Action]{
        $progressBar = $global:GA_MainWindow.FindName('WizardProgressBar')
        $txtStatus = $global:GA_MainWindow.FindName('WizardTxtStatus')
        $panelComplete = $global:GA_MainWindow.FindName('WizardPanelComplete')
        $panelProgress = $global:GA_MainWindow.FindName('WizardPanelProgress')
        $txtResult = $global:GA_MainWindow.FindName('WizardTxtResult')
        $txtDuration = $global:GA_MainWindow.FindName('WizardTxtDuration')
        
        if ($progressBar) { $progressBar.Value = 100 }
        if ($panelProgress) { $panelProgress.Visibility = 'Collapsed' }
        if ($panelComplete) { $panelComplete.Visibility = 'Visible' }
        
        if ($Result.Success) {
            if ($txtStatus) { $txtStatus.Text = "Generation complete!" }
            if ($txtResult) { 
                $txtResult.Text = "$($Result.RulesCreated) rules created`n" +
                    "Skipped: $($Result.Skipped) (exclusions)`n" +
                    "Duplicates: $($Result.Duplicates) (already exist)"
                $txtResult.Foreground = [System.Windows.Media.Brushes]::LightGreen
            }
        } else {
            if ($txtStatus) { $txtStatus.Text = "Generation failed" }
            if ($txtResult) { 
                $errors = if ($Result.Errors) { $Result.Errors -join "`n" } else { "Unknown error" }
                $txtResult.Text = $errors
                $txtResult.Foreground = [System.Windows.Media.Brushes]::Salmon
            }
        }
        
        if ($txtDuration -and $Result.Duration) {
            $txtDuration.Text = "Duration: $($Result.Duration.TotalSeconds.ToString('F1'))s"
        }
        
        # Update buttons
        Update-WizardButtons
        
        # Show toast notification (use try-catch - Get-Command fails in WPF context)
        if ($Result.Success) {
            try { Show-Toast -Message "Created $($Result.RulesCreated) rules in $($Result.Duration.TotalSeconds.ToString('F1'))s" -Type Success } catch { }
        }
    })
}
#endregion

#region ===== UI HELPERS =====
function global:Update-WizardStepIndicators {
    param([int]$Step)
    
    $ind1 = $global:GA_MainWindow.FindName('WizardIndicator1')
    $ind2 = $global:GA_MainWindow.FindName('WizardIndicator2')
    $ind3 = $global:GA_MainWindow.FindName('WizardIndicator3')
    
    # Active = filled, Inactive = outline only
    $activeStyle = 'WizardStepActive'
    $inactiveStyle = 'WizardStepInactive'
    $completedStyle = 'WizardStepCompleted'
    
    # Update indicator styles based on current step
    if ($ind1) {
        $ind1.Tag = if ($Step -eq 1) { 'Active' } elseif ($Step -gt 1) { 'Completed' } else { 'Inactive' }
    }
    if ($ind2) {
        $ind2.Tag = if ($Step -eq 2) { 'Active' } elseif ($Step -gt 2) { 'Completed' } else { 'Inactive' }
    }
    if ($ind3) {
        $ind3.Tag = if ($Step -eq 3) { 'Active' } else { 'Inactive' }
    }
}

function global:Update-WizardButtons {
    $btnBack = $global:GA_MainWindow.FindName('WizardBtnBack')
    $btnNext = $global:GA_MainWindow.FindName('WizardBtnNext')
    $btnCancel = $global:GA_MainWindow.FindName('WizardBtnCancel')
    $btnClose = $global:GA_MainWindow.FindName('WizardBtnClose')
    $btnGenerate = $global:GA_MainWindow.FindName('WizardBtnGenerate')
    
    $step = $script:WizardState.CurrentStep
    $isGenerating = $script:WizardState.IsGenerating
    
    switch ($step) {
        1 {
            if ($btnBack) { $btnBack.Visibility = 'Collapsed' }
            if ($btnNext) { $btnNext.Visibility = 'Visible'; $btnNext.Content = 'Next: Preview' }
            if ($btnCancel) { $btnCancel.Visibility = 'Visible' }
            if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
            if ($btnGenerate) { $btnGenerate.Visibility = 'Collapsed' }
        }
        2 {
            if ($btnBack) { $btnBack.Visibility = 'Visible' }
            if ($btnNext) { $btnNext.Visibility = 'Collapsed' }
            if ($btnCancel) { $btnCancel.Visibility = 'Visible' }
            if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
            if ($btnGenerate) { $btnGenerate.Visibility = 'Visible' }
        }
        3 {
            if ($isGenerating) {
                if ($btnBack) { $btnBack.Visibility = 'Collapsed' }
                if ($btnNext) { $btnNext.Visibility = 'Collapsed' }
                if ($btnCancel) { $btnCancel.Visibility = 'Visible'; $btnCancel.Content = 'Cancel' }
                if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
                if ($btnGenerate) { $btnGenerate.Visibility = 'Collapsed' }
            } else {
                if ($btnBack) { $btnBack.Visibility = 'Collapsed' }
                if ($btnNext) { $btnNext.Visibility = 'Collapsed' }
                if ($btnCancel) { $btnCancel.Visibility = 'Collapsed' }
                if ($btnClose) { $btnClose.Visibility = 'Visible' }
                if ($btnGenerate) { $btnGenerate.Visibility = 'Collapsed' }
            }
        }
    }
}

function global:Close-RuleGenerationWizard {
    <#
    .SYNOPSIS
        Closes the wizard overlay.
    #>
    $wizard = $global:GA_MainWindow.FindName('RuleWizardOverlay')
    if ($wizard) {
        $wizard.Visibility = 'Collapsed'
    }
    
    # Reset state
    $script:WizardState.CurrentStep = 1
    $script:WizardState.IsGenerating = $false
    
    # Always refresh rules panel when wizard closes (rules may have been created)
    # Reset cache to force reload from disk on next query
    try { Reset-RulesIndexCache } catch { }
    
    # Invalidate any cached queries
    try {
        Clear-AppLockerCache -Pattern 'GlobalSearch_*' | Out-Null
        Clear-AppLockerCache -Pattern 'RuleCounts*' | Out-Null
        Clear-AppLockerCache -Pattern 'RuleQuery*' | Out-Null
    } catch { }
    
    # Refresh the rules grid directly
    Update-RulesDataGrid -Window $global:GA_MainWindow
    
    # Refresh dashboard stats and sidebar counts
    Update-DashboardStats -Window $global:GA_MainWindow
    Update-WorkflowBreadcrumb -Window $global:GA_MainWindow
    
    global:Write-Log "Wizard closed"
}

function global:Invoke-WizardNavigation {
    <#
    .SYNOPSIS
        Handles wizard navigation button clicks.
    #>
    param([string]$Direction)
    
    switch ($Direction) {
        'Next' {
            if ($script:WizardState.CurrentStep -eq 1) {
                Show-WizardStep2
            }
        }
        'Back' {
            if ($script:WizardState.CurrentStep -eq 2) {
                Show-WizardStep1
            }
        }
        'Generate' {
            Show-WizardStep3
        }
        'Cancel' {
            Close-RuleGenerationWizard
        }
        'Close' {
            Close-RuleGenerationWizard
        }
    }
}
#endregion

#region ===== BUTTON HANDLERS =====
function global:Invoke-WizardButtonAction {
    <#
    .SYNOPSIS
        Central button dispatcher for wizard buttons.
    #>
    param([string]$ButtonName)
    
    switch ($ButtonName) {
        'WizardBtnNext' { Invoke-WizardNavigation -Direction 'Next' }
        'WizardBtnBack' { Invoke-WizardNavigation -Direction 'Back' }
        'WizardBtnGenerate' { Invoke-WizardNavigation -Direction 'Generate' }
        'WizardBtnCancel' { Invoke-WizardNavigation -Direction 'Cancel' }
        'WizardBtnClose' { Invoke-WizardNavigation -Direction 'Close' }
        default {
            global:Write-Log "Unknown wizard button: $ButtonName" -Level 'WARN'
        }
    }
}
#endregion
