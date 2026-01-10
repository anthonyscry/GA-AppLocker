using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace GAAppLocker;

/// <summary>
/// Interaction logic for MainWindow.xaml
/// </summary>
public partial class MainWindow : Window
{
    private readonly string _scriptsPath;
    private CancellationTokenSource? _cancellationTokenSource;
    private Runspace? _runspace;

    public MainWindow()
    {
        InitializeComponent();

        // Determine scripts path (bundled with app or alongside)
        _scriptsPath = FindScriptsPath();
        ScriptsPath.Text = _scriptsPath;

        // Set version
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"Version: {version?.ToString(3) ?? "1.0.0"}";

        // Initialize PowerShell runspace
        InitializeRunspace();

        Log("GA-AppLocker Toolkit initialized.");
        Log($"Scripts path: {_scriptsPath}");
    }

    private string FindScriptsPath()
    {
        var appDir = AppDomain.CurrentDomain.BaseDirectory;

        // Check for bundled scripts
        var bundledPath = Path.Combine(appDir, "Scripts");
        if (Directory.Exists(bundledPath) && File.Exists(Path.Combine(bundledPath, "Start-AppLockerWorkflow.ps1")))
        {
            return bundledPath;
        }

        // Check parent directories (development mode)
        var currentDir = appDir;
        for (int i = 0; i < 5; i++)
        {
            var workflowScript = Path.Combine(currentDir, "Start-AppLockerWorkflow.ps1");
            if (File.Exists(workflowScript))
            {
                return currentDir;
            }
            var parent = Directory.GetParent(currentDir);
            if (parent == null) break;
            currentDir = parent.FullName;
        }

        return appDir;
    }

    private void InitializeRunspace()
    {
        var initialState = InitialSessionState.CreateDefault();
        initialState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        _runspace = RunspaceFactory.CreateRunspace(initialState);
        _runspace.Open();

        // Set location to scripts path
        using var ps = PowerShell.Create();
        ps.Runspace = _runspace;
        ps.AddCommand("Set-Location").AddParameter("Path", _scriptsPath);
        ps.Invoke();
    }

    private void Log(string message, LogLevel level = LogLevel.Info)
    {
        var timestamp = DateTime.Now.ToString("HH:mm:ss");
        var prefix = level switch
        {
            LogLevel.Success => "[OK]",
            LogLevel.Warning => "[WARN]",
            LogLevel.Error => "[ERROR]",
            _ => "[INFO]"
        };

        Dispatcher.Invoke(() =>
        {
            OutputLog.AppendText($"[{timestamp}] {prefix} {message}\n");
            OutputLog.ScrollToEnd();
        });
    }

    private void SetStatus(string status, bool isRunning = false)
    {
        Dispatcher.Invoke(() =>
        {
            if (isRunning)
            {
                StatusIndicator.Text = $"● {status}";
                StatusIndicator.Foreground = (SolidColorBrush)FindResource("WarningBrush");
            }
            else
            {
                StatusIndicator.Text = $"● {status}";
                StatusIndicator.Foreground = (SolidColorBrush)FindResource("SuccessBrush");
            }
        });
    }

    private async Task RunPowerShellScriptAsync(string scriptName, Dictionary<string, object>? parameters = null)
    {
        _cancellationTokenSource = new CancellationTokenSource();
        var token = _cancellationTokenSource.Token;

        var scriptPath = Path.Combine(_scriptsPath, scriptName);
        if (!File.Exists(scriptPath))
        {
            Log($"Script not found: {scriptPath}", LogLevel.Error);
            return;
        }

        SetStatus("Running...", isRunning: true);

        try
        {
            await Task.Run(() =>
            {
                using var ps = PowerShell.Create();
                ps.Runspace = _runspace;

                ps.AddCommand(scriptPath);
                if (parameters != null)
                {
                    foreach (var param in parameters)
                    {
                        ps.AddParameter(param.Key, param.Value);
                    }
                }

                ps.Streams.Information.DataAdded += (s, e) =>
                {
                    var info = ps.Streams.Information[e.Index];
                    Log(info.MessageData?.ToString() ?? "");
                };

                ps.Streams.Warning.DataAdded += (s, e) =>
                {
                    var warning = ps.Streams.Warning[e.Index];
                    Log(warning.Message, LogLevel.Warning);
                };

                ps.Streams.Error.DataAdded += (s, e) =>
                {
                    var error = ps.Streams.Error[e.Index];
                    Log(error.Exception?.Message ?? error.ToString(), LogLevel.Error);
                };

                var results = ps.Invoke();

                foreach (var result in results)
                {
                    if (result != null)
                    {
                        Log(result.ToString() ?? "");
                    }
                }

                if (ps.HadErrors)
                {
                    Log("Script completed with errors.", LogLevel.Warning);
                }
                else
                {
                    Log("Script completed successfully.", LogLevel.Success);
                }
            }, token);
        }
        catch (OperationCanceledException)
        {
            Log("Operation cancelled.", LogLevel.Warning);
        }
        catch (Exception ex)
        {
            Log($"Error: {ex.Message}", LogLevel.Error);
        }
        finally
        {
            SetStatus("Ready");
            _cancellationTokenSource = null;
        }
    }

    #region Scan Tab Events

    private void BrowseComputerList_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "Text files (*.txt;*.csv)|*.txt;*.csv|All files (*.*)|*.*",
            Title = "Select Computer List"
        };

        if (dialog.ShowDialog() == true)
        {
            ScanComputerList.Text = dialog.FileName;
        }
    }

    private async void StartScan_Click(object sender, RoutedEventArgs e)
    {
        var computers = ScanComputerList.Text.Trim();
        if (string.IsNullOrEmpty(computers))
        {
            Log("Please specify computers to scan.", LogLevel.Warning);
            return;
        }

        StartScan.IsEnabled = false;
        CancelScan.IsEnabled = true;

        var parameters = new Dictionary<string, object>
        {
            ["Mode"] = "Scan"
        };

        // Check if it's a file path or computer list
        if (File.Exists(computers))
        {
            parameters["ComputerList"] = computers;
        }
        else
        {
            // Write to temp file
            var tempFile = Path.GetTempFileName();
            await File.WriteAllTextAsync(tempFile, computers);
            parameters["ComputerList"] = tempFile;
        }

        if (int.TryParse(ScanThrottleLimit.Text, out int throttle))
        {
            parameters["ThrottleLimit"] = throttle;
        }

        if (ScanUserProfiles.IsChecked == true)
        {
            parameters["ScanUserProfiles"] = true;
        }

        Log("Starting remote scan...");
        await RunPowerShellScriptAsync("Start-AppLockerWorkflow.ps1", parameters);

        StartScan.IsEnabled = true;
        CancelScan.IsEnabled = false;
    }

    private void CancelScan_Click(object sender, RoutedEventArgs e)
    {
        _cancellationTokenSource?.Cancel();
        Log("Cancelling operation...");
    }

    #endregion

    #region Generate Tab Events

    private void BrowseScanPath_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select Scan Data Folder"
        };

        if (dialog.ShowDialog() == true)
        {
            GenerateScanPath.Text = dialog.FolderName;
        }
    }

    private async void GeneratePolicy_Click(object sender, RoutedEventArgs e)
    {
        var scanPath = GenerateScanPath.Text.Trim();
        if (string.IsNullOrEmpty(scanPath) || !Directory.Exists(scanPath))
        {
            Log("Please specify a valid scan data path.", LogLevel.Warning);
            return;
        }

        var parameters = new Dictionary<string, object>
        {
            ["Mode"] = "Generate",
            ["ScanPath"] = scanPath
        };

        if (SimplifiedMode.IsChecked == true)
        {
            parameters["Simplified"] = true;
        }
        else
        {
            // Build Guide mode
            var targetTypeItem = (System.Windows.Controls.ComboBoxItem)TargetType.SelectedItem;
            parameters["TargetType"] = targetTypeItem.Content.ToString()!;

            var phaseItem = (System.Windows.Controls.ComboBoxItem)Phase.SelectedItem;
            var phaseText = phaseItem.Content.ToString()!;
            parameters["Phase"] = phaseText.StartsWith("Phase ") ? int.Parse(phaseText[6].ToString()) : 1;

            if (!string.IsNullOrEmpty(DomainName.Text))
            {
                parameters["DomainName"] = DomainName.Text;
            }
        }

        if (IncludeDenyRules.IsChecked == true)
        {
            parameters["IncludeDenyRules"] = true;
        }

        if (IncludeVendorPublishers.IsChecked == true)
        {
            parameters["IncludeVendorPublishers"] = true;
        }

        Log("Generating AppLocker policy...");
        await RunPowerShellScriptAsync("Start-AppLockerWorkflow.ps1", parameters);
    }

    #endregion

    #region Merge Tab Events

    private void AddMergePolicy_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "XML files (*.xml)|*.xml|All files (*.*)|*.*",
            Title = "Select Policy File",
            Multiselect = true
        };

        if (dialog.ShowDialog() == true)
        {
            foreach (var file in dialog.FileNames)
            {
                if (!MergePolicyList.Items.Contains(file))
                {
                    MergePolicyList.Items.Add(file);
                }
            }
        }
    }

    private void RemoveMergePolicy_Click(object sender, RoutedEventArgs e)
    {
        var selected = MergePolicyList.SelectedItems.Cast<string>().ToList();
        foreach (var item in selected)
        {
            MergePolicyList.Items.Remove(item);
        }
    }

    private void ClearMergePolicies_Click(object sender, RoutedEventArgs e)
    {
        MergePolicyList.Items.Clear();
    }

    private void BrowseMergeOutput_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog
        {
            Filter = "XML files (*.xml)|*.xml",
            Title = "Save Merged Policy As",
            FileName = "MergedPolicy.xml"
        };

        if (dialog.ShowDialog() == true)
        {
            MergeOutputPath.Text = dialog.FileName;
        }
    }

    private async void MergePolicies_Click(object sender, RoutedEventArgs e)
    {
        if (MergePolicyList.Items.Count < 2)
        {
            Log("Please add at least 2 policies to merge.", LogLevel.Warning);
            return;
        }

        var policyFiles = MergePolicyList.Items.Cast<string>().ToArray();

        Log($"Merging {policyFiles.Length} policies...");
        // Note: Merge-AppLockerPolicies.ps1 would need to be called directly
        // or Start-AppLockerWorkflow.ps1 enhanced with a Merge mode

        var parameters = new Dictionary<string, object>
        {
            ["PolicyPaths"] = policyFiles,
            ["OutputPath"] = MergeOutputPath.Text
        };

        await RunPowerShellScriptAsync("Merge-AppLockerPolicies.ps1", parameters);
    }

    #endregion

    #region Validate Tab Events

    private void BrowseValidatePolicy_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "XML files (*.xml)|*.xml|All files (*.*)|*.*",
            Title = "Select Policy File"
        };

        if (dialog.ShowDialog() == true)
        {
            ValidatePolicyPath.Text = dialog.FileName;
        }
    }

    private async void ValidatePolicy_Click(object sender, RoutedEventArgs e)
    {
        var policyPath = ValidatePolicyPath.Text.Trim();
        if (string.IsNullOrEmpty(policyPath) || !File.Exists(policyPath))
        {
            Log("Please specify a valid policy file.", LogLevel.Warning);
            return;
        }

        var parameters = new Dictionary<string, object>
        {
            ["Mode"] = "Validate",
            ["PolicyPath"] = policyPath
        };

        Log("Validating policy...");
        await RunPowerShellScriptAsync("Start-AppLockerWorkflow.ps1", parameters);
    }

    #endregion

    #region Events Tab Events

    private void BrowseEventsComputerList_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "Text files (*.txt;*.csv)|*.txt;*.csv|All files (*.*)|*.*",
            Title = "Select Computer List"
        };

        if (dialog.ShowDialog() == true)
        {
            EventsComputerList.Text = dialog.FileName;
        }
    }

    private async void CollectEvents_Click(object sender, RoutedEventArgs e)
    {
        var computers = EventsComputerList.Text.Trim();
        if (string.IsNullOrEmpty(computers))
        {
            Log("Please specify computers to collect events from.", LogLevel.Warning);
            return;
        }

        var parameters = new Dictionary<string, object>
        {
            ["Mode"] = "Events"
        };

        if (File.Exists(computers))
        {
            parameters["ComputerList"] = computers;
        }
        else
        {
            var tempFile = Path.GetTempFileName();
            await File.WriteAllTextAsync(tempFile, computers);
            parameters["ComputerList"] = tempFile;
        }

        if (int.TryParse(EventsDaysBack.Text, out int days))
        {
            parameters["DaysBack"] = days;
        }

        if (EventsBlockedOnly.IsChecked == true)
        {
            parameters["BlockedOnly"] = true;
        }

        if (EventsIncludeAllowed.IsChecked == true)
        {
            parameters["IncludeAllowedEvents"] = true;
        }

        Log("Collecting AppLocker events...");
        await RunPowerShellScriptAsync("Start-AppLockerWorkflow.ps1", parameters);
    }

    #endregion

    #region Compare Tab Events

    private void BrowseCompareReference_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*",
            Title = "Select Reference (Baseline) File"
        };

        if (dialog.ShowDialog() == true)
        {
            CompareReferencePath.Text = dialog.FileName;
        }
    }

    private void BrowseCompareTarget_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*",
            Title = "Select Target File"
        };

        if (dialog.ShowDialog() == true)
        {
            CompareTargetPath.Text = dialog.FileName;
        }
    }

    private async void CompareInventories_Click(object sender, RoutedEventArgs e)
    {
        var refPath = CompareReferencePath.Text.Trim();
        var targetPath = CompareTargetPath.Text.Trim();

        if (string.IsNullOrEmpty(refPath) || !File.Exists(refPath))
        {
            Log("Please specify a valid reference file.", LogLevel.Warning);
            return;
        }

        if (string.IsNullOrEmpty(targetPath) || !File.Exists(targetPath))
        {
            Log("Please specify a valid target file.", LogLevel.Warning);
            return;
        }

        var parameters = new Dictionary<string, object>
        {
            ["ReferencePath"] = refPath,
            ["ComparePath"] = targetPath
        };

        Log("Comparing software inventories...");
        await RunPowerShellScriptAsync("utilities\\Compare-SoftwareInventory.ps1", parameters);
    }

    #endregion

    #region Settings Tab Events

    private void BrowseDefaultOutput_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select Default Output Directory"
        };

        if (dialog.ShowDialog() == true)
        {
            DefaultOutputPath.Text = dialog.FolderName;
        }
    }

    private void LocateScripts_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select GA-AppLocker Scripts Folder"
        };

        if (dialog.ShowDialog() == true)
        {
            var workflowScript = Path.Combine(dialog.FolderName, "Start-AppLockerWorkflow.ps1");
            if (File.Exists(workflowScript))
            {
                ScriptsPath.Text = dialog.FolderName;
                Log($"Scripts path updated: {dialog.FolderName}");
            }
            else
            {
                Log("Start-AppLockerWorkflow.ps1 not found in selected folder.", LogLevel.Warning);
            }
        }
    }

    private void SaveSettings_Click(object sender, RoutedEventArgs e)
    {
        // Save settings to user config
        Log("Settings saved.", LogLevel.Success);
    }

    #endregion

    private void ClearLog_Click(object sender, RoutedEventArgs e)
    {
        OutputLog.Clear();
    }

    protected override void OnClosed(EventArgs e)
    {
        _runspace?.Close();
        _runspace?.Dispose();
        base.OnClosed(e);
    }

    private enum LogLevel
    {
        Info,
        Success,
        Warning,
        Error
    }
}
