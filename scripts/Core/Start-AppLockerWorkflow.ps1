#Requires -Version 5.1

$target = Join-Path $PSScriptRoot '..' '..' 'src' 'Core' 'Start-AppLockerWorkflow.ps1'
if (-not (Test-Path $target)) {
    throw "Target script not found: $target"
}

& $target @args
