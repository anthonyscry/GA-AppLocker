#region UI Helper Functions
# UIHelpers.ps1 - Shared UI utility functions

function global:Show-AppLockerMessageBox {
    <#
    .SYNOPSIS
        Testable wrapper around [System.Windows.MessageBox]::Show().
    .DESCRIPTION
        Accepts same positional args as MessageBox.Show(message, title, button, icon).
        In test mode ($global:GA_TestMode), returns 'Yes'/'OK' without showing a dialog.
    #>
    param(
        [Parameter(Position=0)][string]$Message,
        [Parameter(Position=1)][string]$Title = 'GA-AppLocker',
        [Parameter(Position=2)][string]$Button = 'OK',
        [Parameter(Position=3)][string]$Icon = 'Information'
    )
    if ($global:GA_TestMode) {
        if ($Button -eq 'YesNo' -or $Button -eq 'YesNoCancel') { return 'Yes' }
        return 'OK'
    }
    return [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Icon)
}

function global:Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    try {
        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message $Message -Level $Level -NoConsole
        }
    }
    catch {
        # Absolute fallback: if even Get-Command fails (WPF delegate context cmdlet resolution loss),
        # silently swallow — logging must NEVER crash the UI
        try {
            $ts = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
            $fallbackPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'GA-AppLocker', 'Logs')
            if ([System.IO.Directory]::Exists($fallbackPath)) {
                $fallbackFile = [System.IO.Path]::Combine($fallbackPath, "GA-AppLocker_$([DateTime]::Now.ToString('yyyy-MM-dd')).log")
                [System.IO.File]::AppendAllText($fallbackFile, "[$ts] [$Level] $Message`r`n")
            }
        }
        catch { }
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
