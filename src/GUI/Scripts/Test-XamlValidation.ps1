<#
.SYNOPSIS
    Validates all XAML content in the GA-AppLocker GUI project
.DESCRIPTION
    Scans PowerShell files for embedded XAML and standalone XAML files,
    then validates they can be parsed correctly. Reports any errors found.
.EXAMPLE
    .\Test-XamlValidation.ps1
.EXAMPLE
    .\Test-XamlValidation.ps1 -Verbose
.OUTPUTS
    Returns $true if all XAML is valid, $false if any errors found
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Join-Path $PSScriptRoot "..")
)

# Load WPF assemblies
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
} catch {
    Write-Error "Failed to load WPF assemblies. This script requires Windows."
    return $false
}

$results = @{
    Passed = @()
    Failed = @()
}

Write-Host "`n=== XAML Validation ===" -ForegroundColor Cyan
Write-Host "Scanning: $Path`n" -ForegroundColor Gray

# Find standalone XAML files
$xamlFiles = Get-ChildItem -Path $Path -Filter "*.xaml" -Recurse -ErrorAction SilentlyContinue

foreach ($file in $xamlFiles) {
    Write-Verbose "Checking standalone XAML: $($file.Name)"
    try {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($content))
        $null = [System.Windows.Markup.XamlReader]::Load($reader)
        $reader.Dispose()

        Write-Host "[PASS] $($file.Name)" -ForegroundColor Green
        $results.Passed += $file.FullName
    }
    catch {
        Write-Host "[FAIL] $($file.Name)" -ForegroundColor Red
        Write-Host "       Error: $($_.Exception.Message)" -ForegroundColor Yellow
        $results.Failed += @{
            File = $file.FullName
            Error = $_.Exception.Message
        }
    }
}

# Find PowerShell files with embedded XAML
$psFiles = Get-ChildItem -Path $Path -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue

foreach ($file in $psFiles) {
    Write-Verbose "Scanning for embedded XAML: $($file.Name)"
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    # Look for XAML here-strings: [xml]$varname = @"....."@
    $pattern = '(?s)\[xml\]\s*\$(\w+)\s*=\s*@"(.+?)"@'
    $matches = [regex]::Matches($content, $pattern)

    foreach ($match in $matches) {
        $varName = $match.Groups[1].Value
        $xamlContent = $match.Groups[2].Value

        Write-Verbose "Found embedded XAML in variable: `$$varName"

        try {
            # First validate as XML
            $testXml = [xml]$xamlContent

            # Check for required WPF namespace
            $root = $testXml.DocumentElement
            if ($root.NamespaceURI -ne 'http://schemas.microsoft.com/winfx/2006/xaml/presentation') {
                throw "Missing or incorrect WPF namespace"
            }

            # Count named elements
            $namedElements = $testXml.SelectNodes("//*[@*[local-name()='Name']]")
            $elementCount = if ($namedElements) { $namedElements.Count } else { 0 }

            Write-Host "[PASS] $($file.Name) (`$$varName) - $elementCount named elements" -ForegroundColor Green
            $results.Passed += "$($file.FullName):`$$varName"
        }
        catch {
            Write-Host "[FAIL] $($file.Name) (`$$varName)" -ForegroundColor Red
            Write-Host "       Error: $($_.Exception.Message)" -ForegroundColor Yellow

            # Try to identify the problematic line
            $lines = $xamlContent -split "`n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $_.Exception.Message -or
                    ($_.Exception.InnerException -and $lines[$i] -match $_.Exception.InnerException.Message)) {
                    Write-Host "       Near line $($i + 1): $($lines[$i].Trim())" -ForegroundColor Gray
                    break
                }
            }

            $results.Failed += @{
                File = "$($file.FullName):`$$varName"
                Error = $_.Exception.Message
            }
        }
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $($results.Passed.Count)" -ForegroundColor Green
Write-Host "Failed: $($results.Failed.Count)" -ForegroundColor $(if ($results.Failed.Count -gt 0) { 'Red' } else { 'Green' })

if ($results.Failed.Count -gt 0) {
    Write-Host "`nFailed items:" -ForegroundColor Red
    foreach ($fail in $results.Failed) {
        Write-Host "  - $($fail.File)" -ForegroundColor Yellow
        Write-Host "    $($fail.Error)" -ForegroundColor Gray
    }
    return $false
}

return $true
