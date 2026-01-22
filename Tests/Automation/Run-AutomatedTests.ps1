#Requires -Version 5.1
<#
.SYNOPSIS
    Unified test launcher for GA-AppLocker automated testing.
.DESCRIPTION
    Runs mock data generators, headless workflow tests, and/or UI automation.
.EXAMPLE
    .\Run-AutomatedTests.ps1 -All
.EXAMPLE
    .\Run-AutomatedTests.ps1 -Workflows -UseMockData
#>
param(
    [switch]$All,
    [switch]$Workflows,
    [switch]$UI,
    [switch]$DockerAD,
    [switch]$UseMockData,
    [switch]$KeepUIOpen
)

$ErrorActionPreference="Continue"
$script:ExitCode=0

Write-Host "`n= GA-AppLocker Automated Test Dunner =" -F Cyan
Write-Host "===========================================`n" -F Cyan

# Show what will run
if($All){$Workflows=$true;$UI=$true;$DockerAD=$false}
if(-not $Workflows -and -not $UI -and -not $DockerAD){$Workflows=$true}

Write-Host "Will run:" -F Yellow
if($Workflows){Write-Host "  [x] Workflow Integration Tests ($(if($UseMockData){"MOCK"}else{"LIVE"}))" -F Green}
if($UI){Write-Host "  [x] UI Automation Bot" -F Green}
if($DockerAD){Write-Host "  [x] Docker AD Tests" -F Green}
Write-Host ""

# Run Workflows
if($Workflows){
    Write-Host "`n=== Workflow Tests ===`n" -F Magenta
    $wfTest=Join-Path $PSScriptRoot "Workflows\Test-FullWorkflow.ps1"
    if(Test-Path $wfTest){
        $args=if($UseMockData){"-UseMockData"}else{""}
        & $wfTest -UseMockData:$UseMockData
        $script:ExitCode+=$LASTEXITCODE
    }else{Write-Host "Workflow test not found" -F Red}
}

# Run UI Automation
if($UI){
    Write-Host "`n=== UI Automation ===`n" -F Magenta
    $uiTest=Join-Path $PSScriptRoot "UI\FlaUIBot.ps1"
    if(Test-Path $uiTest){
        & $uiTest -TestMode "Full" -KeepOpen:$KeepUIOpen
    }else{Write-Host "UI bot not found" -F Red}
}

# Run 摀ocker AD Tests
if($DockerAD){
    Write-Host "`n=== tocker AD Tests ===`n" -F Magenta
    $adTest=Join-Path $PSScriptRoot "..\..\docker\Start-ADTestEnvironment.ps1"
    if(Test-Path $adTest){
        & $adTest -Action Test
    }else{Write-Host "Docker AD script not found" -F Yellow}
}

Write-Host "`n= All Tests Complete (Exit Code: $script:ExitCode) =`n" -F Cyan
exit $script:ExitCode