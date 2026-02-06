#region Async Helper Functions
# AsyncHelpers.ps1 - Background runspace operations for non-blocking UI

<#
.SYNOPSIS
    Executes a script block asynchronously in a background runspace.

.DESCRIPTION
    Runs long-running operations in a background thread to keep the UI responsive.
    Shows a loading overlay during execution and invokes a completion callback on the UI thread.

.PARAMETER ScriptBlock
    The script block to execute in the background.

.PARAMETER Arguments
    Optional hashtable of arguments to pass to the script block.

.PARAMETER LoadingMessage
    Message to display in the loading overlay.

.PARAMETER OnComplete
    Script block to execute when the background operation completes.
    Receives $Result parameter with the operation's return value.

.PARAMETER OnError
    Script block to execute if the background operation throws an exception.
    Receives $ErrorMessage parameter.

.EXAMPLE
    Invoke-AsyncOperation -ScriptBlock { Get-AllRules } -LoadingMessage "Loading rules..." -OnComplete {
        param($Result)
        $dataGrid.ItemsSource = $Result.Data
    }
#>
function Invoke-AsyncOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [hashtable]$Arguments = @{},

        [Parameter()]
        [string]$LoadingMessage = 'Processing...',

        [Parameter()]
        [string]$LoadingSubMessage = '',

        [Parameter()]
        [scriptblock]$OnComplete,

        [Parameter()]
        [scriptblock]$OnError,

        [Parameter()]
        [int]$TimeoutSeconds = 60,

        [Parameter()]
        [switch]$NoLoadingOverlay
    )

    $win = $global:GA_MainWindow
    if (-not $win) {
        Write-Warning "MainWindow not available, running synchronously"
        try {
            $result = & $ScriptBlock
            if ($OnComplete) { & $OnComplete -Result $result }
        }
        catch {
            if ($OnError) { & $OnError -ErrorMessage $_.Exception.Message }
        }
        return
    }

    # Show loading overlay
    if (-not $NoLoadingOverlay) {
        Show-LoadingOverlay -Message $LoadingMessage -SubMessage $LoadingSubMessage
    }

    # Create runspace with full PowerShell environment (includes Get-Command, etc.)
    $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspace = [runspacefactory]::CreateRunspace($initialState)
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()

    # Import required modules into runspace
    $runspace.SessionStateProxy.SetVariable('ScriptBlock', $ScriptBlock)
    $runspace.SessionStateProxy.SetVariable('Arguments', $Arguments)

    # Create PowerShell instance
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace

    # The script that runs in background
    [void]$powershell.AddScript({
        param($ScriptBlock, $Arguments, $ModulePath)
        
        try {
            # Import the main module in the runspace
            $moduleLoaded = $false
            if ($ModulePath -and (Test-Path $ModulePath)) {
                try {
                    Import-Module $ModulePath -Force -ErrorAction Stop
                    $moduleLoaded = $true
                    # Log success for diagnostics
                    Write-Host "[AsyncHelpers] Module imported successfully in runspace: $ModulePath"
                }
                catch {
                    # Module import failed - FATAL ERROR, cannot proceed
                    $errorMsg = "FATAL: Module import failed in runspace: $($_.Exception.Message)"
                    Write-Host "[AsyncHelpers] $errorMsg" -ForegroundColor Red
                    throw $errorMsg
                }
            }
            elseif (-not $ModulePath) {
                throw "FATAL: Module path not provided to runspace"
            }
            else {
                throw "FATAL: Module not found at path: $ModulePath"
            }
            
            # Execute the script block with arguments
            if ($Arguments -and $Arguments.Count -gt 0) {
                $result = & $ScriptBlock @Arguments
            }
            else {
                $result = & $ScriptBlock
            }
            
            return @{
                Success = $true
                Result = $result
                Error = $null
            }
        }
        catch {
            # Provide a cleaner error message for common runspace issues
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "is not recognized as the name of a cmdlet") {
                $cmdName = if ($errorMsg -match "'([^']+)'") { $matches[1] } else { "Unknown" }
                $errorMsg = "Function '$cmdName' not available (async module load issue)"
            }
            return @{
                Success = $false
                Result = $null
                Error = $errorMsg
            }
        }
    })

    # Get module path for the runspace - use Get-Module to find actual location
    $modulePath = $null
    $gaModule = Get-Module -Name 'GA-AppLocker' -ErrorAction SilentlyContinue
    if ($gaModule) {
        $modulePath = Join-Path $gaModule.ModuleBase 'GA-AppLocker.psd1'
    }
    elseif (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
        # Fallback: try to find module relative to script location
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        $parentRoot = Split-Path -Parent $scriptRoot
        $candidatePath = Join-Path $parentRoot 'GA-AppLocker.psd1'
        if (Test-Path $candidatePath) {
            $modulePath = $candidatePath
        }
    }

    [void]$powershell.AddParameter('ScriptBlock', $ScriptBlock)
    [void]$powershell.AddParameter('Arguments', $Arguments)
    [void]$powershell.AddParameter('ModulePath', $modulePath)

    # Start async execution
    $asyncResult = $powershell.BeginInvoke()

    # Create timer to check for completion
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)

    # Store context for the timer handler
    $context = @{
        PowerShell = $powershell
        Runspace = $runspace
        AsyncResult = $asyncResult
        Timer = $timer
        Window = $win
        OnComplete = $OnComplete
        OnError = $OnError
        NoLoadingOverlay = $NoLoadingOverlay
        StartTime = [DateTime]::UtcNow
        TimeoutSeconds = $TimeoutSeconds
    }

    $timer.Add_Tick({
        $ctx = $context
        
        # Safety timeout — prevent loading overlay from hanging forever
        $elapsed = ([DateTime]::UtcNow - $ctx.StartTime).TotalSeconds
        $timedOut = $elapsed -ge $ctx.TimeoutSeconds
        
        if ($ctx.AsyncResult.IsCompleted -or $timedOut) {
            $ctx.Timer.Stop()
            
            if ($timedOut -and -not $ctx.AsyncResult.IsCompleted) {
                # Timed out — force cleanup and show error
                if (-not $ctx.NoLoadingOverlay) {
                    Hide-LoadingOverlay
                }
                
                try {
                    $ctx.PowerShell.Stop()
                } catch { }
                
                $timeoutMsg = "Operation timed out after $($ctx.TimeoutSeconds) seconds"
                try {
                    Write-AppLockerLog -Message $timeoutMsg -Level 'WARNING'
                } catch { }
                
                if ($ctx.OnError) {
                    & $ctx.OnError -ErrorMessage $timeoutMsg
                }
                else {
                    Show-Toast -Message $timeoutMsg -Type 'Warning'
                }
                
                try {
                    $ctx.PowerShell.Dispose()
                    $ctx.Runspace.Close()
                    $ctx.Runspace.Dispose()
                } catch { }
                return
            }
            
            try {
                $output = $ctx.PowerShell.EndInvoke($ctx.AsyncResult)
                
                # Hide loading overlay
                if (-not $ctx.NoLoadingOverlay) {
                    Hide-LoadingOverlay
                }
                
                if ($output -and $output.Count -gt 0) {
                    $result = $output[0]
                    
                    if ($result.Success) {
                        if ($ctx.OnComplete) {
                            & $ctx.OnComplete -Result $result.Result
                        }
                    }
                    else {
                        if ($ctx.OnError) {
                            & $ctx.OnError -ErrorMessage $result.Error
                        }
                        else {
                            Show-Toast -Message "Operation failed: $($result.Error)" -Type 'Error'
                        }
                    }
                }
            }
            catch {
                if (-not $ctx.NoLoadingOverlay) {
                    Hide-LoadingOverlay
                }
                
                if ($ctx.OnError) {
                    & $ctx.OnError -ErrorMessage $_.Exception.Message
                }
                else {
                    Show-Toast -Message "Operation failed: $($_.Exception.Message)" -Type 'Error'
                }
            }
            finally {
                # Cleanup
                $ctx.PowerShell.Dispose()
                $ctx.Runspace.Close()
                $ctx.Runspace.Dispose()
            }
        }
    }.GetNewClosure())

    $timer.Start()
}

<#
.SYNOPSIS
    Updates the UI from a background thread using the Dispatcher.

.DESCRIPTION
    Safely invokes UI updates from background operations by marshalling
    the call to the UI thread via the Dispatcher.

.PARAMETER Action
    Script block containing UI updates to perform.

.EXAMPLE
    Invoke-UIUpdate { $dataGrid.ItemsSource = $newData }
#>
function Invoke-UIUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $win = $global:GA_MainWindow
    if (-not $win) {
        # No window, just execute directly
        & $Action
        return
    }

    # Check if we're on the UI thread
    if ($win.Dispatcher.CheckAccess()) {
        & $Action
    }
    else {
        # Marshal to UI thread
        $null = $win.Dispatcher.BeginInvoke([action]$Action, [System.Windows.Threading.DispatcherPriority]::Normal)
    }
}

<#
.SYNOPSIS
    Runs a quick background task without loading overlay.

.DESCRIPTION
    For short operations that don't need visual feedback.
    Useful for preloading data or updating caches.

.PARAMETER ScriptBlock
    The script block to execute.

.PARAMETER OnComplete
    Optional callback when complete.
#>
# UNUSED — Wrapper around Invoke-AsyncOperation, never called directly
function Start-BackgroundTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [scriptblock]$OnComplete
    )

    Invoke-AsyncOperation -ScriptBlock $ScriptBlock -OnComplete $OnComplete -NoLoadingOverlay
}

<#
.SYNOPSIS
    Updates loading overlay progress.

.DESCRIPTION
    Updates the loading overlay with progress information during long operations.

.PARAMETER Current
    Current item number.

.PARAMETER Total
    Total number of items.

.PARAMETER Message
    Optional message to display.
#>
# UNUSED — Not called from any panel or helper
function Update-AsyncProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Current,

        [Parameter(Mandatory)]
        [int]$Total,

        [Parameter()]
        [string]$Message
    )

    $pct = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $subMsg = "$Current of $Total ($pct%)"
    
    Invoke-UIUpdate {
        Update-LoadingText -Message $Message -SubMessage $subMsg
    }
}

<#
.SYNOPSIS
    Executes a script block with progress reporting support.

.DESCRIPTION
    Runs a long operation in the background while providing progress updates to the UI.
    The script block receives a synchronized hashtable ($Progress) that it can update
    with Current, Total, and Message properties.

.PARAMETER ScriptBlock
    The script block to execute. Receives $Progress hashtable parameter.
    Update $Progress.Current, $Progress.Total, and $Progress.Message from your script.

.PARAMETER LoadingMessage
    Initial message to display in the loading overlay.

.PARAMETER OnComplete
    Script block to execute when the background operation completes.

.PARAMETER OnError
    Script block to execute if the operation throws an exception.

.EXAMPLE
    Invoke-AsyncWithProgress -ScriptBlock {
        param($Progress)
        $items = 1..100
        $Progress.Total = $items.Count
        foreach ($i in $items) {
            $Progress.Current = $i
            $Progress.Message = "Processing item $i..."
            Start-Sleep -Milliseconds 50
        }
        return "Done!"
    } -LoadingMessage "Processing items..." -OnComplete {
        param($Result)
        Write-Host "Result: $Result"
    }
#>
function Invoke-AsyncWithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [string]$LoadingMessage = 'Processing...',

        [Parameter()]
        [scriptblock]$OnComplete,

        [Parameter()]
        [scriptblock]$OnError
    )

    $win = $global:GA_MainWindow
    if (-not $win) {
        Write-Warning "MainWindow not available, running synchronously"
        try {
            $syncProgress = @{ Current = 0; Total = 0; Message = '' }
            $result = & $ScriptBlock -Progress $syncProgress
            if ($OnComplete) { & $OnComplete -Result $result }
        }
        catch {
            if ($OnError) { & $OnError -ErrorMessage $_.Exception.Message }
        }
        return
    }

    # Show loading overlay
    Show-LoadingOverlay -Message $LoadingMessage -SubMessage 'Starting...'

    # Create synchronized hashtable for progress reporting
    $syncHash = [hashtable]::Synchronized(@{
        Current = 0
        Total = 0
        Message = ''
        LastUpdate = [datetime]::MinValue
    })

    # Create runspace with full PowerShell environment (includes Get-Command, etc.)
    $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspace = [runspacefactory]::CreateRunspace($initialState)
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()

    # Create PowerShell instance
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace

    # The script that runs in background
    [void]$powershell.AddScript({
        param($ScriptBlock, $Progress, $ModulePath)
        
        try {
            # Import the main module in the runspace
            $moduleLoaded = $false
            if ($ModulePath -and (Test-Path $ModulePath)) {
                try {
                    Import-Module $ModulePath -Force -ErrorAction Stop
                    $moduleLoaded = $true
                }
                catch {
                    # Module import failed - continue but note the error
                    $moduleError = $_.Exception.Message
                }
            }
            
            # Execute the script block with progress hashtable
            $result = & $ScriptBlock -Progress $Progress
            
            return @{
                Success = $true
                Result = $result
                Error = $null
            }
        }
        catch {
            # Provide a cleaner error message for common runspace issues
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "is not recognized as the name of a cmdlet") {
                $cmdName = if ($errorMsg -match "'([^']+)'") { $matches[1] } else { "Unknown" }
                $errorMsg = "Function '$cmdName' not available (async module load issue)"
            }
            return @{
                Success = $false
                Result = $null
                Error = $errorMsg
            }
        }
    })

    # Get module path for the runspace - use Get-Module to find actual location
    $modulePath = $null
    $gaModule = Get-Module -Name 'GA-AppLocker' -ErrorAction SilentlyContinue
    if ($gaModule) {
        $modulePath = Join-Path $gaModule.ModuleBase 'GA-AppLocker.psd1'
    }
    elseif (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
        # Fallback: try to find module relative to script location
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        $parentRoot = Split-Path -Parent $scriptRoot
        $candidatePath = Join-Path $parentRoot 'GA-AppLocker.psd1'
        if (Test-Path $candidatePath) {
            $modulePath = $candidatePath
        }
    }

    [void]$powershell.AddParameter('ScriptBlock', $ScriptBlock)
    [void]$powershell.AddParameter('Progress', $syncHash)
    [void]$powershell.AddParameter('ModulePath', $modulePath)

    # Start async execution
    $asyncResult = $powershell.BeginInvoke()

    # Create timer to check for completion and update progress
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)

    # Store context for the timer handler
    $context = @{
        PowerShell = $powershell
        Runspace = $runspace
        AsyncResult = $asyncResult
        Timer = $timer
        Window = $win
        OnComplete = $OnComplete
        OnError = $OnError
        Progress = $syncHash
        LoadingMessage = $LoadingMessage
    }

    $timer.Add_Tick({
        $ctx = $context
        
        # Update progress display
        $pHash = $ctx.Progress
        if ($pHash.Total -gt 0) {
            $pct = [math]::Round(($pHash.Current / $pHash.Total) * 100)
            $subMsg = "$($pHash.Current) of $($pHash.Total) ($pct%)"
            $msg = if ($pHash.Message) { $pHash.Message } else { $ctx.LoadingMessage }
            Update-LoadingText -Message $msg -SubMessage $subMsg
        }
        elseif ($pHash.Message) {
            Update-LoadingText -Message $pHash.Message -SubMessage ''
        }
        
        if ($ctx.AsyncResult.IsCompleted) {
            $ctx.Timer.Stop()
            
            try {
                $output = $ctx.PowerShell.EndInvoke($ctx.AsyncResult)
                
                # Hide loading overlay
                Hide-LoadingOverlay
                
                if ($output -and $output.Count -gt 0) {
                    $result = $output[0]
                    
                    if ($result.Success) {
                        if ($ctx.OnComplete) {
                            & $ctx.OnComplete -Result $result.Result
                        }
                    }
                    else {
                        if ($ctx.OnError) {
                            & $ctx.OnError -ErrorMessage $result.Error
                        }
                        else {
                            Show-Toast -Message "Operation failed: $($result.Error)" -Type 'Error'
                        }
                    }
                }
            }
            catch {
                Hide-LoadingOverlay
                
                if ($ctx.OnError) {
                    & $ctx.OnError -ErrorMessage $_.Exception.Message
                }
                else {
                    Show-Toast -Message "Operation failed: $($_.Exception.Message)" -Type 'Error'
                }
            }
            finally {
                # Cleanup
                $ctx.PowerShell.Dispose()
                $ctx.Runspace.Close()
                $ctx.Runspace.Dispose()
            }
        }
    }.GetNewClosure())

    $timer.Start()
}

<#
.SYNOPSIS
    Creates a progress tracker for use with Invoke-AsyncWithProgress.

.DESCRIPTION
    Returns a synchronized hashtable that can be used to track progress
    in async operations. Use this when you need to create the tracker
    outside of Invoke-AsyncWithProgress.

.OUTPUTS
    [hashtable] A synchronized hashtable with Current, Total, Message properties.
#>
# UNUSED — Not called from any panel or helper
function New-ProgressTracker {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return [hashtable]::Synchronized(@{
        Current = 0
        Total = 0
        Message = ''
    })
}

#endregion
