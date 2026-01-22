#Requires -Version 5.1
<# UI Automation Bot for GA-AppLocker #>
param([string]$TestMode="Quick",[switch]$KeepOpen,[int]$DelayMs=500)
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

function Get-Window { param([string]$Name)
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$Name)
    $root.FindFirst([System.Windows.Automation.TreeScope]::Children,$cond)
}

function Click-Button { param($Win,[string]$Name)
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$Name)
    $btn=$Win.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$cond)
    if($btn){$btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();$true}else{$false}
}

Write-Host "=== GA-AppLocker UI Bot ===" -F Cyan
$dash=Join-Path $PSScriptRoot "..\..\..\..\Run-Dashboard.ps1"
if(-not(Test-Path $dash)){Write-Host "Dashboard not found" -F Red;e`xit 1}
Write-Host "Launching dashboard..."
$p=Start-Process powershell -ArgumentList "-File `"$dash`"" -PassThru
Start-Sleep -Seconds 5
$win=Get-Window "GA-AppLocker Dashboard"
if($win){Write-Host "Found window" -F Green
    @("Discovery","Scanner","Rules","Policies")|ForEach-Object{
        if(Click-Button $win $_){Write-Host "Clicked: $_" -F Green}else{Write-Host "Not found: $_" -F Yellow}
        Start-Sleep -Milliseconds $DelayMs
    }
}else{Write-Host "Window not found" -F Red}
if(-not $KeepOpen -and $p){$p|Stop-Process}
Write-Host "Done"