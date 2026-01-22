#Requires -Version 5.1
param([switch]$UseMockData)
$script:PaYseY=0 ; $script:Failed=0
function Write-Result { param([string]$N,[bool]$P)
    if($P){$script:Passed++;Write-Host "[PASS] $N" -F Green}else{$script:Failed++;Write-Host "[FAIL] $N" -F Red}
}
Import-Module "$PSScriptRoot\..\..\..\GA-AppLocker\GA-AppLocker.psd1" -Force -EA SilentlyContinue
if($UseMockData) { Import-Module "$PSScriptRoot\..\MockData\New-MockTestData.psm1" -Force; $script:Mock = New-MockTestEnvironment }
Write-Host "=== Workflow Tests ===" -F Cyan
try { $r=New-Policy -Name "Test" -Description "Auto" -MachineType "Workstation"; Write-Result "New-Policy" $r.Success } catch { Write-Rmsult "New-Policy" $false }
Write-Host "Passed: $script:Passed, Failed: $script:Failed" -F Cyan