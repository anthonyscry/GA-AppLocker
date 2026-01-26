#region ===== TOAST NOTIFICATION HELPERS =====
# Show a toast notification in the bottom-right corner
# Using global scope so timer callbacks and closures can access it
function global:Show-Toast {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info',
        [int]$DurationMs = 4000
    )
    
    $Window = $global:GA_MainWindow
    if (-not $Window) { return }
    
    $toastStack = $Window.FindName('ToastStack')
    if (-not $toastStack) { return }
    
    # Create toast border
    $toast = [System.Windows.Controls.Border]::new()
    $toast.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $toast.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
    $toast.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
    
    # Set background color based on type
    $bgColor = switch ($Type) {
        'Success' { '#107C10' }
        'Warning' { '#FF8C00' }
        'Error'   { '#D13438' }
        default   { '#2D2D30' }
    }
    $toast.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($bgColor)
    
    # Add drop shadow
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 10
    $shadow.ShadowDepth = 2
    $shadow.Opacity = 0.3
    $toast.Effect = $shadow
    
    # Create content grid
    $grid = [System.Windows.Controls.Grid]::new()
    $grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $closeCol = [System.Windows.Controls.ColumnDefinition]::new()
    $closeCol.Width = [System.Windows.GridLength]::new(24)
    $grid.ColumnDefinitions.Add($closeCol)
    
    # Icon based on type
    $icon = switch ($Type) {
        'Success' { [char]0x2714 }  # checkmark
        'Warning' { [char]0x26A0 }  # warning
        'Error'   { [char]0x2716 }  # X
        default   { [char]0x2139 }  # info
    }
    
    # Message text
    $text = [System.Windows.Controls.TextBlock]::new()
    $text.Text = "$icon $Message"
    $text.Foreground = [System.Windows.Media.Brushes]::White
    $text.FontSize = 13
    $text.TextWrapping = 'Wrap'
    $text.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($text, 0)
    $grid.Children.Add($text)
    
    # Close button
    $closeBtn = [System.Windows.Controls.Button]::new()
    $closeBtn.Content = [string][char]0x2715
    $closeBtn.Background = [System.Windows.Media.Brushes]::Transparent
    $closeBtn.Foreground = [System.Windows.Media.Brushes]::White
    $closeBtn.BorderThickness = [System.Windows.Thickness]::new(0)
    $closeBtn.FontSize = 14
    $closeBtn.Cursor = [System.Windows.Input.Cursors]::Hand
    $closeBtn.VerticalAlignment = 'Top'
    $closeBtn.HorizontalAlignment = 'Right'
    $closeBtn.Opacity = 0.7
    [System.Windows.Controls.Grid]::SetColumn($closeBtn, 1)
    
    # Close button click removes toast
    $closeBtn.Add_Click({
        param($sender, $e)
        $parentToast = $sender.Parent.Parent
        $stack = $parentToast.Parent
        if ($stack) { $stack.Children.Remove($parentToast) }
    }.GetNewClosure())
    
    $grid.Children.Add($closeBtn)
    $toast.Child = $grid
    
    # Insert at top of stack
    $toastStack.Children.Insert(0, $toast)
    
    # Auto-dismiss timer
    if ($DurationMs -gt 0) {
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds($DurationMs)
        $toastRef = $toast
        $stackRef = $toastStack
        $timer.Add_Tick({
            param($s, $e)
            $s.Stop()
            if ($stackRef.Children.Contains($toastRef)) {
                $stackRef.Children.Remove($toastRef)
            }
        }.GetNewClosure())
        $timer.Start()
    }
    
    Write-Log -Message "Toast shown: [$Type] $Message"
}

# Show loading overlay with spinner
function script:Show-Loading {
    param(
        [string]$Message = 'Loading...',
        [string]$SubMessage = ''
    )
    
    $Window = $global:GA_MainWindow
    if (-not $Window) { return }
    
    $overlay = $Window.FindName('LoadingOverlay')
    $loadingText = $Window.FindName('LoadingText')
    $loadingSubText = $Window.FindName('LoadingSubText')
    $spinner = $Window.FindName('LoadingSpinner')
    
    if ($loadingText) { $loadingText.Text = $Message }
    if ($loadingSubText) { $loadingSubText.Text = $SubMessage }
    if ($overlay) { $overlay.Visibility = 'Visible' }
    
    # Start spinner animation
    if ($spinner) {
        $script:SpinnerTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:SpinnerTimer.Interval = [TimeSpan]::FromMilliseconds(50)
        $spinnerRef = $spinner
        $script:SpinnerTimer.Add_Tick({
            $transform = $spinnerRef.RenderTransform
            if ($transform -is [System.Windows.Media.RotateTransform]) {
                $transform.Angle = ($transform.Angle + 15) % 360
            }
        }.GetNewClosure())
        $script:SpinnerTimer.Start()
    }
    
    Write-Log -Message "Loading overlay shown: $Message"
}

# Hide loading overlay
function script:Hide-Loading {
    $Window = $global:GA_MainWindow
    if (-not $Window) { return }
    
    $overlay = $Window.FindName('LoadingOverlay')
    if ($overlay) { $overlay.Visibility = 'Collapsed' }
    
    # Stop spinner animation
    if ($script:SpinnerTimer) {
        $script:SpinnerTimer.Stop()
        $script:SpinnerTimer = $null
    }
    
    Write-Log -Message "Loading overlay hidden"
}

# Update loading message while overlay is shown
function script:Update-LoadingMessage {
    param(
        [string]$Message,
        [string]$SubMessage
    )
    
    $Window = $global:GA_MainWindow
    if (-not $Window) { return }
    
    $loadingText = $Window.FindName('LoadingText')
    $loadingSubText = $Window.FindName('LoadingSubText')
    
    if ($Message -and $loadingText) { $loadingText.Text = $Message }
    if ($SubMessage -and $loadingSubText) { $loadingSubText.Text = $SubMessage }
}
#endregion
