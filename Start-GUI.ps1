<#
.SYNOPSIS
    Launches the GA-AppLocker WPF GUI Application
.DESCRIPTION
    This is a simple launcher script that starts the graphical user interface
    for the GA-AppLocker toolkit.
.EXAMPLE
    .\Start-GUI.ps1
.NOTES
    Requires: PowerShell 5.1+, Windows Presentation Foundation
#>

#Requires -Version 5.1

$guiScript = Join-Path $PSScriptRoot "GUI\Start-AppLockerGUI.ps1"

if (Test-Path $guiScript) {
    & $guiScript
} else {
    Write-Error "GUI script not found at: $guiScript"
    exit 1
}
