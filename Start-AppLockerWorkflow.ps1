<#
.SYNOPSIS
    Unified entry point for GA-AppLocker workflow.

.DESCRIPTION
    This script provides a single, simplified interface to the AppLocker policy
    generation workflow. Instead of running multiple scripts separately, use
    this unified workflow to:

    - Scan: Collect data from remote computers
    - Generate: Create AppLocker policies from scan data
    - Merge: Combine multiple policy files
    - Validate: Check policy files for issues
    - Full: Run the complete workflow (Scan -> Generate)

    Interactive mode guides you through each step with prompts.

.PARAMETER Mode
    Workflow mode to execute:
    - Scan: Run remote data collection
    - Generate: Create policy from scan data
    - Merge: Combine multiple policies
    - Validate: Validate a policy file
    - Full: Complete workflow
    - Interactive: Menu-driven mode (default)

.PARAMETER ScanPath
    Path to scan results (for Generate/Merge modes).

.PARAMETER OutputPath
    Path to save generated files.

.PARAMETER ComputerList
    Path to text file with computer names (for Scan mode).

.PARAMETER PolicyPath
    Path to policy file (for Validate mode).

.PARAMETER Simplified
    Use simplified policy generation mode.

.PARAMETER TargetType
    Target type for Build Guide mode: Workstation, Server, DomainController.

.PARAMETER DomainName
    Domain name for Build Guide mode.

.PARAMETER Phase
    Build phase (1-4) for Build Guide mode.

.EXAMPLE
    # Interactive menu mode
    .\Start-AppLockerWorkflow.ps1

.EXAMPLE
    # Quick scan
    .\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt -OutputPath .\Scans

.EXAMPLE
    # Generate simplified policy
    .\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified

.EXAMPLE
    # Generate Build Guide policy
    .\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -TargetType Workstation -DomainName CONTOSO -Phase 1

.EXAMPLE
    # Validate existing policy
    .\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath .\policy.xml

.NOTES
    Part of GA-AppLocker toolkit.
    See README.md for full documentation.
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Direct')]
    [ValidateSet("Scan", "Generate", "Merge", "Validate", "Full", "Compare", "ADSetup", "ADExport", "ADImport", "Diagnostic", "Interactive")]
    [string]$Mode = "Interactive",

    [string]$ScanPath,
    [string]$OutputPath = ".\Outputs",
    [string]$ComputerList,
    [string]$PolicyPath,
    [switch]$Simplified,
    [ValidateSet("Workstation", "Server", "DomainController")]
    [string]$TargetType,
    [string]$DomainName,
    [ValidateRange(1, 4)]
    [int]$Phase = 1,
    [PSCredential]$Credential,

    # Compare mode parameters
    [string]$ReferencePath,
    [string]$ComparePath,
    [ValidateSet("Name", "NameVersion", "Hash", "Publisher")]
    [string]$CompareBy = "Name",

    # Diagnostic mode parameters
    [ValidateSet("Connectivity", "JobSession", "JobFull", "SimpleScan")]
    [string]$DiagnosticType,
    [string]$ComputerName,

    # AD mode parameters
    [string]$ParentOU,
    [string]$GroupPrefix = "AppLocker",
    [string]$InputPath,
    [string]$SearchBase,
    [switch]$IncludeDisabled,
    [switch]$Force
)

#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# Import utilities (includes validation functions)
$modulePath = Join-Path $scriptRoot "utilities\Common.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}
else {
    Write-Warning "Utilities module not found. Some features may not work correctly."
}

#region Banner and Menu

function Show-Banner {
    Write-Host ""
    Write-Host "  GA-AppLocker - AppLocker Policy Generation Toolkit" -ForegroundColor Cyan
    Write-Host "  -------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Menu {
    Write-Host "  Select an option:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  === Core Workflow ===" -ForegroundColor Cyan
    Write-Host "    [1] Scan       - Collect data from remote computers" -ForegroundColor White
    Write-Host "    [2] Generate   - Create AppLocker policy from scan data" -ForegroundColor White
    Write-Host "    [3] Merge      - Combine multiple policy files" -ForegroundColor White
    Write-Host "    [4] Validate   - Check a policy file for issues" -ForegroundColor White
    Write-Host "    [5] Full       - Complete workflow (Scan + Generate)" -ForegroundColor White
    Write-Host ""
    Write-Host "  === Analysis ===" -ForegroundColor Cyan
    Write-Host "    [6] Compare    - Compare software inventories" -ForegroundColor White
    Write-Host ""
    Write-Host "  === Software Lists ===" -ForegroundColor Cyan
    Write-Host "    [S] Software   - Manage software lists for rule generation" -ForegroundColor White
    Write-Host ""
    Write-Host "  === AD Management ===" -ForegroundColor Cyan
    Write-Host "    [7] AD Setup   - Create AppLocker OUs and groups" -ForegroundColor White
    Write-Host "    [8] AD Export  - Export user group memberships" -ForegroundColor White
    Write-Host "    [9] AD Import  - Apply group membership changes" -ForegroundColor White
    Write-Host ""
    Write-Host "  === Infrastructure ===" -ForegroundColor Cyan
    Write-Host "    [W] WinRM      - Deploy/Remove WinRM GPO" -ForegroundColor White
    Write-Host "    [D] Diagnostic - Troubleshoot remote scanning" -ForegroundColor White
    Write-Host ""
    Write-Host "    [Q] Quit" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "  Enter choice"
    return $choice
}

function Show-GenerateMenu {
    Write-Host ""
    Write-Host "  Policy Generation Mode:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    [1] Simplified  - Quick policy from scan data" -ForegroundColor White
    Write-Host "        Best for: Testing, small environments, quick deployments"
    Write-Host ""
    Write-Host "    [2] Build Guide - Enterprise policy with proper scoping" -ForegroundColor White
    Write-Host "        Best for: Production, large enterprises, phased rollout"
    Write-Host ""
    Write-Host "    [B] Back" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "  Enter choice"
    return $choice
}

#endregion

#region Workflow Functions

# =============================================================================
# Helper Functions for Folder/File Selection
# =============================================================================

function Select-ScanFolder {
    <#
    .SYNOPSIS
    Interactive menu to select a scan folder from the Scans directory.

    .PARAMETER BasePath
    Base path to look for scan folders. Default: .\Scans

    .PARAMETER Prompt
    Custom prompt text.

    .PARAMETER AllowMultiple
    Allow selecting multiple folders.

    .PARAMETER AllowCancel
    Show cancel option.

    .RETURNS
    Selected folder path(s) or $null if cancelled.
    #>
    param(
        [string]$BasePath = ".\Scans",
        [string]$Prompt = "Select scan folder",
        [switch]$AllowMultiple,
        [switch]$AllowCancel
    )

    # Check if base path exists
    if (-not (Test-Path $BasePath)) {
        Write-Host "  [-] Scan directory not found: $BasePath" -ForegroundColor Red
        Write-Host "      Run a scan first using the Scan workflow." -ForegroundColor Yellow
        return $null
    }

    # Get all scan folders (folders containing CSV files)
    $scanFolders = @(Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $csvFiles = Get-ChildItem -Path $_.FullName -Filter "*.csv" -ErrorAction SilentlyContinue
            $csvFiles.Count -gt 0
        } |
        Sort-Object LastWriteTime -Descending)

    if ($scanFolders.Count -eq 0) {
        Write-Host "  [-] No scan data found in: $BasePath" -ForegroundColor Red
        Write-Host "      Scan folders should contain CSV files (Executables.csv, etc.)" -ForegroundColor Yellow
        return $null
    }

    # Display available folders
    Write-Host ""
    Write-Host "  Available scan folders:" -ForegroundColor Yellow
    Write-Host ""

    $i = 1
    foreach ($folder in $scanFolders) {
        # Get scan info
        $csvCount = @(Get-ChildItem -Path $folder.FullName -Filter "*.csv" -ErrorAction SilentlyContinue).Count
        $exeFile = Join-Path $folder.FullName "Executables.csv"
        $exeCount = 0
        if (Test-Path $exeFile) {
            $exeCount = @(Import-Csv $exeFile -ErrorAction SilentlyContinue).Count
        }
        $scanDate = $folder.LastWriteTime.ToString("yyyy-MM-dd HH:mm")

        Write-Host "    [$i] $($folder.Name)" -ForegroundColor White
        Write-Host "        Scanned: $scanDate | Files: $csvCount CSVs | Executables: $exeCount" -ForegroundColor DarkGray
        $i++
    }

    Write-Host ""
    if ($AllowMultiple) {
        Write-Host "    [A] All folders" -ForegroundColor Cyan
    }
    if ($AllowCancel) {
        Write-Host "    [C] Cancel" -ForegroundColor Gray
    }
    Write-Host ""

    # Get selection
    if ($AllowMultiple) {
        Write-Host "  Enter numbers separated by commas (e.g., 1,3,5) or 'A' for all" -ForegroundColor DarkGray
    }
    $selection = Read-Host "  $Prompt"

    # Handle cancel
    if ($AllowCancel -and $selection -in @("C", "c")) {
        return $null
    }

    # Handle all
    if ($AllowMultiple -and $selection -in @("A", "a", "all")) {
        return $scanFolders.FullName
    }

    # Parse selection
    $selectedPaths = @()
    $indices = $selection -split "," | ForEach-Object { $_.Trim() }

    foreach ($idx in $indices) {
        if ($idx -match "^\d+$") {
            $num = [int]$idx
            if ($num -ge 1 -and $num -le $scanFolders.Count) {
                $selectedPaths += $scanFolders[$num - 1].FullName
            }
            else {
                Write-Host "  [-] Invalid selection: $idx (out of range)" -ForegroundColor Red
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($idx)) {
            Write-Host "  [-] Invalid selection: $idx" -ForegroundColor Red
        }
    }

    if ($selectedPaths.Count -eq 0) {
        Write-Host "  [-] No valid selection made" -ForegroundColor Red
        return $null
    }

    if ($AllowMultiple) {
        return $selectedPaths
    }
    else {
        return $selectedPaths[0]
    }
}


function Select-CsvFile {
    <#
    .SYNOPSIS
    Interactive menu to select a specific CSV file from scan folders.

    .PARAMETER BasePath
    Base path to look for scan folders. Default: .\Scans

    .PARAMETER FileType
    Type of CSV to look for: Executables, Publishers, WritableDirectories, InstalledSoftware, All

    .PARAMETER Prompt
    Custom prompt text.

    .RETURNS
    Selected file path or $null if cancelled.
    #>
    param(
        [string]$BasePath = ".\Scans",
        [ValidateSet("Executables", "Publishers", "WritableDirectories", "InstalledSoftware", "All")]
        [string]$FileType = "Executables",
        [string]$Prompt = "Select CSV file"
    )

    # First select the folder
    $folder = Select-ScanFolder -BasePath $BasePath -Prompt "Select scan folder" -AllowCancel

    if (-not $folder) {
        return $null
    }

    # If specific file type, return it directly
    if ($FileType -ne "All") {
        $csvPath = Join-Path $folder "$FileType.csv"
        if (Test-Path $csvPath) {
            return $csvPath
        }
        else {
            Write-Host "  [-] $FileType.csv not found in selected folder" -ForegroundColor Red
            return $null
        }
    }

    # Show available CSV files in folder
    $csvFiles = @(Get-ChildItem -Path $folder -Filter "*.csv" -ErrorAction SilentlyContinue)

    if ($csvFiles.Count -eq 0) {
        Write-Host "  [-] No CSV files found in: $folder" -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "  Available files in $([System.IO.Path]::GetFileName($folder)):" -ForegroundColor Yellow
    $i = 1
    foreach ($file in $csvFiles) {
        $rowCount = @(Import-Csv $file.FullName -ErrorAction SilentlyContinue).Count
        Write-Host "    [$i] $($file.Name) ($rowCount rows)" -ForegroundColor White
        $i++
    }
    Write-Host "    [C] Cancel" -ForegroundColor Gray
    Write-Host ""

    $selection = Read-Host "  $Prompt"

    if ($selection -in @("C", "c")) {
        return $null
    }

    if ($selection -match "^\d+$") {
        $num = [int]$selection
        if ($num -ge 1 -and $num -le $csvFiles.Count) {
            return $csvFiles[$num - 1].FullName
        }
    }

    Write-Host "  [-] Invalid selection" -ForegroundColor Red
    return $null
}

# =============================================================================
# Core Workflow Functions
# =============================================================================

function Invoke-ScanWorkflow {
    param(
        [string]$ComputerListPath,
        [string]$OutputPath,
        [PSCredential]$Credential
    )

    Write-Host "`n=== Remote Scan Workflow ===" -ForegroundColor Cyan

    # Get computer list - validate input with default
    if ([string]::IsNullOrWhiteSpace($ComputerListPath)) {
        $ComputerListPath = Read-Host "  Enter path to computer list file (default: .\computers.txt)"
        if ([string]::IsNullOrWhiteSpace($ComputerListPath)) {
            $ComputerListPath = ".\computers.txt"
        }
    }

    if (-not (Test-Path $ComputerListPath)) {
        Write-Host "  [-] Computer list not found: $ComputerListPath" -ForegroundColor Red
        return $null
    }

    # Ensure it's a file, not a directory
    if ((Get-Item $ComputerListPath).PSIsContainer) {
        Write-Host "  [-] Path is a directory, not a file: $ComputerListPath" -ForegroundColor Red
        Write-Host "      Please provide a text file containing computer names (one per line)" -ForegroundColor Yellow
        return $null
    }

    # Get output path - validate and set default
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Read-Host "  Enter output path (default: .\Scans)"
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $OutputPath = ".\Scans"
        }
    }

    # Get credentials if not provided
    if ($null -eq $Credential) {
        Write-Host "  Enter credentials for remote connections:" -ForegroundColor Yellow
        $Credential = Get-Credential -Message "Remote scan credentials (DOMAIN\username)"
    }

    # Validate we have credentials
    if ($null -eq $Credential) {
        Write-Host "  [-] Credentials are required for remote scanning" -ForegroundColor Red
        return $null
    }

    # Run scan
    $scanScript = Join-Path $scriptRoot "Invoke-RemoteScan.ps1"
    if (Test-Path $scanScript) {
        Write-Host "`n  Starting remote scan..." -ForegroundColor Cyan

        # Build parameter hashtable with only valid, non-null values
        $scanParams = @{
            ComputerListPath = $ComputerListPath
            SharePath        = $OutputPath
            Credential       = $Credential
        }

        try {
            & $scanScript @scanParams
            return $OutputPath
        }
        catch {
            Write-Host "  [-] Scan failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    else {
        Write-Host "  [-] Scan script not found: $scanScript" -ForegroundColor Red
        return $null
    }
}

function Invoke-GenerateWorkflow {
    param(
        [string]$ScanPath,
        [string]$OutputPath,
        [switch]$Simplified,
        [string]$TargetType,
        [string]$DomainName,
        [int]$Phase
    )

    Write-Host "`n=== Policy Generation Workflow ===" -ForegroundColor Cyan

    # Get scan path - validate input
    if ([string]::IsNullOrWhiteSpace($ScanPath)) {
        $ScanPath = Read-Host "  Enter path to scan results"
    }

    if ([string]::IsNullOrWhiteSpace($ScanPath)) {
        Write-Host "  [-] Scan path is required" -ForegroundColor Red
        return $null
    }

    if (-not (Test-Path $ScanPath)) {
        Write-Host "  [-] Scan path not found: $ScanPath" -ForegroundColor Red
        return $null
    }

    # Validate scan data
    if (Get-Command Test-ScanData -ErrorAction SilentlyContinue) {
        Write-Host "  Validating scan data..." -ForegroundColor Gray
        $validation = Test-ScanData -ScanPath $ScanPath
        if (-not $validation.IsValid) {
            Write-Host "  [-] Scan data validation failed" -ForegroundColor Red
            Show-ValidationResult -ValidationResult $validation
            return $null
        }
        Write-Host "  [+] Scan data validated: $($validation.ComputerCount) computers" -ForegroundColor Green
    }

    # Determine generation mode - only prompt if neither Simplified nor TargetType is set
    $useSimplified = $Simplified.IsPresent
    if (-not $useSimplified -and [string]::IsNullOrWhiteSpace($TargetType)) {
        $modeChoice = Show-GenerateMenu
        switch ($modeChoice) {
            "1" { $useSimplified = $true }
            "2" {
                $TargetType = Read-Host "  Enter target type (Workstation/Server/DomainController)"
                $DomainName = Read-Host "  Enter domain name (e.g., CONTOSO)"
                Write-Host ""
                Write-Host "  Deployment Phases:" -ForegroundColor Yellow
                Write-Host "    [1] EXE only           - Start here, lowest risk" -ForegroundColor White
                Write-Host "    [2] EXE + Script       - Adds .ps1, .bat, .vbs rules (highest bypass risk)" -ForegroundColor White
                Write-Host "    [3] EXE + Script + MSI - Adds installer rules (test deployments)" -ForegroundColor White
                Write-Host "    [4] All + DLL          - Full policy (audit 14+ days before enforcing!)" -ForegroundColor White
                Write-Host ""
                $phaseInput = Read-Host "  Enter phase (1-4, default: 1)"
                $Phase = if ([int]::TryParse($phaseInput, [ref]$null)) { [int]$phaseInput } else { 1 }
                if ($Phase -lt 1 -or $Phase -gt 4) { $Phase = 1 }
            }
            "B" { return $null }
            default {
                Write-Host "  Invalid choice" -ForegroundColor Red
                return $null
            }
        }
    }

    # Run generation
    $genScript = Join-Path $scriptRoot "New-AppLockerPolicyFromGuide.ps1"
    if (Test-Path $genScript) {
        Write-Host "`n  Generating policy..." -ForegroundColor Cyan

        # Build parameter hashtable carefully to avoid parameter set conflicts
        $params = @{}

        # Always add ScanPath if valid
        if (-not [string]::IsNullOrWhiteSpace($ScanPath)) {
            $params.ScanPath = $ScanPath
        }

        # Always add OutputPath if valid
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $params.OutputPath = $OutputPath
        }

        if ($useSimplified) {
            # Simplified mode - only add the switch
            $params.Simplified = $true
        }
        else {
            # Build Guide mode - validate required parameters before adding
            if ([string]::IsNullOrWhiteSpace($TargetType)) {
                Write-Host "  [-] Target type is required for Build Guide mode" -ForegroundColor Red
                return $null
            }
            if ([string]::IsNullOrWhiteSpace($DomainName)) {
                Write-Host "  [-] Domain name is required for Build Guide mode" -ForegroundColor Red
                return $null
            }

            $params.TargetType = $TargetType
            $params.DomainName = $DomainName
            if ($Phase -ge 1 -and $Phase -le 4) {
                $params.Phase = $Phase
            }
        }

        try {
            $result = & $genScript @params
            return $result
        }
        catch {
            Write-Host "  [-] Policy generation failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    else {
        Write-Host "  [-] Generation script not found: $genScript" -ForegroundColor Red
        return $null
    }
}

function Invoke-MergeWorkflow {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    Write-Host "`n=== Policy Merge Workflow ===" -ForegroundColor Cyan

    # Get input path - validate
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $InputPath = Read-Host "  Enter path to folder containing policy files"
    }

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        Write-Host "  [-] Input path is required" -ForegroundColor Red
        return $null
    }

    if (-not (Test-Path $InputPath)) {
        Write-Host "  [-] Input path not found: $InputPath" -ForegroundColor Red
        return $null
    }

    # Get output path - validate and set default
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $defaultOutput = ".\MergedPolicy.xml"
        $OutputPath = Read-Host "  Enter output file path (default: $defaultOutput)"
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $OutputPath = $defaultOutput
        }
    }

    # Run merge
    $mergeScript = Join-Path $scriptRoot "Merge-AppLockerPolicies.ps1"
    if (Test-Path $mergeScript) {
        Write-Host "`n  Merging policies..." -ForegroundColor Cyan

        $mergeParams = @{
            InputPath = $InputPath
        }
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $mergeParams.OutputPath = $OutputPath
        }

        try {
            $result = & $mergeScript @mergeParams
            return $result
        }
        catch {
            Write-Host "  [-] Merge failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    else {
        Write-Host "  [-] Merge script not found: $mergeScript" -ForegroundColor Red
        return $null
    }
}

function Invoke-ValidateWorkflow {
    param(
        [string]$PolicyPath
    )

    Write-Host "`n=== Policy Validation Workflow ===" -ForegroundColor Cyan
    Write-Host "  Validates an AppLocker policy XML file for correctness." -ForegroundColor Gray
    Write-Host ""

    # Get policy path - validate
    if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
        Write-Host "  Example: .\Outputs\AppLockerPolicy-Workstation-Phase1-AuditOnly-20260108.xml" -ForegroundColor DarkGray
        $PolicyPath = Read-Host "  Enter path to policy XML file"
    }

    if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
        Write-Host "  [-] Policy path is required" -ForegroundColor Red
        return $null
    }

    if (-not (Test-Path $PolicyPath -PathType Leaf)) {
        Write-Host "  [-] Policy XML file not found: $PolicyPath" -ForegroundColor Red
        Write-Host "      Make sure to specify an XML file, not a directory." -ForegroundColor Yellow
        return $null
    }

    # Run validation
    if (Get-Command Test-AppLockerPolicy -ErrorAction SilentlyContinue) {
        Write-Host "  Validating policy..." -ForegroundColor Gray
        try {
            $validation = Test-AppLockerPolicy -PolicyPath $PolicyPath
            Show-ValidationResult -ValidationResult $validation
            return $validation
        }
        catch {
            Write-Host "  [-] Validation failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    else {
        # Basic validation without module
        Write-Host "  Performing basic XML validation..." -ForegroundColor Gray
        try {
            [xml]$policy = Get-Content -Path $PolicyPath -Raw
            if ($null -ne $policy.AppLockerPolicy) {
                Write-Host "  [+] Policy XML is valid" -ForegroundColor Green

                $ruleCount = 0
                foreach ($coll in $policy.AppLockerPolicy.RuleCollection) {
                    $count = ($coll.FilePublisherRule | Measure-Object).Count +
                             ($coll.FilePathRule | Measure-Object).Count +
                             ($coll.FileHashRule | Measure-Object).Count
                    Write-Host "    $($coll.Type): $count rules ($($coll.EnforcementMode))" -ForegroundColor Gray
                    $ruleCount += $count
                }
                Write-Host "  Total rules: $ruleCount" -ForegroundColor Cyan

                # Return basic validation result
                return @{
                    IsValid = $true
                    RuleCount = $ruleCount
                    PolicyPath = $PolicyPath
                }
            }
            else {
                Write-Host "  [-] Missing AppLockerPolicy element" -ForegroundColor Red
                return @{
                    IsValid = $false
                    Error = "Missing AppLockerPolicy element"
                    PolicyPath = $PolicyPath
                }
            }
        }
        catch {
            Write-Host "  [-] Invalid XML: $($_.Exception.Message)" -ForegroundColor Red
            return @{
                IsValid = $false
                Error = $_.Exception.Message
                PolicyPath = $PolicyPath
            }
        }
    }
}

function Invoke-FullWorkflow {
    param(
        [string]$ComputerList,
        [string]$OutputPath,
        [PSCredential]$Credential,
        [switch]$Simplified,
        [string]$TargetType,
        [string]$DomainName,
        [int]$Phase
    )

    Write-Host "`n=== Full Workflow ===" -ForegroundColor Cyan
    Write-Host "  This will run: Scan -> Generate" -ForegroundColor Gray
    Write-Host ""

    # Step 1: Scan - pass parameters correctly
    $scanParams = @{}
    if (-not [string]::IsNullOrWhiteSpace($ComputerList)) {
        $scanParams.ComputerListPath = $ComputerList
    }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $scanParams.OutputPath = $OutputPath
    }
    if ($null -ne $Credential) {
        $scanParams.Credential = $Credential
    }

    $scanOutput = Invoke-ScanWorkflow @scanParams

    if (-not $scanOutput) {
        Write-Host "  [-] Scan failed, aborting workflow" -ForegroundColor Red
        return
    }

    # Find the latest scan folder
    $latestScan = Get-ChildItem -Path $scanOutput -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestScan) {
        $scanDataPath = $latestScan.FullName
    }
    else {
        $scanDataPath = $scanOutput
    }

    Write-Host "`n  [+] Scan complete: $scanDataPath" -ForegroundColor Green
    Write-Host ""

    # Step 2: Generate - build parameters carefully
    $genParams = @{
        ScanPath = $scanDataPath
    }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $genParams.OutputPath = $OutputPath
    }
    if ($Simplified.IsPresent) {
        $genParams.Simplified = $true
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TargetType)) {
        $genParams.TargetType = $TargetType
        if (-not [string]::IsNullOrWhiteSpace($DomainName)) {
            $genParams.DomainName = $DomainName
        }
        if ($Phase -ge 1 -and $Phase -le 4) {
            $genParams.Phase = $Phase
        }
    }

    $policyPath = Invoke-GenerateWorkflow @genParams

    if ($policyPath) {
        Write-Host "`n  [+] Full workflow complete!" -ForegroundColor Green
        Write-Host "  Policy file: $policyPath" -ForegroundColor Cyan
    }
}

function Invoke-WinRMWorkflow {
    Write-Host "`n=== WinRM Deployment Workflow ===" -ForegroundColor Cyan
    Write-Host "  This will create a GPO to enable WinRM across domain computers." -ForegroundColor Gray
    Write-Host "  Requires: Domain Controller, RSAT tools, Domain Admin privileges." -ForegroundColor Yellow
    Write-Host ""

    $winrmScript = Join-Path $scriptRoot "utilities\Enable-WinRM-Domain.ps1"
    if (Test-Path $winrmScript) {
        $confirm = Read-Host "  Proceed with WinRM GPO deployment? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            Write-Host "  Aborted." -ForegroundColor Yellow
            return
        }

        try {
            & $winrmScript
        }
        catch {
            Write-Host "  [-] WinRM deployment failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [-] WinRM script not found: $winrmScript" -ForegroundColor Red
    }
}

function Invoke-RemoveWinRMWorkflow {
    Write-Host "`n=== WinRM GPO Removal Workflow ===" -ForegroundColor Cyan
    Write-Host "  This will remove the WinRM GPO from the domain." -ForegroundColor Gray
    Write-Host "  Requires: Domain Controller, RSAT tools, Domain Admin privileges." -ForegroundColor Yellow
    Write-Host ""

    $winrmScript = Join-Path $scriptRoot "utilities\Enable-WinRM-Domain.ps1"
    if (Test-Path $winrmScript) {
        $confirm = Read-Host "  Proceed with WinRM GPO removal? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            Write-Host "  Aborted." -ForegroundColor Yellow
            return
        }

        try {
            & $winrmScript -Remove
        }
        catch {
            Write-Host "  [-] WinRM GPO removal failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [-] WinRM script not found: $winrmScript" -ForegroundColor Red
    }
}

function Invoke-CompareWorkflow {
    param(
        [string]$RefPath,
        [string]$CompPath,
        [string]$Method = "Name",
        [string]$OutPath
    )

    Write-Host "`n=== Software Inventory Comparison ===" -ForegroundColor Cyan
    Write-Host "  Compares software inventory between scan folders." -ForegroundColor Gray
    Write-Host "  Useful for: baseline comparison, drift detection, identifying changes." -ForegroundColor Gray
    Write-Host ""

    # Selection method menu
    Write-Host "  How would you like to select files?" -ForegroundColor Yellow
    Write-Host "    [1] Browse scan folders (recommended)" -ForegroundColor White
    Write-Host "    [2] Enter paths manually" -ForegroundColor White
    Write-Host "    [C] Cancel" -ForegroundColor Gray
    Write-Host ""
    $selectionMethod = Read-Host "  Choice"

    if ($selectionMethod -in @("C", "c")) {
        return $null
    }

    if ($selectionMethod -eq "1") {
        # Browse mode - use folder selectors
        Write-Host ""
        Write-Host "  Step 1: Select REFERENCE (baseline) scan folder" -ForegroundColor Yellow
        $refFolder = Select-ScanFolder -Prompt "Select reference folder" -AllowCancel
        if (-not $refFolder) { return $null }

        # Select file type
        Write-Host ""
        Write-Host "  What would you like to compare?" -ForegroundColor Yellow
        Write-Host "    [1] Executables (recommended)" -ForegroundColor White
        Write-Host "    [2] Publishers" -ForegroundColor White
        Write-Host "    [3] Installed Software" -ForegroundColor White
        Write-Host "    [C] Cancel" -ForegroundColor Gray
        $fileTypeChoice = Read-Host "  Choice"

        if ($fileTypeChoice -in @("C", "c")) { return $null }

        $fileType = switch ($fileTypeChoice) {
            "2" { "Publishers" }
            "3" { "InstalledSoftware" }
            default { "Executables" }
        }

        $RefPath = Join-Path $refFolder "$fileType.csv"
        if (-not (Test-Path $RefPath)) {
            Write-Host "  [-] $fileType.csv not found in reference folder" -ForegroundColor Red
            return $null
        }
        Write-Host "  Selected: $RefPath" -ForegroundColor Green

        Write-Host ""
        Write-Host "  Step 2: Select COMPARISON scan folder(s)" -ForegroundColor Yellow
        Write-Host "  You can select multiple folders to compare against the baseline." -ForegroundColor Gray
        $compFolders = Select-ScanFolder -Prompt "Select comparison folder(s)" -AllowMultiple -AllowCancel

        if (-not $compFolders) { return $null }

        # Build comparison paths
        $compPaths = @()
        foreach ($folder in @($compFolders)) {
            $compFile = Join-Path $folder "$fileType.csv"
            if (Test-Path $compFile) {
                $compPaths += $compFile
            }
            else {
                Write-Host "  [!] Skipping $([System.IO.Path]::GetFileName($folder)) - no $fileType.csv" -ForegroundColor Yellow
            }
        }

        if ($compPaths.Count -eq 0) {
            Write-Host "  [-] No valid comparison files found" -ForegroundColor Red
            return $null
        }

        # If single path, use directly; if multiple, join for pattern
        if ($compPaths.Count -eq 1) {
            $CompPath = $compPaths[0]
        }
        else {
            # Create a pattern that matches all selected files
            $CompPath = $compPaths -join ","
        }
        Write-Host "  Selected: $($compPaths.Count) file(s) for comparison" -ForegroundColor Green
    }
    else {
        # Manual entry mode
        if ([string]::IsNullOrWhiteSpace($RefPath)) {
            Write-Host "  Example: .\Scans\COMPUTER01\Executables.csv" -ForegroundColor DarkGray
            $RefPath = Read-Host "  Enter path to reference/baseline CSV file"
        }

        if ([string]::IsNullOrWhiteSpace($RefPath) -or -not (Test-Path $RefPath -PathType Leaf)) {
            Write-Host "  [-] Reference CSV file not found: $RefPath" -ForegroundColor Red
            Write-Host "      Make sure to specify a CSV file, not a directory." -ForegroundColor Yellow
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($CompPath)) {
            Write-Host "  Example: .\Scans\COMPUTER02\Executables.csv" -ForegroundColor DarkGray
            $CompPath = Read-Host "  Enter path to comparison CSV file"
        }

        if ([string]::IsNullOrWhiteSpace($CompPath)) {
            Write-Host "  [-] Comparison path is required" -ForegroundColor Red
            return $null
        }
    }

    # Get comparison method
    Write-Host ""
    Write-Host "  Step 3: Select comparison method" -ForegroundColor Yellow
    Write-Host "    [1] Name - Compare by filename only" -ForegroundColor White
    Write-Host "    [2] NameVersion - Compare by name and version" -ForegroundColor White
    Write-Host "    [3] Hash - Compare by file hash (exact match)" -ForegroundColor White
    Write-Host "    [4] Publisher - Compare by publisher/signer" -ForegroundColor White
    $methodChoice = Read-Host "  Choice (default: 1)"
    $Method = switch ($methodChoice) {
        "2" { "NameVersion" }
        "3" { "Hash" }
        "4" { "Publisher" }
        default { "Name" }
    }

    # Run comparison
    $compareScript = Join-Path $scriptRoot "utilities\Compare-SoftwareInventory.ps1"
    if (-not (Test-Path $compareScript)) {
        Write-Host "  [-] Compare script not found: $compareScript" -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "  Comparing inventories by $Method..." -ForegroundColor Cyan

    # Handle multiple comparison paths
    $allResults = @()
    $compPathList = if ($CompPath -match ",") { $CompPath -split "," } else { @($CompPath) }

    foreach ($singleCompPath in $compPathList) {
        $singleCompPath = $singleCompPath.Trim()
        if (-not (Test-Path $singleCompPath)) {
            Write-Host "  [!] Skipping - file not found: $singleCompPath" -ForegroundColor Yellow
            continue
        }

        $compareParams = @{
            ReferencePath = $RefPath
            ComparePath   = $singleCompPath
            CompareBy     = $Method
        }
        if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
            $compareParams.OutputPath = $OutPath
        }

        try {
            $result = & $compareScript @compareParams
            if ($result) {
                $allResults += $result
            }
        }
        catch {
            Write-Host "  [-] Comparison failed for $singleCompPath : $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if ($allResults.Count -gt 0) {
        Write-Host ""
        Write-Host "  [+] Comparison complete!" -ForegroundColor Green
        return $allResults
    }
    else {
        Write-Host "  [-] No comparison results" -ForegroundColor Yellow
        return $null
    }
}

function Invoke-ADSetupWorkflow {
    param(
        [string]$Domain,
        [string]$Parent,
        [string]$Prefix,
        [switch]$NoConfirm
    )

    Write-Host "`n=== AD Structure Setup ===" -ForegroundColor Cyan
    Write-Host "  Creates AppLocker OUs and security groups in Active Directory." -ForegroundColor Gray
    Write-Host "  Requires: ActiveDirectory module, Domain Admin privileges." -ForegroundColor Yellow
    Write-Host ""

    # Get domain name
    if ([string]::IsNullOrWhiteSpace($Domain)) {
        $Domain = Read-Host "  Enter domain name (e.g., CONTOSO)"
    }

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        Write-Host "  [-] Domain name is required" -ForegroundColor Red
        return $null
    }

    $adScript = Join-Path $scriptRoot "utilities\Manage-ADResources.ps1"
    if (Test-Path $adScript) {
        $adParams = @{
            Action     = "CreateStructure"
            DomainName = $Domain
        }
        if (-not [string]::IsNullOrWhiteSpace($Parent)) {
            $adParams.ParentOU = $Parent
        }
        if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
            $adParams.GroupPrefix = $Prefix
        }
        if ($NoConfirm) {
            $adParams.Force = $true
        }

        try {
            $result = & $adScript @adParams
            return $result
        }
        catch {
            Write-Host "  [-] AD setup failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    else {
        Write-Host "  [-] AD management script not found: $adScript" -ForegroundColor Red
        return $null
    }
}

function Invoke-ADExportWorkflow {
    param(
        [string]$Search,
        [string]$OutPath,
        [switch]$Disabled
    )

    Write-Host "`n=== AD User Export ===" -ForegroundColor Cyan
    Write-Host "  Exports users and their group memberships to CSV for editing." -ForegroundColor Gray
    Write-Host ""

    # Get output path
    if ([string]::IsNullOrWhiteSpace($OutPath)) {
        $defaultPath = ".\ADUserGroups-Export.csv"
        $OutPath = Read-Host "  Enter output path (default: $defaultPath)"
        if ([string]::IsNullOrWhiteSpace($OutPath)) {
            $OutPath = $defaultPath
        }
    }

    $adScript = Join-Path $scriptRoot "utilities\Manage-ADResources.ps1"
    if (Test-Path $adScript) {
        $adParams = @{
            Action     = "ExportUsers"
            OutputPath = $OutPath
        }
        if (-not [string]::IsNullOrWhiteSpace($Search)) {
            $adParams.SearchBase = $Search
        }
        if ($Disabled) {
            $adParams.IncludeDisabled = $true
        }

        try {
            $result = & $adScript @adParams
            return $result
        }
        catch {
            Write-Host "  [-] AD export failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    else {
        Write-Host "  [-] AD management script not found: $adScript" -ForegroundColor Red
        return $null
    }
}

function Invoke-ADImportWorkflow {
    param(
        [string]$InPath,
        [switch]$Preview
    )

    Write-Host "`n=== AD User Import ===" -ForegroundColor Cyan
    Write-Host "  Applies group membership changes from CSV to Active Directory." -ForegroundColor Gray
    Write-Host ""

    # Get input path
    if ([string]::IsNullOrWhiteSpace($InPath)) {
        $InPath = Read-Host "  Enter path to CSV file with group changes"
    }

    if ([string]::IsNullOrWhiteSpace($InPath) -or -not (Test-Path $InPath)) {
        Write-Host "  [-] Input file not found: $InPath" -ForegroundColor Red
        return $null
    }

    # Ask about preview mode
    if (-not $Preview) {
        $previewChoice = Read-Host "  Preview changes first? (Y/n)"
        $Preview = ($previewChoice -ne 'n' -and $previewChoice -ne 'N')
    }

    $adScript = Join-Path $scriptRoot "utilities\Manage-ADResources.ps1"
    if (Test-Path $adScript) {
        $adParams = @{
            Action    = "ImportUsers"
            InputPath = $InPath
        }

        if ($Preview) {
            Write-Host "`n  Running in preview mode (no changes will be made)..." -ForegroundColor Yellow
            $adParams.WhatIf = $true
        }

        try {
            & $adScript @adParams
        }
        catch {
            Write-Host "  [-] AD import failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [-] AD management script not found: $adScript" -ForegroundColor Red
    }
}

function Invoke-DiagnosticWorkflow {
    param(
        [string]$Type,
        [string]$Computer,
        [string]$ComputerList,
        [string]$OutPath,
        [PSCredential]$Cred
    )

    Write-Host "`n=== Diagnostic Tools ===" -ForegroundColor Cyan
    Write-Host "  Troubleshoot remote scanning issues." -ForegroundColor Gray
    Write-Host ""

    # Select diagnostic type if not provided
    if ([string]::IsNullOrWhiteSpace($Type)) {
        Write-Host "  Diagnostic Types:" -ForegroundColor Yellow
        Write-Host "    [1] Connectivity - Test ping, WinRM, sessions" -ForegroundColor White
        Write-Host "    [2] JobSession   - Test PowerShell job execution" -ForegroundColor White
        Write-Host "    [3] JobFull      - Full job test with tracing" -ForegroundColor White
        Write-Host "    [4] SimpleScan   - Scan without parallel jobs" -ForegroundColor White
        Write-Host ""

        $typeChoice = Read-Host "  Enter choice"
        $Type = switch ($typeChoice) {
            "1" { "Connectivity" }
            "2" { "JobSession" }
            "3" { "JobFull" }
            "4" { "SimpleScan" }
            default { "Connectivity" }
        }
    }

    $diagScript = Join-Path $scriptRoot "utilities\Test-AppLockerDiagnostic.ps1"
    if (Test-Path $diagScript) {
        $diagParams = @{
            TestType = $Type
        }

        if ($Type -eq "SimpleScan") {
            # SimpleScan needs a computer list
            if ([string]::IsNullOrWhiteSpace($ComputerList)) {
                Write-Host "  Example: .\computers.txt" -ForegroundColor DarkGray
                $ComputerList = Read-Host "  Enter path to computer list file"
            }
            if (-not [string]::IsNullOrWhiteSpace($ComputerList)) {
                $diagParams.ComputerListPath = $ComputerList
            }
        }
        else {
            # Connectivity, JobSession, JobFull need a single computer name
            if ([string]::IsNullOrWhiteSpace($Computer)) {
                Write-Host "  Example: WORKSTATION01 or 192.168.1.100" -ForegroundColor DarkGray
                $Computer = Read-Host "  Enter target computer name"
            }
            if ([string]::IsNullOrWhiteSpace($Computer)) {
                Write-Host "  [-] Computer name is required for $Type test" -ForegroundColor Red
                return
            }
            $diagParams.ComputerName = $Computer
        }

        if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
            $diagParams.OutputPath = $OutPath
        }

        if ($null -ne $Cred) {
            $diagParams.Credential = $Cred
        }

        try {
            & $diagScript @diagParams
        }
        catch {
            Write-Host "  [-] Diagnostic failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [-] Diagnostic script not found: $diagScript" -ForegroundColor Red
    }
}

function Show-WinRMMenu {
    Write-Host ""
    Write-Host "  WinRM GPO Options:" -ForegroundColor Yellow
    Write-Host "    [1] Deploy  - Create WinRM GPO" -ForegroundColor White
    Write-Host "    [2] Remove  - Remove WinRM GPO" -ForegroundColor White
    Write-Host "    [B] Back" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "  Enter choice"
    return $choice
}

function Show-SoftwareListMenu {
    Write-Host ""
    Write-Host "  Software List Management:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  --- List Operations ---" -ForegroundColor DarkGray
    Write-Host "    [1] Create     - Create a new software list" -ForegroundColor White
    Write-Host "    [2] View       - View/search existing software lists" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- Add Software ---" -ForegroundColor DarkGray
    Write-Host "    [3] Add Manual - Add software manually (publisher/hash)" -ForegroundColor White
    Write-Host "    [4] Add Common - Quick-add from common publishers" -ForegroundColor White
    Write-Host "    [5] Import     - Import from scan data or executable" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- Manage Items ---" -ForegroundColor DarkGray
    Write-Host "    [6] Toggle     - Approve/unapprove items" -ForegroundColor White
    Write-Host "    [7] Delete     - Remove items from a list" -ForegroundColor White
    Write-Host "    [8] Search     - Search across all lists" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- Policy ---" -ForegroundColor DarkGray
    Write-Host "    [9] Export     - Export list to CSV" -ForegroundColor White
    Write-Host "    [G] Generate   - Generate policy from software list" -ForegroundColor White
    Write-Host ""
    Write-Host "    [B] Back" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "  Enter choice"
    return $choice
}

function Invoke-SoftwareListWorkflow {
    <#
    .SYNOPSIS
    Interactive workflow for managing software lists.
    #>
    Write-Host "`n=== Software List Management ===" -ForegroundColor Cyan

    # Import software list module
    $softwareListModule = Join-Path $PSScriptRoot "utilities\Manage-SoftwareLists.ps1"
    if (Test-Path $softwareListModule) {
        . $softwareListModule
    }
    else {
        Write-Host "  [-] Software list module not found: $softwareListModule" -ForegroundColor Red
        return
    }

    # Load config for common publishers
    $configPath = Join-Path $PSScriptRoot "utilities\Config.psd1"
    $config = if (Test-Path $configPath) { Import-PowerShellDataFile $configPath } else { $null }

    # Default path for software lists
    $defaultListPath = ".\SoftwareLists"
    if (-not (Test-Path $defaultListPath)) {
        New-Item -ItemType Directory -Path $defaultListPath -Force | Out-Null
    }

    # Helper function to select a list
    function Select-SoftwareList {
        param([string]$Prompt = "Select list")
        $lists = Get-ChildItem -Path $defaultListPath -Filter "*.json" -ErrorAction SilentlyContinue
        if ($lists.Count -eq 0) {
            Write-Host "  No software lists found. Create one first." -ForegroundColor Yellow
            return $null
        }
        Write-Host "  Available lists:" -ForegroundColor Gray
        $i = 1
        foreach ($list in $lists) {
            Write-Host "    [$i] $($list.BaseName)" -ForegroundColor White
            $i++
        }
        $listChoice = Read-Host "  $Prompt"
        if (-not ($listChoice -match "^\d+$") -or [int]$listChoice -lt 1 -or [int]$listChoice -gt $lists.Count) {
            Write-Host "  [-] Invalid selection" -ForegroundColor Red
            return $null
        }
        return $lists[[int]$listChoice - 1].FullName
    }

    do {
        $slChoice = Show-SoftwareListMenu

        switch ($slChoice) {
            "1" {
                # Create new software list
                Write-Host "`n  --- Create New Software List ---" -ForegroundColor Cyan
                $listName = Read-Host "  Enter list name"
                if ([string]::IsNullOrWhiteSpace($listName)) {
                    Write-Host "  [-] Name is required" -ForegroundColor Red
                    continue
                }
                $listDesc = Read-Host "  Enter description (optional)"
                New-SoftwareList -Name $listName -Description $listDesc -OutputPath $defaultListPath
            }
            "2" {
                # View software lists
                Write-Host "`n  --- Software Lists ---" -ForegroundColor Cyan
                $lists = Get-ChildItem -Path $defaultListPath -Filter "*.json" -ErrorAction SilentlyContinue
                if ($lists.Count -eq 0) {
                    Write-Host "  No software lists found in $defaultListPath" -ForegroundColor Yellow
                    continue
                }

                Write-Host ""
                $i = 1
                foreach ($list in $lists) {
                    $summary = Get-SoftwareListSummary -ListPath $list.FullName
                    Write-Host "    [$i] $($summary.Name)" -ForegroundColor White
                    Write-Host "        Items: $($summary.TotalItems) | Approved: $($summary.ApprovedItems) | Publishers: $($summary.PublisherRules) | Hashes: $($summary.HashRules)" -ForegroundColor Gray
                    $i++
                }
                Write-Host ""

                $viewChoice = Read-Host "  Enter number to view details (or Enter to skip)"
                if ($viewChoice -match "^\d+$") {
                    $idx = [int]$viewChoice - 1
                    if ($idx -ge 0 -and $idx -lt $lists.Count) {
                        $selectedList = $lists[$idx].FullName
                        $listData = Get-SoftwareList -ListPath $selectedList
                        $items = @($listData.items)
                        Write-Host "`n  Items in $($lists[$idx].BaseName):" -ForegroundColor Yellow

                        if ($items.Count -eq 0) {
                            Write-Host "    (empty list)" -ForegroundColor DarkGray
                        }
                        else {
                            $itemNum = 1
                            foreach ($item in $items | Select-Object -First 25) {
                                $status = if ($item.approved) { "[+]" } else { "[-]" }
                                $typeIcon = switch ($item.ruleType) {
                                    "Publisher" { "PUB" }
                                    "Hash" { "HSH" }
                                    "Path" { "PTH" }
                                    default { "???" }
                                }
                                Write-Host "    $itemNum. $status [$typeIcon] $($item.name)" -ForegroundColor $(if ($item.approved) { "Green" } else { "Gray" })
                                if ($item.publisher) {
                                    Write-Host "            Publisher: $($item.publisher)" -ForegroundColor DarkGray
                                }
                                $itemNum++
                            }
                            if ($items.Count -gt 25) {
                                Write-Host "    ... and $($items.Count - 25) more items" -ForegroundColor DarkGray
                            }
                        }
                    }
                }
            }
            "3" {
                # Add software manually
                Write-Host "`n  --- Add Software Manually ---" -ForegroundColor Cyan
                $selectedListPath = Select-SoftwareList -Prompt "Select list to add to"
                if (-not $selectedListPath) { continue }

                Write-Host ""
                Write-Host "  Rule type:" -ForegroundColor Gray
                Write-Host "    [1] Publisher (signature-based) - Best for signed software" -ForegroundColor White
                Write-Host "    [2] Hash (file hash-based) - For unsigned or specific versions" -ForegroundColor White
                $ruleTypeChoice = Read-Host "  Select rule type"

                $name = Read-Host "  Software name"
                if ([string]::IsNullOrWhiteSpace($name)) {
                    Write-Host "  [-] Name is required" -ForegroundColor Red
                    continue
                }

                $category = Read-Host "  Category (default: Uncategorized)"
                if ([string]::IsNullOrWhiteSpace($category)) { $category = "Uncategorized" }

                if ($ruleTypeChoice -eq "1") {
                    $publisher = Read-Host "  Publisher name (e.g., ADOBE INC.)"
                    if ([string]::IsNullOrWhiteSpace($publisher)) {
                        Write-Host "  [-] Publisher is required" -ForegroundColor Red
                        continue
                    }
                    $product = Read-Host "  Product name (default: * for all)"
                    if ([string]::IsNullOrWhiteSpace($product)) { $product = "*" }
                    $binary = Read-Host "  Binary name (default: * for all)"
                    if ([string]::IsNullOrWhiteSpace($binary)) { $binary = "*" }

                    Add-SoftwareListItem -ListPath $selectedListPath -Name $name -Publisher $publisher `
                        -ProductName $product -BinaryName $binary -Category $category -RuleType "Publisher" -Approved $true
                }
                else {
                    $hash = Read-Host "  SHA256 hash (64 characters)"
                    if ([string]::IsNullOrWhiteSpace($hash) -or $hash.Length -ne 64) {
                        Write-Host "  [-] Valid SHA256 hash required (64 hex characters)" -ForegroundColor Red
                        continue
                    }
                    $fileName = Read-Host "  Original filename"
                    $fileSize = Read-Host "  File size in bytes (or Enter to skip)"
                    $fileSizeInt = if ($fileSize -match "^\d+$") { [int64]$fileSize } else { 0 }

                    Add-SoftwareListItem -ListPath $selectedListPath -Name $name -Hash $hash `
                        -HashSourceFile $fileName -HashSourceSize $fileSizeInt -Category $category -RuleType "Hash" -Approved $true
                }
            }
            "4" {
                # Quick-add from common publishers
                Write-Host "`n  --- Add Common Publisher ---" -ForegroundColor Cyan

                if (-not $config -or -not $config.CommonPublishers) {
                    Write-Host "  [-] Common publishers not configured in Config.psd1" -ForegroundColor Red
                    continue
                }

                $selectedListPath = Select-SoftwareList -Prompt "Select list to add to"
                if (-not $selectedListPath) { continue }

                Write-Host ""
                Write-Host "  Common Publishers:" -ForegroundColor Gray
                $pubs = $config.CommonPublishers
                $i = 1
                foreach ($pub in $pubs) {
                    Write-Host "    [$i] $($pub.Name) - $($pub.Publisher)" -ForegroundColor White
                    $i++
                }
                Write-Host ""
                Write-Host "  Enter numbers separated by commas (e.g., 1,3,5) or 'all'" -ForegroundColor DarkGray
                $pubChoice = Read-Host "  Select publishers"

                $selectedPubs = @()
                if ($pubChoice -eq "all") {
                    $selectedPubs = $pubs
                }
                else {
                    $indices = $pubChoice -split "," | ForEach-Object { $_.Trim() }
                    foreach ($idx in $indices) {
                        if ($idx -match "^\d+$" -and [int]$idx -ge 1 -and [int]$idx -le $pubs.Count) {
                            $selectedPubs += $pubs[[int]$idx - 1]
                        }
                    }
                }

                foreach ($pub in $selectedPubs) {
                    Add-SoftwareListItem -ListPath $selectedListPath -Name $pub.Name -Publisher $pub.Publisher `
                        -ProductName "*" -Category $pub.Category -RuleType "Publisher" -Approved $true -ErrorAction SilentlyContinue
                }
                Write-Host "  [+] Added $($selectedPubs.Count) publishers" -ForegroundColor Green
            }
            "5" {
                # Import from scan data or executable
                Write-Host "`n  --- Import Software ---" -ForegroundColor Cyan
                Write-Host "    [1] Import from scan data (browse folders)" -ForegroundColor White
                Write-Host "    [2] Import from executable file" -ForegroundColor White
                Write-Host "    [C] Cancel" -ForegroundColor Gray
                $importChoice = Read-Host "  Select import source"

                if ($importChoice -in @("C", "c")) { continue }

                # Get target list
                $lists = @(Get-ChildItem -Path $defaultListPath -Filter "*.json" -ErrorAction SilentlyContinue)
                $targetList = $null

                Write-Host ""
                if ($lists.Count -gt 0) {
                    Write-Host "  Import to existing list or create new?" -ForegroundColor Gray
                    $i = 1
                    foreach ($list in $lists) {
                        Write-Host "    [$i] $($list.BaseName)" -ForegroundColor White
                        $i++
                    }
                    Write-Host "    [N] Create new list" -ForegroundColor White
                    Write-Host "    [C] Cancel" -ForegroundColor Gray
                    $listChoice = Read-Host "  Select option"

                    if ($listChoice -in @("C", "c")) { continue }

                    if ($listChoice -match "^\d+$" -and [int]$listChoice -ge 1 -and [int]$listChoice -le $lists.Count) {
                        $targetList = $lists[[int]$listChoice - 1].FullName
                    }
                }

                if (-not $targetList) {
                    $newName = Read-Host "  Enter new list name"
                    if ([string]::IsNullOrWhiteSpace($newName)) {
                        Write-Host "  [-] List name is required" -ForegroundColor Red
                        continue
                    }
                    $targetList = Join-Path $defaultListPath "$newName.json"
                    New-SoftwareList -Name $newName -Description "Imported software" -OutputPath $defaultListPath | Out-Null
                }

                if ($importChoice -eq "1") {
                    # Browse scan folders
                    Write-Host ""
                    Write-Host "  Select scan folder(s) to import from:" -ForegroundColor Yellow
                    $scanFolders = Select-ScanFolder -Prompt "Select folder(s)" -AllowMultiple -AllowCancel

                    if (-not $scanFolders) { continue }

                    Write-Host ""
                    Write-Host "  Import options:" -ForegroundColor Gray
                    Write-Host "    [1] Signed software only (publisher rules)" -ForegroundColor White
                    Write-Host "    [2] Unsigned software only (hash rules)" -ForegroundColor White
                    Write-Host "    [3] All software" -ForegroundColor White
                    $filterChoice = Read-Host "  Select filter (default: 1)"

                    $autoApprove = Read-Host "  Auto-approve imported items? (y/N)"
                    $doAutoApprove = $autoApprove -in @("y", "Y")

                    # Import from each selected folder
                    $totalImported = 0
                    foreach ($folder in @($scanFolders)) {
                        Write-Host "  Importing from $([System.IO.Path]::GetFileName($folder))..." -ForegroundColor Cyan

                        $importParams = @{
                            ScanPath    = $folder
                            ListPath    = $targetList
                            Deduplicate = $true
                        }

                        switch ($filterChoice) {
                            "1" { $importParams.SignedOnly = $true }
                            "2" { $importParams.UnsignedOnly = $true }
                        }

                        if ($doAutoApprove) {
                            $importParams.AutoApprove = $true
                        }

                        try {
                            Import-ScanDataToSoftwareList @importParams -ErrorAction Stop
                            $totalImported++
                        }
                        catch {
                            Write-Host "  [-] Failed to import from $folder : $_" -ForegroundColor Red
                        }
                    }

                    if ($totalImported -gt 0) {
                        Write-Host "  [+] Import complete from $totalImported folder(s)" -ForegroundColor Green
                    }
                }
                else {
                    # Import from executable file
                    $exePath = Read-Host "  Enter executable file path"
                    if ([string]::IsNullOrWhiteSpace($exePath)) {
                        Write-Host "  [-] File path is required" -ForegroundColor Red
                        continue
                    }

                    if (Test-Path $exePath) {
                        # Validate it's a file not directory
                        if ((Get-Item $exePath).PSIsContainer) {
                            Write-Host "  [-] Please specify a file, not a directory" -ForegroundColor Red
                            continue
                        }

                        $category = Read-Host "  Category (default: Imported)"
                        if ([string]::IsNullOrWhiteSpace($category)) { $category = "Imported" }

                        try {
                            Import-ExecutableToSoftwareList -FilePath $exePath -ListPath $targetList -Category $category -ErrorAction Stop
                        }
                        catch {
                            Write-Host "  [-] Failed to import executable: $_" -ForegroundColor Red
                        }
                    }
                    else {
                        Write-Host "  [-] File not found: $exePath" -ForegroundColor Red
                    }
                }
            }
            "6" {
                # Toggle approve/unapprove
                Write-Host "`n  --- Toggle Item Approval ---" -ForegroundColor Cyan
                $selectedListPath = Select-SoftwareList -Prompt "Select list"
                if (-not $selectedListPath) { continue }

                $listData = Get-SoftwareList -ListPath $selectedListPath
                $items = @($listData.items)
                if ($items.Count -eq 0) {
                    Write-Host "  List is empty" -ForegroundColor Yellow
                    continue
                }

                Write-Host ""
                $i = 1
                foreach ($item in $items | Select-Object -First 30) {
                    $status = if ($item.approved) { "[+]" } else { "[-]" }
                    Write-Host "    $i. $status $($item.name)" -ForegroundColor $(if ($item.approved) { "Green" } else { "Gray" })
                    $i++
                }
                if ($items.Count -gt 30) {
                    Write-Host "    ... and $($items.Count - 30) more items" -ForegroundColor DarkGray
                }

                Write-Host ""
                Write-Host "  Enter item numbers to toggle (e.g., 1,3,5) or 'all'" -ForegroundColor DarkGray
                $toggleChoice = Read-Host "  Select items"

                $toToggle = @()
                if ($toggleChoice -eq "all") {
                    $toToggle = $items
                }
                else {
                    $indices = $toggleChoice -split "," | ForEach-Object { $_.Trim() }
                    foreach ($idx in $indices) {
                        if ($idx -match "^\d+$" -and [int]$idx -ge 1 -and [int]$idx -le $items.Count) {
                            $toToggle += $items[[int]$idx - 1]
                        }
                    }
                }

                foreach ($item in $toToggle) {
                    $newStatus = -not $item.approved
                    Update-SoftwareListItem -ListPath $selectedListPath -Id $item.id -Properties @{ approved = $newStatus } | Out-Null
                }
                Write-Host "  [+] Toggled $($toToggle.Count) items" -ForegroundColor Green
            }
            "7" {
                # Delete items
                Write-Host "`n  --- Delete Items ---" -ForegroundColor Cyan
                $selectedListPath = Select-SoftwareList -Prompt "Select list"
                if (-not $selectedListPath) { continue }

                $listData = Get-SoftwareList -ListPath $selectedListPath
                $items = @($listData.items)
                if ($items.Count -eq 0) {
                    Write-Host "  List is empty" -ForegroundColor Yellow
                    continue
                }

                Write-Host ""
                $i = 1
                foreach ($item in $items | Select-Object -First 30) {
                    Write-Host "    $i. $($item.name) [$($item.ruleType)]" -ForegroundColor White
                    $i++
                }
                if ($items.Count -gt 30) {
                    Write-Host "    ... and $($items.Count - 30) more items" -ForegroundColor DarkGray
                }

                Write-Host ""
                Write-Host "  Enter item numbers to delete (e.g., 1,3,5)" -ForegroundColor DarkGray
                $deleteChoice = Read-Host "  Select items"

                $toDelete = @()
                $indices = $deleteChoice -split "," | ForEach-Object { $_.Trim() }
                foreach ($idx in $indices) {
                    if ($idx -match "^\d+$" -and [int]$idx -ge 1 -and [int]$idx -le $items.Count) {
                        $toDelete += $items[[int]$idx - 1]
                    }
                }

                if ($toDelete.Count -gt 0) {
                    $confirm = Read-Host "  Delete $($toDelete.Count) items? (y/N)"
                    if ($confirm -eq "y" -or $confirm -eq "Y") {
                        foreach ($item in $toDelete) {
                            Remove-SoftwareListItem -ListPath $selectedListPath -Id $item.id
                        }
                    }
                }
            }
            "8" {
                # Search across all lists
                Write-Host "`n  --- Search Software Lists ---" -ForegroundColor Cyan
                $searchTerm = Read-Host "  Enter search term (name or publisher, wildcards supported)"
                if ([string]::IsNullOrWhiteSpace($searchTerm)) { continue }

                $lists = Get-ChildItem -Path $defaultListPath -Filter "*.json" -ErrorAction SilentlyContinue
                $allResults = @()

                foreach ($list in $lists) {
                    $items = Find-SoftwareListItem -ListPath $list.FullName -Name "*$searchTerm*"
                    $items += Find-SoftwareListItem -ListPath $list.FullName -Publisher "*$searchTerm*"
                    foreach ($item in $items) {
                        $allResults += [PSCustomObject]@{
                            List      = $list.BaseName
                            Name      = $item.name
                            Publisher = $item.publisher
                            Type      = $item.ruleType
                            Approved  = $item.approved
                        }
                    }
                }

                $allResults = $allResults | Select-Object -Unique List, Name, Publisher, Type, Approved

                if ($allResults.Count -eq 0) {
                    Write-Host "  No results found for '$searchTerm'" -ForegroundColor Yellow
                }
                else {
                    Write-Host ""
                    Write-Host "  Found $($allResults.Count) results:" -ForegroundColor Green
                    foreach ($result in $allResults | Select-Object -First 20) {
                        $status = if ($result.Approved) { "[+]" } else { "[-]" }
                        Write-Host "    $status [$($result.List)] $($result.Name)" -ForegroundColor White
                        if ($result.Publisher) {
                            Write-Host "        Publisher: $($result.Publisher)" -ForegroundColor DarkGray
                        }
                    }
                    if ($allResults.Count -gt 20) {
                        Write-Host "    ... and $($allResults.Count - 20) more results" -ForegroundColor DarkGray
                    }
                }
            }
            "9" {
                # Export to CSV
                Write-Host "`n  --- Export to CSV ---" -ForegroundColor Cyan
                $selectedListPath = Select-SoftwareList -Prompt "Select list to export"
                if (-not $selectedListPath) { continue }

                $listName = [System.IO.Path]::GetFileNameWithoutExtension($selectedListPath)
                $csvPath = Join-Path $defaultListPath "$listName.csv"
                Export-SoftwareListToCsv -ListPath $selectedListPath -OutputPath $csvPath
            }
            { $_ -in @("G", "g") } {
                # Generate policy from software list
                Write-Host "`n  --- Generate Policy from Software List ---" -ForegroundColor Cyan
                $lists = Get-ChildItem -Path $defaultListPath -Filter "*.json" -ErrorAction SilentlyContinue
                if ($lists.Count -eq 0) {
                    Write-Host "  No software lists found. Create one first." -ForegroundColor Yellow
                    continue
                }

                Write-Host "  Select software list:" -ForegroundColor Gray
                $i = 1
                foreach ($list in $lists) {
                    $summary = Get-SoftwareListSummary -ListPath $list.FullName
                    Write-Host "    [$i] $($list.BaseName) ($($summary.ApprovedItems) approved items)" -ForegroundColor White
                    $i++
                }
                $listChoice = Read-Host "  Select list"
                if (-not ($listChoice -match "^\d+$") -or [int]$listChoice -lt 1 -or [int]$listChoice -gt $lists.Count) {
                    continue
                }
                $selectedList = $lists[[int]$listChoice - 1].FullName

                Write-Host ""
                Write-Host "  Also combine with scan data? (y/N)" -ForegroundColor Gray
                $combineScan = Read-Host "  Choice"
                $scanPath = $null
                if ($combineScan -eq "y" -or $combineScan -eq "Y") {
                    $scanPath = Read-Host "  Enter scan data path (default: .\Scans)"
                    if ([string]::IsNullOrWhiteSpace($scanPath)) { $scanPath = ".\Scans" }
                    if (-not (Test-Path $scanPath)) {
                        Write-Host "  [-] Scan path not found, continuing without scan data" -ForegroundColor Yellow
                        $scanPath = $null
                    }
                }

                Write-Host ""
                Write-Host "  Generating policy..." -ForegroundColor Cyan

                $policyScript = Join-Path $PSScriptRoot "New-AppLockerPolicyFromGuide.ps1"
                $policyParams = @{
                    Simplified       = $true
                    SoftwareListPath = $selectedList
                }
                if ($scanPath) {
                    $policyParams.ScanPath = $scanPath
                }
                & $policyScript @policyParams

                Write-Host ""
                Write-Host "  [+] Policy generation complete!" -ForegroundColor Green
            }
            "B" { }
            "b" { }
            default {
                if ($slChoice -notin @("B", "b")) {
                    Write-Host "  [-] Invalid choice" -ForegroundColor Red
                }
            }
        }

        if ($slChoice -notin @("B", "b")) {
            Write-Host ""
            Read-Host "  Press Enter to continue"
        }

    } while ($slChoice -notin @("B", "b"))
}

#endregion

#region Main Execution

# Show banner
Show-Banner

# Handle direct mode execution
if ($Mode -ne "Interactive") {
    switch ($Mode) {
        "Scan" {
            $scanParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($ComputerList)) {
                $scanParams.ComputerListPath = $ComputerList
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $scanParams.OutputPath = $OutputPath
            }
            if ($null -ne $Credential) {
                $scanParams.Credential = $Credential
            }
            Invoke-ScanWorkflow @scanParams
        }
        "Generate" {
            $genParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($ScanPath)) {
                $genParams.ScanPath = $ScanPath
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $genParams.OutputPath = $OutputPath
            }
            if ($Simplified.IsPresent) {
                $genParams.Simplified = $true
            }
            elseif (-not [string]::IsNullOrWhiteSpace($TargetType)) {
                $genParams.TargetType = $TargetType
                if (-not [string]::IsNullOrWhiteSpace($DomainName)) {
                    $genParams.DomainName = $DomainName
                }
                if ($Phase -ge 1 -and $Phase -le 4) {
                    $genParams.Phase = $Phase
                }
            }
            Invoke-GenerateWorkflow @genParams
        }
        "Merge" {
            $mergeParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($ScanPath)) {
                $mergeParams.InputPath = $ScanPath
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $mergeParams.OutputPath = $OutputPath
            }
            Invoke-MergeWorkflow @mergeParams
        }
        "Validate" {
            $validateParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) {
                $validateParams.PolicyPath = $PolicyPath
            }
            Invoke-ValidateWorkflow @validateParams
        }
        "Full" {
            $fullParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($ComputerList)) {
                $fullParams.ComputerList = $ComputerList
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $fullParams.OutputPath = $OutputPath
            }
            if ($null -ne $Credential) {
                $fullParams.Credential = $Credential
            }
            if ($Simplified.IsPresent) {
                $fullParams.Simplified = $true
            }
            elseif (-not [string]::IsNullOrWhiteSpace($TargetType)) {
                $fullParams.TargetType = $TargetType
                if (-not [string]::IsNullOrWhiteSpace($DomainName)) {
                    $fullParams.DomainName = $DomainName
                }
                if ($Phase -ge 1 -and $Phase -le 4) {
                    $fullParams.Phase = $Phase
                }
            }
            Invoke-FullWorkflow @fullParams
        }
        "Compare" {
            $compareParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($ReferencePath)) {
                $compareParams.RefPath = $ReferencePath
            }
            if (-not [string]::IsNullOrWhiteSpace($ComparePath)) {
                $compareParams.CompPath = $ComparePath
            }
            if (-not [string]::IsNullOrWhiteSpace($CompareBy)) {
                $compareParams.Method = $CompareBy
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $compareParams.OutPath = $OutputPath
            }
            Invoke-CompareWorkflow @compareParams
        }
        "ADSetup" {
            $adParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($DomainName)) {
                $adParams.Domain = $DomainName
            }
            if (-not [string]::IsNullOrWhiteSpace($ParentOU)) {
                $adParams.Parent = $ParentOU
            }
            if (-not [string]::IsNullOrWhiteSpace($GroupPrefix)) {
                $adParams.Prefix = $GroupPrefix
            }
            if ($Force) {
                $adParams.NoConfirm = $true
            }
            Invoke-ADSetupWorkflow @adParams
        }
        "ADExport" {
            $adParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($SearchBase)) {
                $adParams.Search = $SearchBase
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $adParams.OutPath = $OutputPath
            }
            if ($IncludeDisabled) {
                $adParams.Disabled = $true
            }
            Invoke-ADExportWorkflow @adParams
        }
        "ADImport" {
            $adParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
                $adParams.InPath = $InputPath
            }
            Invoke-ADImportWorkflow @adParams
        }
        "Diagnostic" {
            $diagParams = @{}
            if (-not [string]::IsNullOrWhiteSpace($DiagnosticType)) {
                $diagParams.Type = $DiagnosticType
            }
            if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
                $diagParams.Computer = $ComputerName
            }
            if (-not [string]::IsNullOrWhiteSpace($ComputerList)) {
                $diagParams.ComputerList = $ComputerList
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $diagParams.OutPath = $OutputPath
            }
            if ($null -ne $Credential) {
                $diagParams.Cred = $Credential
            }
            Invoke-DiagnosticWorkflow @diagParams
        }
    }
    exit
}

# Interactive mode
do {
    $choice = Show-Menu

    switch ($choice) {
        "1" { Invoke-ScanWorkflow }
        "2" { Invoke-GenerateWorkflow }
        "3" { Invoke-MergeWorkflow }
        "4" { Invoke-ValidateWorkflow }
        "5" { Invoke-FullWorkflow }
        "6" { Invoke-CompareWorkflow }
        "7" { Invoke-ADSetupWorkflow }
        "8" { Invoke-ADExportWorkflow }
        "9" { Invoke-ADImportWorkflow }
        "W" {
            $winrmChoice = Show-WinRMMenu
            switch ($winrmChoice) {
                "1" { Invoke-WinRMWorkflow }
                "2" { Invoke-RemoveWinRMWorkflow }
                "B" { }
                "b" { }
                default { Write-Host "  Invalid option" -ForegroundColor Red }
            }
        }
        "w" {
            $winrmChoice = Show-WinRMMenu
            switch ($winrmChoice) {
                "1" { Invoke-WinRMWorkflow }
                "2" { Invoke-RemoveWinRMWorkflow }
                "B" { }
                "b" { }
                default { Write-Host "  Invalid option" -ForegroundColor Red }
            }
        }
        "S" { Invoke-SoftwareListWorkflow }
        "s" { Invoke-SoftwareListWorkflow }
        "D" { Invoke-DiagnosticWorkflow }
        "d" { Invoke-DiagnosticWorkflow }
        "Q" {
            Write-Host "`n  Goodbye!" -ForegroundColor Cyan
            exit
        }
        "q" {
            Write-Host "`n  Goodbye!" -ForegroundColor Cyan
            exit
        }
        default {
            Write-Host "  Invalid option, please try again." -ForegroundColor Red
        }
    }

    if ($choice -in @("1", "2", "3", "4", "5", "6", "7", "8", "9", "W", "w", "S", "s", "D", "d")) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
        Clear-Host
        Show-Banner
    }
} while ($true)

#endregion
