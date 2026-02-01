<#
.SYNOPSIS
    Dialog functions for the Rules panel.
.DESCRIPTION
    Contains dialog creation and handling code extracted from Rules.ps1.
    These functions handle popup dialogs for rule history, add-to-policy, etc.
#>

function global:Invoke-ViewRuleHistory {
    <#
    .SYNOPSIS
        Shows the version history for the selected rule.
    #>
    param($Window)
    
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
        $Window,
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
    
    # Add Escape key handler
    $dialog.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq 'Escape') {
            $sender.Close()
        }
    })
    
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
            Show-AppLockerMessageBox 'Please select a version to restore.' 'No Selection' 'OK' 'Warning'
            return
        }
        
        $ver = $selectedItem.Tag
        $confirm = Show-AppLockerMessageBox "Restore rule to version $($ver.Version)?`n`nThis will revert the rule to its state at that version." 'Confirm Restore' 'YesNo' 'Question'
        
        if ($confirm -eq 'Yes') {
            $restoreResult = Restore-RuleVersion -RuleId $script:HistoryRuleId -Version $ver.Version
            if ($restoreResult.Success) {
                Show-AppLockerMessageBox 'Rule restored successfully.' 'Restored' 'OK' 'Information'
                $dialog.Close()
                # Refresh rules grid
                Update-RulesDataGrid -Window $global:GA_MainWindow -Async
            }
            else {
                Show-AppLockerMessageBox "Restore failed: $($restoreResult.Error)" 'Error' 'OK' 'Error'
            }
        }
    }.GetNewClosure())
    
    # Compare button handler
    $btnCompare.Add_Click({
        if ($versionsList.Items.Count -lt 2) {
            Show-AppLockerMessageBox 'Need at least 2 versions to compare.' 'Cannot Compare' 'OK' 'Information'
            return
        }
        
        $selectedItem = $versionsList.SelectedItem
        if (-not $selectedItem -or -not $selectedItem.Tag) {
            Show-AppLockerMessageBox 'Select a version to compare with the current rule.' 'No Selection' 'OK' 'Warning'
            return
        }
        
        $ver = $selectedItem.Tag
        $compareResult = Compare-RuleVersions -RuleId $script:HistoryRuleId -Version1 $ver.Version
        
        if ($compareResult.Success) {
            if ($compareResult.Differences.Count -eq 0) {
                Show-AppLockerMessageBox "No differences between version $($ver.Version) and current rule." 'No Differences' 'OK' 'Information'
            }
            else {
                $diffText = "Differences between v$($ver.Version) and Current:`n`n"
                foreach ($diff in $compareResult.Differences) {
                    $diffText += "$($diff.Property):`n"
                    $diffText += "  v$($ver.Version): $($diff.Version1Value)`n"
                    $diffText += "  Current: $($diff.Version2Value)`n`n"
                }
                Show-AppLockerMessageBox $diffText 'Version Comparison' 'OK' 'Information'
            }
        }
        else {
            Show-AppLockerMessageBox "Compare failed: $($compareResult.Error)" 'Error' 'OK' 'Error'
        }
    }.GetNewClosure())
    
    # Close button
    $btnClose.Add_Click({
        $dialog.Close()
    }.GetNewClosure())
    
    [void]$dialog.ShowDialog()
}

function global:Show-AddRulesToPolicyDialog {
    <#
    .SYNOPSIS
        Shows dialog to select a policy and add rules to it.
    .DESCRIPTION
        Creates and shows a dialog for selecting a policy to add rules to.
        Returns the selected policy ID or $null if cancelled.
    #>
    param(
        $Window,
        [array]$SelectedRules,
        [array]$Policies
    )
    
    # Create selection dialog
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = "Add $($SelectedRules.Count) Rule(s) to Policy"
    $dialog.Width = 420
    $dialog.Height = 340
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.Owner = $Window
    $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1E1E1E')
    $dialog.ResizeMode = 'NoResize'

    # Add Escape key handler
    $dialog.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq 'Escape') {
            $sender.Close()
        }
    })

    $stack = [System.Windows.Controls.StackPanel]::new()
    $stack.Margin = [System.Windows.Thickness]::new(20)

    # Label
    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = "Select a policy to add $($SelectedRules.Count) rule(s):"
    $label.Foreground = [System.Windows.Media.Brushes]::White
    $label.FontSize = 14
    $label.Margin = [System.Windows.Thickness]::new(0, 0, 0, 15)
    $stack.Children.Add($label)

    # Policy ListBox
    $listBox = [System.Windows.Controls.ListBox]::new()
    $listBox.Height = 160
    $listBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2D2D30')
    $listBox.Foreground = [System.Windows.Media.Brushes]::White
    $listBox.BorderThickness = [System.Windows.Thickness]::new(1)
    $listBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')

    foreach ($policy in $Policies) {
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $item.Content = "$($policy.Name) (Phase $($policy.Phase)) - $($policy.Status)"
        $item.Tag = $policy.PolicyId
        $item.Foreground = [System.Windows.Media.Brushes]::White
        $item.Padding = [System.Windows.Thickness]::new(5, 3, 5, 3)
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
    $dialogRef = $dialog

    $btnAdd.Add_Click({
        if ($listBoxRef.SelectedItem) {
            $dialogRef.DialogResult = $true
            $dialogRef.Close()
        }
        else {
            Show-Toast -Message 'Please select a policy.' -Type 'Warning'
        }
    }.GetNewClosure())

    $btnCancel.Add_Click({
        $dialogRef.DialogResult = $false
        $dialogRef.Close()
    }.GetNewClosure())

    $result = $dialog.ShowDialog()
    
    if ($result -eq $true -and $listBox.SelectedItem) {
        return [string]$listBox.SelectedItem.Tag
    }
    return $null
}

function global:Show-RuleDetailsDialog {
    <#
    .SYNOPSIS
        Shows details of a selected rule in a message box.
    #>
    param(
        $Window,
        [PSCustomObject]$Rule
    )
    
    if (-not $Rule) {
        Show-Toast -Message 'Please select a rule to view details.' -Type 'Warning'
        return
    }

    $details = @"
Rule Details
============

ID: $($Rule.RuleId)
Name: $($Rule.Name)
Type: $($Rule.RuleType)
Action: $($Rule.Action)
Status: $($Rule.Status)
Collection: $($Rule.Collection)
Rule Collection: $($Rule.RuleCollection)

Description:
$($Rule.Description)

Created: $($Rule.CreatedAt)
Modified: $($Rule.ModifiedAt)

Condition Data:
$($Rule | Select-Object -Property Publisher*, Hash*, Path* | Format-List | Out-String)
"@

    Show-AppLockerMessageBox $details.Trim() 'Rule Details' 'OK' 'Information'
}
