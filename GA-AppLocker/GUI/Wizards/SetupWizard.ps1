<#
.SYNOPSIS
    First-run Setup Wizard for GA-AppLocker Dashboard.

.DESCRIPTION
    A 7-step guided wizard that helps new users configure GA-AppLocker:
    
    Step 1: Welcome & Prerequisites Check
    Step 2: Domain Configuration
    Step 3: Credential Setup
    Step 4: WinRM Configuration
    Step 5: AppLocker GPO Setup
    Step 6: Initial Scan Target Selection
    Step 7: Summary & Launch

.NOTES
    The wizard runs on first launch (no config) or when explicitly invoked.
    Progress is saved so users can resume if interrupted.
#>

#region ===== WIZARD STATE =====
$script:WizardState = @{
    CurrentStep = 1
    TotalSteps = 7
    Completed = $false
    Results = @{
        Prerequisites = @{}
        Domain = @{}
        Credentials = @{}
        WinRM = @{}
        GPO = @{}
        ScanTargets = @{}
    }
}
#endregion

#region ===== MAIN WIZARD FUNCTION =====

function Show-SetupWizard {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$ParentWindow = $null,
        [int]$ResumeFromStep = 1
    )

    $script:WizardState.CurrentStep = $ResumeFromStep

    # Build wizard XAML
    $xaml = Get-WizardXaml
    
    # Parse XAML
    Add-Type -AssemblyName PresentationFramework
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $wizardWindow = [System.Windows.Markup.XamlReader]::Load($reader)

    # Store reference
    $script:WizardWindow = $wizardWindow

    # Wire up controls
    Initialize-WizardControls -Window $wizardWindow

    # Show first step
    Show-WizardStep -Window $wizardWindow -StepNumber $script:WizardState.CurrentStep

    # Set owner if parent provided
    if ($ParentWindow) {
        $wizardWindow.Owner = $ParentWindow
        $wizardWindow.WindowStartupLocation = 'CenterOwner'
    }
    else {
        $wizardWindow.WindowStartupLocation = 'CenterScreen'
    }

    # Show dialog
    $result = $wizardWindow.ShowDialog()

    return $script:WizardState.Completed
}

#endregion

#region ===== WIZARD XAML =====

function Get-WizardXaml {
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GA-AppLocker Setup Wizard"
        Width="700" Height="550"
        WindowStyle="SingleBorderWindow"
        ResizeMode="NoResize"
        Background="#1e1e2e">
    
    <Window.Resources>
        <Style TargetType="Button" x:Key="WizardButton">
            <Setter Property="Background" Value="#4a90a4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#3a3a4a"/>
                    <Setter Property="Foreground" Value="#888"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="TextBlock" x:Key="StepTitle">
            <Setter Property="FontSize" Value="24"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style TargetType="TextBlock" x:Key="StepDescription">
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Foreground" Value="#b0b0b0"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="Margin" Value="0,0,0,20"/>
        </Style>
    </Window.Resources>
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header with Progress -->
        <Border Grid.Row="0" Background="#2a2a3a" Padding="20">
            <StackPanel>
                <TextBlock Text="GA-AppLocker Setup" FontSize="18" FontWeight="Bold" Foreground="White"/>
                <ProgressBar Name="WizardProgress" Height="8" Margin="0,10,0,0" Value="14" Maximum="100"
                             Background="#3a3a4a" Foreground="#4a90a4"/>
                <TextBlock Name="StepIndicator" Text="Step 1 of 7" Foreground="#888" Margin="0,5,0,0"/>
            </StackPanel>
        </Border>
        
        <!-- Content Area -->
        <Border Grid.Row="1" Padding="30">
            <Grid Name="StepContainer">
                <!-- Step 1: Welcome -->
                <StackPanel Name="Step1" Visibility="Visible">
                    <TextBlock Style="{StaticResource StepTitle}" Text="Welcome to GA-AppLocker"/>
                    <TextBlock Style="{StaticResource StepDescription}">
                        This wizard will help you configure GA-AppLocker Dashboard for your environment.
                        We'll guide you through connecting to Active Directory, setting up credentials,
                        and preparing your environment for AppLocker policy management.
                    </TextBlock>
                    
                    <TextBlock Text="Prerequisites Check:" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,10"/>
                    <StackPanel Name="PrereqList" Margin="10,0,0,0">
                        <TextBlock Name="PrereqPowerShell" Text="* PowerShell 5.1 or later" Foreground="#b0b0b0"/>
                        <TextBlock Name="PrereqADModule" Text="* Active Directory module" Foreground="#b0b0b0"/>
                        <TextBlock Name="PrereqGPModule" Text="* Group Policy module" Foreground="#b0b0b0"/>
                        <TextBlock Name="PrereqAdmin" Text="* Administrative privileges" Foreground="#b0b0b0"/>
                    </StackPanel>
                    
                    <Button Name="CheckPrereqsBtn" Content="Check Prerequisites" Style="{StaticResource WizardButton}" 
                            HorizontalAlignment="Left" Margin="0,20,0,0"/>
                </StackPanel>
                
                <!-- Step 2: Domain -->
                <StackPanel Name="Step2" Visibility="Collapsed">
                    <TextBlock Style="{StaticResource StepTitle}" Text="Domain Configuration"/>
                    <TextBlock Style="{StaticResource StepDescription}">
                        Enter your Active Directory domain information. This will be used to discover
                        computers and manage AppLocker policies.
                    </TextBlock>
                    
                    <Grid Margin="0,10,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        
                        <TextBlock Text="Domain Name:" Foreground="White" VerticalAlignment="Center"/>
                        <TextBox Name="DomainName" Grid.Column="1" Padding="8" Margin="0,0,0,10"/>
                        
                        <TextBlock Grid.Row="1" Text="Domain Controller:" Foreground="White" VerticalAlignment="Center"/>
                        <TextBox Name="DomainController" Grid.Row="1" Grid.Column="1" Padding="8" Margin="0,0,0,10"/>
                        
                        <TextBlock Grid.Row="2" Text="Base Search DN:" Foreground="White" VerticalAlignment="Center"/>
                        <TextBox Name="SearchBase" Grid.Row="2" Grid.Column="1" Padding="8" Margin="0,0,0,10"/>
                    </Grid>
                    
                    <Button Name="AutoDetectDomainBtn" Content="Auto-Detect Domain" Style="{StaticResource WizardButton}"
                            HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
                
                <!-- Step 3: Credentials -->
                <StackPanel Name="Step3" Visibility="Collapsed">
                    <TextBlock Style="{StaticResource StepTitle}" Text="Credential Setup"/>
                    <TextBlock Style="{StaticResource StepDescription}">
                        Configure credentials for connecting to domain computers. You can use your current
                        credentials or specify an account with appropriate permissions.
                    </TextBlock>
                    
                    <StackPanel Margin="0,10,0,0">
                        <RadioButton Name="UseCurrentCreds" Content="Use current logged-in credentials" 
                                     Foreground="White" IsChecked="True" Margin="0,0,0,10"/>
                        <RadioButton Name="UseSpecificCreds" Content="Use specific credentials" 
                                     Foreground="White" Margin="0,0,0,10"/>
                    </StackPanel>
                    
                    <StackPanel Name="CredentialFields" Margin="20,10,0,0" Visibility="Collapsed">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="120"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            
                            <TextBlock Text="Username:" Foreground="White" VerticalAlignment="Center"/>
                            <TextBox Name="CredUsername" Grid.Column="1" Padding="8" Margin="0,0,0,10"/>
                            
                            <TextBlock Grid.Row="1" Text="Password:" Foreground="White" VerticalAlignment="Center"/>
                            <PasswordBox Name="CredPassword" Grid.Row="1" Grid.Column="1" Padding="8"/>
                        </Grid>
                    </StackPanel>
                    
                    <Button Name="TestCredentialsBtn" Content="Test Connection" Style="{StaticResource WizardButton}"
                            HorizontalAlignment="Left" Margin="0,20,0,0"/>
                </StackPanel>
                
                <!-- Step 4: WinRM -->
                <StackPanel Name="Step4" Visibility="Collapsed">
                    <TextBlock Style="{StaticResource StepTitle}" Text="WinRM Configuration"/>
                    <TextBlock Style="{StaticResource StepDescription}">
                        Windows Remote Management (WinRM) is required to scan computers and deploy policies.
                        We can help you configure WinRM through Group Policy.
                    </TextBlock>
                    
                    <Border Background="#2a2a3a" Padding="15" CornerRadius="5" Margin="0,10,0,0">
                        <StackPanel>
                            <TextBlock Text="WinRM Status" FontWeight="SemiBold" Foreground="White" Margin="0,0,0,5"/>
                            <TextBlock Name="WinRMStatus" Text="Checking..." Foreground="#b0b0b0"/>
                        </StackPanel>
                    </Border>
                    
                    <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
                        <Button Name="ConfigureWinRMBtn" Content="Configure WinRM GPO" Style="{StaticResource WizardButton}" Margin="0,0,10,0"/>
                        <Button Name="SkipWinRMBtn" Content="Skip (Configure Later)" Style="{StaticResource WizardButton}" 
                                Background="#3a3a4a"/>
                    </StackPanel>
                </StackPanel>
                
                <!-- Step 5: GPO Setup -->
                <StackPanel Name="Step5" Visibility="Collapsed">
                    <TextBlock Style="{StaticResource StepTitle}" Text="AppLocker GPO Setup"/>
                    <TextBlock Style="{StaticResource StepDescription}">
                        Create the necessary Group Policy Objects for managing AppLocker policies.
                        This will create GPOs for audit mode testing and enforcement.
                    </TextBlock>
                    
                    <CheckBox Name="CreateAuditGPO" Content="Create Audit Mode GPO (recommended for testing)"
                              Foreground="White" IsChecked="True" Margin="0,10,0,10"/>
                    <CheckBox Name="CreateEnforceGPO" Content="Create Enforcement GPO"
                              Foreground="White" Margin="0,0,0,10"/>
                    <CheckBox Name="CreateADStructure" Content="Create AppLocker OU structure"
                              Foreground="White" Margin="0,0,0,10"/>
                    
                    <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
                        <Button Name="CreateGPOsBtn" Content="Create GPOs" Style="{StaticResource WizardButton}" Margin="0,0,10,0"/>
                        <Button Name="SkipGPOBtn" Content="Skip (Configure Later)" Style="{StaticResource WizardButton}"
                                Background="#3a3a4a"/>
                    </StackPanel>
                </StackPanel>
                
                <!-- Step 6: Scan Targets -->
                <StackPanel Name="Step6" Visibility="Collapsed">
                    <TextBlock Style="{StaticResource StepTitle}" Text="Initial Scan Targets"/>
                    <TextBlock Style="{StaticResource StepDescription}">
                        Select the OUs or computers you'd like to scan for applications.
                        This will help build your initial AppLocker baseline.
                    </TextBlock>
                    
                    <TextBlock Text="Select target OUs:" Foreground="White" Margin="0,10,0,5"/>
                    <Border BorderBrush="#3a3a4a" BorderThickness="1" Height="150" Margin="0,0,0,10">
                        <ListBox Name="OUList" Background="#2a2a3a" Foreground="White" SelectionMode="Multiple"/>
                    </Border>
                    
                    <StackPanel Orientation="Horizontal">
                        <Button Name="RefreshOUsBtn" Content="Refresh OUs" Style="{StaticResource WizardButton}" Margin="0,0,10,0"/>
                        <TextBlock Name="SelectedOUCount" Text="0 OUs selected" Foreground="#888" VerticalAlignment="Center"/>
                    </StackPanel>
                </StackPanel>
                
                <!-- Step 7: Summary -->
                <StackPanel Name="Step7" Visibility="Collapsed">
                    <TextBlock Style="{StaticResource StepTitle}" Text="Setup Complete!"/>
                    <TextBlock Style="{StaticResource StepDescription}">
                        GA-AppLocker is now configured and ready to use. Here's a summary of your setup:
                    </TextBlock>
                    
                    <Border Background="#2a2a3a" Padding="15" CornerRadius="5" Margin="0,10,0,0">
                        <StackPanel Name="SummaryPanel">
                            <TextBlock Name="SummaryDomain" Text="Domain: " Foreground="White"/>
                            <TextBlock Name="SummaryCredentials" Text="Credentials: " Foreground="White"/>
                            <TextBlock Name="SummaryWinRM" Text="WinRM: " Foreground="White"/>
                            <TextBlock Name="SummaryGPOs" Text="GPOs: " Foreground="White"/>
                            <TextBlock Name="SummaryTargets" Text="Scan Targets: " Foreground="White"/>
                        </StackPanel>
                    </Border>
                    
                    <TextBlock Text="What's Next?" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,20,0,10"/>
                    <TextBlock Text="1. Navigate to Scanner to discover applications" Foreground="#b0b0b0"/>
                    <TextBlock Text="2. Review artifacts and create rules" Foreground="#b0b0b0"/>
                    <TextBlock Text="3. Build policies and test in audit mode" Foreground="#b0b0b0"/>
                    <TextBlock Text="4. Deploy to production when ready" Foreground="#b0b0b0"/>
                </StackPanel>
            </Grid>
        </Border>
        
        <!-- Footer with Navigation -->
        <Border Grid.Row="2" Background="#2a2a3a" Padding="20">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <Button Name="BackBtn" Content="Back" Style="{StaticResource WizardButton}" 
                        Background="#3a3a4a" HorizontalAlignment="Left" Visibility="Collapsed"/>
                
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button Name="SkipBtn" Content="Skip All" Style="{StaticResource WizardButton}"
                            Background="#3a3a4a" Margin="0,0,10,0"/>
                    <Button Name="NextBtn" Content="Next" Style="{StaticResource WizardButton}"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@
}

#endregion

#region ===== WIZARD CONTROLS =====

function Initialize-WizardControls {
    param([System.Windows.Window]$Window)

    # Navigation buttons
    $Window.FindName('BackBtn').add_Click({ Move-WizardBack -Window $script:WizardWindow })
    $Window.FindName('NextBtn').add_Click({ Move-WizardNext -Window $script:WizardWindow })
    $Window.FindName('SkipBtn').add_Click({ Skip-Wizard -Window $script:WizardWindow })

    # Step 1: Prerequisites
    $Window.FindName('CheckPrereqsBtn').add_Click({ Check-Prerequisites -Window $script:WizardWindow })

    # Step 2: Domain
    $Window.FindName('AutoDetectDomainBtn').add_Click({ Auto-DetectDomain -Window $script:WizardWindow })

    # Step 3: Credentials
    $Window.FindName('UseSpecificCreds').add_Checked({
        $script:WizardWindow.FindName('CredentialFields').Visibility = 'Visible'
    })
    $Window.FindName('UseCurrentCreds').add_Checked({
        $script:WizardWindow.FindName('CredentialFields').Visibility = 'Collapsed'
    })
    $Window.FindName('TestCredentialsBtn').add_Click({ Test-WizardCredentials -Window $script:WizardWindow })

    # Step 4: WinRM
    $Window.FindName('ConfigureWinRMBtn').add_Click({ Configure-WinRMGPO -Window $script:WizardWindow })
    $Window.FindName('SkipWinRMBtn').add_Click({ Move-WizardNext -Window $script:WizardWindow })

    # Step 5: GPO
    $Window.FindName('CreateGPOsBtn').add_Click({ Create-AppLockerGPOs -Window $script:WizardWindow })
    $Window.FindName('SkipGPOBtn').add_Click({ Move-WizardNext -Window $script:WizardWindow })

    # Step 6: Scan Targets
    $Window.FindName('RefreshOUsBtn').add_Click({ Refresh-WizardOUs -Window $script:WizardWindow })
    $Window.FindName('OUList').add_SelectionChanged({
        $count = $script:WizardWindow.FindName('OUList').SelectedItems.Count
        $script:WizardWindow.FindName('SelectedOUCount').Text = "$count OUs selected"
    })
}

function Show-WizardStep {
    param(
        [System.Windows.Window]$Window,
        [int]$StepNumber
    )

    # Hide all steps
    for ($i = 1; $i -le 7; $i++) {
        $step = $Window.FindName("Step$i")
        if ($step) { $step.Visibility = 'Collapsed' }
    }

    # Show current step
    $currentStep = $Window.FindName("Step$StepNumber")
    if ($currentStep) { $currentStep.Visibility = 'Visible' }

    # Update progress
    $progress = [int](($StepNumber / 7) * 100)
    $Window.FindName('WizardProgress').Value = $progress
    $Window.FindName('StepIndicator').Text = "Step $StepNumber of 7"

    # Update navigation buttons
    $Window.FindName('BackBtn').Visibility = if ($StepNumber -gt 1) { 'Visible' } else { 'Collapsed' }
    $Window.FindName('NextBtn').Content = if ($StepNumber -eq 7) { 'Finish' } else { 'Next' }

    # Step-specific initialization
    switch ($StepNumber) {
        4 { Check-WinRMStatus -Window $Window }
        6 { Refresh-WizardOUs -Window $Window }
        7 { Update-WizardSummary -Window $Window }
    }

    $script:WizardState.CurrentStep = $StepNumber
}

function Move-WizardBack {
    param([System.Windows.Window]$Window)
    
    if ($script:WizardState.CurrentStep -gt 1) {
        Show-WizardStep -Window $Window -StepNumber ($script:WizardState.CurrentStep - 1)
    }
}

function Move-WizardNext {
    param([System.Windows.Window]$Window)
    
    # Validate current step
    $valid = Validate-WizardStep -Window $Window -StepNumber $script:WizardState.CurrentStep
    if (-not $valid) { return }

    # Save current step data
    Save-WizardStepData -Window $Window -StepNumber $script:WizardState.CurrentStep

    if ($script:WizardState.CurrentStep -lt 7) {
        Show-WizardStep -Window $Window -StepNumber ($script:WizardState.CurrentStep + 1)
    }
    else {
        # Finish wizard
        Complete-Wizard -Window $Window
    }
}

function Skip-Wizard {
    param([System.Windows.Window]$Window)
    
    $result = [System.Windows.MessageBox]::Show(
        "Are you sure you want to skip the setup wizard?`n`nYou can run it again from Settings > Setup.",
        "Skip Setup",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq 'Yes') {
        $script:WizardState.Completed = $false
        $Window.DialogResult = $false
        $Window.Close()
    }
}

function Complete-Wizard {
    param([System.Windows.Window]$Window)

    # Save configuration
    Save-WizardConfiguration

    $script:WizardState.Completed = $true
    $Window.DialogResult = $true
    $Window.Close()
}

#endregion

#region ===== STEP HANDLERS =====

function Check-Prerequisites {
    param([System.Windows.Window]$Window)

    $prereqPs = $Window.FindName('PrereqPowerShell')
    $prereqAd = $Window.FindName('PrereqADModule')
    $prereqGp = $Window.FindName('PrereqGPModule')
    $prereqAdmin = $Window.FindName('PrereqAdmin')

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        $prereqPs.Text = "[OK] PowerShell $($psVersion.Major).$($psVersion.Minor)"
        $prereqPs.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $script:WizardState.Results.Prerequisites['PowerShell'] = $true
    }
    else {
        $prereqPs.Text = "[X] PowerShell 5.1+ required (found $($psVersion.Major).$($psVersion.Minor))"
        $prereqPs.Foreground = [System.Windows.Media.Brushes]::Salmon
        $script:WizardState.Results.Prerequisites['PowerShell'] = $false
    }

    # Check AD module
    $adModule = Get-Module -ListAvailable -Name ActiveDirectory
    if ($adModule) {
        $prereqAd.Text = "[OK] Active Directory module installed"
        $prereqAd.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $script:WizardState.Results.Prerequisites['ADModule'] = $true
    }
    else {
        $prereqAd.Text = "[X] Active Directory module not found"
        $prereqAd.Foreground = [System.Windows.Media.Brushes]::Salmon
        $script:WizardState.Results.Prerequisites['ADModule'] = $false
    }

    # Check GP module
    $gpModule = Get-Module -ListAvailable -Name GroupPolicy
    if ($gpModule) {
        $prereqGp.Text = "[OK] Group Policy module installed"
        $prereqGp.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $script:WizardState.Results.Prerequisites['GPModule'] = $true
    }
    else {
        $prereqGp.Text = "[X] Group Policy module not found"
        $prereqGp.Foreground = [System.Windows.Media.Brushes]::Salmon
        $script:WizardState.Results.Prerequisites['GPModule'] = $false
    }

    # Check admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        $prereqAdmin.Text = "[OK] Running with administrative privileges"
        $prereqAdmin.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $script:WizardState.Results.Prerequisites['Admin'] = $true
    }
    else {
        $prereqAdmin.Text = "[!] Not running as administrator (some features may not work)"
        $prereqAdmin.Foreground = [System.Windows.Media.Brushes]::Yellow
        $script:WizardState.Results.Prerequisites['Admin'] = $false
    }
}

function Auto-DetectDomain {
    param([System.Windows.Window]$Window)

    try {
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        
        $Window.FindName('DomainName').Text = $domain.Name
        $Window.FindName('DomainController').Text = $domain.PdcRoleOwner.Name
        
        # Build search base from domain name
        $parts = $domain.Name -split '\.'
        $searchBase = ($parts | ForEach-Object { "DC=$_" }) -join ','
        $Window.FindName('SearchBase').Text = $searchBase

        $script:WizardState.Results.Domain['Name'] = $domain.Name
        $script:WizardState.Results.Domain['DC'] = $domain.PdcRoleOwner.Name
        $script:WizardState.Results.Domain['SearchBase'] = $searchBase
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Could not auto-detect domain. Please enter details manually.`n`nError: $($_.Exception.Message)",
            "Auto-Detect Failed",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
    }
}

function Test-WizardCredentials {
    param([System.Windows.Window]$Window)

    $dc = $script:WizardState.Results.Domain['DC']
    if (-not $dc) { $dc = $Window.FindName('DomainController').Text }

    try {
        if ($Window.FindName('UseCurrentCreds').IsChecked) {
            # Test with current credentials
            $result = Test-Connection -ComputerName $dc -Count 1 -Quiet
            if ($result) {
                [System.Windows.MessageBox]::Show("Connection successful!", "Test Result", 
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                $script:WizardState.Results.Credentials['Type'] = 'Current'
            }
        }
        else {
            $username = $Window.FindName('CredUsername').Text
            $password = $Window.FindName('CredPassword').SecurePassword
            
            if ([string]::IsNullOrEmpty($username)) {
                [System.Windows.MessageBox]::Show("Please enter a username.", "Validation", 
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }

            $cred = New-Object System.Management.Automation.PSCredential($username, $password)
            
            # Test credential
            $result = Test-WsMan -ComputerName $dc -Credential $cred -ErrorAction Stop
            
            [System.Windows.MessageBox]::Show("Credentials verified successfully!", "Test Result",
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            
            $script:WizardState.Results.Credentials['Type'] = 'Specific'
            $script:WizardState.Results.Credentials['Username'] = $username
        }
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Connection test failed.`n`nError: $($_.Exception.Message)",
            "Test Failed",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Check-WinRMStatus {
    param([System.Windows.Window]$Window)

    $statusText = $Window.FindName('WinRMStatus')
    
    try {
        $winrmService = Get-Service -Name WinRM -ErrorAction Stop
        if ($winrmService.Status -eq 'Running') {
            $statusText.Text = "[OK] WinRM service is running locally"
            $statusText.Foreground = [System.Windows.Media.Brushes]::LightGreen
            $script:WizardState.Results.WinRM['LocalStatus'] = 'Running'
        }
        else {
            $statusText.Text = "[!] WinRM service is not running"
            $statusText.Foreground = [System.Windows.Media.Brushes]::Yellow
            $script:WizardState.Results.WinRM['LocalStatus'] = 'Stopped'
        }
    }
    catch {
        $statusText.Text = "[X] Could not check WinRM status"
        $statusText.Foreground = [System.Windows.Media.Brushes]::Salmon
        $script:WizardState.Results.WinRM['LocalStatus'] = 'Unknown'
    }
}

function Configure-WinRMGPO {
    param([System.Windows.Window]$Window)

    if (Get-Command -Name 'Initialize-WinRMGPO' -ErrorAction SilentlyContinue) {
        try {
            $result = Initialize-WinRMGPO
            if ($result.Success) {
                [System.Windows.MessageBox]::Show("WinRM GPO created successfully!", "Success",
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                $script:WizardState.Results.WinRM['GPOCreated'] = $true
                Move-WizardNext -Window $Window
            }
            else {
                throw $result.Error
            }
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to create WinRM GPO.`n`n$($_.Exception.Message)",
                "Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
    else {
        [System.Windows.MessageBox]::Show("WinRM GPO function not available.", "Error",
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
}

function Create-AppLockerGPOs {
    param([System.Windows.Window]$Window)

    $createAudit = $Window.FindName('CreateAuditGPO').IsChecked
    $createEnforce = $Window.FindName('CreateEnforceGPO').IsChecked
    $createAD = $Window.FindName('CreateADStructure').IsChecked

    $created = @()

    try {
        if ($createAudit -and (Get-Command -Name 'New-AppLockerAuditGPO' -ErrorAction SilentlyContinue)) {
            $result = New-AppLockerAuditGPO
            if ($result.Success) { $created += 'Audit GPO' }
        }

        if ($createEnforce -and (Get-Command -Name 'New-AppLockerEnforceGPO' -ErrorAction SilentlyContinue)) {
            $result = New-AppLockerEnforceGPO
            if ($result.Success) { $created += 'Enforce GPO' }
        }

        if ($createAD -and (Get-Command -Name 'Initialize-AppLockerADStructure' -ErrorAction SilentlyContinue)) {
            $result = Initialize-AppLockerADStructure
            if ($result.Success) { $created += 'AD Structure' }
        }

        $script:WizardState.Results.GPO['Created'] = $created

        if ($created.Count -gt 0) {
            [System.Windows.MessageBox]::Show(
                "Created: $($created -join ', ')",
                "Success",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
            Move-WizardNext -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("No items were created.", "Info",
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Error creating GPOs: $($_.Exception.Message)",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Refresh-WizardOUs {
    param([System.Windows.Window]$Window)

    $ouList = $Window.FindName('OUList')
    $ouList.Items.Clear()

    try {
        if (Get-Command -Name 'Get-OUTree' -ErrorAction SilentlyContinue) {
            $result = Get-OUTree
            if ($result.Success) {
                foreach ($ou in $result.Data) {
                    $ouList.Items.Add($ou.DistinguishedName)
                }
            }
        }
        else {
            # Fallback: basic AD query
            $searchBase = $script:WizardState.Results.Domain['SearchBase']
            if ($searchBase) {
                $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $searchBase -ErrorAction Stop
                foreach ($ou in $ous) {
                    $ouList.Items.Add($ou.DistinguishedName)
                }
            }
        }
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Could not retrieve OUs: $($_.Exception.Message)",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
    }
}

function Update-WizardSummary {
    param([System.Windows.Window]$Window)

    $domain = $script:WizardState.Results.Domain['Name']
    $creds = $script:WizardState.Results.Credentials['Type']
    $winrm = $script:WizardState.Results.WinRM['LocalStatus']
    $gpos = $script:WizardState.Results.GPO['Created']
    $targets = $script:WizardState.Results.ScanTargets['OUs']

    # PowerShell 5.1 compatible - use if/else instead of ??
    $domainText = if ($domain) { $domain } else { 'Not configured' }
    $credsText = if ($creds) { $creds } else { 'Not set' }
    $winrmText = if ($winrm) { $winrm } else { 'Unknown' }
    $gposText = if ($gpos) { $gpos -join ', ' } else { 'None created' }
    $targetsText = if ($targets) { "$($targets.Count) OUs" } else { 'None selected' }

    $Window.FindName('SummaryDomain').Text = "Domain: $domainText"
    $Window.FindName('SummaryCredentials').Text = "Credentials: $credsText"
    $Window.FindName('SummaryWinRM').Text = "WinRM: $winrmText"
    $Window.FindName('SummaryGPOs').Text = "GPOs: $gposText"
    $Window.FindName('SummaryTargets').Text = "Scan Targets: $targetsText"
}

#endregion

#region ===== VALIDATION & SAVING =====

function Validate-WizardStep {
    param(
        [System.Windows.Window]$Window,
        [int]$StepNumber
    )

    switch ($StepNumber) {
        2 {
            # Domain step - require at least domain name
            $domainName = $Window.FindName('DomainName').Text
            if ([string]::IsNullOrWhiteSpace($domainName)) {
                [System.Windows.MessageBox]::Show("Please enter or auto-detect a domain name.", "Validation",
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return $false
            }
        }
        3 {
            # Credentials - if specific creds, require username
            if ($Window.FindName('UseSpecificCreds').IsChecked) {
                $username = $Window.FindName('CredUsername').Text
                if ([string]::IsNullOrWhiteSpace($username)) {
                    [System.Windows.MessageBox]::Show("Please enter a username.", "Validation",
                        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                    return $false
                }
            }
        }
    }

    return $true
}

function Save-WizardStepData {
    param(
        [System.Windows.Window]$Window,
        [int]$StepNumber
    )

    switch ($StepNumber) {
        2 {
            $script:WizardState.Results.Domain['Name'] = $Window.FindName('DomainName').Text
            $script:WizardState.Results.Domain['DC'] = $Window.FindName('DomainController').Text
            $script:WizardState.Results.Domain['SearchBase'] = $Window.FindName('SearchBase').Text
        }
        3 {
            if ($Window.FindName('UseCurrentCreds').IsChecked) {
                $script:WizardState.Results.Credentials['Type'] = 'Current'
            }
            else {
                $script:WizardState.Results.Credentials['Type'] = 'Specific'
                $script:WizardState.Results.Credentials['Username'] = $Window.FindName('CredUsername').Text
            }
        }
        6 {
            $selectedOUs = @($Window.FindName('OUList').SelectedItems)
            $script:WizardState.Results.ScanTargets['OUs'] = $selectedOUs
        }
    }
}

function Save-WizardConfiguration {
    # Save to app configuration
    if (Get-Command -Name 'Set-AppLockerConfig' -ErrorAction SilentlyContinue) {
        $config = @{
            DomainName = $script:WizardState.Results.Domain['Name']
            DomainController = $script:WizardState.Results.Domain['DC']
            SearchBase = $script:WizardState.Results.Domain['SearchBase']
            CredentialType = $script:WizardState.Results.Credentials['Type']
            WizardCompleted = $true
            WizardCompletedDate = (Get-Date).ToString('o')
        }

        foreach ($key in $config.Keys) {
            Set-AppLockerConfig -Key $key -Value $config[$key] | Out-Null
        }
    }

    Write-Log -Message "Setup wizard completed and configuration saved"
}

#endregion

#region ===== WIZARD ENTRY POINT =====

function Test-ShouldShowWizard {
    if (Get-Command -Name 'Get-AppLockerConfig' -ErrorAction SilentlyContinue) {
        $config = Get-AppLockerConfig
        if ($config.WizardCompleted) {
            return $false
        }
    }
    return $true
}

#endregion
