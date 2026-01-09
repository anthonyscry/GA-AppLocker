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
    [ValidateSet("Scan", "Generate", "Merge", "Validate", "Full", "Interactive")]
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
    [PSCredential]$Credential
)

#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# Import utilities
$modulePath = Join-Path $scriptRoot "utilities\Common.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}
else {
    Write-Warning "Utilities module not found. Some features may not work correctly."
}

# Dot-source validators
$validatorsPath = Join-Path $scriptRoot "utilities\Validators.ps1"
if (Test-Path $validatorsPath) {
    . $validatorsPath
}

#region Banner and Menu

function Show-Banner {
    $banner = @"

  ╔═══════════════════════════════════════════════════════════════════════════╗
  ║                                                                           ║
  ║     ██████╗  █████╗        █████╗ ██████╗ ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗███████╗██████╗
  ║    ██╔════╝ ██╔══██╗      ██╔══██╗██╔══██╗██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
  ║    ██║  ███╗███████║█████╗███████║██████╔╝██████╔╝██║     ██║   ██║██║     █████╔╝ █████╗  ██████╔╝
  ║    ██║   ██║██╔══██║╚════╝██╔══██║██╔═══╝ ██╔═══╝ ██║     ██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗
  ║    ╚██████╔╝██║  ██║      ██║  ██║██║     ██║     ███████╗╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║
  ║     ╚═════╝ ╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝     ╚═╝     ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
  ║                                                                           ║
  ║                     AppLocker Policy Generation Toolkit                   ║
  ╚═══════════════════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Show-Menu {
    Write-Host "  Select an option:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    [1] Scan       - Collect data from remote computers" -ForegroundColor White
    Write-Host "    [2] Generate   - Create AppLocker policy from scan data" -ForegroundColor White
    Write-Host "    [3] Merge      - Combine multiple policy files" -ForegroundColor White
    Write-Host "    [4] Validate   - Check a policy file for issues" -ForegroundColor White
    Write-Host "    [5] Full       - Complete workflow (Scan + Generate)" -ForegroundColor White
    Write-Host ""
    Write-Host "    [6] WinRM      - Deploy WinRM GPO for domain computers" -ForegroundColor White
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

function Invoke-ScanWorkflow {
    param(
        [string]$ComputerListPath,
        [string]$OutputPath,
        [PSCredential]$Credential
    )

    Write-Host "`n=== Remote Scan Workflow ===" -ForegroundColor Cyan

    # Get computer list - validate input
    if ([string]::IsNullOrWhiteSpace($ComputerListPath)) {
        $ComputerListPath = Read-Host "  Enter path to computer list file"
    }

    if ([string]::IsNullOrWhiteSpace($ComputerListPath)) {
        Write-Host "  [-] Computer list path is required" -ForegroundColor Red
        return $null
    }

    if (-not (Test-Path $ComputerListPath)) {
        Write-Host "  [-] Computer list not found: $ComputerListPath" -ForegroundColor Red
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

    # Get policy path - validate
    if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
        $PolicyPath = Read-Host "  Enter path to policy file"
    }

    if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
        Write-Host "  [-] Policy path is required" -ForegroundColor Red
        return $null
    }

    if (-not (Test-Path $PolicyPath)) {
        Write-Host "  [-] Policy file not found: $PolicyPath" -ForegroundColor Red
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
        "6" { Invoke-WinRMWorkflow }
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

    if ($choice -in @("1", "2", "3", "4", "5", "6")) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
        Clear-Host
        Show-Banner
    }
} while ($true)

#endregion
