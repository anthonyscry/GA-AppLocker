$file = 'C:\Projects\GA-AppLocker2\GA-AppLocker\GUI\MainWindow.xaml.ps1'
$lines = Get-Content $file
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^function ') {
        $lineNum = ($i + 1).ToString().PadLeft(4, '0')
        Write-Output "$lineNum : $($lines[$i].Trim())"
    }
}
