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

    # Keep dialogs owned by the main window to avoid "hidden modal" states
    # (common after minimize/restore in VM/RDP sessions).
    try {
        $owner = $global:GA_MainWindow
        $mbButton = [System.Windows.MessageBoxButton]::$Button
        $mbIcon = [System.Windows.MessageBoxImage]::$Icon

        if ($owner) {
            try {
                if ($owner.WindowState -eq 'Minimized') { $owner.WindowState = 'Normal' }
                $owner.Activate() | Out-Null
            }
            catch {
                Write-AppLockerLog -Message "[UIHelpers] Failed to restore/activate owner window: $_" -Level DEBUG
            }

            $result = [System.Windows.MessageBox]::Show($owner, $Message, $Title, $mbButton, $mbIcon)
        }
        else {
            $result = [System.Windows.MessageBox]::Show($Message, $Title, $mbButton, $mbIcon)
        }

        return [string]$result
    }
    catch {
        # Fallback for unexpected enum/owner issues
        return [string][System.Windows.MessageBox]::Show($Message, $Title, $Button, $Icon)
    }
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

function global:Request-UiRender {
    param($Window)

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    try {
        $win.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Render,
            [Action]{
                $win.InvalidateVisual()
                $win.UpdateLayout()
            }
        ) | Out-Null
    }
    catch {
        Write-AppLockerLog -Message "[UIHelpers] Failed to request UI render via dispatcher: $_" -Level DEBUG
    }
}

#endregion

#region Background Work Engine
<#
.SYNOPSIS
    Centralized background work system for all long-running operations.
.DESCRIPTION
    Replaces all ad-hoc runspace + DispatcherTimer patterns with a single reliable engine.
    Design principles:
      - ALL state stored in $global:GA_BackgroundJobs (no $script: in callbacks)
      - ONE shared DispatcherTimer monitors all jobs (no per-job timers)
      - NO .GetNewClosure() on the timer tick (avoids PS scope bugs)
      - Bare MTA runspaces with NO module imports (fast startup)
      - OnComplete callbacks run on the UI thread and receive results as parameters
    
    Usage:
      Invoke-BackgroundWork -ScriptBlock { param($a,$b); ... return @{...} } `
          -ArgumentList @($arg1, $arg2) `
          -OnComplete $onCompleteBlock `
          -LoadingMessage 'Working...'
    
    The OnComplete scriptblock receives one parameter: the background result object.
    Use $global: variables if OnComplete needs to update module-scoped state.
#>

function global:Invoke-BackgroundWork {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList,

        [scriptblock]$OnComplete,

        [scriptblock]$OnTimeout,

        [string]$LoadingMessage = 'Processing...',
        [string]$LoadingSubMessage = '',

        [switch]$NoLoadingOverlay,

        [int]$TimeoutSeconds = 60
    )

    # Show overlay only for operations that request it
    $usesOverlay = -not $NoLoadingOverlay
    if ($usesOverlay) {
        Show-LoadingOverlay -Message $LoadingMessage -SubMessage $LoadingSubMessage
    }

    # Create bare MTA runspace (NO module import -- fast startup)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($ScriptBlock)
    if ($ArgumentList) {
        foreach ($arg in $ArgumentList) {
            [void]$ps.AddArgument($arg)
        }
    }

    $handle = $ps.BeginInvoke()

    # Register job in global registry
    if (-not $global:GA_BackgroundJobs) { $global:GA_BackgroundJobs = @{} }
    $jobId = 'bgj_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $global:GA_BackgroundJobs[$jobId] = @{
        PS         = $ps
        Runspace   = $rs
        Handle     = $handle
        StartTime  = [DateTime]::UtcNow
        Timeout    = $TimeoutSeconds
        UsesOverlay = $usesOverlay
        OnComplete = $OnComplete
        OnTimeout  = $OnTimeout
    }

    # Ensure the shared monitor timer is running
    global:Start-BackgroundMonitor

    return $jobId
}

function global:Stop-BackgroundWork {
    <# Stops a specific background job by JobId. #>
    param(
        [Parameter(Mandatory)]
        [string]$JobId,

        [switch]$SuppressToast
    )

    if (-not $global:GA_BackgroundJobs -or -not $global:GA_BackgroundJobs.ContainsKey($JobId)) {
        return $false
    }

    $job = $global:GA_BackgroundJobs[$JobId]
    try { $job.PS.Stop() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to stop PS instance for job $JobId`: $_" -Level DEBUG }
    try { $job.PS.Dispose() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to dispose PS instance for job $JobId`: $_" -Level DEBUG }
    try { $job.Runspace.Close(); $job.Runspace.Dispose() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to close/dispose runspace for job $JobId`: $_" -Level DEBUG }
    [void]$global:GA_BackgroundJobs.Remove($JobId)

    if ($global:GA_BackgroundJobs.Count -eq 0) {
        try { Hide-LoadingOverlay } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to hide loading overlay after job stop: $_" -Level DEBUG }
        if ($global:GA_BackgroundTimer) {
            try { $global:GA_BackgroundTimer.Stop() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to stop background monitor timer: $_" -Level DEBUG }
        }
    }
    else {
        $hasOverlayJobs = $false
        foreach ($j in @($global:GA_BackgroundJobs.Values)) {
            if ($j -and $j.UsesOverlay) { $hasOverlayJobs = $true; break }
        }
        if (-not $hasOverlayJobs) {
            try { Hide-LoadingOverlay } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to hide loading overlay (no overlay jobs remain): $_" -Level DEBUG }
        }
    }

    if (-not $SuppressToast) {
        try { Show-Toast -Message 'Background operation canceled.' -Type 'Info' } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to show cancellation toast: $_" -Level DEBUG }
    }

    return $true
}

function global:Start-BackgroundMonitor {
    <# Starts the single shared DispatcherTimer that monitors all background jobs. #>
    if ($global:GA_BackgroundTimer -and $global:GA_BackgroundTimer.IsEnabled) { return }

    if (-not $global:GA_BackgroundTimer) {
        $global:GA_BackgroundTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $global:GA_BackgroundTimer.Interval = [TimeSpan]::FromMilliseconds(250)

        # CRITICAL: NO .GetNewClosure() -- only references $global: variables
        $global:GA_BackgroundTimer.Add_Tick({
            if (-not $global:GA_BackgroundJobs -or $global:GA_BackgroundJobs.Count -eq 0) {
                # No jobs -- stop the timer to save CPU
                try { Hide-LoadingOverlay } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to hide loading overlay (no jobs): $_" -Level DEBUG }
                $global:GA_BackgroundTimer.Stop()
                return
            }

            $completedIds = [System.Collections.Generic.List[string]]::new()

            foreach ($id in @($global:GA_BackgroundJobs.Keys)) {
                $job = $global:GA_BackgroundJobs[$id]
                if ($null -eq $job) { [void]$completedIds.Add($id); continue }

                $elapsed = ([DateTime]::UtcNow - $job.StartTime).TotalSeconds
                $done = $false
                try { $done = $job.Handle.IsCompleted } catch { $done = $true }
                $timedOut = ($elapsed -ge $job.Timeout)

                if (-not $done -and -not $timedOut) { continue }

                [void]$completedIds.Add($id)

                if ($timedOut -and -not $done) {
                    # Kill hung job
                    try { $job.PS.Stop() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to stop timed-out PS instance (job $id): $_" -Level DEBUG }
                    try { $job.PS.Dispose() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to dispose timed-out PS instance (job $id): $_" -Level DEBUG }
                    try { $job.Runspace.Close(); $job.Runspace.Dispose() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to close/dispose timed-out runspace (job $id): $_" -Level DEBUG }

                    $timeoutMessage = "Operation timed out after $($job.Timeout)s."
                    if ($job.OnTimeout) {
                        try {
                            & $job.OnTimeout $timeoutMessage
                        }
                        catch {
                            try { Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error' } catch { }
                            try { Write-AppLockerLog -Message "OnTimeout error: $($_.Exception.Message)" -Level ERROR -NoConsole } catch { }
                        }
                    }
                    else {
                        try { Show-Toast -Message $timeoutMessage -Type 'Warning' } catch { }
                    }
                    continue
                }

                # Harvest result
                $result = $null
                try {
                    $output = $job.PS.EndInvoke($job.Handle)
                    $result = if ($output -and $output.Count -gt 0) { $output[0] } else { $null }
                }
                catch {
                    try { Write-AppLockerLog -Message "Background job error: $($_.Exception.Message)" -Level ERROR -NoConsole } catch { }
                }

                # Cleanup runspace
                try { $job.PS.Dispose() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to dispose PS instance after completion (job $id): $_" -Level DEBUG }
                try { $job.Runspace.Close(); $job.Runspace.Dispose() } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to close/dispose runspace after completion (job $id): $_" -Level DEBUG }

                if ($job.OnComplete) {
                    try {
                        & $job.OnComplete $result
                    }
                    catch {
                        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
                        try { Write-AppLockerLog -Message "OnComplete error: $($_.Exception.Message)" -Level ERROR -NoConsole } catch { }
                    }
                }
            }

            # Remove completed jobs
            foreach ($id in $completedIds) {
                [void]$global:GA_BackgroundJobs.Remove($id)
            }

            # Keep overlay visible only while overlay-using jobs remain
            if ($global:GA_BackgroundJobs.Count -gt 0) {
                $hasOverlayJobs = $false
                foreach ($j in @($global:GA_BackgroundJobs.Values)) {
                    if ($j -and $j.UsesOverlay) { $hasOverlayJobs = $true; break }
                }
                if (-not $hasOverlayJobs) {
                    try { Hide-LoadingOverlay } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to hide loading overlay (no overlay jobs in monitor tick): $_" -Level DEBUG }
                }
            }

            # Auto-stop timer when no jobs remain
            if ($global:GA_BackgroundJobs.Count -eq 0) {
                try { Hide-LoadingOverlay } catch { Write-AppLockerLog -Message "[UIHelpers] Failed to hide loading overlay (all jobs complete): $_" -Level DEBUG }
                $global:GA_BackgroundTimer.Stop()
            }
        })
        # NO .GetNewClosure() here!
    }

    $global:GA_BackgroundTimer.Start()
}
#endregion
