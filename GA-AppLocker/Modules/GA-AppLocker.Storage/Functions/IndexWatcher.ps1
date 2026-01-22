<#
.SYNOPSIS
    FileSystemWatcher for automatic index rebuilding.

.DESCRIPTION
    Monitors the Rules JSON directory and triggers index rebuilds when files change.
    Uses debouncing to avoid rebuilding on every single file change.
#>

$script:RulesWatcher = $null
$script:WatcherEnabled = $false
$script:PendingRebuild = $false
$script:RebuildTimer = $null
$script:RebuildDebounceMs = 2000  # Wait 2 seconds after last change before rebuilding

<#
.SYNOPSIS
    Starts monitoring the Rules directory for changes.

.DESCRIPTION
    Creates a FileSystemWatcher that monitors the Rules JSON directory.
    When files are added, modified, or deleted, it schedules an index rebuild
    with debouncing to batch multiple rapid changes.

.PARAMETER RulesPath
    Path to the Rules directory. If not specified, uses the default data path.

.EXAMPLE
    Start-RuleIndexWatcher
    
    Starts watching the default Rules directory.

.OUTPUTS
    [PSCustomObject] Result with Success status and watcher state.
#>
function Start-RuleIndexWatcher {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$RulesPath
    )

    $result = [PSCustomObject]@{
        Success = $false
        WatcherActive = $false
        WatchedPath = $null
        Error = $null
    }

    try {
        # Stop existing watcher if any
        if ($script:RulesWatcher) {
            Stop-RuleIndexWatcher | Out-Null
        }

        # Determine path to watch
        if (-not $RulesPath) {
            $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
                Get-AppLockerDataPath
            } else {
                Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
            }
            $RulesPath = Join-Path $dataPath 'Rules'
        }

        if (-not (Test-Path $RulesPath)) {
            $result.Error = "Rules directory not found: $RulesPath"
            Write-StorageLog -Message $result.Error -Level 'WARNING'
            return $result
        }

        # Create FileSystemWatcher
        $watcher = [System.IO.FileSystemWatcher]::new()
        $watcher.Path = $RulesPath
        $watcher.Filter = '*.json'
        $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor 
                                [System.IO.NotifyFilters]::LastWrite -bor
                                [System.IO.NotifyFilters]::CreationTime
        $watcher.IncludeSubdirectories = $false

        # Create debounce timer (WPF DispatcherTimer for UI thread safety)
        if ([System.Windows.Threading.Dispatcher]::CurrentDispatcher) {
            $script:RebuildTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:RebuildTimer.Interval = [TimeSpan]::FromMilliseconds($script:RebuildDebounceMs)
            $script:RebuildTimer.Add_Tick({
                $script:RebuildTimer.Stop()
                Invoke-DebouncedRebuild
            })
        }

        # Event handlers - schedule rebuild on any change
        $changeAction = {
            Schedule-IndexRebuild
        }

        Register-ObjectEvent -InputObject $watcher -EventName 'Created' -Action $changeAction -SourceIdentifier 'RulesWatcher_Created' | Out-Null
        Register-ObjectEvent -InputObject $watcher -EventName 'Changed' -Action $changeAction -SourceIdentifier 'RulesWatcher_Changed' | Out-Null
        Register-ObjectEvent -InputObject $watcher -EventName 'Deleted' -Action $changeAction -SourceIdentifier 'RulesWatcher_Deleted' | Out-Null
        Register-ObjectEvent -InputObject $watcher -EventName 'Renamed' -Action $changeAction -SourceIdentifier 'RulesWatcher_Renamed' | Out-Null

        # Start watching
        $watcher.EnableRaisingEvents = $true
        
        $script:RulesWatcher = $watcher
        $script:WatcherEnabled = $true

        $result.Success = $true
        $result.WatcherActive = $true
        $result.WatchedPath = $RulesPath

        Write-StorageLog -Message "Started watching Rules directory: $RulesPath"
    }
    catch {
        $result.Error = "Failed to start watcher: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }

    return $result
}

<#
.SYNOPSIS
    Stops monitoring the Rules directory.

.EXAMPLE
    Stop-RuleIndexWatcher

.OUTPUTS
    [PSCustomObject] Result with Success status.
#>
function Stop-RuleIndexWatcher {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        Error = $null
    }

    try {
        # Unregister events
        @('RulesWatcher_Created', 'RulesWatcher_Changed', 'RulesWatcher_Deleted', 'RulesWatcher_Renamed') | ForEach-Object {
            Unregister-Event -SourceIdentifier $_ -ErrorAction SilentlyContinue
            Remove-Job -Name $_ -Force -ErrorAction SilentlyContinue
        }

        # Stop and dispose watcher
        if ($script:RulesWatcher) {
            $script:RulesWatcher.EnableRaisingEvents = $false
            $script:RulesWatcher.Dispose()
            $script:RulesWatcher = $null
        }

        # Stop timer
        if ($script:RebuildTimer) {
            $script:RebuildTimer.Stop()
            $script:RebuildTimer = $null
        }

        $script:WatcherEnabled = $false
        $script:PendingRebuild = $false

        $result.Success = $true
        Write-StorageLog -Message "Stopped Rules directory watcher"
    }
    catch {
        $result.Error = "Failed to stop watcher: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }

    return $result
}

<#
.SYNOPSIS
    Gets the current watcher status.

.OUTPUTS
    [PSCustomObject] Watcher status information.
#>
function Get-RuleIndexWatcherStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return [PSCustomObject]@{
        Enabled = $script:WatcherEnabled
        WatchedPath = if ($script:RulesWatcher) { $script:RulesWatcher.Path } else { $null }
        PendingRebuild = $script:PendingRebuild
        DebounceMs = $script:RebuildDebounceMs
    }
}

<#
.SYNOPSIS
    Sets the debounce delay for index rebuilding.

.PARAMETER Milliseconds
    Delay in milliseconds to wait after the last file change before rebuilding.

.EXAMPLE
    Set-RuleIndexWatcherDebounce -Milliseconds 5000
#>
function Set-RuleIndexWatcherDebounce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(500, 30000)]
        [int]$Milliseconds
    )

    $script:RebuildDebounceMs = $Milliseconds
    
    if ($script:RebuildTimer) {
        $script:RebuildTimer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
    }

    Write-StorageLog -Message "Set index watcher debounce to ${Milliseconds}ms"
}

# Internal: Schedule an index rebuild with debouncing
function script:Schedule-IndexRebuild {
    $script:PendingRebuild = $true
    
    if ($script:RebuildTimer) {
        # Reset timer - this provides debouncing
        $script:RebuildTimer.Stop()
        $script:RebuildTimer.Start()
    }
    else {
        # No timer available, rebuild immediately (but still debounced via flag)
        if (-not $script:RebuildInProgress) {
            Start-Job -ScriptBlock {
                Start-Sleep -Milliseconds 2000
                Invoke-DebouncedRebuild
            } -Name 'IndexRebuild' | Out-Null
        }
    }
}

# Internal: Perform the actual rebuild after debounce period
function script:Invoke-DebouncedRebuild {
    if (-not $script:PendingRebuild) { return }
    
    $script:PendingRebuild = $false
    $script:RebuildInProgress = $true

    try {
        Write-StorageLog -Message "Rebuilding index due to file changes..."
        
        # Use the JSON index rebuild function if available
        if (Get-Command -Name 'Import-RulesToDatabase' -ErrorAction SilentlyContinue) {
            $result = Import-RulesToDatabase -Force
            if ($result.Success) {
                Write-StorageLog -Message "Index rebuilt: $($result.ImportedCount) rules indexed"
            }
            else {
                Write-StorageLog -Message "Index rebuild failed: $($result.Error)" -Level 'ERROR'
            }
        }
    }
    catch {
        Write-StorageLog -Message "Index rebuild error: $($_.Exception.Message)" -Level 'ERROR'
    }
    finally {
        $script:RebuildInProgress = $false
    }
}

<#
.SYNOPSIS
    Manually triggers an index rebuild.

.DESCRIPTION
    Forces an immediate index rebuild without waiting for file changes.
    Useful after bulk operations or when the index appears stale.

.EXAMPLE
    Invoke-RuleIndexRebuild

.OUTPUTS
    [PSCustomObject] Result from Import-RulesToDatabase.
#>
function Invoke-RuleIndexRebuild {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Write-StorageLog -Message "Manual index rebuild triggered"
    
    if (Get-Command -Name 'Import-RulesToDatabase' -ErrorAction SilentlyContinue) {
        return Import-RulesToDatabase -Force
    }
    
    return [PSCustomObject]@{
        Success = $false
        Error = "Import-RulesToDatabase function not available"
    }
}
