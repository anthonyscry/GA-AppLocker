#region ===== GLOBAL SEARCH =====
<#
.SYNOPSIS
    Global search functionality for GA-AppLocker Dashboard.

.DESCRIPTION
    Provides search across all data types: machines, artifacts, rules, policies.
    Results are displayed in a popup with categorized sections.
    Uses 300ms debouncing to prevent excessive searches during rapid typing.
#>

# Script-scoped debounce timer
$script:SearchDebounceTimer = $null

function Initialize-GlobalSearch {
    <#
    .SYNOPSIS
        Initializes global search functionality.
    #>
    param([System.Windows.Window]$Window)
    
    $searchBox = $Window.FindName('GlobalSearchBox')
    $placeholder = $Window.FindName('GlobalSearchPlaceholder')
    $clearBtn = $Window.FindName('BtnClearGlobalSearch')
    $popup = $Window.FindName('GlobalSearchPopup')
    
    if (-not $searchBox) { return }
    
    # Text changed event - search as user types with 300ms debouncing
    $searchBox.Add_TextChanged({
        param($sender, $e)
        $win = $script:MainWindow
        $text = $sender.Text
        $placeholder = $win.FindName('GlobalSearchPlaceholder')
        $clearBtn = $win.FindName('BtnClearGlobalSearch')
        $popup = $win.FindName('GlobalSearchPopup')
        
        # Toggle placeholder visibility
        if ($placeholder) {
            $placeholder.Visibility = if ([string]::IsNullOrWhiteSpace($text)) { 'Visible' } else { 'Collapsed' }
        }
        
        # Toggle clear button visibility
        if ($clearBtn) {
            $clearBtn.Visibility = if ([string]::IsNullOrWhiteSpace($text)) { 'Collapsed' } else { 'Visible' }
        }
        
        # Stop existing timer if running
        if ($script:SearchDebounceTimer) {
            $script:SearchDebounceTimer.Stop()
        }
        
        # If text too short, close popup and return
        if ($text.Length -lt 2) {
            if ($popup) { $popup.IsOpen = $false }
            return
        }
        
        # Create debounce timer if not exists
        if (-not $script:SearchDebounceTimer) {
            $script:SearchDebounceTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:SearchDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        }
        
        # Store current search text for the timer callback
        $script:PendingSearchQuery = $text
        
        # Set up timer tick handler (remove old one first to avoid accumulation)
        $script:SearchDebounceTimer.Remove_Tick($script:SearchDebounceTickHandler)
        $script:SearchDebounceTickHandler = {
            $script:SearchDebounceTimer.Stop()
            $query = $script:PendingSearchQuery
            
            if ($query -and $query.Length -ge 2) {
                # Use async operation for background search
                Invoke-AsyncGlobalSearch -Query $query
            }
        }
        $script:SearchDebounceTimer.Add_Tick($script:SearchDebounceTickHandler)
        
        # Start the debounce timer
        $script:SearchDebounceTimer.Start()
    })
    
    # Focus event - show results if text exists
    $searchBox.Add_GotFocus({
        param($sender, $e)
        $text = $sender.Text
        
        if ($text.Length -ge 2) {
            # Use async search for non-blocking UI
            Invoke-AsyncGlobalSearch -Query $text
        }
    })
    
    # Lost focus - hide popup (with slight delay for click handling)
    $searchBox.Add_LostFocus({
        param($sender, $e)
        $win = $script:MainWindow
        $popup = $win.FindName('GlobalSearchPopup')
        # Use dispatcher to delay hiding, allowing click events to process
        $win.Dispatcher.BeginInvoke([Action]{
            Start-Sleep -Milliseconds 200
            $popup = $script:MainWindow.FindName('GlobalSearchPopup')
            if ($popup -and -not $popup.IsMouseOver) {
                $popup.IsOpen = $false
            }
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    })
    
    # Clear button click
    if ($clearBtn) {
        $clearBtn.Add_Click({
            $win = $script:MainWindow
            $searchBox = $win.FindName('GlobalSearchBox')
            $popup = $win.FindName('GlobalSearchPopup')
            if ($searchBox) { $searchBox.Text = '' }
            if ($popup) { $popup.IsOpen = $false }
        })
    }
    
    # Keyboard shortcut Ctrl+K to focus search
    $Window.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq 'K' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
            $searchBox = $script:MainWindow.FindName('GlobalSearchBox')
            if ($searchBox) {
                $searchBox.Focus()
                $searchBox.SelectAll()
            }
            $e.Handled = $true
        }
        # Escape to close popup and clear
        if ($e.Key -eq 'Escape') {
            $popup = $script:MainWindow.FindName('GlobalSearchPopup')
            $searchBox = $script:MainWindow.FindName('GlobalSearchBox')
            if ($popup -and $popup.IsOpen) {
                $popup.IsOpen = $false
                $e.Handled = $true
            }
        }
    })
}

function Invoke-AsyncGlobalSearch {
    <#
    .SYNOPSIS
        Performs global search asynchronously in a background runspace.
    .DESCRIPTION
        Moves the search filtering to a background thread to prevent UI blocking.
        Uses pre-fetched cached data for rules/policies.
    #>
    param([string]$Query)
    
    $win = $script:MainWindow
    $popup = $win.FindName('GlobalSearchPopup')
    
    # Pre-fetch data on UI thread (uses cache, so fast)
    $machines = @()
    $artifacts = @()
    $allRules = @()
    $allPolicies = @()
    
    # Machines - from in-memory discovery data
    if (Get-Command -Name 'Get-DiscoveredMachine' -ErrorAction SilentlyContinue) {
        $machines = @(Get-DiscoveredMachine -ErrorAction SilentlyContinue)
    }
    
    # Artifacts - from script-scoped scan data
    if ($script:CurrentScanArtifacts -and $script:CurrentScanArtifacts.Count -gt 0) {
        $artifacts = @($script:CurrentScanArtifacts)
    }
    
    # Rules - from cache (60s TTL)
    if (Get-Command -Name 'Get-AllRules' -ErrorAction SilentlyContinue) {
        $allRules = Get-CachedValue -Key 'GlobalSearch_AllRules' -MaxAgeSeconds 60 -Factory {
            $result = Get-AllRules -ErrorAction SilentlyContinue
            if ($result.Success -and $result.Data) { $result.Data } else { @() }
        }
    }
    
    # Policies - from cache (60s TTL)
    if (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue) {
        $allPolicies = Get-CachedValue -Key 'GlobalSearch_AllPolicies' -MaxAgeSeconds 60 -Factory {
            $result = Get-AllPolicies -ErrorAction SilentlyContinue
            if ($result.Success -and $result.Data) { $result.Data } else { @() }
        }
    }
    
    # Run filtering in background runspace
    Invoke-AsyncOperation -ScriptBlock {
        param($Query, $Machines, $Artifacts, $AllRules, $AllPolicies)
        
        $query = $Query.ToLower().Trim()
        $results = @{
            Machines = @()
            Artifacts = @()
            Rules = @()
            Policies = @()
        }
        
        if ([string]::IsNullOrWhiteSpace($query)) { return $results }
        
        # Filter Machines
        if ($Machines -and $Machines.Count -gt 0) {
            $results.Machines = @($Machines.Where({
                $_.Name -like "*$query*" -or
                $_.DNSHostName -like "*$query*" -or
                $_.OU -like "*$query*" -or
                $_.OperatingSystem -like "*$query*"
            }) | Select-Object -First 5)
        }
        
        # Filter Artifacts
        if ($Artifacts -and $Artifacts.Count -gt 0) {
            $results.Artifacts = @($Artifacts.Where({
                $_.FileName -like "*$query*" -or
                $_.Publisher -like "*$query*" -or
                $_.ProductName -like "*$query*" -or
                $_.FilePath -like "*$query*"
            }) | Select-Object -First 5)
        }
        
        # Filter Rules
        if ($AllRules -and $AllRules.Count -gt 0) {
            $results.Rules = @($AllRules.Where({
                $_.Name -like "*$query*" -or
                $_.Publisher -like "*$query*" -or
                $_.ProductName -like "*$query*" -or
                $_.FileName -like "*$query*" -or
                $_.Description -like "*$query*"
            }) | Select-Object -First 5)
        }
        
        # Filter Policies
        if ($AllPolicies -and $AllPolicies.Count -gt 0) {
            $results.Policies = @($AllPolicies.Where({
                $_.Name -like "*$query*" -or
                $_.Description -like "*$query*"
            }) | Select-Object -First 5)
        }
        
        return $results
    } -Arguments @{
        Query = $Query
        Machines = $machines
        Artifacts = $artifacts
        AllRules = $allRules
        AllPolicies = $allPolicies
    } -OnComplete {
        param($Result)
        $win = $script:MainWindow
        $popup = $win.FindName('GlobalSearchPopup')
        
        if ($Result -and $Result.Success -and $Result.Result) {
            Update-SearchResultsPopup -Window $win -Results $Result.Result
            if ($popup) { $popup.IsOpen = $true }
        } elseif ($Result -and -not $Result.Success) {
            Write-Log -Message "Async search error: $($Result.Error)" -Level Warning
        }
    } -NoLoadingOverlay
}

function Invoke-GlobalSearch {
    <#
    .SYNOPSIS
        Performs search across all data types (synchronous version).
    .DESCRIPTION
        Used for direct calls. The async version (Invoke-AsyncGlobalSearch) 
        should be preferred for UI interactions.
    #>
    param([string]$Query)
    
    $results = @{
        Machines = @()
        Artifacts = @()
        Rules = @()
        Policies = @()
    }
    
    $query = $Query.ToLower().Trim()
    if ([string]::IsNullOrWhiteSpace($query)) { return $results }
    
    try {
        # Search Machines
        if (Get-Command -Name 'Get-DiscoveredMachine' -ErrorAction SilentlyContinue) {
            $machines = Get-DiscoveredMachine -ErrorAction SilentlyContinue
            if ($machines) {
                $results.Machines = @($machines.Where({
                    $_.Name -like "*$query*" -or
                    $_.DNSHostName -like "*$query*" -or
                    $_.OU -like "*$query*" -or
                    $_.OperatingSystem -like "*$query*"
                }) | Select-Object -First 5)
            }
        }
        
        # Search Artifacts (from current scan data)
        if ($script:CurrentScanArtifacts -and $script:CurrentScanArtifacts.Count -gt 0) {
            $results.Artifacts = @($script:CurrentScanArtifacts.Where({
                $_.FileName -like "*$query*" -or
                $_.Publisher -like "*$query*" -or
                $_.ProductName -like "*$query*" -or
                $_.FilePath -like "*$query*"
            }) | Select-Object -First 5)
        }
        
        # Search Rules (with 60s cache)
        if (Get-Command -Name 'Get-AllRules' -ErrorAction SilentlyContinue) {
            $allRules = Get-CachedValue -Key 'GlobalSearch_AllRules' -MaxAgeSeconds 60 -Factory {
                $result = Get-AllRules -ErrorAction SilentlyContinue
                if ($result.Success -and $result.Data) { $result.Data } else { @() }
            }
            if ($allRules -and $allRules.Count -gt 0) {
                $results.Rules = @($allRules.Where({
                    $_.Name -like "*$query*" -or
                    $_.Publisher -like "*$query*" -or
                    $_.ProductName -like "*$query*" -or
                    $_.FileName -like "*$query*" -or
                    $_.Description -like "*$query*"
                }) | Select-Object -First 5)
            }
        }
        
        # Search Policies (with 60s cache)
        if (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue) {
            $allPolicies = Get-CachedValue -Key 'GlobalSearch_AllPolicies' -MaxAgeSeconds 60 -Factory {
                $result = Get-AllPolicies -ErrorAction SilentlyContinue
                if ($result.Success -and $result.Data) { $result.Data } else { @() }
            }
            if ($allPolicies -and $allPolicies.Count -gt 0) {
                $results.Policies = @($allPolicies.Where({
                    $_.Name -like "*$query*" -or
                    $_.Description -like "*$query*"
                }) | Select-Object -First 5)
            }
        }
    }
    catch {
        Write-Log -Message "Global search error: $($_.Exception.Message)" -Level Warning
    }
    
    return $results
}

function Update-SearchResultsPopup {
    <#
    .SYNOPSIS
        Updates the search results popup with categorized results.
    #>
    param(
        [System.Windows.Window]$Window,
        [hashtable]$Results
    )
    
    $resultsPanel = $Window.FindName('GlobalSearchResults')
    if (-not $resultsPanel) { return }
    
    $resultsPanel.Children.Clear()
    
    $totalResults = 0
    
    # Add Machines section
    if ($Results.Machines.Count -gt 0) {
        $totalResults += $Results.Machines.Count
        Add-SearchResultSection -Panel $resultsPanel -Title 'MACHINES' -Icon '&#x1F5A5;' `
            -Items $Results.Machines -DisplayProperty 'Name' -SubProperty 'OperatingSystem' `
            -ClickAction { param($item) 
                Set-ActivePanel -PanelName 'PanelDiscovery'
                # Could also filter/select the machine in the grid
            }
    }
    
    # Add Artifacts section
    if ($Results.Artifacts.Count -gt 0) {
        $totalResults += $Results.Artifacts.Count
        Add-SearchResultSection -Panel $resultsPanel -Title 'ARTIFACTS' -Icon '&#x1F4C4;' `
            -Items $Results.Artifacts -DisplayProperty 'FileName' -SubProperty 'Publisher' `
            -ClickAction { param($item)
                Set-ActivePanel -PanelName 'PanelScanner'
            }
    }
    
    # Add Rules section
    if ($Results.Rules.Count -gt 0) {
        $totalResults += $Results.Rules.Count
        Add-SearchResultSection -Panel $resultsPanel -Title 'RULES' -Icon '&#x1F4DD;' `
            -Items $Results.Rules -DisplayProperty 'Name' -SubProperty 'Status' `
            -ClickAction { param($item)
                Set-ActivePanel -PanelName 'PanelRules'
            }
    }
    
    # Add Policies section
    if ($Results.Policies.Count -gt 0) {
        $totalResults += $Results.Policies.Count
        Add-SearchResultSection -Panel $resultsPanel -Title 'POLICIES' -Icon '&#x1F4CB;' `
            -Items $Results.Policies -DisplayProperty 'Name' -SubProperty 'Status' `
            -ClickAction { param($item)
                Set-ActivePanel -PanelName 'PanelPolicy'
            }
    }
    
    # No results message
    if ($totalResults -eq 0) {
        $noResults = New-Object System.Windows.Controls.TextBlock
        $noResults.Text = "No results found"
        $noResults.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#888888')
        $noResults.FontSize = 13
        $noResults.Margin = [System.Windows.Thickness]::new(10)
        $noResults.HorizontalAlignment = 'Center'
        $resultsPanel.Children.Add($noResults) | Out-Null
    }
}

function Add-SearchResultSection {
    <#
    .SYNOPSIS
        Adds a categorized section to search results.
    #>
    param(
        [System.Windows.Controls.StackPanel]$Panel,
        [string]$Title,
        [string]$Icon,
        [array]$Items,
        [string]$DisplayProperty,
        [string]$SubProperty,
        [scriptblock]$ClickAction
    )
    
    # Section header
    $header = New-Object System.Windows.Controls.TextBlock
    $header.Text = "$Icon $Title ($($Items.Count))"
    $header.FontSize = 10
    $header.FontWeight = 'SemiBold'
    $header.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#888888')
    $header.Margin = [System.Windows.Thickness]::new(8, 10, 8, 5)
    $Panel.Children.Add($header) | Out-Null
    
    foreach ($item in $Items) {
        $resultItem = New-Object System.Windows.Controls.Border
        $resultItem.Background = [System.Windows.Media.Brushes]::Transparent
        $resultItem.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
        $resultItem.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
        $resultItem.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $resultItem.Cursor = [System.Windows.Input.Cursors]::Hand
        $resultItem.Tag = $item
        
        $stack = New-Object System.Windows.Controls.StackPanel
        
        $mainText = New-Object System.Windows.Controls.TextBlock
        $mainText.Text = $item.$DisplayProperty
        $mainText.FontSize = 13
        $mainText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFFFFF')
        $mainText.TextTrimming = 'CharacterEllipsis'
        $stack.Children.Add($mainText) | Out-Null
        
        if ($SubProperty -and $item.$SubProperty) {
            $subText = New-Object System.Windows.Controls.TextBlock
            $subText.Text = $item.$SubProperty
            $subText.FontSize = 11
            $subText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#888888')
            $subText.TextTrimming = 'CharacterEllipsis'
            $stack.Children.Add($subText) | Out-Null
        }
        
        $resultItem.Child = $stack
        
        # Hover effect
        $resultItem.Add_MouseEnter({
            param($sender, $e)
            $sender.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2D2D2D')
        })
        $resultItem.Add_MouseLeave({
            param($sender, $e)
            $sender.Background = [System.Windows.Media.Brushes]::Transparent
        })
        
        # Click handler
        $resultItem.Add_MouseLeftButtonDown({
            param($sender, $e)
            $win = $script:MainWindow
            $popup = $win.FindName('GlobalSearchPopup')
            if ($popup) { $popup.IsOpen = $false }
            
            # Clear search
            $searchBox = $win.FindName('GlobalSearchBox')
            if ($searchBox) { $searchBox.Text = '' }
            
            # Navigate to appropriate panel
            $item = $sender.Tag
            if ($item.PSObject.Properties['OperatingSystem']) {
                Set-ActivePanel -PanelName 'PanelDiscovery'
            } elseif ($item.PSObject.Properties['FilePath'] -and -not $item.PSObject.Properties['RuleType']) {
                Set-ActivePanel -PanelName 'PanelScanner'
            } elseif ($item.PSObject.Properties['RuleType']) {
                Set-ActivePanel -PanelName 'PanelRules'
            } elseif ($item.PSObject.Properties['RuleCount']) {
                Set-ActivePanel -PanelName 'PanelPolicy'
            }
        })
        
        $Panel.Children.Add($resultItem) | Out-Null
    }
}

#endregion
