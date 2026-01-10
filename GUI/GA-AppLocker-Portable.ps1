<#
.SYNOPSIS
    GA-AppLocker Portable GUI Application
.DESCRIPTION
    A standalone, portable graphical user interface for the GA-AppLocker toolkit.
    Can be compiled to a single .exe file using PS2EXE or run directly.
.NOTES
    Author: GA-AppLocker Project
    Requires: PowerShell 5.1+, Windows Presentation Foundation

    To compile to EXE:
    Install-Module -Name PS2EXE -Scope CurrentUser
    Invoke-PS2EXE -InputFile .\GA-AppLocker-Portable.ps1 -OutputFile .\GA-AppLocker.exe -NoConsole -Title "GA-AppLocker" -Version "1.0.0"
#>

#Requires -Version 5.1

param(
    [string]$ScriptsPath = ""
)

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

#region Script Path Detection
# Detect script root - handles EXE, PS1, and ISE scenarios
$Script:AppRoot = $null

# Try multiple methods to find the app root
if ($ScriptsPath -and (Test-Path $ScriptsPath)) {
    $Script:AppRoot = $ScriptsPath
}
elseif ($PSScriptRoot) {
    # Running as .ps1 file
    $testPath = Split-Path -Parent $PSScriptRoot
    if (Test-Path (Join-Path $testPath "Start-AppLockerWorkflow.ps1")) {
        $Script:AppRoot = $testPath
    } else {
        $Script:AppRoot = $PSScriptRoot
    }
}
elseif ($MyInvocation.MyCommand.Path) {
    # Running from command
    $testPath = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    if (Test-Path (Join-Path $testPath "Start-AppLockerWorkflow.ps1")) {
        $Script:AppRoot = $testPath
    } else {
        $Script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
}
else {
    # Fallback to current directory
    $Script:AppRoot = (Get-Location).Path
}

# Check if running as compiled EXE
$Script:IsPortable = $true
$Script:ScriptsAvailable = Test-Path (Join-Path $Script:AppRoot "Start-AppLockerWorkflow.ps1")
#endregion

#region XAML Definition
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="GA-AppLocker Toolkit"
    Height="800"
    Width="1200"
    MinHeight="600"
    MinWidth="900"
    WindowStartupLocation="CenterScreen"
    Background="#0D1117">

    <Window.Resources>
        <!-- Modern Color Palette -->
        <Color x:Key="BgDark">#0D1117</Color>
        <Color x:Key="BgSidebar">#161B22</Color>
        <Color x:Key="BgCard">#21262D</Color>
        <Color x:Key="BgInput">#0D1117</Color>
        <Color x:Key="BorderColor">#30363D</Color>
        <Color x:Key="AccentBlue">#58A6FF</Color>
        <Color x:Key="AccentGreen">#3FB950</Color>
        <Color x:Key="AccentOrange">#D29922</Color>
        <Color x:Key="AccentRed">#F85149</Color>
        <Color x:Key="TextPrimary">#E6EDF3</Color>
        <Color x:Key="TextSecondary">#8B949E</Color>
        <Color x:Key="TextMuted">#484F58</Color>

        <SolidColorBrush x:Key="BgDarkBrush" Color="{StaticResource BgDark}"/>
        <SolidColorBrush x:Key="BgSidebarBrush" Color="{StaticResource BgSidebar}"/>
        <SolidColorBrush x:Key="BgCardBrush" Color="{StaticResource BgCard}"/>
        <SolidColorBrush x:Key="BgInputBrush" Color="{StaticResource BgInput}"/>
        <SolidColorBrush x:Key="BorderBrush" Color="{StaticResource BorderColor}"/>
        <SolidColorBrush x:Key="AccentBlueBrush" Color="{StaticResource AccentBlue}"/>
        <SolidColorBrush x:Key="AccentGreenBrush" Color="{StaticResource AccentGreen}"/>
        <SolidColorBrush x:Key="AccentOrangeBrush" Color="{StaticResource AccentOrange}"/>
        <SolidColorBrush x:Key="AccentRedBrush" Color="{StaticResource AccentRed}"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="{StaticResource TextPrimary}"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="{StaticResource TextSecondary}"/>
        <SolidColorBrush x:Key="TextMutedBrush" Color="{StaticResource TextMuted}"/>

        <!-- Primary Button Style -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource AccentBlueBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="20,12"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#79C0FF"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#30363D"/>
                                <Setter Property="Foreground" Value="#484F58"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary Button Style -->
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource BgCardBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#30363D"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#484F58"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#484F58"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Small Button Style -->
        <Style x:Key="SmallButton" TargetType="Button" BasedOn="{StaticResource SecondaryButton}">
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>

        <!-- Navigation Button Style -->
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="Padding" Value="16,12"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#21262D"/>
                                <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Active Navigation Button Style -->
        <Style x:Key="NavButtonActive" TargetType="Button" BasedOn="{StaticResource NavButton}">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
        </Style>

        <!-- Modern TextBox Style -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource BgInputBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern PasswordBox Style -->
        <Style TargetType="PasswordBox">
            <Setter Property="Background" Value="{StaticResource BgInputBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="PasswordBox">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="{StaticResource BgInputBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <!-- Modern CheckBox Style -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <!-- Modern RadioButton Style -->
        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <!-- Modern ListBox Style -->
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="{StaticResource BgInputBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="4"/>
        </Style>

        <!-- Card Style -->
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource BgCardBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="20"/>
            <Setter Property="Margin" Value="0,0,0,16"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="240"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="{StaticResource BgSidebarBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,1,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Logo/Title -->
                <Border Grid.Row="0" Padding="20,24,20,20" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1">
                    <StackPanel>
                        <TextBlock Text="GA-AppLocker" FontSize="20" FontWeight="Bold"
                                   Foreground="{StaticResource TextPrimaryBrush}"/>
                        <TextBlock Text="Security Policy Toolkit" FontSize="11"
                                   Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>
                    </StackPanel>
                </Border>

                <!-- Navigation -->
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8,12,8,12">
                        <TextBlock Text="WORKFLOWS" FontSize="10" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextMutedBrush}"
                                   Margin="16,8,0,8"/>

                        <Button x:Name="NavScan" Style="{StaticResource NavButtonActive}" Content="Scan Computers"/>
                        <Button x:Name="NavGenerate" Style="{StaticResource NavButton}" Content="Generate Policy"/>
                        <Button x:Name="NavMerge" Style="{StaticResource NavButton}" Content="Merge Policies"/>
                        <Button x:Name="NavValidate" Style="{StaticResource NavButton}" Content="Validate Policy"/>
                        <Button x:Name="NavEvents" Style="{StaticResource NavButton}" Content="Collect Events"/>
                        <Button x:Name="NavCompare" Style="{StaticResource NavButton}" Content="Compare Inventory"/>

                        <TextBlock Text="MANAGEMENT" FontSize="10" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextMutedBrush}"
                                   Margin="16,20,0,8"/>

                        <Button x:Name="NavSoftware" Style="{StaticResource NavButton}" Content="Software Lists"/>
                        <Button x:Name="NavAD" Style="{StaticResource NavButton}" Content="Active Directory"/>

                        <TextBlock Text="UTILITIES" FontSize="10" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextMutedBrush}"
                                   Margin="16,20,0,8"/>

                        <Button x:Name="NavDiagnostics" Style="{StaticResource NavButton}" Content="Diagnostics"/>
                        <Button x:Name="NavWinRM" Style="{StaticResource NavButton}" Content="WinRM Setup"/>
                        <Button x:Name="NavSettings" Style="{StaticResource NavButton}" Content="Settings"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- Status Bar -->
                <Border Grid.Row="2" Padding="16,12" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="{StaticResource AccentGreenBrush}" Margin="0,0,8,0"/>
                            <TextBlock x:Name="StatusText" Text="Ready" FontSize="12"
                                       Foreground="{StaticResource TextSecondaryBrush}"/>
                        </StackPanel>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <!-- Main Content Area -->
        <Grid Grid.Column="1">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Content Pages -->
            <Grid x:Name="ContentArea" Grid.Row="0" Margin="0">

                <!-- Scan Page -->
                <ScrollViewer x:Name="PageScan" VerticalScrollBarVisibility="Auto" Visibility="Visible">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Scan Computers" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Collect application inventory from remote computers via WinRM"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Computer List" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="ScanComputerList" Grid.Column="0"/>
                                    <Button x:Name="BrowseScanComputerList" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                                <TextBlock Text="Text file with one computer per line, or CSV with ComputerName column"
                                           FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,8,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Credentials (Optional)" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="16"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="Username" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <TextBox x:Name="ScanUsername" />
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="Password" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <PasswordBox x:Name="ScanPassword"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Options" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <WrapPanel>
                                    <CheckBox x:Name="ScanUserProfiles" Content="Scan User Profiles" Margin="0,0,24,8"/>
                                    <CheckBox x:Name="ScanIncludeDLLs" Content="Include DLLs" Margin="0,0,24,8"/>
                                </WrapPanel>
                                <Grid Margin="0,8,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="100"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="Throttle Limit:" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"
                                               VerticalAlignment="Center" Margin="0,0,12,0"/>
                                    <TextBox x:Name="ScanThrottleLimit" Grid.Column="1" Text="10"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Output Location" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="ScanOutputPath" Grid.Column="0" Text=".\Scans"/>
                                    <Button x:Name="BrowseScanOutput" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Button x:Name="StartScan" Content="Start Scan" Style="{StaticResource PrimaryButton}"
                                HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- Generate Page -->
                <ScrollViewer x:Name="PageGenerate" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Generate Policy" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Create AppLocker policies from scan data"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Scan Data Source" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="GenerateScanPath" Grid.Column="0"/>
                                    <Button x:Name="BrowseGenerateScanPath" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Policy Mode" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <RadioButton x:Name="GenerateSimplified" Content="Simplified Mode" IsChecked="True" Margin="0,0,0,4"/>
                                <TextBlock Text="Quick deployment with single target user/group"
                                           FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="20,0,0,16"/>
                                <RadioButton x:Name="GenerateBuildGuide" Content="Build Guide Mode" Margin="0,0,0,4"/>
                                <TextBlock Text="Enterprise deployment with proper scoping"
                                           FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="20,0,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border x:Name="BuildGuideOptions" Style="{StaticResource Card}" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Build Guide Options" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="16"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="Target Type" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <ComboBox x:Name="GenerateTargetType" SelectedIndex="0">
                                            <ComboBoxItem Content="Workstation"/>
                                            <ComboBoxItem Content="Server"/>
                                            <ComboBoxItem Content="DomainController"/>
                                        </ComboBox>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="Phase" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <ComboBox x:Name="GeneratePhase" SelectedIndex="0">
                                            <ComboBoxItem Content="Phase 1 - EXE only"/>
                                            <ComboBoxItem Content="Phase 2 - EXE + Script"/>
                                            <ComboBoxItem Content="Phase 3 - EXE + Script + MSI"/>
                                            <ComboBoxItem Content="Phase 4 - Full"/>
                                        </ComboBox>
                                    </StackPanel>
                                </Grid>
                                <TextBlock Text="Domain Name" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,16,0,6"/>
                                <TextBox x:Name="GenerateDomainName"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Additional Options" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <WrapPanel>
                                    <CheckBox x:Name="GenerateIncludeDenyRules" Content="Include LOLBins Deny Rules" Margin="0,0,24,8"/>
                                    <CheckBox x:Name="GenerateIncludeVendorPublishers" Content="Trust Vendor Publishers" Margin="0,0,0,8"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Output Location" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="GenerateOutputPath" Grid.Column="0" Text=".\Outputs"/>
                                    <Button x:Name="BrowseGenerateOutput" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Button x:Name="StartGenerate" Content="Generate Policy" Style="{StaticResource PrimaryButton}"
                                HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- Merge Page -->
                <ScrollViewer x:Name="PageMerge" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Merge Policies" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Combine multiple AppLocker policy files"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Policy Files" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ListBox x:Name="MergePolicyList" Grid.Column="0" Height="180"/>
                                    <StackPanel Grid.Column="1" Margin="12,0,0,0">
                                        <Button x:Name="MergeAddFile" Content="Add File" Style="{StaticResource SmallButton}" Margin="0,0,0,4"/>
                                        <Button x:Name="MergeAddFolder" Content="Add Folder" Style="{StaticResource SmallButton}" Margin="0,0,0,4"/>
                                        <Button x:Name="MergeRemoveFile" Content="Remove" Style="{StaticResource SmallButton}" Margin="0,0,0,4"/>
                                        <Button x:Name="MergeClearList" Content="Clear All" Style="{StaticResource SmallButton}"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Output Location" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="MergeOutputPath" Grid.Column="0" Text=".\Outputs"/>
                                    <Button x:Name="BrowseMergeOutput" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Button x:Name="StartMerge" Content="Merge Policies" Style="{StaticResource PrimaryButton}"
                                HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- Validate Page -->
                <ScrollViewer x:Name="PageValidate" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Validate Policy" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Check an AppLocker policy for issues"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Policy File" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="ValidatePolicyPath" Grid.Column="0"/>
                                    <Button x:Name="BrowseValidatePolicy" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border x:Name="ValidationResultsCard" Style="{StaticResource Card}" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Validation Results" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <TextBox x:Name="ValidationResults" Height="300" IsReadOnly="True"
                                         TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                                         FontFamily="Consolas" FontSize="12"/>
                            </StackPanel>
                        </Border>

                        <Button x:Name="StartValidate" Content="Validate Policy" Style="{StaticResource PrimaryButton}"
                                HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- Events Page -->
                <ScrollViewer x:Name="PageEvents" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Collect Events" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Collect AppLocker audit events from remote computers"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Computer List" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="EventsComputerList" Grid.Column="0"/>
                                    <Button x:Name="BrowseEventsComputerList" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Credentials (Optional)" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="16"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="Username" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <TextBox x:Name="EventsUsername"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="Password" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <PasswordBox x:Name="EventsPassword"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Event Options" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="16"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="Days Back" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <ComboBox x:Name="EventsDaysBack" SelectedIndex="1">
                                            <ComboBoxItem Content="7 days"/>
                                            <ComboBoxItem Content="14 days"/>
                                            <ComboBoxItem Content="30 days"/>
                                            <ComboBoxItem Content="90 days"/>
                                            <ComboBoxItem Content="All available"/>
                                        </ComboBox>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="Event Types" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <ComboBox x:Name="EventsType" SelectedIndex="0">
                                            <ComboBoxItem Content="Blocked Only"/>
                                            <ComboBoxItem Content="All Audit Events"/>
                                        </ComboBox>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Output Location" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="EventsOutputPath" Grid.Column="0" Text=".\Events"/>
                                    <Button x:Name="BrowseEventsOutput" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Button x:Name="StartEvents" Content="Collect Events" Style="{StaticResource PrimaryButton}"
                                HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- Compare Page -->
                <ScrollViewer x:Name="PageCompare" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Compare Inventory" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Compare software inventories between systems"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Reference (Baseline)" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="CompareReferencePath" Grid.Column="0"/>
                                    <Button x:Name="BrowseCompareReference" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Target (Compare To)" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="CompareTargetPath" Grid.Column="0"/>
                                    <Button x:Name="BrowseCompareTarget" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Comparison Method" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <ComboBox x:Name="CompareMethod" SelectedIndex="0">
                                    <ComboBoxItem Content="Name - Compare by file name"/>
                                    <ComboBoxItem Content="NameVersion - Include version"/>
                                    <ComboBoxItem Content="Hash - Compare by file hash"/>
                                    <ComboBoxItem Content="Publisher - Compare by publisher"/>
                                </ComboBox>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Output Location" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="CompareOutputPath" Grid.Column="0" Text=".\Outputs"/>
                                    <Button x:Name="BrowseCompareOutput" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Button x:Name="StartCompare" Content="Compare Inventories" Style="{StaticResource PrimaryButton}"
                                HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- Software Page -->
                <ScrollViewer x:Name="PageSoftware" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Software Lists" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Manage curated software allowlists"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Available Lists" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ListBox x:Name="SoftwareListBox" Grid.Column="0" Height="180"/>
                                    <StackPanel Grid.Column="1" Margin="12,0,0,0">
                                        <Button x:Name="SoftwareRefresh" Content="Refresh" Style="{StaticResource SmallButton}" Margin="0,0,0,4"/>
                                        <Button x:Name="SoftwareNew" Content="New List" Style="{StaticResource SmallButton}" Margin="0,0,0,4"/>
                                        <Button x:Name="SoftwareDelete" Content="Delete" Style="{StaticResource SmallButton}"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Generate Policy from List" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ComboBox x:Name="SoftwareGenerateList" Grid.Column="0"/>
                                    <Button x:Name="SoftwareGeneratePolicy" Grid.Column="1" Content="Generate"
                                            Style="{StaticResource PrimaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- AD Page -->
                <ScrollViewer x:Name="PageAD" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Active Directory" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Manage AD resources for AppLocker deployment"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="AD Setup" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <TextBlock Text="Domain Name" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                <TextBox x:Name="ADDomainName" Margin="0,0,0,12"/>
                                <TextBlock Text="Group Prefix" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                <TextBox x:Name="ADGroupPrefix" Text="AppLocker" Margin="0,0,0,16"/>
                                <Button x:Name="ADSetup" Content="Create OUs and Groups" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Computer Export" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Button x:Name="ADExportComputers" Content="Export Computer List" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- Diagnostics Page -->
                <ScrollViewer x:Name="PageDiagnostics" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Diagnostics" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Troubleshoot connectivity issues"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Target Computer" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <TextBox x:Name="DiagnosticComputerName" Margin="0,0,0,16"/>
                                <Button x:Name="StartDiagnostic" Content="Run Diagnostic" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- WinRM Page -->
                <ScrollViewer x:Name="PageWinRM" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="WinRM Setup" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Deploy WinRM for remote scanning"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Deploy WinRM GPO" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                <TextBlock Text="Creates a GPO to enable WinRM on domain computers"
                                           FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,16"/>
                                <Button x:Name="WinRMDeploy" Content="Deploy GPO" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Remove WinRM GPO" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                <Button x:Name="WinRMRemove" Content="Remove GPO" Style="{StaticResource SecondaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- Settings Page -->
                <ScrollViewer x:Name="PageSettings" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Settings" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Configure application settings"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Scripts Location" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="SettingsScriptsPath" Grid.Column="0"/>
                                    <Button x:Name="BrowseScriptsPath" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                                <TextBlock x:Name="ScriptsStatusText" Text="" FontSize="11"
                                           Foreground="{StaticResource TextMutedBrush}" Margin="0,8,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Application Info" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <TextBlock Text="GA-AppLocker Toolkit v1.0" FontSize="12"
                                           Foreground="{StaticResource TextSecondaryBrush}"/>
                                <TextBlock Text="Windows AppLocker Policy Management" FontSize="11"
                                           Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </Grid>

            <!-- Log Panel -->
            <Border x:Name="LogPanel" Grid.Row="1" Background="{StaticResource BgSidebarBrush}"
                    BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0"
                    Height="180">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Padding="16,8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Output Log" FontSize="12" FontWeight="SemiBold"
                                       Foreground="{StaticResource TextPrimaryBrush}" VerticalAlignment="Center"/>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button x:Name="ToggleLog" Content="Hide" Style="{StaticResource SmallButton}" Margin="0,0,8,0"/>
                                <Button x:Name="ClearLog" Content="Clear" Style="{StaticResource SmallButton}" Margin="0,0,8,0"/>
                                <Button x:Name="SaveLog" Content="Save" Style="{StaticResource SmallButton}"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <TextBox x:Name="LogOutput" Grid.Row="1"
                             IsReadOnly="True" TextWrapping="NoWrap"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             FontFamily="Consolas" FontSize="11"
                             Background="{StaticResource BgDarkBrush}"
                             Foreground="{StaticResource TextSecondaryBrush}"
                             BorderThickness="0" Padding="16,8"/>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@
#endregion

#region Window Creation
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$controls = @{}
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    $name = $_.Name
    if (-not $name) { $name = $_.'x:Name' }
    if ($name) { $controls[$name] = $window.FindName($name) }
}
#endregion

#region Helper Functions
function Write-Log {
    param([string]$Message, [ValidateSet('Info','Success','Warning','Error')][string]$Level = 'Info')
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) { 'Success' { "[+]" } 'Warning' { "[!]" } 'Error' { "[-]" } default { "[*]" } }
    $controls['LogOutput'].Dispatcher.Invoke([Action]{
        $controls['LogOutput'].AppendText("[$timestamp] $prefix $Message`r`n")
        $controls['LogOutput'].ScrollToEnd()
    })
}

function Set-Status {
    param([ValidateSet('Ready','Running','Success','Error')][string]$State = 'Ready')
    $controls['StatusText'].Dispatcher.Invoke([Action]{
        $controls['StatusText'].Text = switch ($State) { 'Running' { "Running..." } 'Success' { "Complete" } 'Error' { "Error" } default { "Ready" } }
        $controls['StatusDot'].Fill = switch ($State) {
            'Running' { [System.Windows.Media.Brushes]::Orange }
            'Success' { [System.Windows.Media.Brushes]::LightGreen }
            'Error'   { [System.Windows.Media.Brushes]::Red }
            default   { [System.Windows.Media.Brushes]::LightGreen }
        }
    })
}

function Get-OpenFileDialog {
    param([string]$Title = "Select File", [string]$Filter = "All Files (*.*)|*.*")
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = $Title; $dialog.Filter = $Filter
    if ($dialog.ShowDialog() -eq $true) { return $dialog.FileName }
    return $null
}

function Get-FolderDialog {
    param([string]$Description = "Select Folder")
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    if ($dialog.ShowDialog() -eq 'OK') { return $dialog.SelectedPath }
    return $null
}

function Invoke-Script {
    param([string]$ScriptName, [hashtable]$Parameters = @{})

    if (-not $Script:ScriptsAvailable) {
        Write-Log "Scripts not found. Please configure Scripts Location in Settings." -Level Error
        return
    }

    $scriptPath = Join-Path $Script:AppRoot $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Write-Log "Script not found: $scriptPath" -Level Error
        return
    }

    Set-Status -State 'Running'
    try {
        & $scriptPath @Parameters 2>&1 | ForEach-Object { Write-Log $_.ToString() }
        Set-Status -State 'Success'
    } catch {
        Write-Log "Error: $_" -Level Error
        Set-Status -State 'Error'
    }
}

# Navigation
$Script:Pages = @("Scan","Generate","Merge","Validate","Events","Compare","Software","AD","Diagnostics","WinRM","Settings")

function Switch-Page {
    param([string]$PageName)
    foreach ($page in $Script:Pages) { $controls["Page$page"].Visibility = 'Collapsed' }
    $controls["Page$PageName"].Visibility = 'Visible'
    foreach ($page in $Script:Pages) {
        $nav = $controls["Nav$page"]
        if ($nav) { $nav.Style = $window.FindResource($(if ($page -eq $PageName) { "NavButtonActive" } else { "NavButton" })) }
    }
}
#endregion

#region Event Handlers
# Navigation
$controls['NavScan'].Add_Click({ Switch-Page "Scan" })
$controls['NavGenerate'].Add_Click({ Switch-Page "Generate" })
$controls['NavMerge'].Add_Click({ Switch-Page "Merge" })
$controls['NavValidate'].Add_Click({ Switch-Page "Validate" })
$controls['NavEvents'].Add_Click({ Switch-Page "Events" })
$controls['NavCompare'].Add_Click({ Switch-Page "Compare" })
$controls['NavSoftware'].Add_Click({ Switch-Page "Software" })
$controls['NavAD'].Add_Click({ Switch-Page "AD" })
$controls['NavDiagnostics'].Add_Click({ Switch-Page "Diagnostics" })
$controls['NavWinRM'].Add_Click({ Switch-Page "WinRM" })
$controls['NavSettings'].Add_Click({ Switch-Page "Settings" })

# Build Guide toggle
$controls['GenerateBuildGuide'].Add_Checked({ $controls['BuildGuideOptions'].Visibility = 'Visible' })
$controls['GenerateSimplified'].Add_Checked({ $controls['BuildGuideOptions'].Visibility = 'Collapsed' })

# Log panel toggle
$Script:LogExpanded = $true
$controls['ToggleLog'].Add_Click({
    if ($Script:LogExpanded) { $controls['LogPanel'].Height = 36; $controls['ToggleLog'].Content = "Show"; $Script:LogExpanded = $false }
    else { $controls['LogPanel'].Height = 180; $controls['ToggleLog'].Content = "Hide"; $Script:LogExpanded = $true }
})

$controls['ClearLog'].Add_Click({ $controls['LogOutput'].Clear() })
$controls['SaveLog'].Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "Text Files (*.txt)|*.txt"; $dialog.FileName = "AppLocker-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    if ($dialog.ShowDialog() -eq $true) { $controls['LogOutput'].Text | Out-File $dialog.FileName -Encoding UTF8; Write-Log "Log saved." -Level Success }
})

# Browse buttons
$controls['BrowseScanComputerList'].Add_Click({ $f = Get-OpenFileDialog -Title "Select Computer List" -Filter "Text/CSV (*.txt;*.csv)|*.txt;*.csv"; if ($f) { $controls['ScanComputerList'].Text = $f } })
$controls['BrowseScanOutput'].Add_Click({ $f = Get-FolderDialog; if ($f) { $controls['ScanOutputPath'].Text = $f } })
$controls['BrowseGenerateScanPath'].Add_Click({ $f = Get-FolderDialog; if ($f) { $controls['GenerateScanPath'].Text = $f } })
$controls['BrowseGenerateOutput'].Add_Click({ $f = Get-FolderDialog; if ($f) { $controls['GenerateOutputPath'].Text = $f } })
$controls['BrowseMergeOutput'].Add_Click({ $f = Get-FolderDialog; if ($f) { $controls['MergeOutputPath'].Text = $f } })
$controls['BrowseValidatePolicy'].Add_Click({ $f = Get-OpenFileDialog -Title "Select Policy" -Filter "XML (*.xml)|*.xml"; if ($f) { $controls['ValidatePolicyPath'].Text = $f } })
$controls['BrowseEventsComputerList'].Add_Click({ $f = Get-OpenFileDialog -Filter "Text/CSV (*.txt;*.csv)|*.txt;*.csv"; if ($f) { $controls['EventsComputerList'].Text = $f } })
$controls['BrowseEventsOutput'].Add_Click({ $f = Get-FolderDialog; if ($f) { $controls['EventsOutputPath'].Text = $f } })
$controls['BrowseCompareReference'].Add_Click({ $f = Get-OpenFileDialog -Filter "CSV (*.csv)|*.csv"; if ($f) { $controls['CompareReferencePath'].Text = $f } })
$controls['BrowseCompareTarget'].Add_Click({ $f = Get-OpenFileDialog -Filter "CSV (*.csv)|*.csv"; if ($f) { $controls['CompareTargetPath'].Text = $f } })
$controls['BrowseCompareOutput'].Add_Click({ $f = Get-FolderDialog; if ($f) { $controls['CompareOutputPath'].Text = $f } })
$controls['BrowseScriptsPath'].Add_Click({ $f = Get-FolderDialog -Description "Select GA-AppLocker folder"; if ($f) { $controls['SettingsScriptsPath'].Text = $f; $Script:AppRoot = $f; $Script:ScriptsAvailable = Test-Path (Join-Path $f "Start-AppLockerWorkflow.ps1"); $controls['ScriptsStatusText'].Text = if ($Script:ScriptsAvailable) { "Scripts found!" } else { "Scripts not found" } } })

# Merge list management
$controls['MergeAddFile'].Add_Click({ $f = Get-OpenFileDialog -Filter "XML (*.xml)|*.xml"; if ($f) { $controls['MergePolicyList'].Items.Add($f) } })
$controls['MergeAddFolder'].Add_Click({ $f = Get-FolderDialog; if ($f) { Get-ChildItem $f -Filter "*.xml" | ForEach-Object { $controls['MergePolicyList'].Items.Add($_.FullName) } } })
$controls['MergeRemoveFile'].Add_Click({ if ($controls['MergePolicyList'].SelectedItem) { $controls['MergePolicyList'].Items.Remove($controls['MergePolicyList'].SelectedItem) } })
$controls['MergeClearList'].Add_Click({ $controls['MergePolicyList'].Items.Clear() })

# Main operations
$controls['StartScan'].Add_Click({
    $list = $controls['ScanComputerList'].Text
    if (-not $list -or -not (Test-Path $list)) { Write-Log "Please select a valid computer list." -Level Error; return }
    $params = @{ ComputerList = $list; OutputPath = $controls['ScanOutputPath'].Text; ThrottleLimit = [int]$controls['ScanThrottleLimit'].Text }
    if ($controls['ScanUserProfiles'].IsChecked) { $params['ScanUserProfiles'] = $true }
    Write-Log "Starting scan..." -Level Info
    Invoke-Script -ScriptName "Invoke-RemoteScan.ps1" -Parameters $params
    Write-Log "Scan completed." -Level Success
})

$controls['StartGenerate'].Add_Click({
    $scanPath = $controls['GenerateScanPath'].Text
    if (-not $scanPath -or -not (Test-Path $scanPath)) { Write-Log "Please select a valid scan folder." -Level Error; return }
    $params = @{ ScanPath = $scanPath; OutputPath = $controls['GenerateOutputPath'].Text }
    if ($controls['GenerateSimplified'].IsChecked) { $params['Simplified'] = $true }
    else {
        $domain = $controls['GenerateDomainName'].Text
        if (-not $domain) { Write-Log "Domain name required for Build Guide mode." -Level Error; return }
        $params['DomainName'] = $domain; $params['Phase'] = $controls['GeneratePhase'].SelectedIndex + 1
    }
    if ($controls['GenerateIncludeDenyRules'].IsChecked) { $params['IncludeDenyRules'] = $true }
    Write-Log "Generating policy..." -Level Info
    Invoke-Script -ScriptName "New-AppLockerPolicyFromGuide.ps1" -Parameters $params
    Write-Log "Generation completed." -Level Success
})

$controls['StartMerge'].Add_Click({
    $files = @($controls['MergePolicyList'].Items)
    if ($files.Count -lt 2) { Write-Log "Add at least 2 policy files." -Level Error; return }
    Write-Log "Merging $($files.Count) policies..." -Level Info
    Invoke-Script -ScriptName "Merge-AppLockerPolicies.ps1" -Parameters @{ PolicyPaths = $files; OutputPath = $controls['MergeOutputPath'].Text }
    Write-Log "Merge completed." -Level Success
})

$controls['StartValidate'].Add_Click({
    $path = $controls['ValidatePolicyPath'].Text
    if (-not $path -or -not (Test-Path $path)) { Write-Log "Please select a valid policy file." -Level Error; return }
    Write-Log "Validating policy..." -Level Info
    Set-Status -State 'Running'
    try {
        [xml]$policy = Get-Content $path -Raw
        $results = @("Policy Validation Results", "=" * 40, "")
        if ($policy.DocumentElement.Name -eq 'AppLockerPolicy') { $results += "[+] Valid AppLocker structure" }
        else { $results += "[-] Invalid structure" }
        $results += ""; $results += "Rule Collections:"
        foreach ($c in $policy.AppLockerPolicy.RuleCollection) {
            $count = ($c.ChildNodes | Where-Object { $_.LocalName -match 'Rule$' }).Count
            $results += "  - $($c.Type): $count rules ($($c.EnforcementMode))"
        }
        $everyone = $policy.SelectNodes("//*[contains(@UserOrGroupSid, 'S-1-1-0')]")
        $results += ""; $results += "Security:"
        if ($everyone.Count -gt 0) { $results += "[!] $($everyone.Count) Everyone rules" }
        else { $results += "[+] No Everyone rules" }
        $controls['ValidationResultsCard'].Visibility = 'Visible'
        $controls['ValidationResults'].Text = $results -join "`r`n"
        Set-Status -State 'Success'; Write-Log "Validation completed." -Level Success
    } catch { Write-Log "Error: $_" -Level Error; Set-Status -State 'Error' }
})

$controls['StartEvents'].Add_Click({
    $list = $controls['EventsComputerList'].Text
    if (-not $list -or -not (Test-Path $list)) { Write-Log "Please select a valid computer list." -Level Error; return }
    $days = switch ($controls['EventsDaysBack'].SelectedIndex) { 0 { 7 } 1 { 14 } 2 { 30 } 3 { 90 } 4 { 0 } default { 14 } }
    $params = @{ ComputerList = $list; OutputPath = $controls['EventsOutputPath'].Text; DaysBack = $days }
    if ($controls['EventsType'].SelectedIndex -eq 1) { $params['IncludeAllowedEvents'] = $true }
    Write-Log "Collecting events..." -Level Info
    Invoke-Script -ScriptName "Invoke-RemoteEventCollection.ps1" -Parameters $params
    Write-Log "Collection completed." -Level Success
})

$controls['StartCompare'].Add_Click({
    $ref = $controls['CompareReferencePath'].Text; $target = $controls['CompareTargetPath'].Text
    if (-not $ref -or -not $target -or -not (Test-Path $ref) -or -not (Test-Path $target)) { Write-Log "Select valid reference and target files." -Level Error; return }
    $method = switch ($controls['CompareMethod'].SelectedIndex) { 0 { "Name" } 1 { "NameVersion" } 2 { "Hash" } 3 { "Publisher" } default { "Name" } }
    Write-Log "Comparing inventories..." -Level Info
    Invoke-Script -ScriptName "utilities\Compare-SoftwareInventory.ps1" -Parameters @{ ReferencePath = $ref; ComparePath = $target; CompareBy = $method; OutputPath = $controls['CompareOutputPath'].Text }
    Write-Log "Comparison completed." -Level Success
})

$controls['StartDiagnostic'].Add_Click({
    $computer = $controls['DiagnosticComputerName'].Text
    if (-not $computer) { Write-Log "Enter a computer name." -Level Error; return }
    Write-Log "Running diagnostic on $computer..." -Level Info
    Invoke-Script -ScriptName "utilities\Test-AppLockerDiagnostic.ps1" -Parameters @{ ComputerName = $computer }
    Write-Log "Diagnostic completed." -Level Success
})

$controls['ADSetup'].Add_Click({
    $domain = $controls['ADDomainName'].Text
    if (-not $domain) { Write-Log "Enter domain name." -Level Error; return }
    Write-Log "Creating AD resources..." -Level Info
    Invoke-Script -ScriptName "utilities\Manage-ADResources.ps1" -Parameters @{ Action = 'Setup'; DomainName = $domain; GroupPrefix = $controls['ADGroupPrefix'].Text }
    Write-Log "AD setup completed." -Level Success
})

$controls['ADExportComputers'].Add_Click({
    Write-Log "Exporting computers..." -Level Info
    Invoke-Script -ScriptName "utilities\Manage-ADResources.ps1" -Parameters @{ Action = 'ExportComputers' }
    Write-Log "Export completed." -Level Success
})

$controls['WinRMDeploy'].Add_Click({
    Write-Log "Deploying WinRM GPO..." -Level Info
    Invoke-Script -ScriptName "utilities\Enable-WinRM-Domain.ps1" -Parameters @{ Action = 'Deploy' }
    Write-Log "Deployment completed." -Level Success
})

$controls['WinRMRemove'].Add_Click({
    Write-Log "Removing WinRM GPO..." -Level Info
    Invoke-Script -ScriptName "utilities\Enable-WinRM-Domain.ps1" -Parameters @{ Action = 'Remove' }
    Write-Log "Removal completed." -Level Success
})

# Software list management
function Update-SoftwareLists {
    $controls['SoftwareListBox'].Items.Clear()
    $controls['SoftwareGenerateList'].Items.Clear()
    $listsPath = Join-Path $Script:AppRoot "SoftwareLists"
    if (Test-Path $listsPath) {
        Get-ChildItem $listsPath -Filter "*.json" | ForEach-Object {
            $controls['SoftwareListBox'].Items.Add($_.BaseName)
            $controls['SoftwareGenerateList'].Items.Add($_.BaseName)
        }
    }
    if ($controls['SoftwareGenerateList'].Items.Count -gt 0) { $controls['SoftwareGenerateList'].SelectedIndex = 0 }
}

$controls['SoftwareRefresh'].Add_Click({ Update-SoftwareLists; Write-Log "Lists refreshed." -Level Info })

$controls['SoftwareNew'].Add_Click({
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Enter list name:", "New Software List", "")
    if ($name) {
        $listsPath = Join-Path $Script:AppRoot "SoftwareLists"
        if (-not (Test-Path $listsPath)) { New-Item $listsPath -ItemType Directory -Force | Out-Null }
        @{ name = $name; items = @() } | ConvertTo-Json | Out-File (Join-Path $listsPath "$name.json") -Encoding UTF8
        Update-SoftwareLists; Write-Log "Created list: $name" -Level Success
    }
})

$controls['SoftwareDelete'].Add_Click({
    $sel = $controls['SoftwareListBox'].SelectedItem
    if ($sel) {
        $result = [System.Windows.MessageBox]::Show("Delete '$sel'?", "Confirm", "YesNo", "Warning")
        if ($result -eq 'Yes') {
            Remove-Item (Join-Path $Script:AppRoot "SoftwareLists\$sel.json") -Force
            Update-SoftwareLists; Write-Log "Deleted: $sel" -Level Success
        }
    }
})

$controls['SoftwareGeneratePolicy'].Add_Click({
    $sel = $controls['SoftwareGenerateList'].SelectedItem
    if (-not $sel) { Write-Log "Select a list." -Level Error; return }
    $listPath = Join-Path $Script:AppRoot "SoftwareLists\$sel.json"
    Write-Log "Generating from $sel..." -Level Info
    Invoke-Script -ScriptName "New-AppLockerPolicyFromGuide.ps1" -Parameters @{ SoftwareListPath = $listPath; OutputPath = ".\Outputs"; Simplified = $true }
    Write-Log "Generation completed." -Level Success
})
#endregion

#region Initialization
# Add Microsoft.VisualBasic for InputBox
Add-Type -AssemblyName Microsoft.VisualBasic

Write-Log "GA-AppLocker Portable GUI started." -Level Info
Write-Log "App Root: $Script:AppRoot" -Level Info
Write-Log "Scripts Available: $Script:ScriptsAvailable" -Level Info

# Set paths
$controls['SettingsScriptsPath'].Text = $Script:AppRoot
$controls['ScriptsStatusText'].Text = if ($Script:ScriptsAvailable) { "Scripts found!" } else { "Scripts not found - configure path in Settings" }
$controls['ScanOutputPath'].Text = Join-Path $Script:AppRoot "Scans"
$controls['GenerateOutputPath'].Text = Join-Path $Script:AppRoot "Outputs"
$controls['MergeOutputPath'].Text = Join-Path $Script:AppRoot "Outputs"
$controls['EventsOutputPath'].Text = Join-Path $Script:AppRoot "Events"
$controls['CompareOutputPath'].Text = Join-Path $Script:AppRoot "Outputs"

Update-SoftwareLists

if (-not $Script:ScriptsAvailable) {
    Write-Log "To use all features, configure the scripts location in Settings." -Level Warning
}
#endregion

$window.ShowDialog() | Out-Null
