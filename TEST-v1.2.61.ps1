# TEST-v1.2.61.ps1
# Quick test script for v1.2.61 bug fixes

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GA-AppLocker v1.2.61 Test Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator" -ForegroundColor Yellow
    Write-Host "Local scans require elevation to access system directories" -ForegroundColor Yellow
    Write-Host ""
}

# Clear module cache
Write-Host "Clearing module cache..." -ForegroundColor Green
Get-Module GA-AppLocker | Remove-Module -Force -ErrorAction SilentlyContinue
Write-Host "Done." -ForegroundColor Green
Write-Host ""

# Show what to test
Write-Host "Starting GA-AppLocker Dashboard..." -ForegroundColor Green
Write-Host ""
Write-Host "PLEASE TEST THESE 4 SCENARIOS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. RULES PANEL BUTTONS (Ctrl+5)" -ForegroundColor White
Write-Host "   - Click: + Service Allow" -ForegroundColor Gray
Write-Host "   - Click: + Admin Allow" -ForegroundColor Gray
Write-Host "   - Click: + Deny Paths" -ForegroundColor Gray
Write-Host "   Expected: Buttons work, no errors" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. LOCAL SCAN (Ctrl+4)" -ForegroundColor White
Write-Host "   - Check: Scan Local" -ForegroundColor Gray
Write-Host "   - Click: Start Scan" -ForegroundColor Gray
Write-Host "   Expected: Finds EXE/DLL/MSI (not just Appx)" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. AD DISCOVERY AUTO-REFRESH (Ctrl+2)" -ForegroundColor White
Write-Host "   - Select machines" -ForegroundColor Gray
Write-Host "   - Click: Test Connectivity" -ForegroundColor Gray
Write-Host "   Expected: DataGrid updates automatically" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. CHECK LOGS" -ForegroundColor White
Write-Host "   Location: %LOCALAPPDATA%\GA-AppLocker\Logs\" -ForegroundColor Gray
Write-Host "   Look for: Diagnostic output, any errors" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Start the app
.\Run-Dashboard.ps1
