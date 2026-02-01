#region ===== THEME MANAGER =====
<#
.SYNOPSIS
    Manages Dark/Light theme switching for GA-AppLocker Dashboard.

.DESCRIPTION
    Provides functions to toggle between dark and light themes,
    persisting user preference to settings file.
#>

# Theme color definitions
$script:ThemeColors = @{
    Dark = @{
        Background = '#000000'
        Sidebar = '#121212'
        Content = '#1E1E1E'
        Foreground = '#FFFFFF'
        Muted = '#E0E0E0'
        Border = '#555555'
        Hover = '#2D2D2D'
        DataGridRow = '#252526'
        DataGridAltRow = '#2D2D30'
        DataGridHeader = '#2D2D30'
        InputBackground = '#1E1E1E'
        InputBorder = '#3E3E42'
        NavHover = '#333337'
    }
    Light = @{
        Background = '#F5F5F5'
        Sidebar = '#FFFFFF'
        Content = '#FAFAFA'
        Foreground = '#1A1A1A'
        Muted = '#666666'
        Border = '#E0E0E0'
        Hover = '#EEEEEE'
        DataGridRow = '#FFFFFF'
        DataGridAltRow = '#F5F5F5'
        DataGridHeader = '#E8E8E8'
        InputBackground = '#FFFFFF'
        InputBorder = '#CCCCCC'
        NavHover = '#E8E8E8'
    }
}

# Current theme state
$script:CurrentTheme = 'Dark'

function Get-CurrentTheme {
    <#
    .SYNOPSIS
        Gets the current theme name.
    #>
    return $script:CurrentTheme
}

function Set-Theme {
    <#
    .SYNOPSIS
        Applies the specified theme to the window.
    
    .PARAMETER Window
        The WPF Window object.
    
    .PARAMETER Theme
        Theme name: 'Dark' or 'Light'
    #>
    param(
        [System.Windows.Window]$Window,
        [ValidateSet('Dark', 'Light')]
        [string]$Theme
    )
    
    if (-not $Window) { return }
    
    $colors = $script:ThemeColors[$Theme]
    $script:CurrentTheme = $Theme
    
    try {
        # Update Window background
        $Window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($colors.Background)
        
        # Update resource brushes
        $resources = $Window.Resources
        
        # Helper to update a brush resource (clone to avoid frozen brush exception)
        $updateBrush = {
            param($key, $color)
            if ($resources.Contains($key)) {
                $brush = $resources[$key]
                if ($brush -is [System.Windows.Media.SolidColorBrush]) {
                    $newBrush = $brush.Clone()
                    $newBrush.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($color)
                    $resources[$key] = $newBrush
                }
            }
        }
        
        # Update core brushes
        & $updateBrush 'BackgroundBrush' $colors.Background
        & $updateBrush 'SidebarBrush' $colors.Sidebar
        & $updateBrush 'ContentBrush' $colors.Content
        & $updateBrush 'ForegroundBrush' $colors.Foreground
        & $updateBrush 'MutedBrush' $colors.Muted
        & $updateBrush 'BorderBrush' $colors.Border
        & $updateBrush 'HoverBrush' $colors.Hover
        
        # Update sidebar
        $sidebar = $Window.FindName('SidebarBorder')
        if ($sidebar) {
            $sidebar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($colors.Sidebar)
        }
        
        # Update theme toggle UI
        Update-ThemeToggleUI -Window $Window -Theme $Theme
        
        # Save preference
        Save-ThemePreference -Theme $Theme
        
        Write-Log -Message "Theme changed to $Theme" -Level Info
    }
    catch {
        Write-Log -Message "Failed to apply theme: $($_.Exception.Message)" -Level Warning
    }
}

function Toggle-Theme {
    <#
    .SYNOPSIS
        Toggles between dark and light themes.
    
    .PARAMETER Window
        The WPF Window object.
    #>
    param([System.Windows.Window]$Window)
    
    $newTheme = if ($script:CurrentTheme -eq 'Dark') { 'Light' } else { 'Dark' }
    Set-Theme -Window $Window -Theme $newTheme
    
    Show-Toast -Message "Switched to $newTheme theme" -Type 'Info'
}

function Update-ThemeToggleUI {
    <#
    .SYNOPSIS
        Updates the theme toggle switch visual state.
    #>
    param(
        [System.Windows.Window]$Window,
        [string]$Theme
    )
    
    $toggleKnob = $Window.FindName('ThemeToggleKnob')
    $labelDark = $Window.FindName('ThemeLabelDark')
    $labelLight = $Window.FindName('ThemeLabelLight')
    
    if ($toggleKnob) {
        if ($Theme -eq 'Light') {
            $toggleKnob.HorizontalAlignment = 'Right'
            $toggleKnob.Margin = [System.Windows.Thickness]::new(0, 0, 2, 0)
        } else {
            $toggleKnob.HorizontalAlignment = 'Left'
            $toggleKnob.Margin = [System.Windows.Thickness]::new(2, 0, 0, 0)
        }
    }
    
    # Update label colors based on active theme
    $activeColor = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFFFFF')
    $inactiveColor = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#888888')
    
    if ($Theme -eq 'Light') {
        $activeColor = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1A1A1A')
        $inactiveColor = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#999999')
    }
    
    if ($labelDark) {
        $labelDark.Foreground = if ($Theme -eq 'Dark') { $activeColor } else { $inactiveColor }
    }
    if ($labelLight) {
        $labelLight.Foreground = if ($Theme -eq 'Light') { $activeColor } else { $inactiveColor }
    }
}

function Save-ThemePreference {
    <#
    .SYNOPSIS
        Saves theme preference to settings file.
    #>
    param([string]$Theme)
    
    try {
        $settingsPath = Join-Path $env:LOCALAPPDATA 'GA-AppLocker\settings.json'
        $settingsDir = Split-Path $settingsPath -Parent
        
        if (-not (Test-Path $settingsDir)) {
            New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        }
        
        $settings = @{}
        if (Test-Path $settingsPath) {
            $content = Get-Content $settingsPath -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $obj = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($obj) {
                    $obj.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
                }
            }
        }
        
        $settings['Theme'] = $Theme
        $settings | ConvertTo-Json | Set-Content $settingsPath -Force
    }
    catch {
        Write-Log -Message "Failed to save theme preference: $($_.Exception.Message)" -Level Warning
    }
}

function Get-ThemePreference {
    <#
    .SYNOPSIS
        Loads theme preference from settings file.
    #>
    try {
        $settingsPath = Join-Path $env:LOCALAPPDATA 'GA-AppLocker\settings.json'
        
        if (Test-Path $settingsPath) {
            $content = Get-Content $settingsPath -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $obj = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($obj -and $obj.PSObject.Properties.Name -contains 'Theme') {
                    return $obj.Theme
                }
            }
        }
    }
    catch {
        # Silently return default
    }
    
    return 'Dark'  # Default theme
}

function Initialize-Theme {
    <#
    .SYNOPSIS
        Initializes the theme on application startup.
    #>
    param([System.Windows.Window]$Window)
    
    $savedTheme = Get-ThemePreference
    $script:CurrentTheme = $savedTheme
    
    # Apply saved theme if it's Light (Dark is default in XAML)
    if ($savedTheme -eq 'Light') {
        Set-Theme -Window $Window -Theme 'Light'
    } else {
        # Just update the toggle UI to reflect dark theme
        Update-ThemeToggleUI -Window $Window -Theme 'Dark'
    }
}

#endregion
