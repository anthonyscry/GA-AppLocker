#Requires -Version 5.1

$target = Join-Path $PSScriptRoot '..' '..' 'src' 'Core' 'Invoke-RemoteScan.ps1'
if (-not (Test-Path $target)) {
    throw "Target script not found: $target"
}

& $target @args
