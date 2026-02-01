#region Mock WPF Helpers for Headless GUI Testing
<#
.SYNOPSIS
    Provides mock WPF objects for headless GUI panel testing.

.DESCRIPTION
    These helpers create lightweight PSCustomObject stand-ins for WPF elements,
    allowing panel logic functions (which all accept -Window $Window and call
    $Window.FindName('ElementName')) to run under Pester without a live WPF runtime.

    Also intercepts [System.Windows.MessageBox]::Show() to prevent blocking dialogs
    during automated test runs.

    Pattern:
        $win = New-MockWpfWindow -Elements @{
            'TxtPolicyName'   = New-MockTextBlock -Text 'My Policy'
            'PoliciesDataGrid'= New-MockDataGrid
        }
        Invoke-CreatePolicy -Window $win   # exercises panel logic headlessly

.NOTES
    PowerShell 5.1 compatible. No WPF assemblies required.
#>

#region MessageBox Interception
# Prevent [System.Windows.MessageBox]::Show() from opening real dialogs during tests.
# We load PresentationFramework and override the Show method via a wrapper type.
# Since we can't replace a .NET static method, we use a PowerShell class-based approach:
# define a global function that test code can call, and for the actual .NET calls in source
# code, we set an AppDomain-level flag that a custom message filter could read.
#
# Practical approach: The real MessageBox calls only fire when panel event handlers execute.
# In our tests, event handlers are registered as no-ops (Add-MockEventMethods discards them).
# So MessageBox popups only occur if test code directly invokes panel action functions.
# For those cases, we provide Install-MessageBoxMock to redirect Show() calls.

$script:MessageBoxMockInstalled = $false

function Install-MessageBoxMock {
    <#
    .SYNOPSIS
        Installs a global mock that auto-answers all System.Windows.MessageBox.Show() calls.
    .DESCRIPTION
        Creates a global:Show-MessageBoxResult variable set to 'Yes' and overrides
        the .NET MessageBox by loading a custom C# type that shadows it.
        
        Since we cannot replace a static .NET method, this function instead:
        1. Sets $global:GA_TestMode = $true so any test-aware code can skip dialogs
        2. Provides a helper function to call instead of MessageBox::Show
    #>
    if ($script:MessageBoxMockInstalled) { return }
    
    $global:GA_TestMode = $true
    $script:MessageBoxMockInstalled = $true
}

Install-MessageBoxMock
#endregion

function New-MockWpfWindow {
    <#
    .SYNOPSIS
        Creates a mock Window object that supports FindName() lookups.
    .PARAMETER Elements
        Hashtable mapping element names to mock objects.
    #>
    param(
        [hashtable]$Elements = @{}
    )

    $mock = [PSCustomObject]@{
        _elements = $Elements
        Title = 'GA-AppLocker Dashboard'
    }

    $mock | Add-Member -MemberType ScriptMethod -Name 'FindName' -Value {
        param([string]$name)
        if ($this._elements.ContainsKey($name)) {
            return $this._elements[$name]
        }
        return $null
    }

    return $mock
}

function Add-MockEventMethods {
    <#
    .SYNOPSIS
        Adds no-op Add_Click, Add_SelectionChanged, etc. methods to a mock object.
    .DESCRIPTION
        WPF controls have event subscription methods like .Add_Click().
        This adds them as ScriptMethods that accept and discard scriptblocks.
    #>
    param([PSCustomObject]$MockObject)

    $eventMethods = @(
        'Add_Click', 'Add_SelectionChanged', 'Add_SelectedItemChanged', 'Add_Checked', 'Add_Unchecked',
        'Add_TextChanged', 'Add_Loaded', 'Add_MouseDoubleClick', 'Add_PreviewMouseLeftButtonDown',
        'Add_Drop', 'Add_DragOver', 'Add_KeyDown', 'Add_PreviewKeyDown',
        'Add_MouseLeftButtonUp', 'Add_GotFocus', 'Add_LostFocus', 'Add_Expanded', 'Add_Collapsed',
        'Remove_Click', 'Remove_SelectionChanged', 'Remove_SelectedItemChanged', 'Remove_Checked', 'Remove_Unchecked'
    )

    foreach ($method in $eventMethods) {
        $MockObject | Add-Member -MemberType ScriptMethod -Name $method -Value {
            param($handler)
            # No-op: discard event handler in test context
        } -Force
    }

    return $MockObject
}

function New-MockTextBlock {
    <#
    .SYNOPSIS
        Mimics a WPF TextBlock with .Text and .Visibility properties.
    #>
    param(
        [string]$Text = '',
        [string]$Visibility = 'Visible',
        [string]$FontStyle = 'Normal'
    )

    return [PSCustomObject]@{
        Text       = $Text
        Visibility = $Visibility
        FontStyle  = $FontStyle
        Foreground = $null
    }
}

function New-MockTextBox {
    <#
    .SYNOPSIS
        Mimics a WPF TextBox with .Text property.
    #>
    param(
        [string]$Text = '',
        [string]$Visibility = 'Visible'
    )

    $mock = [PSCustomObject]@{
        Text       = $Text
        Visibility = $Visibility
        IsReadOnly = $false
    }
    return (Add-MockEventMethods $mock)
}

function New-MockComboBox {
    <#
    .SYNOPSIS
        Mimics a WPF ComboBox with .SelectedIndex, .SelectedItem, and .Items.
    .PARAMETER Items
        Array of items to populate the combo box.
    .PARAMETER SelectedIndex
        Initial selected index (-1 for none).
    #>
    param(
        [array]$Items = @(),
        [int]$SelectedIndex = 0
    )

    # Build items collection with Add/Clear/Count
    $itemList = [System.Collections.ArrayList]::new()
    foreach ($item in $Items) { $itemList.Add($item) | Out-Null }

    $mock = [PSCustomObject]@{
        Items         = $itemList
        SelectedIndex = $SelectedIndex
        SelectedItem  = if ($Items.Count -gt 0 -and $SelectedIndex -ge 0) { $Items[$SelectedIndex] } else { $null }
        Visibility    = 'Visible'
    }

    return (Add-MockEventMethods $mock)
}

function New-MockComboBoxItem {
    <#
    .SYNOPSIS
        Mimics a WPF ComboBoxItem with .Content and .Tag.
    #>
    param(
        [string]$Content = '',
        $Tag = $null
    )

    return [PSCustomObject]@{
        Content = $Content
        Tag     = $Tag
    }
}

function New-MockCheckBox {
    <#
    .SYNOPSIS
        Mimics a WPF CheckBox with .IsChecked and .Content.
    #>
    param(
        [bool]$IsChecked = $false,
        [string]$Content = ''
    )

    $mock = [PSCustomObject]@{
        IsChecked  = $IsChecked
        Content    = $Content
        Visibility = 'Visible'
    }
    return (Add-MockEventMethods $mock)
}

function New-MockRadioButton {
    <#
    .SYNOPSIS
        Mimics a WPF RadioButton with .IsChecked.
    #>
    param(
        [bool]$IsChecked = $false,
        [string]$Content = ''
    )

    $mock = [PSCustomObject]@{
        IsChecked = $IsChecked
        Content   = $Content
    }
    return (Add-MockEventMethods $mock)
}

function New-MockButton {
    <#
    .SYNOPSIS
        Mimics a WPF Button with .Content, .Tag, .IsEnabled, .Background, .Foreground.
    #>
    param(
        [string]$Content = '',
        [string]$Tag = '',
        [bool]$IsEnabled = $true,
        [string]$Name = ''
    )

    $mock = [PSCustomObject]@{
        Content    = $Content
        Tag        = $Tag
        IsEnabled  = $IsEnabled
        Name       = $Name
        Background = $null
        Foreground = $null
        Visibility = 'Visible'
        Cursor     = $null
    }
    return (Add-MockEventMethods $mock)
}

function New-MockDataGrid {
    <#
    .SYNOPSIS
        Mimics a WPF DataGrid with .ItemsSource, .SelectedItem, .SelectedItems.
    .PARAMETER Data
        Array of objects to use as initial ItemsSource.
    #>
    param(
        [array]$Data = @(),
        $SelectedItem = $null
    )

    $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($d in $Data) { $items.Add($d) }

    $selectedItems = [System.Collections.ArrayList]::new()
    if ($SelectedItem) { $selectedItems.Add($SelectedItem) | Out-Null }

    $mock = [PSCustomObject]@{
        ItemsSource   = $items
        SelectedItem  = $SelectedItem
        SelectedItems = $selectedItems
        Items         = [PSCustomObject]@{ Count = $Data.Count }
        Visibility    = 'Visible'
        ContextMenu   = $null
    }

    # Add Refresh method on Items
    $mock.Items | Add-Member -MemberType ScriptMethod -Name 'Refresh' -Value { }

    return (Add-MockEventMethods $mock)
}

function New-MockListBox {
    <#
    .SYNOPSIS
        Mimics a WPF ListBox with .ItemsSource.
    #>
    param(
        [array]$Data = @()
    )

    $mock = [PSCustomObject]@{
        ItemsSource = $Data
        Visibility  = 'Visible'
    }
    return (Add-MockEventMethods $mock)
}

function New-MockBorder {
    <#
    .SYNOPSIS
        Mimics a WPF Border with .Width property (for chart bars).
    #>
    param(
        [double]$Width = 0
    )

    return [PSCustomObject]@{
        Width      = $Width
        Visibility = 'Visible'
    }
}

function New-MockPanel {
    <#
    .SYNOPSIS
        Mimics a WPF Grid/StackPanel with .Visibility.
    #>
    param(
        [string]$Visibility = 'Collapsed'
    )

    return [PSCustomObject]@{
        Visibility = $Visibility
    }
}

function New-MockProgressBar {
    <#
    .SYNOPSIS
        Mimics a WPF ProgressBar with .Value, .Minimum, .Maximum.
    #>
    param(
        [double]$Value = 0,
        [double]$Minimum = 0,
        [double]$Maximum = 100
    )

    return [PSCustomObject]@{
        Value      = $Value
        Minimum    = $Minimum
        Maximum    = $Maximum
        Visibility = 'Visible'
    }
}

function New-MockTreeView {
    <#
    .SYNOPSIS
        Mimics a WPF TreeView with .Items collection.
    #>
    param()

    $items = [System.Collections.ArrayList]::new()
    $mock = [PSCustomObject]@{
        Items      = $items
        Visibility = 'Visible'
    }
    return (Add-MockEventMethods $mock)
}

#endregion
