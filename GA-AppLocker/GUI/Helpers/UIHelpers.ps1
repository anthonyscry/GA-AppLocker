#region UI Helper Functions
# UIHelpers.ps1 - Shared UI utility functions

function global:Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}

function global:Show-LoadingOverlay {
    param([string]$Message = 'Processing...', [string]$SubMessage = '')
    
    $win = $global:GA_MainWindow
    if (-not $win) { return }
    
    $overlay = $win.FindName('LoadingOverlay')
    $txtMain = $win.FindName('LoadingText')
    $txtSub = $win.FindName('LoadingSubText')
    
    if ($overlay) { $overlay.Visibility = 'Visible' }
    if ($txtMain) { $txtMain.Text = $Message }
    if ($txtSub) { $txtSub.Text = $SubMessage }
}

function global:Hide-LoadingOverlay {
    $win = $global:GA_MainWindow
    if (-not $win) { return }
    
    $overlay = $win.FindName('LoadingOverlay')
    if ($overlay) { $overlay.Visibility = 'Collapsed' }
}

function global:Update-LoadingText {
    param([string]$Message, [string]$SubMessage)
    
    $win = $global:GA_MainWindow
    if (-not $win) { return }
    
    $txtMain = $win.FindName('LoadingText')
    $txtSub = $win.FindName('LoadingSubText')
    
    if ($txtMain -and $Message) { $txtMain.Text = $Message }
    if ($txtSub -and $SubMessage) { $txtSub.Text = $SubMessage }
}

#endregion
