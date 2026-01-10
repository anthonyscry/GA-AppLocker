<#
.SYNOPSIS
    GA-AppLocker WPF GUI Application
.DESCRIPTION
    A graphical user interface for the GA-AppLocker toolkit.
    Provides access to all workflows: Scan, Generate, Merge, Validate, Events, Compare, and more.
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
    Height="750"
    Width="1100"
    WindowStartupLocation="CenterScreen"
    Background="#1E1E1E">

    <Window.Resources>
        <!-- Color Scheme -->
        <SolidColorBrush x:Key="PrimaryBrush" Color="#0078D4"/>
        <SolidColorBrush x:Key="SecondaryBrush" Color="#106EBE"/>
        <SolidColorBrush x:Key="BackgroundBrush" Color="#1E1E1E"/>
        <SolidColorBrush x:Key="PanelBrush" Color="#252526"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#3F3F46"/>
        <SolidColorBrush x:Key="TextBrush" Color="#CCCCCC"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="#4EC9B0"/>
        <SolidColorBrush x:Key="WarningBrush" Color="#DCDCAA"/>
        <SolidColorBrush x:Key="ErrorBrush" Color="#F14C4C"/>

        <!-- Button Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="{StaticResource SecondaryBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#555555"/>
                                <Setter Property="Foreground" Value="#888888"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#3C3C3C"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="CaretBrush" Value="White"/>
        </Style>

        <!-- ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#3C3C3C"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Margin" Value="5"/>
        </Style>

        <!-- CheckBox Style -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="Margin" Value="5"/>
        </Style>

        <!-- Label Style -->
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="Margin" Value="5,5,5,0"/>
        </Style>

        <!-- GroupBox Style -->
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="Padding" Value="10"/>
        </Style>

        <!-- TabItem Style -->
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="Background" Value="{StaticResource PanelBrush}"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Border" Background="{StaticResource PanelBrush}"
                                BorderBrush="{StaticResource BorderBrush}"
                                BorderThickness="1,1,1,0" CornerRadius="4,4,0,0"
                                Padding="{TemplateBinding Padding}" Margin="2,0,2,0">
                            <ContentPresenter x:Name="ContentSite" ContentSource="Header"
                                              HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="{StaticResource PrimaryBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="{StaticResource SecondaryBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="200"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="{StaticResource PanelBrush}" Padding="15">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="GA-AppLocker Toolkit" FontSize="24" FontWeight="Bold"
                               Foreground="{StaticResource PrimaryBrush}"/>
                    <TextBlock Text="Windows AppLocker Policy Management" FontSize="12"
                               Foreground="{StaticResource TextBrush}" Margin="0,5,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="StatusIndicator" Text="● Ready" Foreground="{StaticResource SuccessBrush}"
                               FontSize="14" VerticalAlignment="Center" Margin="10,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Content -->
        <TabControl Grid.Row="1" x:Name="MainTabs" Background="{StaticResource BackgroundBrush}"
                    BorderBrush="{StaticResource BorderBrush}" Margin="10,10,10,0">

            <!-- Scan Tab -->
            <TabItem Header="📡 Scan">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Remote Computer Scanning" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Collect application inventory data from remote computers via WinRM."
                                   Foreground="#888888" Margin="0,0,0,20" TextWrapping="Wrap"/>

                        <GroupBox Header="Computer List">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="ScanComputerList" Grid.Column="0"/>
                                    <Button x:Name="BrowseScanComputerList" Grid.Column="1" Content="Browse..." Width="100"/>
                                </Grid>
                                <TextBlock Text="Text file (one per line) or CSV with ComputerName column"
                                           Foreground="#888888" FontSize="11" Margin="5,0,0,0"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Credentials">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <Label Content="Username (DOMAIN\User):"/>
                                    <TextBox x:Name="ScanUsername"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <Label Content="Password:"/>
                                    <PasswordBox x:Name="ScanPassword" Background="#3C3C3C"
                                                 Foreground="{StaticResource TextBrush}"
                                                 BorderBrush="{StaticResource BorderBrush}"
                                                 Padding="8,6" Margin="5"/>
                                </StackPanel>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Options">
                            <WrapPanel>
                                <CheckBox x:Name="ScanUserProfiles" Content="Scan User Profiles" Margin="10,5"/>
                                <CheckBox x:Name="ScanIncludeDLLs" Content="Include DLLs" Margin="10,5"/>
                                <StackPanel Orientation="Horizontal" Margin="10,5">
                                    <Label Content="Throttle Limit:" VerticalAlignment="Center"/>
                                    <TextBox x:Name="ScanThrottleLimit" Text="10" Width="50"/>
                                </StackPanel>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Output">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="ScanOutputPath" Grid.Column="0" Text=".\Scans"/>
                                <Button x:Name="BrowseScanOutput" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <Button x:Name="StartScan" Content="Start Scan" HorizontalAlignment="Left"
                                FontSize="14" Padding="30,12" Margin="5,15,5,5"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Generate Tab -->
            <TabItem Header="📝 Generate">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Policy Generation" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Create AppLocker policies from scan data."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="Scan Data Source">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="GenerateScanPath" Grid.Column="0"/>
                                    <Button x:Name="BrowseGenerateScanPath" Grid.Column="1" Content="Browse..." Width="100"/>
                                </Grid>
                                <TextBlock Text="Select a scan folder containing computer subdirectories"
                                           Foreground="#888888" FontSize="11" Margin="5,0,0,0"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Policy Mode">
                            <StackPanel>
                                <RadioButton x:Name="GenerateSimplified" Content="Simplified Mode"
                                             Foreground="{StaticResource TextBrush}" IsChecked="True" Margin="5"/>
                                <TextBlock Text="Quick deployment - single target user/group"
                                           Foreground="#888888" FontSize="11" Margin="25,0,0,10"/>

                                <RadioButton x:Name="GenerateBuildGuide" Content="Build Guide Mode"
                                             Foreground="{StaticResource TextBrush}" Margin="5"/>
                                <TextBlock Text="Enterprise deployment - proper scoping, phased rollout"
                                           Foreground="#888888" FontSize="11" Margin="25,0,0,5"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox x:Name="BuildGuideOptions" Header="Build Guide Options" Visibility="Collapsed">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <Label Content="Target Type:"/>
                                        <ComboBox x:Name="GenerateTargetType" SelectedIndex="0">
                                            <ComboBoxItem Content="Workstation"/>
                                            <ComboBoxItem Content="Server"/>
                                            <ComboBoxItem Content="DomainController"/>
                                        </ComboBox>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1">
                                        <Label Content="Phase:"/>
                                        <ComboBox x:Name="GeneratePhase" SelectedIndex="0">
                                            <ComboBoxItem Content="Phase 1 - EXE only (lowest risk)"/>
                                            <ComboBoxItem Content="Phase 2 - EXE + Script"/>
                                            <ComboBoxItem Content="Phase 3 - EXE + Script + MSI"/>
                                            <ComboBoxItem Content="Phase 4 - Full (EXE + Script + MSI + DLL)"/>
                                        </ComboBox>
                                    </StackPanel>
                                </Grid>
                                <Label Content="Domain Name:"/>
                                <TextBox x:Name="GenerateDomainName" />
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Additional Options">
                            <WrapPanel>
                                <CheckBox x:Name="GenerateIncludeDenyRules" Content="Include LOLBins Deny Rules" Margin="10,5"/>
                                <CheckBox x:Name="GenerateIncludeVendorPublishers" Content="Trust Vendor Publishers" Margin="10,5"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Output">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="GenerateOutputPath" Grid.Column="0" Text=".\Outputs"/>
                                <Button x:Name="BrowseGenerateOutput" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <Button x:Name="StartGenerate" Content="Generate Policy" HorizontalAlignment="Left"
                                FontSize="14" Padding="30,12" Margin="5,15,5,5"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Merge Tab -->
            <TabItem Header="🔗 Merge">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Policy Merge" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Combine multiple AppLocker policy files with deduplication."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="Policy Files">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ListBox x:Name="MergePolicyList" Grid.Column="0" Height="150"
                                             Background="#3C3C3C" Foreground="{StaticResource TextBrush}"
                                             BorderBrush="{StaticResource BorderBrush}"/>
                                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                        <Button x:Name="MergeAddFile" Content="Add File" Width="100"/>
                                        <Button x:Name="MergeAddFolder" Content="Add Folder" Width="100"/>
                                        <Button x:Name="MergeRemoveFile" Content="Remove" Width="100"/>
                                        <Button x:Name="MergeClearList" Content="Clear All" Width="100"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Output">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="MergeOutputPath" Grid.Column="0" Text=".\Outputs"/>
                                <Button x:Name="BrowseMergeOutput" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <Button x:Name="StartMerge" Content="Merge Policies" HorizontalAlignment="Left"
                                FontSize="14" Padding="30,12" Margin="5,15,5,5"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Validate Tab -->
            <TabItem Header="✓ Validate">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Policy Validation" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Check an AppLocker policy file for issues and security concerns."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="Policy File">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="ValidatePolicyPath" Grid.Column="0"/>
                                <Button x:Name="BrowseValidatePolicy" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Validation Results" Visibility="Collapsed" x:Name="ValidationResultsGroup">
                            <StackPanel>
                                <TextBox x:Name="ValidationResults" Height="300"
                                         IsReadOnly="True" TextWrapping="Wrap"
                                         VerticalScrollBarVisibility="Auto"
                                         FontFamily="Consolas" FontSize="12"/>
                            </StackPanel>
                        </GroupBox>

                        <Button x:Name="StartValidate" Content="Validate Policy" HorizontalAlignment="Left"
                                FontSize="14" Padding="30,12" Margin="5,15,5,5"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Events Tab -->
            <TabItem Header="📊 Events">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="AppLocker Event Collection" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Collect AppLocker audit events (8003/8004) from remote computers."
                                   Foreground="#888888" Margin="0,0,0,20" TextWrapping="Wrap"/>

                        <GroupBox Header="Computer List">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="EventsComputerList" Grid.Column="0"/>
                                <Button x:Name="BrowseEventsComputerList" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Credentials">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <Label Content="Username (DOMAIN\User):"/>
                                    <TextBox x:Name="EventsUsername"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <Label Content="Password:"/>
                                    <PasswordBox x:Name="EventsPassword" Background="#3C3C3C"
                                                 Foreground="{StaticResource TextBrush}"
                                                 BorderBrush="{StaticResource BorderBrush}"
                                                 Padding="8,6" Margin="5"/>
                                </StackPanel>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Event Options">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <Label Content="Days Back:"/>
                                        <ComboBox x:Name="EventsDaysBack" SelectedIndex="1">
                                            <ComboBoxItem Content="7 days"/>
                                            <ComboBoxItem Content="14 days"/>
                                            <ComboBoxItem Content="30 days"/>
                                            <ComboBoxItem Content="90 days"/>
                                            <ComboBoxItem Content="All available"/>
                                        </ComboBox>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1">
                                        <Label Content="Event Types:"/>
                                        <ComboBox x:Name="EventsType" SelectedIndex="0">
                                            <ComboBoxItem Content="Blocked Only (8004/8006/8008)"/>
                                            <ComboBoxItem Content="All Audit Events"/>
                                        </ComboBox>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Output">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="EventsOutputPath" Grid.Column="0" Text=".\Events"/>
                                <Button x:Name="BrowseEventsOutput" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <Button x:Name="StartEvents" Content="Collect Events" HorizontalAlignment="Left"
                                FontSize="14" Padding="30,12" Margin="5,15,5,5"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Compare Tab -->
            <TabItem Header="⚖ Compare">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Software Inventory Comparison" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Compare executables between two machines to identify drift."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="Reference (Baseline)">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="CompareReferencePath" Grid.Column="0"/>
                                <Button x:Name="BrowseCompareReference" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Compare (Target)">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="CompareTargetPath" Grid.Column="0"/>
                                <Button x:Name="BrowseCompareTarget" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Comparison Method">
                            <ComboBox x:Name="CompareMethod" SelectedIndex="0">
                                <ComboBoxItem Content="Name - Compare by file name only"/>
                                <ComboBoxItem Content="NameVersion - Compare by name and version"/>
                                <ComboBoxItem Content="Hash - Compare by file hash"/>
                                <ComboBoxItem Content="Publisher - Compare by publisher"/>
                            </ComboBox>
                        </GroupBox>

                        <GroupBox Header="Output">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="CompareOutputPath" Grid.Column="0" Text=".\Outputs"/>
                                <Button x:Name="BrowseCompareOutput" Grid.Column="1" Content="Browse..." Width="100"/>
                            </Grid>
                        </GroupBox>

                        <Button x:Name="StartCompare" Content="Compare Inventories" HorizontalAlignment="Left"
                                FontSize="14" Padding="30,12" Margin="5,15,5,5"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Software Lists Tab -->
            <TabItem Header="📋 Software">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Software List Management" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Manage curated software allowlists for policy generation."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="Available Lists">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ListBox x:Name="SoftwareListBox" Grid.Column="0" Height="150"
                                             Background="#3C3C3C" Foreground="{StaticResource TextBrush}"
                                             BorderBrush="{StaticResource BorderBrush}"/>
                                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                        <Button x:Name="SoftwareRefresh" Content="Refresh" Width="100"/>
                                        <Button x:Name="SoftwareNew" Content="New List" Width="100"/>
                                        <Button x:Name="SoftwareView" Content="View/Edit" Width="100"/>
                                        <Button x:Name="SoftwareDelete" Content="Delete" Width="100"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Import Options">
                            <WrapPanel>
                                <Button x:Name="SoftwareImportScan" Content="From Scan Data" Width="130"/>
                                <Button x:Name="SoftwareImportPolicy" Content="From Policy XML" Width="130"/>
                                <Button x:Name="SoftwareImportPublishers" Content="Common Publishers" Width="130"/>
                                <Button x:Name="SoftwareImportCSV" Content="From CSV" Width="130"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Generate Policy from List">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ComboBox x:Name="SoftwareGenerateList" Grid.Column="0"/>
                                    <Button x:Name="SoftwareGeneratePolicy" Grid.Column="1" Content="Generate Policy" Width="120"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- AD Management Tab -->
            <TabItem Header="🏢 AD">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Active Directory Management" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Manage AD resources for AppLocker deployment."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="AD Setup">
                            <StackPanel>
                                <Label Content="Domain Name:"/>
                                <TextBox x:Name="ADDomainName"/>
                                <Label Content="Parent OU (optional):"/>
                                <TextBox x:Name="ADParentOU"/>
                                <Label Content="Group Prefix:"/>
                                <TextBox x:Name="ADGroupPrefix" Text="AppLocker"/>
                                <Button x:Name="ADSetup" Content="Create AppLocker OUs and Groups"
                                        HorizontalAlignment="Left" Margin="5,15,5,5"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Computer Export">
                            <StackPanel>
                                <Label Content="Search Base (optional):"/>
                                <TextBox x:Name="ADSearchBase"/>
                                <Button x:Name="ADExportComputers" Content="Export Computer List"
                                        HorizontalAlignment="Left" Margin="5,10,5,5"/>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="User Group Export/Import">
                            <WrapPanel>
                                <Button x:Name="ADExportUsers" Content="Export User Groups" Width="150"/>
                                <Button x:Name="ADImportUsers" Content="Import Group Changes" Width="150"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Diagnostics Tab -->
            <TabItem Header="🔧 Diagnostics">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="Diagnostic Tools" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Troubleshoot connectivity and scanning issues."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="Test Type">
                            <ComboBox x:Name="DiagnosticType" SelectedIndex="0">
                                <ComboBoxItem Content="Connectivity - Test ping, WinRM, sessions"/>
                                <ComboBoxItem Content="JobSession - Test PowerShell job execution"/>
                                <ComboBoxItem Content="JobFull - Full job test with tracing"/>
                                <ComboBoxItem Content="SimpleScan - Scan without parallel jobs"/>
                            </ComboBox>
                        </GroupBox>

                        <GroupBox Header="Target Computer">
                            <StackPanel>
                                <RadioButton x:Name="DiagnosticSingle" Content="Single Computer"
                                             Foreground="{StaticResource TextBrush}" IsChecked="True" Margin="5"/>
                                <TextBox x:Name="DiagnosticComputerName"/>
                                <RadioButton x:Name="DiagnosticMultiple" Content="Computer List"
                                             Foreground="{StaticResource TextBrush}" Margin="5,15,5,5"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="DiagnosticComputerList" Grid.Column="0" IsEnabled="False"/>
                                    <Button x:Name="BrowseDiagnosticList" Grid.Column="1" Content="Browse..."
                                            Width="100" IsEnabled="False"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Credentials">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <Label Content="Username (DOMAIN\User):"/>
                                    <TextBox x:Name="DiagnosticUsername"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <Label Content="Password:"/>
                                    <PasswordBox x:Name="DiagnosticPassword" Background="#3C3C3C"
                                                 Foreground="{StaticResource TextBrush}"
                                                 BorderBrush="{StaticResource BorderBrush}"
                                                 Padding="8,6" Margin="5"/>
                                </StackPanel>
                            </Grid>
                        </GroupBox>

                        <Button x:Name="StartDiagnostic" Content="Run Diagnostic" HorizontalAlignment="Left"
                                FontSize="14" Padding="30,12" Margin="5,15,5,5"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- WinRM Tab -->
            <TabItem Header="🌐 WinRM">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="WinRM GPO Management" FontSize="18" FontWeight="Bold"
                                   Foreground="{StaticResource TextBrush}" Margin="0,0,0,15"/>
                        <TextBlock Text="Deploy or remove WinRM Group Policy Objects for remote scanning."
                                   Foreground="#888888" Margin="0,0,0,20"/>

                        <GroupBox Header="WinRM GPO Actions">
                            <StackPanel>
                                <Button x:Name="WinRMDeploy" Content="Deploy WinRM GPO"
                                        HorizontalAlignment="Left" FontSize="14" Padding="30,12"/>
                                <TextBlock Text="Creates a GPO to enable WinRM on domain computers"
                                           Foreground="#888888" FontSize="11" Margin="5,5,0,15"/>

                                <Button x:Name="WinRMRemove" Content="Remove WinRM GPO"
                                        HorizontalAlignment="Left" FontSize="14" Padding="30,12"/>
                                <TextBlock Text="Removes the WinRM GPO created by this tool"
                                           Foreground="#888888" FontSize="11" Margin="5,5,0,5"/>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Log Panel -->
        <Border Grid.Row="2" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource BorderBrush}"
                BorderThickness="0,1,0,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="10,5">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0" Orientation="Horizontal">
                        <TextBlock Text="Output Log" FontWeight="Bold" Foreground="{StaticResource TextBrush}"
                                   VerticalAlignment="Center"/>
                        <ProgressBar x:Name="ProgressBar" Width="200" Height="18" Margin="20,0,0,0"
                                     Visibility="Collapsed"/>
                        <TextBlock x:Name="ProgressText" Text="" Foreground="{StaticResource TextBrush}"
                                   VerticalAlignment="Center" Margin="10,0,0,0"/>
                    </StackPanel>
                    <Button Grid.Column="1" x:Name="ClearLog" Content="Clear" Padding="10,4" Margin="5,0"/>
                    <Button Grid.Column="2" x:Name="SaveLog" Content="Save Log" Padding="10,4" Margin="5,0"/>
                </Grid>

                <TextBox Grid.Row="1" x:Name="LogOutput"
                         IsReadOnly="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto"
                         FontFamily="Consolas"
                         FontSize="11"
                         Background="#1E1E1E"
                         Foreground="{StaticResource TextBrush}"
                         BorderThickness="0"
                         Margin="10,0,10,10"/>
            </Grid>
        </Border>
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

# PSScriptAnalyzer thinks Set-Status changes system state, but it only updates UI elements
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
function Set-Status {
    param(
        [string]$Status,
        [ValidateSet('Ready', 'Running', 'Success', 'Error')]
        [string]$State = 'Ready'
    )

    $controls['StatusIndicator'].Dispatcher.Invoke([Action]{
        $controls['StatusIndicator'].Text = switch ($State) {
            'Running' { "● Running..." }
            'Success' { "● Complete" }
            'Error'   { "● Error" }
            default   { "● Ready" }
        }
        $controls['StatusIndicator'].Foreground = switch ($State) {
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

function Invoke-AsyncOperation {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [string]$OperationName = "Operation"
    )

    Set-Status -State 'Running'
    Write-Log "Starting $OperationName..." -Level Info
    Show-Progress -Percent 0 -Text "Initializing..."

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()

    # Pass variables to runspace
    $runspace.SessionStateProxy.SetVariable('AppRoot', $Script:AppRoot)
    $runspace.SessionStateProxy.SetVariable('Parameters', $Parameters)

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $powershell.AddScript($ScriptBlock) | Out-Null

    $handle = $powershell.BeginInvoke()

    # Poll for completion
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Tag = @{
        PowerShell = $powershell
        Handle = $handle
        Runspace = $runspace
        OperationName = $OperationName
    }

    $timer.Add_Tick({
        $tag = $this.Tag
        if ($tag.Handle.IsCompleted) {
            $this.Stop()

            try {
                $result = $tag.PowerShell.EndInvoke($tag.Handle)
                if ($tag.PowerShell.Streams.Error.Count -gt 0) {
                    foreach ($err in $tag.PowerShell.Streams.Error) {
                        Write-Log $err.ToString() -Level Error
                    }
                    Set-Status -State 'Error'
                } else {
                    Write-Log "$($tag.OperationName) completed successfully." -Level Success
                    Set-Status -State 'Success'
                }

                # Log output
                foreach ($output in $result) {
                    if ($output) {
                        Write-Log $output.ToString() -Level Info
                    }
                }
            }
            catch {
                Write-Log "Error: $_" -Level Error
                Set-Status -State 'Error'
            }
            finally {
                Hide-Progress
                $tag.PowerShell.Dispose()
                $tag.Runspace.Close()
                $tag.Runspace.Dispose()
            }
        }
    })

    $timer.Start()
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
#endregion

#region Event Handlers

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

# Browse buttons
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

# Merge policy list management
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

# Log management
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

# Software list management
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
    $inputDialog.Background = [System.Windows.Media.Brushes]::FromHtml("#252526")

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

        $controls['ValidationResultsGroup'].Visibility = 'Visible'
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
