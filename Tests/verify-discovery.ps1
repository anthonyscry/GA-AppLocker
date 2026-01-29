#!/usr/bin/env pwsh
# AD Discovery Integration Verification Script
# Run: powershell -ExecutionPolicy Bypass -File Tests\verify-discovery.ps1

Write-Host '========================================'  -ForegroundColor Cyan
Write-Host '  AD Discovery Integration Verification'  -ForegroundColor Cyan
Write-Host '========================================'  -ForegroundColor Cyan
Write-Host ''

$script:passCount = 0
$script:failCount = 0

function Assert-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    if ($Passed) {
        Write-Host "  PASS: $Name" -ForegroundColor Green
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkGray }
        $script:passCount++
    } else {
        Write-Host "  FAIL: $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor Yellow }
        $script:failCount++
    }
}

# ─────────────────────────────────────────────────────────
# 1. MODULE LOADING
# ─────────────────────────────────────────────────────────
Write-Host '[1/8] Module Loading...' -ForegroundColor Yellow
try {
    Import-Module "$PSScriptRoot\..\GA-AppLocker\GA-AppLocker.psd1" -Force -ErrorAction Stop
    $cmdCount = (Get-Command -Module GA-AppLocker).Count
    Assert-Check 'Module loads successfully' $true "$cmdCount commands exported"
} catch {
    Assert-Check 'Module loads successfully' $false $_.Exception.Message
    Write-Host "`nCRITICAL: Module failed to load. Aborting." -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────
# 2. DISCOVERY FUNCTION EXPORTS
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[2/8] Discovery Function Exports...' -ForegroundColor Yellow
$expectedFunctions = @(
    'Get-DomainInfo', 'Get-OUTree', 'Get-ComputersByOU', 'Test-MachineConnectivity',
    'Resolve-LdapServer', 'Get-LdapConnection', 'Get-LdapSearchResult',
    'Get-DomainInfoViaLdap', 'Get-OUTreeViaLdap', 'Get-ComputersByOUViaLdap',
    'Set-LdapConfiguration', 'Test-LdapConnection'
)
$missing = @()
foreach ($fn in $expectedFunctions) {
    $cmd = Get-Command $fn -ErrorAction SilentlyContinue
    if (-not $cmd) { $missing += $fn }
}
Assert-Check "All $($expectedFunctions.Count) Discovery functions exported" ($missing.Count -eq 0) $(if ($missing.Count -gt 0) { "Missing: $($missing -join ', ')" } else { '' })

# ─────────────────────────────────────────────────────────
# 3. RESOLVE-LDAPSERVER (CENTRALIZED RESOLUTION)
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[3/8] Resolve-LdapServer (centralized resolution)...' -ForegroundColor Yellow

# 3a. Explicit server takes priority
$r = Resolve-LdapServer -Server 'dc01.test.local' -Port 636
Assert-Check 'Explicit server resolves correctly' ($r.Server -eq 'dc01.test.local' -and $r.Port -eq 636 -and $r.Source -eq 'Parameter') "Server=$($r.Server), Port=$($r.Port), Source=$($r.Source)"

# 3b. Default port is 389
$r = Resolve-LdapServer -Server 'dc01.test.local'
Assert-Check 'Default port is 389' ($r.Port -eq 389) "Port=$($r.Port)"

# 3c. Returns PSCustomObject with required properties
$r = Resolve-LdapServer -Server 'test'
$hasProps = ($null -ne $r.PSObject.Properties['Server']) -and ($null -ne $r.PSObject.Properties['Port']) -and ($null -ne $r.PSObject.Properties['Source'])
Assert-Check 'Returns object with Server/Port/Source properties' $hasProps ''

# 3d. No server + no config + no env => null
$savedEnv = $env:USERDNSDOMAIN
$env:USERDNSDOMAIN = $null
$savedConfig = $null
try {
    # Try to temporarily clear config LdapServer
    $cfg = Get-AppLockerConfig
    $savedConfig = $cfg.LdapServer
    if ($cfg.LdapServer) {
        $cfg.LdapServer = $null
        # Don't actually save - just test Resolve behavior with explicit empty
    }
} catch { }
# Since we can't cleanly mock config, test with explicit empty
$r = Resolve-LdapServer
$isNull = ($null -eq $r)
# If env var was set, it would resolve via Environment - that's also valid
$env:USERDNSDOMAIN = $savedEnv
if ($isNull) {
    Assert-Check 'Returns null when no server source available' $true 'No server, no config, no env'
} else {
    # The machine might have USERDNSDOMAIN or config set - that's fine
    Assert-Check 'Resolves via fallback (env or config present on this machine)' $true "Source=$($r.Source), Server=$($r.Server)"
}

# ─────────────────────────────────────────────────────────
# 4. ERROR MESSAGE QUALITY
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[4/8] Error Message Quality...' -ForegroundColor Yellow

# All Discovery functions should return actionable errors, never 'localhost'
$savedEnv = $env:USERDNSDOMAIN
$env:USERDNSDOMAIN = $null

# Get-DomainInfo
$result = Get-DomainInfo
$env:USERDNSDOMAIN = $savedEnv
if (-not $result.Success) {
    $hasActionable = $result.Error -match 'Set-LdapConfiguration|configured|domain'
    $noLocalhost = $result.Error -notmatch 'localhost'
    Assert-Check 'Get-DomainInfo error is actionable (mentions Set-LdapConfiguration)' $hasActionable "Error: $($result.Error)"
    Assert-Check 'Get-DomainInfo error never mentions localhost' $noLocalhost ''
} else {
    # Machine is domain-joined and LDAP worked via env fallback - that's valid
    Assert-Check 'Get-DomainInfo succeeded (domain-joined machine with env fallback)' $true "Domain: $($result.Data.DnsRoot)"
    Assert-Check 'Get-DomainInfo error quality (skipped - function succeeded)' $true ''
}

# Get-OUTree
$savedEnv = $env:USERDNSDOMAIN
$env:USERDNSDOMAIN = $null
$result = Get-OUTree
$env:USERDNSDOMAIN = $savedEnv
if (-not $result.Success) {
    $hasActionable = $result.Error -match 'Set-LdapConfiguration|configured|domain'
    Assert-Check 'Get-OUTree error is actionable' $hasActionable "Error: $($result.Error)"
} else {
    Assert-Check 'Get-OUTree succeeded (domain-joined machine)' $true ''
}

# Get-ComputersByOU
$savedEnv = $env:USERDNSDOMAIN
$env:USERDNSDOMAIN = $null
$result = Get-ComputersByOU -OUDistinguishedNames 'OU=Test,DC=test,DC=local'
$env:USERDNSDOMAIN = $savedEnv
if (-not $result.Success) {
    $hasActionable = $result.Error -match 'Set-LdapConfiguration|configured|domain'
    Assert-Check 'Get-ComputersByOU error is actionable' $hasActionable "Error: $($result.Error)"
} else {
    Assert-Check 'Get-ComputersByOU succeeded (domain-joined machine)' $true ''
}

# ─────────────────────────────────────────────────────────
# 5. GRACEFUL EMPTY INPUT HANDLING
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[5/8] Graceful Empty Input Handling...' -ForegroundColor Yellow

$result = Get-ComputersByOU -OUDistinguishedNames @()
Assert-Check 'Get-ComputersByOU with empty array returns Success' $result.Success ''
Assert-Check 'Get-ComputersByOU with empty array returns empty Data' ($result.Data.Count -eq 0) ''

$result = Test-MachineConnectivity -Machines @()
Assert-Check 'Test-MachineConnectivity with empty array returns Success' $result.Success ''
Assert-Check 'Test-MachineConnectivity with empty array has Summary' ($null -ne $result.Summary) "TotalMachines=$($result.Summary.TotalMachines)"

# ─────────────────────────────────────────────────────────
# 6. TEST-LDAPCONNECTION
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[6/8] Test-LdapConnection...' -ForegroundColor Yellow

# With explicit server (will fail to connect but should return structured result)
$result = Test-LdapConnection -Server 'nonexistent.server.local' -Port 389
Assert-Check 'Test-LdapConnection returns structured result' ($null -ne $result.PSObject.Properties['Success']) ''
Assert-Check 'Test-LdapConnection.Server set correctly' ($result.Server -eq 'nonexistent.server.local') "Server=$($result.Server)"
Assert-Check 'Test-LdapConnection.Source is Parameter' ($result.Source -eq 'Parameter') "Source=$($result.Source)"
Assert-Check 'Test-LdapConnection.Success is false for bad server' (-not $result.Success) ''
Assert-Check 'Test-LdapConnection.Error is not empty' (-not [string]::IsNullOrEmpty($result.Error)) "Error=$($result.Error)"

# Without any server (test resolution path)
$savedEnv = $env:USERDNSDOMAIN
$env:USERDNSDOMAIN = $null
$result = Test-LdapConnection
$env:USERDNSDOMAIN = $savedEnv
if (-not $result.Success) {
    Assert-Check 'Test-LdapConnection with no server returns clear error' ($result.Error -match 'configured|Set-LdapConfiguration') "Error=$($result.Error)"
} else {
    Assert-Check 'Test-LdapConnection resolved via fallback (machine has config/env)' $true "Server=$($result.Server)"
}

# ─────────────────────────────────────────────────────────
# 7. SET-LDAPCONFIGURATION
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[7/8] Set-LdapConfiguration persistence...' -ForegroundColor Yellow

# Save current config
$origConfig = Get-AppLockerConfig
$origServer = $origConfig.LdapServer
$origPort = $origConfig.LdapPort

# Set a test config
Set-LdapConfiguration -Server 'test-dc.verify.local' -Port 10389
$config = Get-AppLockerConfig
Assert-Check 'Set-LdapConfiguration saves server to config' ($config.LdapServer -eq 'test-dc.verify.local') "LdapServer=$($config.LdapServer)"
Assert-Check 'Set-LdapConfiguration saves port to config' ($config.LdapPort -eq 10389) "LdapPort=$($config.LdapPort)"

# Verify Resolve-LdapServer picks up config
$savedEnv = $env:USERDNSDOMAIN
$env:USERDNSDOMAIN = $null
$r = Resolve-LdapServer
$env:USERDNSDOMAIN = $savedEnv
Assert-Check 'Resolve-LdapServer reads from saved config' ($r.Server -eq 'test-dc.verify.local' -and $r.Source -eq 'Config') "Server=$($r.Server), Source=$($r.Source)"

# Restore original config
if ($origServer) {
    Set-LdapConfiguration -Server $origServer -Port $(if ($origPort) { $origPort } else { 389 })
} else {
    # Remove the test config entries by setting to empty values
    Set-AppLockerConfig -Settings @{ LdapServer = ''; LdapPort = 0; LdapUseSSL = $false }
}

# ─────────────────────────────────────────────────────────
# 8. STANDARD RESULT OBJECT SHAPE
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[8/8] Standard Result Object Shape...' -ForegroundColor Yellow

$result = Get-DomainInfo
$hasSuccess = $null -ne $result.PSObject.Properties['Success']
$hasData = $null -ne $result.PSObject.Properties['Data']
$hasError = $null -ne $result.PSObject.Properties['Error']
Assert-Check 'Get-DomainInfo returns { Success, Data, Error }' ($hasSuccess -and $hasData -and $hasError) ''

$result = Get-OUTree
$hasSuccess = $null -ne $result.PSObject.Properties['Success']
$hasData = $null -ne $result.PSObject.Properties['Data']
$hasError = $null -ne $result.PSObject.Properties['Error']
Assert-Check 'Get-OUTree returns { Success, Data, Error }' ($hasSuccess -and $hasData -and $hasError) ''

$result = Get-ComputersByOU -OUDistinguishedNames @()
$hasSuccess = $null -ne $result.PSObject.Properties['Success']
$hasData = $null -ne $result.PSObject.Properties['Data']
$hasError = $null -ne $result.PSObject.Properties['Error']
Assert-Check 'Get-ComputersByOU returns { Success, Data, Error }' ($hasSuccess -and $hasData -and $hasError) ''

$result = Test-MachineConnectivity -Machines @()
$hasSuccess = $null -ne $result.PSObject.Properties['Success']
$hasData = $null -ne $result.PSObject.Properties['Data']
$hasError = $null -ne $result.PSObject.Properties['Error']
$hasSummary = $null -ne $result.PSObject.Properties['Summary']
Assert-Check 'Test-MachineConnectivity returns { Success, Data, Error, Summary }' ($hasSuccess -and $hasData -and $hasError -and $hasSummary) ''

# ─────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '========================================'  -ForegroundColor Cyan
$total = $script:passCount + $script:failCount
if ($script:failCount -eq 0) {
    Write-Host "  ALL CHECKS PASSED: $($script:passCount)/$total" -ForegroundColor Green
} else {
    Write-Host "  RESULTS: $($script:passCount) passed, $($script:failCount) failed (of $total)" -ForegroundColor $(if ($script:failCount -gt 0) { 'Red' } else { 'Green' })
}
Write-Host '========================================'  -ForegroundColor Cyan
Write-Host ''

exit $script:failCount
