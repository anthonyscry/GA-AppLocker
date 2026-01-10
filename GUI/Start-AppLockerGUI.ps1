<#
.SYNOPSIS
    GA-AppLocker WPF GUI Application - Modern UI
.DESCRIPTION
    A modern graphical user interface for the GA-AppLocker toolkit.
    Features sidebar navigation, card-based layouts, and clean visual design.
.NOTES
    Author: GA-AppLocker Project
    Requires: PowerShell 5.1+, Windows Presentation Foundation
#>

#Requires -Version 5.1

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Get script root for relative paths (GUI folder is under AppRoot)
$Script:GUIRoot = $PSScriptRoot
if (-not $Script:GUIRoot) { $Script:GUIRoot = (Get-Location).Path }
$Script:AppRoot = Split-Path -Parent $Script:GUIRoot

# Import Common module
$commonPath = Join-Path $Script:AppRoot "utilities\Common.psm1"
if (Test-Path $commonPath) {
    Import-Module $commonPath -Force -ErrorAction SilentlyContinue
}

# Import Async helpers module
$asyncPath = Join-Path $Script:GUIRoot "AsyncHelpers.psm1"
if (Test-Path $asyncPath) {
    Import-Module $asyncPath -Force -ErrorAction SilentlyContinue
    Initialize-AsyncPool -MaxThreads 5
}

# Load configuration
$configPath = Join-Path $Script:AppRoot "utilities\Config.psd1"
$Script:Config = @{}
if (Test-Path $configPath) {
    $Script:Config = Import-PowerShellDataFile -Path $configPath
}

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
                                <TextBlock Text="Leave blank to use current credentials"
                                           FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,8,0,0"/>
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
                                <TextBlock Text="Select a scan folder containing computer subdirectories"
                                           FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,8,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Policy Mode" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>

                                <RadioButton x:Name="GenerateSimplified" Content="Simplified Mode" IsChecked="True" Margin="0,0,0,4"/>
                                <TextBlock Text="Quick deployment with single target user/group. Best for labs and testing."
                                           FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="20,0,0,16"/>

                                <RadioButton x:Name="GenerateBuildGuide" Content="Build Guide Mode" Margin="0,0,0,4"/>
                                <TextBlock Text="Enterprise deployment with proper scoping and phased rollout."
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
                        <TextBlock Text="Combine multiple AppLocker policy files with deduplication"
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
                        <TextBlock Text="Check an AppLocker policy for issues and security concerns"
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
                        <TextBlock Text="Collect AppLocker audit events (8003/8004) from remote computers"
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
                        <TextBlock Text="Compare software inventories between two systems to identify drift"
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
                                    <ComboBoxItem Content="Name - Compare by file name only"/>
                                    <ComboBoxItem Content="NameVersion - Compare by name and version"/>
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

                <!-- Software Lists Page -->
                <ScrollViewer x:Name="PageSoftware" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Software Lists" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Manage curated software allowlists for policy generation"
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
                                        <Button x:Name="SoftwareView" Content="View/Edit" Style="{StaticResource SmallButton}" Margin="0,0,0,4"/>
                                        <Button x:Name="SoftwareDelete" Content="Delete" Style="{StaticResource SmallButton}"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Import Options" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <WrapPanel>
                                    <Button x:Name="SoftwareImportScan" Content="From Scan Data" Style="{StaticResource SecondaryButton}" Margin="0,0,8,8"/>
                                    <Button x:Name="SoftwareImportPolicy" Content="From Policy XML" Style="{StaticResource SecondaryButton}" Margin="0,0,8,8"/>
                                    <Button x:Name="SoftwareImportPublishers" Content="Common Publishers" Style="{StaticResource SecondaryButton}" Margin="0,0,8,8"/>
                                    <Button x:Name="SoftwareImportCSV" Content="From CSV" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8"/>
                                </WrapPanel>
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
                                    <Button x:Name="SoftwareGeneratePolicy" Grid.Column="1" Content="Generate Policy"
                                            Style="{StaticResource PrimaryButton}" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- AD Management Page -->
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
                                <TextBlock Text="Parent OU (optional)" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                <TextBox x:Name="ADParentOU" Margin="0,0,0,12"/>
                                <TextBlock Text="Group Prefix" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                <TextBox x:Name="ADGroupPrefix" Text="AppLocker" Margin="0,0,0,16"/>
                                <Button x:Name="ADSetup" Content="Create AppLocker OUs and Groups" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Computer Export" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <TextBlock Text="Search Base (optional)" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                <TextBox x:Name="ADSearchBase" Margin="0,0,0,16"/>
                                <Button x:Name="ADExportComputers" Content="Export Computer List" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="User Group Management" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <WrapPanel>
                                    <Button x:Name="ADExportUsers" Content="Export User Groups" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                                    <Button x:Name="ADImportUsers" Content="Import Group Changes" Style="{StaticResource SecondaryButton}"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- Diagnostics Page -->
                <ScrollViewer x:Name="PageDiagnostics" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="Diagnostics" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Troubleshoot connectivity and scanning issues"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Test Type" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <ComboBox x:Name="DiagnosticType" SelectedIndex="0">
                                    <ComboBoxItem Content="Connectivity - Test ping, WinRM, sessions"/>
                                    <ComboBoxItem Content="JobSession - Test PowerShell job execution"/>
                                    <ComboBoxItem Content="JobFull - Full job test with tracing"/>
                                    <ComboBoxItem Content="SimpleScan - Scan without parallel jobs"/>
                                </ComboBox>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Target Computer" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                <RadioButton x:Name="DiagnosticSingle" Content="Single Computer" IsChecked="True" Margin="0,0,0,8"/>
                                <TextBox x:Name="DiagnosticComputerName" Margin="0,0,0,12"/>
                                <RadioButton x:Name="DiagnosticMultiple" Content="Computer List" Margin="0,0,0,8"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="DiagnosticComputerList" Grid.Column="0" IsEnabled="False"/>
                                    <Button x:Name="BrowseDiagnosticList" Grid.Column="1" Content="Browse"
                                            Style="{StaticResource SecondaryButton}" Margin="8,0,0,0" IsEnabled="False"/>
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
                                        <TextBox x:Name="DiagnosticUsername"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="Password" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                        <PasswordBox x:Name="DiagnosticPassword"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Button x:Name="StartDiagnostic" Content="Run Diagnostic" Style="{StaticResource PrimaryButton}"
                                HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    </StackPanel>
                </ScrollViewer>

                <!-- WinRM Page -->
                <ScrollViewer x:Name="PageWinRM" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="32,24,32,32">
                        <TextBlock Text="WinRM Setup" FontSize="24" FontWeight="SemiBold"
                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                        <TextBlock Text="Deploy or remove WinRM Group Policy Objects for remote scanning"
                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,24"/>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Deploy WinRM GPO" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                <TextBlock Text="Creates a Group Policy Object to enable WinRM on domain computers"
                                           FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,16"/>
                                <Button x:Name="WinRMDeploy" Content="Deploy WinRM GPO" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Remove WinRM GPO" FontSize="14" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                <TextBlock Text="Removes the WinRM GPO created by this tool"
                                           FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,16"/>
                                <Button x:Name="WinRMRemove" Content="Remove WinRM GPO" Style="{StaticResource SecondaryButton}" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </Grid>

            <!-- Log Panel (Collapsible) -->
            <Border x:Name="LogPanel" Grid.Row="1" Background="{StaticResource BgSidebarBrush}"
                    BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0"
                    Height="200">
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
                            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="Output Log" FontSize="12" FontWeight="SemiBold"
                                           Foreground="{StaticResource TextPrimaryBrush}" VerticalAlignment="Center"/>
                                <ProgressBar x:Name="ProgressBar" Width="150" Height="4" Margin="16,0,0,0"
                                             Visibility="Collapsed" Background="#30363D" Foreground="{StaticResource AccentBlueBrush}"/>
                                <TextBlock x:Name="ProgressText" Text="" FontSize="11"
                                           Foreground="{StaticResource TextSecondaryBrush}"
                                           VerticalAlignment="Center" Margin="8,0,0,0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button x:Name="ToggleLog" Content="Hide" Style="{StaticResource SmallButton}" Margin="0,0,8,0"/>
                                <Button x:Name="ClearLog" Content="Clear" Style="{StaticResource SmallButton}" Margin="0,0,8,0"/>
                                <Button x:Name="SaveLog" Content="Save" Style="{StaticResource SmallButton}"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <TextBox x:Name="LogOutput" Grid.Row="1"
                             IsReadOnly="True"
                             TextWrapping="NoWrap"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             FontFamily="Consolas"
                             FontSize="11"
                             Background="{StaticResource BgDarkBrush}"
                             Foreground="{StaticResource TextSecondaryBrush}"
                             BorderThickness="0"
                             Padding="16,8"/>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@
#endregion

#region Window Creation
# Create window from XAML
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get all named controls
$controls = @{}
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    $name = $_.Name
    if (-not $name) { $name = $_.'x:Name' }
    if ($name) {
        $controls[$name] = $window.FindName($name)
    }
}
#endregion

#region Helper Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        'Success' { "[+]" }
        'Warning' { "[!]" }
        'Error'   { "[-]" }
        default   { "[*]" }
    }

    $logMessage = "[$timestamp] $prefix $Message`r`n"

    $controls['LogOutput'].Dispatcher.Invoke([Action]{
        $controls['LogOutput'].AppendText($logMessage)
        $controls['LogOutput'].ScrollToEnd()
    })
}

# PSScriptAnalyzer: Set-Status only updates UI elements
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
function Set-Status {
    param(
        [string]$Status,
        [ValidateSet('Ready', 'Running', 'Success', 'Error')]
        [string]$State = 'Ready'
    )

    $controls['StatusText'].Dispatcher.Invoke([Action]{
        $controls['StatusText'].Text = switch ($State) {
            'Running' { "Running..." }
            'Success' { "Complete" }
            'Error'   { "Error" }
            default   { "Ready" }
        }
        $controls['StatusDot'].Fill = switch ($State) {
            'Running' { [System.Windows.Media.Brushes]::Orange }
            'Success' { [System.Windows.Media.Brushes]::LightGreen }
            'Error'   { [System.Windows.Media.Brushes]::Red }
            default   { [System.Windows.Media.Brushes]::LightGreen }
        }
    })
}

function Show-Progress {
    param(
        [int]$Percent,
        [string]$Text = ""
    )

    $controls['ProgressBar'].Dispatcher.Invoke([Action]{
        $controls['ProgressBar'].Visibility = 'Visible'
        $controls['ProgressBar'].Value = $Percent
        $controls['ProgressText'].Text = $Text
    })
}

function Hide-Progress {
    $controls['ProgressBar'].Dispatcher.Invoke([Action]{
        $controls['ProgressBar'].Visibility = 'Collapsed'
        $controls['ProgressText'].Text = ""
    })
}

function Get-OpenFileDialog {
    param(
        [string]$Title = "Select File",
        [string]$Filter = "All Files (*.*)|*.*",
        [string]$InitialDirectory = $Script:AppRoot
    )

    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = $Filter
    $dialog.InitialDirectory = $InitialDirectory

    if ($dialog.ShowDialog() -eq $true) {
        return $dialog.FileName
    }
    return $null
}

function Get-FolderDialog {
    param(
        [string]$Description = "Select Folder",
        [string]$InitialDirectory = $Script:AppRoot
    )

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.SelectedPath = $InitialDirectory

    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-Credential-FromInputs {
    param(
        [string]$Username,
        [System.Security.SecureString]$Password
    )

    if ([string]::IsNullOrWhiteSpace($Username)) {
        return $null
    }

    if ($Password -eq $null -or $Password.Length -eq 0) {
        return $null
    }

    return New-Object System.Management.Automation.PSCredential($Username, $Password)
}

function Update-SoftwareLists {
    $controls['SoftwareListBox'].Items.Clear()
    $controls['SoftwareGenerateList'].Items.Clear()

    $listsPath = Join-Path $Script:AppRoot "SoftwareLists"
    if (Test-Path $listsPath) {
        Get-ChildItem -Path $listsPath -Filter "*.json" | ForEach-Object {
            $controls['SoftwareListBox'].Items.Add($_.BaseName)
            $controls['SoftwareGenerateList'].Items.Add($_.BaseName)
        }
    }

    if ($controls['SoftwareGenerateList'].Items.Count -gt 0) {
        $controls['SoftwareGenerateList'].SelectedIndex = 0
    }
}

# Navigation helper
$Script:CurrentPage = "Scan"
$Script:Pages = @("Scan", "Generate", "Merge", "Validate", "Events", "Compare", "Software", "AD", "Diagnostics", "WinRM")

function Switch-Page {
    param([string]$PageName)

    # Hide all pages
    foreach ($page in $Script:Pages) {
        $controls["Page$page"].Visibility = 'Collapsed'
    }

    # Show selected page
    $controls["Page$PageName"].Visibility = 'Visible'

    # Update navigation button styles
    foreach ($page in $Script:Pages) {
        $navButton = $controls["Nav$page"]
        if ($navButton) {
            if ($page -eq $PageName) {
                $navButton.Style = $window.FindResource("NavButtonActive")
            } else {
                $navButton.Style = $window.FindResource("NavButton")
            }
        }
    }

    $Script:CurrentPage = $PageName
}
#endregion

#region Navigation Event Handlers
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
#endregion

#region UI State Handlers
# Build Guide toggle visibility
$controls['GenerateBuildGuide'].Add_Checked({
    $controls['BuildGuideOptions'].Visibility = 'Visible'
})

$controls['GenerateSimplified'].Add_Checked({
    $controls['BuildGuideOptions'].Visibility = 'Collapsed'
})

# Diagnostic mode toggle
$controls['DiagnosticSingle'].Add_Checked({
    $controls['DiagnosticComputerName'].IsEnabled = $true
    $controls['DiagnosticComputerList'].IsEnabled = $false
    $controls['BrowseDiagnosticList'].IsEnabled = $false
})

$controls['DiagnosticMultiple'].Add_Checked({
    $controls['DiagnosticComputerName'].IsEnabled = $false
    $controls['DiagnosticComputerList'].IsEnabled = $true
    $controls['BrowseDiagnosticList'].IsEnabled = $true
})

# Log panel toggle
$Script:LogExpanded = $true
$controls['ToggleLog'].Add_Click({
    if ($Script:LogExpanded) {
        $controls['LogPanel'].Height = 36
        $controls['ToggleLog'].Content = "Show"
        $Script:LogExpanded = $false
    } else {
        $controls['LogPanel'].Height = 200
        $controls['ToggleLog'].Content = "Hide"
        $Script:LogExpanded = $true
    }
})
#endregion

#region Browse Button Handlers
$controls['BrowseScanComputerList'].Add_Click({
    $file = Get-OpenFileDialog -Title "Select Computer List" -Filter "Text/CSV Files (*.txt;*.csv)|*.txt;*.csv|All Files (*.*)|*.*"
    if ($file) { $controls['ScanComputerList'].Text = $file }
})

$controls['BrowseScanOutput'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Scan Output Folder"
    if ($folder) { $controls['ScanOutputPath'].Text = $folder }
})

$controls['BrowseGenerateScanPath'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Scan Data Folder"
    if ($folder) { $controls['GenerateScanPath'].Text = $folder }
})

$controls['BrowseGenerateOutput'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Output Folder"
    if ($folder) { $controls['GenerateOutputPath'].Text = $folder }
})

$controls['BrowseMergeOutput'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Output Folder"
    if ($folder) { $controls['MergeOutputPath'].Text = $folder }
})

$controls['BrowseValidatePolicy'].Add_Click({
    $file = Get-OpenFileDialog -Title "Select Policy File" -Filter "XML Files (*.xml)|*.xml|All Files (*.*)|*.*"
    if ($file) { $controls['ValidatePolicyPath'].Text = $file }
})

$controls['BrowseEventsComputerList'].Add_Click({
    $file = Get-OpenFileDialog -Title "Select Computer List" -Filter "Text/CSV Files (*.txt;*.csv)|*.txt;*.csv|All Files (*.*)|*.*"
    if ($file) { $controls['EventsComputerList'].Text = $file }
})

$controls['BrowseEventsOutput'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Events Output Folder"
    if ($folder) { $controls['EventsOutputPath'].Text = $folder }
})

$controls['BrowseCompareReference'].Add_Click({
    $file = Get-OpenFileDialog -Title "Select Reference CSV" -Filter "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
    if ($file) { $controls['CompareReferencePath'].Text = $file }
})

$controls['BrowseCompareTarget'].Add_Click({
    $file = Get-OpenFileDialog -Title "Select Target CSV" -Filter "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
    if ($file) { $controls['CompareTargetPath'].Text = $file }
})

$controls['BrowseCompareOutput'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Output Folder"
    if ($folder) { $controls['CompareOutputPath'].Text = $folder }
})

$controls['BrowseDiagnosticList'].Add_Click({
    $file = Get-OpenFileDialog -Title "Select Computer List" -Filter "Text/CSV Files (*.txt;*.csv)|*.txt;*.csv|All Files (*.*)|*.*"
    if ($file) { $controls['DiagnosticComputerList'].Text = $file }
})
#endregion

#region Merge Policy List Management
$controls['MergeAddFile'].Add_Click({
    $file = Get-OpenFileDialog -Title "Select Policy File" -Filter "XML Files (*.xml)|*.xml|All Files (*.*)|*.*"
    if ($file) {
        $controls['MergePolicyList'].Items.Add($file)
    }
})

$controls['MergeAddFolder'].Add_Click({
    $folder = Get-FolderDialog -Description "Select Folder with Policy Files"
    if ($folder) {
        Get-ChildItem -Path $folder -Filter "*.xml" | ForEach-Object {
            $controls['MergePolicyList'].Items.Add($_.FullName)
        }
    }
})

$controls['MergeRemoveFile'].Add_Click({
    if ($controls['MergePolicyList'].SelectedItem) {
        $controls['MergePolicyList'].Items.Remove($controls['MergePolicyList'].SelectedItem)
    }
})

$controls['MergeClearList'].Add_Click({
    $controls['MergePolicyList'].Items.Clear()
})
#endregion

#region Log Management
$controls['ClearLog'].Add_Click({
    $controls['LogOutput'].Clear()
})

$controls['SaveLog'].Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = "Save Log File"
    $dialog.Filter = "Text Files (*.txt)|*.txt|Log Files (*.log)|*.log"
    $dialog.FileName = "AppLockerGUI-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    if ($dialog.ShowDialog() -eq $true) {
        $controls['LogOutput'].Text | Out-File -FilePath $dialog.FileName -Encoding UTF8
        Write-Log "Log saved to: $($dialog.FileName)" -Level Success
    }
})
#endregion

#region Software List Management
$controls['SoftwareRefresh'].Add_Click({
    Update-SoftwareLists
    Write-Log "Software lists refreshed." -Level Info
})

$controls['SoftwareNew'].Add_Click({
    $inputDialog = New-Object System.Windows.Window
    $inputDialog.Title = "New Software List"
    $inputDialog.Width = 400
    $inputDialog.Height = 150
    $inputDialog.WindowStartupLocation = "CenterOwner"
    $inputDialog.Owner = $window
    $inputDialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = 20

    $label = New-Object System.Windows.Controls.Label
    $label.Content = "List Name:"
    $label.Foreground = [System.Windows.Media.Brushes]::White

    $textbox = New-Object System.Windows.Controls.TextBox
    $textbox.Margin = "0,5,0,15"

    $button = New-Object System.Windows.Controls.Button
    $button.Content = "Create"
    $button.Width = 100
    $button.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($textbox.Text)) {
            $listsPath = Join-Path $Script:AppRoot "SoftwareLists"
            if (-not (Test-Path $listsPath)) {
                New-Item -Path $listsPath -ItemType Directory -Force | Out-Null
            }

            $listFile = Join-Path $listsPath "$($textbox.Text).json"
            @{
                name = $textbox.Text
                description = ""
                items = @()
            } | ConvertTo-Json | Out-File -FilePath $listFile -Encoding UTF8

            $inputDialog.DialogResult = $true
            $inputDialog.Close()
        }
    })

    $panel.Children.Add($label)
    $panel.Children.Add($textbox)
    $panel.Children.Add($button)
    $inputDialog.Content = $panel

    if ($inputDialog.ShowDialog()) {
        Update-SoftwareLists
        Write-Log "Created new software list: $($textbox.Text)" -Level Success
    }
})

$controls['SoftwareDelete'].Add_Click({
    $selected = $controls['SoftwareListBox'].SelectedItem
    if ($selected) {
        $result = [System.Windows.MessageBox]::Show(
            "Are you sure you want to delete '$selected'?",
            "Confirm Delete",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )

        if ($result -eq 'Yes') {
            $listFile = Join-Path $Script:AppRoot "SoftwareLists\$selected.json"
            if (Test-Path $listFile) {
                Remove-Item -Path $listFile -Force
                Update-SoftwareLists
                Write-Log "Deleted software list: $selected" -Level Success
            }
        }
    }
})
#endregion

#region Main Operations

# Start Scan
$controls['StartScan'].Add_Click({
    $computerList = $controls['ScanComputerList'].Text
    $outputPath = $controls['ScanOutputPath'].Text
    $username = $controls['ScanUsername'].Text
    $password = $controls['ScanPassword'].SecurePassword
    $scanUserProfiles = $controls['ScanUserProfiles'].IsChecked
    $throttleLimit = $controls['ScanThrottleLimit'].Text

    if ([string]::IsNullOrWhiteSpace($computerList)) {
        Write-Log "Please specify a computer list file." -Level Error
        return
    }

    if (-not (Test-Path $computerList)) {
        Write-Log "Computer list file not found: $computerList" -Level Error
        return
    }

    $cred = Get-Credential-FromInputs -Username $username -Password $password

    $params = @{
        ComputerList = $computerList
        OutputPath = $outputPath
        ThrottleLimit = [int]$throttleLimit
    }

    if ($scanUserProfiles) {
        $params['ScanUserProfiles'] = $true
    }

    Write-Log "Starting remote scan..." -Level Info
    Write-Log "Computer List: $computerList" -Level Info
    Write-Log "Output Path: $outputPath" -Level Info

    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "Invoke-RemoteScan.ps1"

    if ($cred) {
        & $scriptPath @params -Credential $cred 2>&1 | ForEach-Object { Write-Log $_.ToString() }
    } else {
        & $scriptPath @params 2>&1 | ForEach-Object { Write-Log $_.ToString() }
    }

    Set-Status -State 'Success'
    Write-Log "Scan operation completed." -Level Success
})

# Start Generate
$controls['StartGenerate'].Add_Click({
    $scanPath = $controls['GenerateScanPath'].Text
    $outputPath = $controls['GenerateOutputPath'].Text
    $simplified = $controls['GenerateSimplified'].IsChecked
    $includeDeny = $controls['GenerateIncludeDenyRules'].IsChecked
    $includeVendor = $controls['GenerateIncludeVendorPublishers'].IsChecked

    if ([string]::IsNullOrWhiteSpace($scanPath)) {
        Write-Log "Please specify a scan data folder." -Level Error
        return
    }

    if (-not (Test-Path $scanPath)) {
        Write-Log "Scan folder not found: $scanPath" -Level Error
        return
    }

    $params = @{
        ScanPath = $scanPath
        OutputPath = $outputPath
    }

    if ($simplified) {
        $params['Simplified'] = $true
    } else {
        $targetType = $controls['GenerateTargetType'].Text
        $phase = $controls['GeneratePhase'].SelectedIndex + 1
        $domainName = $controls['GenerateDomainName'].Text

        if ([string]::IsNullOrWhiteSpace($domainName)) {
            Write-Log "Please specify a domain name for Build Guide mode." -Level Error
            return
        }

        $params['TargetType'] = $targetType
        $params['Phase'] = $phase
        $params['DomainName'] = $domainName
    }

    if ($includeDeny) {
        $params['IncludeDenyRules'] = $true
    }

    if ($includeVendor) {
        $params['IncludeVendorPublishers'] = $true
    }

    Write-Log "Starting policy generation..." -Level Info
    Write-Log "Scan Path: $scanPath" -Level Info
    Write-Log "Mode: $(if ($simplified) { 'Simplified' } else { 'Build Guide' })" -Level Info

    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "New-AppLockerPolicyFromGuide.ps1"
    & $scriptPath @params 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "Policy generation completed." -Level Success
})

# Start Merge
$controls['StartMerge'].Add_Click({
    $policyFiles = @($controls['MergePolicyList'].Items)
    $outputPath = $controls['MergeOutputPath'].Text

    if ($policyFiles.Count -lt 2) {
        Write-Log "Please add at least 2 policy files to merge." -Level Error
        return
    }

    Write-Log "Starting policy merge..." -Level Info
    Write-Log "Merging $($policyFiles.Count) policy files..." -Level Info

    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "Merge-AppLockerPolicies.ps1"
    & $scriptPath -PolicyPaths $policyFiles -OutputPath $outputPath 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "Policy merge completed." -Level Success
})

# Start Validate
$controls['StartValidate'].Add_Click({
    $policyPath = $controls['ValidatePolicyPath'].Text

    if ([string]::IsNullOrWhiteSpace($policyPath)) {
        Write-Log "Please specify a policy file to validate." -Level Error
        return
    }

    if (-not (Test-Path $policyPath)) {
        Write-Log "Policy file not found: $policyPath" -Level Error
        return
    }

    Write-Log "Validating policy: $policyPath" -Level Info
    Set-Status -State 'Running'

    try {
        [xml]$policy = Get-Content -Path $policyPath -Raw

        $results = @()
        $results += "Policy Validation Results"
        $results += "=" * 50
        $results += ""

        # Check root element
        if ($policy.DocumentElement.Name -eq 'AppLockerPolicy') {
            $results += "[+] Valid AppLocker policy structure"
        } else {
            $results += "[-] Invalid root element (expected AppLockerPolicy)"
        }

        # Count rules by collection
        $collections = $policy.AppLockerPolicy.RuleCollection
        $results += ""
        $results += "Rule Collections:"
        foreach ($collection in $collections) {
            $ruleCount = ($collection.ChildNodes | Where-Object { $_.LocalName -match 'Rule$' }).Count
            $enforcement = $collection.EnforcementMode
            $results += "  - $($collection.Type): $ruleCount rules ($enforcement)"
        }

        # Check for security issues
        $results += ""
        $results += "Security Checks:"

        $everyoneRules = $policy.SelectNodes("//*[contains(@UserOrGroupSid, 'S-1-1-0')]")
        if ($everyoneRules.Count -gt 0) {
            $results += "[!] Warning: $($everyoneRules.Count) rules apply to Everyone"
        } else {
            $results += "[+] No overly permissive 'Everyone' rules found"
        }

        $wildcardPaths = $policy.SelectNodes("//Conditions/FilePathCondition[contains(@Path, '*')]")
        if ($wildcardPaths.Count -gt 0) {
            $results += "[!] Warning: $($wildcardPaths.Count) wildcard path conditions found"
        }

        $controls['ValidationResultsCard'].Visibility = 'Visible'
        $controls['ValidationResults'].Text = $results -join "`r`n"

        Set-Status -State 'Success'
        Write-Log "Validation completed." -Level Success
    }
    catch {
        Write-Log "Error validating policy: $_" -Level Error
        Set-Status -State 'Error'
    }
})

# Start Events Collection
$controls['StartEvents'].Add_Click({
    $computerList = $controls['EventsComputerList'].Text
    $outputPath = $controls['EventsOutputPath'].Text
    $username = $controls['EventsUsername'].Text
    $password = $controls['EventsPassword'].SecurePassword

    $daysBackIndex = $controls['EventsDaysBack'].SelectedIndex
    $daysBack = switch ($daysBackIndex) {
        0 { 7 }
        1 { 14 }
        2 { 30 }
        3 { 90 }
        4 { 0 }  # All
        default { 14 }
    }

    $blockedOnly = $controls['EventsType'].SelectedIndex -eq 0

    if ([string]::IsNullOrWhiteSpace($computerList)) {
        Write-Log "Please specify a computer list file." -Level Error
        return
    }

    if (-not (Test-Path $computerList)) {
        Write-Log "Computer list file not found: $computerList" -Level Error
        return
    }

    $cred = Get-Credential-FromInputs -Username $username -Password $password

    $params = @{
        ComputerList = $computerList
        OutputPath = $outputPath
        DaysBack = $daysBack
    }

    if (-not $blockedOnly) {
        $params['IncludeAllowedEvents'] = $true
    }

    Write-Log "Starting event collection..." -Level Info
    Write-Log "Days Back: $(if ($daysBack -eq 0) { 'All' } else { $daysBack })" -Level Info

    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "Invoke-RemoteEventCollection.ps1"

    if ($cred) {
        & $scriptPath @params -Credential $cred 2>&1 | ForEach-Object { Write-Log $_.ToString() }
    } else {
        & $scriptPath @params 2>&1 | ForEach-Object { Write-Log $_.ToString() }
    }

    Set-Status -State 'Success'
    Write-Log "Event collection completed." -Level Success
})

# Start Compare
$controls['StartCompare'].Add_Click({
    $referencePath = $controls['CompareReferencePath'].Text
    $targetPath = $controls['CompareTargetPath'].Text
    $outputPath = $controls['CompareOutputPath'].Text

    $compareMethod = switch ($controls['CompareMethod'].SelectedIndex) {
        0 { "Name" }
        1 { "NameVersion" }
        2 { "Hash" }
        3 { "Publisher" }
        default { "Name" }
    }

    if ([string]::IsNullOrWhiteSpace($referencePath) -or [string]::IsNullOrWhiteSpace($targetPath)) {
        Write-Log "Please specify both reference and target CSV files." -Level Error
        return
    }

    if (-not (Test-Path $referencePath)) {
        Write-Log "Reference file not found: $referencePath" -Level Error
        return
    }

    if (-not (Test-Path $targetPath)) {
        Write-Log "Target file not found: $targetPath" -Level Error
        return
    }

    Write-Log "Starting inventory comparison..." -Level Info
    Write-Log "Compare Method: $compareMethod" -Level Info

    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "utilities\Compare-SoftwareInventory.ps1"
    & $scriptPath -ReferencePath $referencePath -ComparePath $targetPath -CompareBy $compareMethod -OutputPath $outputPath 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "Comparison completed." -Level Success
})

# Start Diagnostic
$controls['StartDiagnostic'].Add_Click({
    $diagType = switch ($controls['DiagnosticType'].SelectedIndex) {
        0 { "Connectivity" }
        1 { "JobSession" }
        2 { "JobFull" }
        3 { "SimpleScan" }
        default { "Connectivity" }
    }

    $username = $controls['DiagnosticUsername'].Text
    $password = $controls['DiagnosticPassword'].SecurePassword
    $cred = Get-Credential-FromInputs -Username $username -Password $password

    $params = @{
        DiagnosticType = $diagType
    }

    if ($controls['DiagnosticSingle'].IsChecked) {
        $computerName = $controls['DiagnosticComputerName'].Text
        if ([string]::IsNullOrWhiteSpace($computerName)) {
            Write-Log "Please specify a computer name." -Level Error
            return
        }
        $params['ComputerName'] = $computerName
    } else {
        $computerList = $controls['DiagnosticComputerList'].Text
        if ([string]::IsNullOrWhiteSpace($computerList)) {
            Write-Log "Please specify a computer list file." -Level Error
            return
        }
        $params['ComputerList'] = $computerList
    }

    Write-Log "Starting diagnostic: $diagType" -Level Info
    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "utilities\Test-AppLockerDiagnostic.ps1"

    if ($cred) {
        & $scriptPath @params -Credential $cred 2>&1 | ForEach-Object { Write-Log $_.ToString() }
    } else {
        & $scriptPath @params 2>&1 | ForEach-Object { Write-Log $_.ToString() }
    }

    Set-Status -State 'Success'
    Write-Log "Diagnostic completed." -Level Success
})

# AD Setup
$controls['ADSetup'].Add_Click({
    $domainName = $controls['ADDomainName'].Text
    $parentOU = $controls['ADParentOU'].Text
    $groupPrefix = $controls['ADGroupPrefix'].Text

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-Log "Please specify a domain name." -Level Error
        return
    }

    $params = @{
        DomainName = $domainName
        GroupPrefix = $groupPrefix
    }

    if (-not [string]::IsNullOrWhiteSpace($parentOU)) {
        $params['ParentOU'] = $parentOU
    }

    Write-Log "Setting up AD resources..." -Level Info
    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "utilities\Manage-ADResources.ps1"
    & $scriptPath -Action Setup @params 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "AD setup completed." -Level Success
})

# AD Export Computers
$controls['ADExportComputers'].Add_Click({
    $searchBase = $controls['ADSearchBase'].Text

    Write-Log "Exporting computer list from AD..." -Level Info
    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "utilities\Manage-ADResources.ps1"
    $params = @{ Action = 'ExportComputers' }

    if (-not [string]::IsNullOrWhiteSpace($searchBase)) {
        $params['SearchBase'] = $searchBase
    }

    & $scriptPath @params 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "Computer export completed." -Level Success
})

# WinRM Deploy
$controls['WinRMDeploy'].Add_Click({
    Write-Log "Deploying WinRM GPO..." -Level Info
    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "utilities\Enable-WinRM-Domain.ps1"
    & $scriptPath -Action Deploy 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "WinRM GPO deployment completed." -Level Success
})

# WinRM Remove
$controls['WinRMRemove'].Add_Click({
    Write-Log "Removing WinRM GPO..." -Level Info
    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "utilities\Enable-WinRM-Domain.ps1"
    & $scriptPath -Action Remove 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "WinRM GPO removal completed." -Level Success
})

# Software Import from Publishers
$controls['SoftwareImportPublishers'].Add_Click({
    $selected = $controls['SoftwareListBox'].SelectedItem
    if (-not $selected) {
        Write-Log "Please select a software list first." -Level Error
        return
    }

    Write-Log "Opening software list manager for publisher import..." -Level Info

    $scriptPath = Join-Path $Script:AppRoot "utilities\Manage-SoftwareLists.ps1"
    & $scriptPath -Action ImportPublishers -ListName $selected 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Write-Log "Publisher import completed." -Level Success
})

# Software Generate Policy
$controls['SoftwareGeneratePolicy'].Add_Click({
    $selected = $controls['SoftwareGenerateList'].SelectedItem
    if (-not $selected) {
        Write-Log "Please select a software list." -Level Error
        return
    }

    $listPath = Join-Path $Script:AppRoot "SoftwareLists\$selected.json"
    if (-not (Test-Path $listPath)) {
        Write-Log "Software list not found: $listPath" -Level Error
        return
    }

    Write-Log "Generating policy from software list: $selected" -Level Info
    Set-Status -State 'Running'

    $scriptPath = Join-Path $Script:AppRoot "New-AppLockerPolicyFromGuide.ps1"
    & $scriptPath -SoftwareListPath $listPath -OutputPath ".\Outputs" -Simplified 2>&1 | ForEach-Object { Write-Log $_.ToString() }

    Set-Status -State 'Success'
    Write-Log "Policy generation completed." -Level Success
})

#endregion

#region Initialization
Write-Log "GA-AppLocker GUI initialized." -Level Info
Write-Log "Application root: $Script:AppRoot" -Level Info

# Refresh software lists on load
Update-SoftwareLists

# Set default paths
$controls['ScanOutputPath'].Text = Join-Path $Script:AppRoot "Scans"
$controls['GenerateOutputPath'].Text = Join-Path $Script:AppRoot "Outputs"
$controls['MergeOutputPath'].Text = Join-Path $Script:AppRoot "Outputs"
$controls['EventsOutputPath'].Text = Join-Path $Script:AppRoot "Events"
$controls['CompareOutputPath'].Text = Join-Path $Script:AppRoot "Outputs"

# Window closing handler - cleanup async pool
$window.Add_Closing({
    Write-Log "Shutting down..." -Level Info
    if (Get-Command 'Close-AsyncPool' -ErrorAction SilentlyContinue) {
        Close-AsyncPool
    }
})
#endregion

# Show the window
$window.ShowDialog() | Out-Null
