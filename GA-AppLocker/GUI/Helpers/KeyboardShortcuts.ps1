<#
.SYNOPSIS
    Keyboard shortcuts handler for GA-AppLocker Dashboard.

.DESCRIPTION
    Implements keyboard shortcuts for efficient navigation and common actions.
    
    Navigation (Ctrl+Number):
        Ctrl+1 = Dashboard
        Ctrl+2 = AD Discovery
        Ctrl+3 = Scanner
        Ctrl+4 = Rules
        Ctrl+5 = Policy
        Ctrl+6 = Deploy
        Ctrl+7 = Settings
        Ctrl+8 = Setup
        Ctrl+9 = About
    
    Actions:
        F5 = Refresh current panel
        Ctrl+R = Refresh current panel
        Ctrl+F = Focus search box (if available)
        Ctrl+S = Save (context-dependent)
        Ctrl+E = Export (context-dependent)
        Ctrl+N = New item (context-dependent)
        Ctrl+A = Select All (in data grids)
        Escape = Cancel/Close dialogs
        Delete = Delete selected items

.NOTES
    Load this file in MainWindow.xaml.ps1 and call Register-KeyboardShortcuts
    after the window is created.
#>

#region ===== KEYBOARD SHORTCUT REGISTRATION =====

function Register-KeyboardShortcuts {
    <#
    .SYNOPSIS
        Registers keyboard shortcuts on the main window.

    .PARAMETER Window
        The WPF Window to register shortcuts on.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    # Add PreviewKeyDown handler for global shortcuts
    $Window.add_PreviewKeyDown({
        param($sender, $e)
        
        $handled = Invoke-KeyboardShortcut -Window $sender -KeyEventArgs $e
        if ($handled) {
            $e.Handled = $true
        }
    })

    Write-Log -Message "Keyboard shortcuts registered"
}

function global:Invoke-KeyboardShortcut {
    <#
    .SYNOPSIS
        Processes keyboard input and triggers appropriate actions.

    .PARAMETER Window
        The main window.

    .PARAMETER KeyEventArgs
        The key event arguments.

    .RETURNS
        $true if the key was handled, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        $KeyEventArgs
    )

    $key = $KeyEventArgs.Key
    $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
    $shift = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift
    $alt = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Alt

    # Don't capture shortcuts when typing in text boxes
    $focusedElement = [System.Windows.Input.Keyboard]::FocusedElement
    if ($focusedElement -is [System.Windows.Controls.TextBox] -or 
        $focusedElement -is [System.Windows.Controls.PasswordBox]) {
        # Allow only Escape and F5 in text boxes
        if ($key -notin @([System.Windows.Input.Key]::Escape, [System.Windows.Input.Key]::F5)) {
            return $false
        }
    }

    #region Ctrl+Number Navigation
    if ($ctrl -and -not $shift -and -not $alt) {
        switch ($key) {
            { $_ -eq [System.Windows.Input.Key]::D1 -or $_ -eq [System.Windows.Input.Key]::NumPad1 } {
                Invoke-ButtonAction -Action 'NavDashboard'
                Show-ShortcutToast -Message "Dashboard (Ctrl+1)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D2 -or $_ -eq [System.Windows.Input.Key]::NumPad2 } {
                Invoke-ButtonAction -Action 'NavDiscovery'
                Show-ShortcutToast -Message "AD Discovery (Ctrl+2)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D3 -or $_ -eq [System.Windows.Input.Key]::NumPad3 } {
                Invoke-ButtonAction -Action 'NavScanner'
                Show-ShortcutToast -Message "Scanner (Ctrl+3)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D4 -or $_ -eq [System.Windows.Input.Key]::NumPad4 } {
                Invoke-ButtonAction -Action 'NavRules'
                Show-ShortcutToast -Message "Rules (Ctrl+4)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D5 -or $_ -eq [System.Windows.Input.Key]::NumPad5 } {
                Invoke-ButtonAction -Action 'NavPolicy'
                Show-ShortcutToast -Message "Policy (Ctrl+5)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D6 -or $_ -eq [System.Windows.Input.Key]::NumPad6 } {
                Invoke-ButtonAction -Action 'NavDeploy'
                Show-ShortcutToast -Message "Deploy (Ctrl+6)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D7 -or $_ -eq [System.Windows.Input.Key]::NumPad7 } {
                Invoke-ButtonAction -Action 'NavSettings'
                Show-ShortcutToast -Message "Settings (Ctrl+7)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D8 -or $_ -eq [System.Windows.Input.Key]::NumPad8 } {
                Invoke-ButtonAction -Action 'NavSetup'
                Show-ShortcutToast -Message "Setup (Ctrl+8)"
                return $true
            }
            { $_ -eq [System.Windows.Input.Key]::D9 -or $_ -eq [System.Windows.Input.Key]::NumPad9 } {
                Invoke-ButtonAction -Action 'NavAbout'
                Show-ShortcutToast -Message "About (Ctrl+9)"
                return $true
            }
        }
    }
    #endregion

    #region Ctrl+Letter Shortcuts
    if ($ctrl -and -not $shift -and -not $alt) {
        switch ($key) {
            ([System.Windows.Input.Key]::R) {
                # Ctrl+R = Refresh
                Invoke-PanelRefresh -Window $Window
                return $true
            }
            ([System.Windows.Input.Key]::F) {
                # Ctrl+F = Focus search
                Invoke-FocusSearch -Window $Window
                return $true
            }
            ([System.Windows.Input.Key]::S) {
                # Ctrl+S = Save
                Invoke-ContextSave -Window $Window
                return $true
            }
            ([System.Windows.Input.Key]::E) {
                # Ctrl+E = Export
                Invoke-ContextExport -Window $Window
                return $true
            }
            ([System.Windows.Input.Key]::N) {
                # Ctrl+N = New
                Invoke-ContextNew -Window $Window
                return $true
            }
            ([System.Windows.Input.Key]::A) {
                # Ctrl+A = Select All (only in data grid context)
                Invoke-SelectAllInGrid -Window $Window
                return $true
            }
        }
    }
    #endregion

    #region Function Keys
    switch ($key) {
        ([System.Windows.Input.Key]::F5) {
            # F5 = Refresh
            Invoke-PanelRefresh -Window $Window
            return $true
        }
        ([System.Windows.Input.Key]::F1) {
            # F1 = Help/About
            Invoke-ButtonAction -Action 'NavAbout'
            return $true
        }
    }
    #endregion

    #region Escape and Delete
    switch ($key) {
        ([System.Windows.Input.Key]::Escape) {
            # Escape = Close dialogs or cancel operations
            Invoke-CancelOrClose -Window $Window
            return $true
        }
        ([System.Windows.Input.Key]::Delete) {
            # Delete = Delete selected items (with confirmation)
            if (-not $ctrl) {
                Invoke-DeleteSelected -Window $Window
                return $true
            }
        }
    }
    #endregion

    #region Rules Panel Shortcuts (when not in textbox - already filtered above)
    $currentPanel = $script:CurrentActivePanel
    if ($currentPanel -eq 'PanelRules' -and -not $ctrl -and -not $shift -and -not $alt) {
        switch ($key) {
            ([System.Windows.Input.Key]::A) {
                # A = Approve selected rules
                Invoke-RuleShortcutAction -Window $Window -Action 'Approve'
                return $true
            }
            ([System.Windows.Input.Key]::R) {
                # R = Reject selected rules
                Invoke-RuleShortcutAction -Window $Window -Action 'Reject'
                return $true
            }
            ([System.Windows.Input.Key]::V) {
                # V = Review (set to pending review)
                Invoke-RuleShortcutAction -Window $Window -Action 'Review'
                return $true
            }
            ([System.Windows.Input.Key]::P) {
                # P = Add to Policy
                Invoke-RuleShortcutAction -Window $Window -Action 'AddToPolicy'
                return $true
            }
            ([System.Windows.Input.Key]::D) {
                # D = View Details
                Invoke-RuleShortcutAction -Window $Window -Action 'ViewDetails'
                return $true
            }
            ([System.Windows.Input.Key]::G) {
                # G = Generate rules (open wizard)
                Invoke-ButtonAction -Action 'GenerateFromArtifacts'
                Show-ShortcutToast -Message "Rule Generation Wizard"
                return $true
            }
        }
    }
    #endregion

    #region Scanner Panel Shortcuts
    if ($currentPanel -eq 'PanelScanner' -and -not $ctrl -and -not $shift -and -not $alt) {
        switch ($key) {
            ([System.Windows.Input.Key]::S) {
                # S = Start scan
                Invoke-ButtonAction -Action 'StartScan'
                Show-ShortcutToast -Message "Starting scan..."
                return $true
            }
        }
    }
    #endregion

    #region Policy Panel Shortcuts
    if ($currentPanel -eq 'PanelPolicy' -and -not $ctrl -and -not $shift -and -not $alt) {
        switch ($key) {
            ([System.Windows.Input.Key]::X) {
                # X = Export policy to XML
                Invoke-ButtonAction -Action 'ExportPolicy'
                return $true
            }
        }
    }
    #endregion

    return $false
}

#endregion

#region ===== CONTEXT-AWARE ACTIONS =====

function Invoke-PanelRefresh {
    <#
    .SYNOPSIS
        Refreshes the current active panel.
    #>
    param([System.Windows.Window]$Window)

    $currentPanel = $script:CurrentActivePanel
    
    switch ($currentPanel) {
        'PanelDashboard' {
            # Dashboard auto-refreshes, but trigger manual refresh
            Update-DashboardStats -Window $Window -Async
            Show-ShortcutToast -Message "Dashboard refreshed"
        }
        'PanelDiscovery' {
            Invoke-ButtonAction -Action 'RefreshDomain'
            Show-ShortcutToast -Message "Refreshing AD Discovery..."
        }
        'PanelScanner' {
            Invoke-ButtonAction -Action 'RefreshScans'
            Show-ShortcutToast -Message "Scans list refreshed"
        }
        'PanelRules' {
            Invoke-ButtonAction -Action 'RefreshRules'
            Show-ShortcutToast -Message "Rules refreshed"
        }
        'PanelPolicy' {
            Invoke-ButtonAction -Action 'RefreshPolicies'
            Show-ShortcutToast -Message "Policies refreshed"
        }
        'PanelDeploy' {
            Invoke-ButtonAction -Action 'RefreshDeployments'
            Show-ShortcutToast -Message "Deployments refreshed"
        }
        'PanelSettings' {
            Show-ShortcutToast -Message "Settings panel"
        }
        'PanelCredentials' {
            Invoke-ButtonAction -Action 'RefreshCredentials'
            Show-ShortcutToast -Message "Credentials refreshed"
        }
        default {
            Show-ShortcutToast -Message "Refresh not available"
        }
    }
}

function Invoke-FocusSearch {
    <#
    .SYNOPSIS
        Focuses the search box in the current panel if available.
    #>
    param([System.Windows.Window]$Window)

    $currentPanel = $script:CurrentActivePanel
    $searchBoxName = $null

    switch ($currentPanel) {
        'PanelRules' { $searchBoxName = 'RulesSearchBox' }
        'PanelPolicy' { $searchBoxName = 'PolicySearchBox' }
        'PanelScanner' { $searchBoxName = 'ArtifactSearchBox' }
        'PanelDiscovery' { $searchBoxName = 'MachineSearchBox' }
    }

    if ($searchBoxName) {
        $searchBox = $Window.FindName($searchBoxName)
        if ($searchBox) {
            $searchBox.Focus()
            $searchBox.SelectAll()
            Show-ShortcutToast -Message "Search (Ctrl+F)"
            return
        }
    }

    Show-ShortcutToast -Message "No search available"
}

function Invoke-ContextSave {
    <#
    .SYNOPSIS
        Saves in the current context (policy changes, credentials, etc).
    #>
    param([System.Windows.Window]$Window)

    $currentPanel = $script:CurrentActivePanel

    switch ($currentPanel) {
        'PanelPolicy' {
            if ($script:SelectedPolicyId) {
                Invoke-ButtonAction -Action 'SavePolicyChanges'
                Show-ShortcutToast -Message "Policy saved"
            }
            else {
                Show-ShortcutToast -Message "No policy selected"
            }
        }
        'PanelCredentials' {
            Invoke-ButtonAction -Action 'SaveCredential'
            Show-ShortcutToast -Message "Credential saved"
        }
        'PanelSettings' {
            # Settings auto-save, but could trigger explicit save
            Show-ShortcutToast -Message "Settings auto-saved"
        }
        default {
            Show-ShortcutToast -Message "Nothing to save"
        }
    }
}

function Invoke-ContextExport {
    <#
    .SYNOPSIS
        Exports data from the current panel.
    #>
    param([System.Windows.Window]$Window)

    $currentPanel = $script:CurrentActivePanel

    switch ($currentPanel) {
        'PanelRules' {
            Invoke-ButtonAction -Action 'ExportRulesXml'
            # Toast handled by export function
        }
        'PanelPolicy' {
            Invoke-ButtonAction -Action 'ExportPolicy'
        }
        'PanelScanner' {
            Invoke-ButtonAction -Action 'ExportArtifacts'
        }
        default {
            Show-ShortcutToast -Message "Export not available"
        }
    }
}

function Invoke-ContextNew {
    <#
    .SYNOPSIS
        Creates new item in the current panel context.
    #>
    param([System.Windows.Window]$Window)

    $currentPanel = $script:CurrentActivePanel

    switch ($currentPanel) {
        'PanelRules' {
            Invoke-ButtonAction -Action 'CreateManualRule'
        }
        'PanelPolicy' {
            Invoke-ButtonAction -Action 'CreatePolicy'
        }
        'PanelCredentials' {
            # Focus credential form for new entry
            $usernameBox = $Window.FindName('CredentialUsername')
            if ($usernameBox) {
                $usernameBox.Focus()
                Show-ShortcutToast -Message "New credential"
            }
        }
        'PanelScanner' {
            Invoke-ButtonAction -Action 'StartScan'
        }
        'PanelDeploy' {
            Invoke-ButtonAction -Action 'CreateDeploymentJob'
        }
        default {
            Show-ShortcutToast -Message "New not available"
        }
    }
}

function Invoke-SelectAllInGrid {
    <#
    .SYNOPSIS
        Selects all items in the current panel's data grid.
    #>
    param([System.Windows.Window]$Window)

    $currentPanel = $script:CurrentActivePanel
    $gridName = $null

    switch ($currentPanel) {
        'PanelRules' { $gridName = 'RulesDataGrid' }
        'PanelPolicy' { $gridName = 'PolicyRulesDataGrid' }
        'PanelScanner' { $gridName = 'ArtifactsDataGrid' }
        'PanelDiscovery' { $gridName = 'MachinesDataGrid' }
        'PanelDeploy' { $gridName = 'DeploymentJobsDataGrid' }
    }

    if ($gridName) {
        $grid = $Window.FindName($gridName)
        if ($grid -and $grid.Items.Count -gt 0) {
            $grid.SelectAll()
            Show-ShortcutToast -Message "Selected all ($($grid.Items.Count) items)"
            return
        }
    }

    Show-ShortcutToast -Message "No items to select"
}

function Invoke-CancelOrClose {
    <#
    .SYNOPSIS
        Cancels current operation or closes dialogs.
    #>
    param([System.Windows.Window]$Window)

    # Check for loading overlay
    $overlay = $Window.FindName('LoadingOverlay')
    if ($overlay -and $overlay.Visibility -eq 'Visible') {
        # Cancel ongoing operation if possible
        if ($script:ScanInProgress) {
            Invoke-ButtonAction -Action 'StopScan'
            return
        }
        if ($script:DeploymentInProgress) {
            Invoke-ButtonAction -Action 'StopDeployment'
            return
        }
    }

    # Clear search boxes
    $currentPanel = $script:CurrentActivePanel
    $searchBoxName = switch ($currentPanel) {
        'PanelRules' { 'RulesSearchBox' }
        'PanelPolicy' { 'PolicySearchBox' }
        'PanelScanner' { 'ArtifactSearchBox' }
        'PanelDiscovery' { 'MachineSearchBox' }
        default { $null }
    }

    if ($searchBoxName) {
        $searchBox = $Window.FindName($searchBoxName)
        if ($searchBox -and $searchBox.Text) {
            $searchBox.Clear()
            Show-ShortcutToast -Message "Search cleared"
            return
        }
    }

    # Clear selection in grids
    $gridName = switch ($currentPanel) {
        'PanelRules' { 'RulesDataGrid' }
        'PanelPolicy' { 'PoliciesDataGrid' }
        'PanelScanner' { 'ArtifactsDataGrid' }
        default { $null }
    }

    if ($gridName) {
        $grid = $Window.FindName($gridName)
        if ($grid -and $grid.SelectedItems.Count -gt 0) {
            $grid.UnselectAll()
            Show-ShortcutToast -Message "Selection cleared"
            return
        }
    }
}

function Invoke-DeleteSelected {
    <#
    .SYNOPSIS
        Deletes selected items with confirmation.
    #>
    param([System.Windows.Window]$Window)

    $currentPanel = $script:CurrentActivePanel

    switch ($currentPanel) {
        'PanelRules' {
            Invoke-ButtonAction -Action 'DeleteRule'
        }
        'PanelPolicy' {
            Invoke-ButtonAction -Action 'DeletePolicy'
        }
        'PanelScanner' {
            Invoke-ButtonAction -Action 'DeleteScan'
        }
        'PanelCredentials' {
            Invoke-ButtonAction -Action 'DeleteCredential'
        }
        'PanelDeploy' {
            Invoke-ButtonAction -Action 'CancelDeploymentJob'
        }
        default {
            Show-ShortcutToast -Message "Delete not available"
        }
    }
}

#endregion

#region ===== TOAST NOTIFICATION FOR SHORTCUTS =====

function Show-ShortcutToast {
    <#
    .SYNOPSIS
        Shows a brief toast notification for keyboard shortcut feedback.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    # Use the existing toast system if available
    if (Get-Command -Name 'Show-Toast' -ErrorAction SilentlyContinue) {
        Show-Toast -Message $Message -Type 'Info' -Duration 1500
    }
    else {
        # Fallback: log only
        Write-Log -Message "Shortcut: $Message"
    }
}

#endregion

#region ===== KEYBOARD SHORTCUT HELP =====

function Get-KeyboardShortcuts {
    <#
    .SYNOPSIS
        Returns a list of all available keyboard shortcuts.
    
    .OUTPUTS
        Array of shortcut definitions for help display.
    #>
    return @(
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+1'; Action = 'Dashboard' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+2'; Action = 'AD Discovery' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+3'; Action = 'Scanner' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+4'; Action = 'Rules' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+5'; Action = 'Policy' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+6'; Action = 'Deploy' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+7'; Action = 'Settings' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+8'; Action = 'Setup' }
        [PSCustomObject]@{ Category = 'Navigation'; Shortcut = 'Ctrl+9'; Action = 'About' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'F5'; Action = 'Refresh current panel' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Ctrl+R'; Action = 'Refresh current panel' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Ctrl+F'; Action = 'Focus search box' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Ctrl+S'; Action = 'Save' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Ctrl+E'; Action = 'Export' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Ctrl+N'; Action = 'New item' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Ctrl+A'; Action = 'Select all' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Escape'; Action = 'Cancel/Clear' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'Delete'; Action = 'Delete selected' }
        [PSCustomObject]@{ Category = 'Actions'; Shortcut = 'F1'; Action = 'Help/About' }
    )
}

#endregion
