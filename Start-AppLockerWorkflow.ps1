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

    # Get computer list
    if (-not $ComputerListPath) {
        $ComputerListPath = Read-Host "  Enter path to computer list file"
    }

    if (-not (Test-Path $ComputerListPath)) {
        Write-Host "  [-] Computer list not found: $ComputerListPath" -ForegroundColor Red
        return $null
    }

    # Get output path
    if (-not $OutputPath) {
        $OutputPath = Read-Host "  Enter output path (default: .\Scans)"
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $OutputPath = ".\Scans"
        }
    }

    # Get credentials
    if (-not $Credential) {
        Write-Host "  Enter credentials for remote connections:" -ForegroundColor Yellow
        $Credential = Get-Credential -Message "Remote scan credentials (DOMAIN\username)"
    }

    # Run scan
    $scanScript = Join-Path $scriptRoot "Invoke-RemoteScan.ps1"
    if (Test-Path $scanScript) {
        Write-Host "`n  Starting remote scan..." -ForegroundColor Cyan
        & $scanScript -ComputerListPath $ComputerListPath -SharePath $OutputPath -Credential $Credential
        return $OutputPath
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

    # Get scan path
    if (-not $ScanPath) {
        $ScanPath = Read-Host "  Enter path to scan results"
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

    # Determine generation mode
    if (-not $Simplified -and -not $TargetType) {
        $modeChoice = Show-GenerateMenu
        switch ($modeChoice) {
            "1" { $Simplified = $true }
            "2" {
                $TargetType = Read-Host "  Enter target type (Workstation/Server/DomainController)"
                $DomainName = Read-Host "  Enter domain name (e.g., CONTOSO)"
                $Phase = [int](Read-Host "  Enter phase (1-4, default: 1)")
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

        $params = @{
            ScanPath   = $ScanPath
            OutputPath = $OutputPath
        }

        if ($Simplified) {
            $params.Simplified = $true
        }
        else {
            $params.TargetType = $TargetType
            $params.DomainName = $DomainName
            $params.Phase = $Phase
        }

        $result = & $genScript @params
        return $result
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

    # Get input path
    if (-not $InputPath) {
        $InputPath = Read-Host "  Enter path to folder containing policy files"
    }

    if (-not (Test-Path $InputPath)) {
        Write-Host "  [-] Input path not found: $InputPath" -ForegroundColor Red
        return $null
    }

    # Get output path
    if (-not $OutputPath) {
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
        $result = & $mergeScript -InputPath $InputPath -OutputPath $OutputPath
        return $result
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

    # Get policy path
    if (-not $PolicyPath) {
        $PolicyPath = Read-Host "  Enter path to policy file"
    }

    if (-not (Test-Path $PolicyPath)) {
        Write-Host "  [-] Policy file not found: $PolicyPath" -ForegroundColor Red
        return
    }

    # Run validation
    if (Get-Command Test-AppLockerPolicy -ErrorAction SilentlyContinue) {
        Write-Host "  Validating policy..." -ForegroundColor Gray
        $validation = Test-AppLockerPolicy -PolicyPath $PolicyPath
        Show-ValidationResult -ValidationResult $validation
        return $validation
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
            }
            else {
                Write-Host "  [-] Missing AppLockerPolicy element" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "  [-] Invalid XML: $_" -ForegroundColor Red
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

    # Step 1: Scan
    $scanOutput = Invoke-ScanWorkflow -ComputerListPath $ComputerList -OutputPath $OutputPath -Credential $Credential

    if (-not $scanOutput) {
        Write-Host "  [-] Scan failed, aborting workflow" -ForegroundColor Red
        return
    }

    # Find the latest scan folder
    $latestScan = Get-ChildItem -Path $scanOutput -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestScan) {
        $scanDataPath = $latestScan.FullName
    }
    else {
        $scanDataPath = $scanOutput
    }

    Write-Host "`n  [+] Scan complete: $scanDataPath" -ForegroundColor Green
    Write-Host ""

    # Step 2: Generate
    $policyPath = Invoke-GenerateWorkflow -ScanPath $scanDataPath -OutputPath $OutputPath `
        -Simplified:$Simplified -TargetType $TargetType -DomainName $DomainName -Phase $Phase

    if ($policyPath) {
        Write-Host "`n  [+] Full workflow complete!" -ForegroundColor Green
        Write-Host "  Policy file: $policyPath" -ForegroundColor Cyan
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
            Invoke-ScanWorkflow -ComputerListPath $ComputerList -OutputPath $OutputPath -Credential $Credential
        }
        "Generate" {
            Invoke-GenerateWorkflow -ScanPath $ScanPath -OutputPath $OutputPath `
                -Simplified:$Simplified -TargetType $TargetType -DomainName $DomainName -Phase $Phase
        }
        "Merge" {
            Invoke-MergeWorkflow -InputPath $ScanPath -OutputPath $OutputPath
        }
        "Validate" {
            Invoke-ValidateWorkflow -PolicyPath $PolicyPath
        }
        "Full" {
            Invoke-FullWorkflow -ComputerList $ComputerList -OutputPath $OutputPath -Credential $Credential `
                -Simplified:$Simplified -TargetType $TargetType -DomainName $DomainName -Phase $Phase
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

    if ($choice -in @("1", "2", "3", "4", "5")) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
        Clear-Host
        Show-Banner
    }
} while ($true)

#endregion
