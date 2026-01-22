# Script to extract panels from MainWindow.xaml.ps1
param(
    [string]$SourceFile = 'C:\Projects\GA-AppLocker2\GA-AppLocker\GUI\MainWindow.xaml.ps1',
    [string]$OutputDir = 'C:\Projects\GA-AppLocker2\GA-AppLocker\GUI\Panels'
)

$content = Get-Content $SourceFile -Raw
$lines = Get-Content $SourceFile

# Panel definitions: Name, StartLine (0-based), EndLine (0-based)
$panels = @(
    @{ Name = 'Scanner'; Start = 1152; End = 2046 },
    @{ Name = 'Rules'; Start = 2050; End = 2982 },
    @{ Name = 'Policy'; Start = 3022; End = 3634 },
    @{ Name = 'Deploy'; Start = 3635; End = 4169 },
    @{ Name = 'Setup'; Start = 4170; End = 4448 }
)

foreach ($panel in $panels) {
    $panelLines = $lines[($panel.Start)..($panel.End)]
    $header = "#region $($panel.Name) Panel Functions`n# $($panel.Name).ps1 - $($panel.Name) panel handlers`n"
    $footer = "`n#endregion"
    
    $outputContent = $header + ($panelLines -join "`n") + $footer
    $outputPath = Join-Path $OutputDir "$($panel.Name).ps1"
    
    Set-Content -Path $outputPath -Value $outputContent -Encoding UTF8
    Write-Host "Extracted $($panel.Name).ps1 ($($panelLines.Count) lines)"
}

Write-Host "`nDone! Panels extracted to $OutputDir"
