#Requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive test suite for GA-AppLocker modules

.DESCRIPTION
    Tests all functions in Core, Discovery, Credentials, and Scanning modules.
    Reports pass/fail status for each test.
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
$script:TestResults = @()
$script:PassCount = 0
$script:FailCount = 0

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = '',
        [string]$Details = ''
    )
    
    $status = if ($Passed) { 
        $script:PassCount++
        Write-Host "[PASS] " -ForegroundColor Green -NoNewline
        'PASS'
    } else { 
        $script:FailCount++
        Write-Host "[FAIL] " -ForegroundColor Red -NoNewline
        'FAIL'
    }
    
    Write-Host "$TestName" -NoNewline
    if ($Message) { Write-Host " - $Message" -ForegroundColor Gray -NoNewline }
    Write-Host ""
    
    if ($Details -and (-not $Passed -or $Verbose)) {
        Write-Host "        $Details" -ForegroundColor DarkGray
    }
    
    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Status   = $status
        Message  = $Message
        Details  = $Details
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
}

# ============================================================
# LOAD MODULE
# ============================================================
Write-Host "Loading GA-AppLocker module..." -ForegroundColor Yellow
try {
    Import-Module "$PSScriptRoot\GA-AppLocker\GA-AppLocker.psd1" -Force -ErrorAction Stop
    Write-Host "Module loaded successfully`n" -ForegroundColor Green
}
catch {
    Write-Host "FATAL: Failed to load module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================
# CORE MODULE TESTS
# ============================================================
Write-Section "CORE MODULE TESTS"

# Test 1: Write-AppLockerLog
try {
    Write-AppLockerLog -Message "Test log message" -NoConsole
    $logPath = Join-Path (Get-AppLockerDataPath) "Logs"
    $todayLog = Join-Path $logPath "GA-AppLocker_$(Get-Date -Format 'yyyy-MM-dd').log"
    $logExists = Test-Path $todayLog
    Write-TestResult -TestName "Write-AppLockerLog" -Passed $logExists -Message "Log file created" -Details $todayLog
}
catch {
    Write-TestResult -TestName "Write-AppLockerLog" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 2: Get-AppLockerDataPath
try {
    $dataPath = Get-AppLockerDataPath
    $pathValid = ($dataPath -ne $null) -and ($dataPath -match 'GA-AppLocker')
    Write-TestResult -TestName "Get-AppLockerDataPath" -Passed $pathValid -Message "Returns valid path" -Details $dataPath
}
catch {
    Write-TestResult -TestName "Get-AppLockerDataPath" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 3: Get-AppLockerConfig
try {
    $config = Get-AppLockerConfig
    $configValid = ($config -ne $null) -and ($config.PSObject.Properties.Count -gt 0)
    Write-TestResult -TestName "Get-AppLockerConfig" -Passed $configValid -Message "Returns config object" -Details "Properties: $($config.PSObject.Properties.Name -join ', ')"
}
catch {
    Write-TestResult -TestName "Get-AppLockerConfig" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 4: Set-AppLockerConfig
try {
    $testValue = "TestValue_$(Get-Random)"
    Set-AppLockerConfig -Key 'TestSetting' -Value $testValue
    $retrieved = (Get-AppLockerConfig).TestSetting
    $setWorks = ($retrieved -eq $testValue)
    Write-TestResult -TestName "Set-AppLockerConfig" -Passed $setWorks -Message "Can set and retrieve config" -Details "Set: $testValue, Got: $retrieved"
}
catch {
    Write-TestResult -TestName "Set-AppLockerConfig" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 5: Test-Prerequisites
try {
    $prereqs = Test-Prerequisites
    $prereqsValid = ($prereqs -ne $null) -and ($prereqs.PSObject.Properties.Name -contains 'AllPassed') -and ($prereqs.PSObject.Properties.Name -contains 'Checks')
    Write-TestResult -TestName "Test-Prerequisites" -Passed $prereqsValid -Message "Returns prereq results" -Details "AllPassed: $($prereqs.AllPassed), Checks: $($prereqs.Checks.Count)"
}
catch {
    Write-TestResult -TestName "Test-Prerequisites" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# ============================================================
# DISCOVERY MODULE TESTS
# ============================================================
Write-Section "DISCOVERY MODULE TESTS"

# Test 6: Get-DomainInfo
try {
    $domainInfo = Get-DomainInfo
    $hasResult = ($domainInfo -ne $null) -and ($domainInfo.PSObject.Properties.Name -contains 'Success')
    # Note: May fail if not domain-joined, but function should still return a result object
    Write-TestResult -TestName "Get-DomainInfo" -Passed $hasResult -Message "Returns result object" -Details "Success: $($domainInfo.Success), Error: $($domainInfo.Error)"
}
catch {
    Write-TestResult -TestName "Get-DomainInfo" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 7: Get-OUTree
try {
    $ouTree = Get-OUTree
    $hasResult = ($ouTree -ne $null) -and ($ouTree.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Get-OUTree" -Passed $hasResult -Message "Returns result object" -Details "Success: $($ouTree.Success), Data count: $($ouTree.Data.Count)"
}
catch {
    Write-TestResult -TestName "Get-OUTree" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 8: Get-ComputersByOU (with empty input - should handle gracefully)
try {
    $computers = Get-ComputersByOU -OUDistinguishedNames @()
    $hasResult = ($computers -ne $null) -and ($computers.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Get-ComputersByOU (empty)" -Passed $hasResult -Message "Handles empty input" -Details "Success: $($computers.Success)"
}
catch {
    Write-TestResult -TestName "Get-ComputersByOU (empty)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 9: Test-MachineConnectivity (with empty input)
try {
    $connectivity = Test-MachineConnectivity -Machines @()
    $hasResult = ($connectivity -ne $null) -and ($connectivity.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Test-MachineConnectivity (empty)" -Passed $hasResult -Message "Handles empty input" -Details "Success: $($connectivity.Success)"
}
catch {
    Write-TestResult -TestName "Test-MachineConnectivity (empty)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# ============================================================
# CREDENTIALS MODULE TESTS
# ============================================================
Write-Section "CREDENTIALS MODULE TESTS"

# Test 10: Get-CredentialStoragePath
try {
    $credPath = Get-CredentialStoragePath
    $pathValid = ($credPath -ne $null) -and ($credPath -match 'Credentials')
    $pathExists = Test-Path $credPath
    Write-TestResult -TestName "Get-CredentialStoragePath" -Passed ($pathValid -and $pathExists) -Message "Returns valid path" -Details $credPath
}
catch {
    Write-TestResult -TestName "Get-CredentialStoragePath" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 11: New-CredentialProfile
$testProfileName = "TestProfile_$(Get-Random)"
try {
    $securePass = ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force
    $testCred = [PSCredential]::new("DOMAIN\TestUser", $securePass)
    
    $newProfile = New-CredentialProfile -Name $testProfileName -Credential $testCred -Tier 2 -Description "Test profile"
    $created = $newProfile.Success -and $newProfile.Data
    Write-TestResult -TestName "New-CredentialProfile" -Passed $created -Message "Creates profile" -Details "Name: $testProfileName, ID: $($newProfile.Data.Id)"
}
catch {
    Write-TestResult -TestName "New-CredentialProfile" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 12: Get-CredentialProfile
try {
    $getProfile = Get-CredentialProfile -Name $testProfileName
    $retrieved = $getProfile.Success -and ($getProfile.Data.Name -eq $testProfileName)
    Write-TestResult -TestName "Get-CredentialProfile" -Passed $retrieved -Message "Retrieves profile by name" -Details "Found: $($getProfile.Data.Name)"
}
catch {
    Write-TestResult -TestName "Get-CredentialProfile" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 13: Get-AllCredentialProfiles
try {
    $allProfiles = Get-AllCredentialProfiles
    $hasResult = $allProfiles.Success
    Write-TestResult -TestName "Get-AllCredentialProfiles" -Passed $hasResult -Message "Returns profiles list" -Details "Count: $($allProfiles.Data.Count)"
}
catch {
    Write-TestResult -TestName "Get-AllCredentialProfiles" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 14: Get-CredentialForTier
try {
    $tierCred = Get-CredentialForTier -Tier 2
    # May or may not succeed depending on if a Tier 2 cred exists with our test profile
    $hasResult = ($tierCred -ne $null) -and ($tierCred.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Get-CredentialForTier" -Passed $hasResult -Message "Returns result object" -Details "Success: $($tierCred.Success), Error: $($tierCred.Error)"
}
catch {
    Write-TestResult -TestName "Get-CredentialForTier" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 15: Remove-CredentialProfile
try {
    $removeResult = Remove-CredentialProfile -Name $testProfileName
    $removed = $removeResult.Success
    
    # Verify it's gone
    $verifyGone = Get-CredentialProfile -Name $testProfileName
    $actuallyGone = -not $verifyGone.Data
    
    Write-TestResult -TestName "Remove-CredentialProfile" -Passed ($removed -and $actuallyGone) -Message "Removes profile" -Details "Removed: $removed, Verified gone: $actuallyGone"
}
catch {
    Write-TestResult -TestName "Remove-CredentialProfile" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# ============================================================
# SCANNING MODULE TESTS
# ============================================================
Write-Section "SCANNING MODULE TESTS"

# Test 16: Get-LocalArtifacts (small scan)
try {
    $localScan = Get-LocalArtifacts -Paths 'C:\Windows' -Extensions @('.exe') -MaxDepth 0
    $hasResult = $localScan.Success -and ($localScan.Data -ne $null)
    $hasArtifacts = $localScan.Data.Count -gt 0
    Write-TestResult -TestName "Get-LocalArtifacts (non-recursive)" -Passed ($hasResult -and $hasArtifacts) -Message "Scans local files" -Details "Found: $($localScan.Data.Count) artifacts"
}
catch {
    Write-TestResult -TestName "Get-LocalArtifacts (non-recursive)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 17: Get-LocalArtifacts with recursion
try {
    $localScanRecurse = Get-LocalArtifacts -Paths 'C:\Windows\System32\drivers' -Extensions @('.sys') -Recurse -MaxDepth 1
    $hasResult = $localScanRecurse.Success
    Write-TestResult -TestName "Get-LocalArtifacts (recursive)" -Passed $hasResult -Message "Recursive scan works" -Details "Found: $($localScanRecurse.Data.Count) artifacts"
}
catch {
    Write-TestResult -TestName "Get-LocalArtifacts (recursive)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 18: Artifact data structure
try {
    $localScan = Get-LocalArtifacts -Paths 'C:\Windows' -Extensions @('.exe') -MaxDepth 0
    if ($localScan.Data.Count -gt 0) {
        $sample = $localScan.Data[0]
        $hasRequiredProps = ($sample.PSObject.Properties.Name -contains 'FilePath') -and
                           ($sample.PSObject.Properties.Name -contains 'SHA256Hash') -and
                           ($sample.PSObject.Properties.Name -contains 'Publisher') -and
                           ($sample.PSObject.Properties.Name -contains 'IsSigned')
        Write-TestResult -TestName "Artifact data structure" -Passed $hasRequiredProps -Message "Has required properties" -Details "Props: FilePath, SHA256Hash, Publisher, IsSigned"
    }
    else {
        Write-TestResult -TestName "Artifact data structure" -Passed $false -Message "No artifacts to check"
    }
}
catch {
    Write-TestResult -TestName "Artifact data structure" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 19: Get-AppLockerEventLogs
try {
    $eventLogs = Get-AppLockerEventLogs -MaxEvents 10
    $hasResult = ($eventLogs -ne $null) -and ($eventLogs.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Get-AppLockerEventLogs" -Passed $hasResult -Message "Returns result object" -Details "Success: $($eventLogs.Success), Events: $($eventLogs.Data.Count)"
}
catch {
    Write-TestResult -TestName "Get-AppLockerEventLogs" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 20: Start-ArtifactScan (local only - small path to avoid timeout)
try {
    $scanResult = Start-ArtifactScan -ScanLocal -Paths @('C:\Windows\System32\drivers') -ScanName "Test_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $hasResult = ($scanResult -ne $null) -and ($scanResult.PSObject.Properties.Name -contains 'Success')
    $hasSummary = $scanResult.Summary -ne $null
    Write-TestResult -TestName "Start-ArtifactScan (local)" -Passed ($hasResult -and $hasSummary) -Message "Orchestrates local scan" -Details "Artifacts: $($scanResult.Data.Artifacts.Count)"
}
catch {
    Write-TestResult -TestName "Start-ArtifactScan (local)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 21: Get-ScanResults (list all)
try {
    $scanList = Get-ScanResults
    $hasResult = ($scanList -ne $null) -and ($scanList.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Get-ScanResults (list)" -Passed $hasResult -Message "Lists saved scans" -Details "Success: $($scanList.Success), Count: $($scanList.Data.Count)"
}
catch {
    Write-TestResult -TestName "Get-ScanResults (list)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 22: Get-RemoteArtifacts structure (with localhost - may fail but should not crash)
try {
    # This will likely fail since localhost doesn't have WinRM to itself typically, 
    # but we're testing that the function handles it gracefully
    $remoteResult = Get-RemoteArtifacts -ComputerName @('localhost') -Paths @('C:\Windows') -Extensions @('.exe')
    $hasResult = ($remoteResult -ne $null) -and ($remoteResult.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Get-RemoteArtifacts (structure)" -Passed $hasResult -Message "Returns result object" -Details "Success: $($remoteResult.Success), PerMachine keys: $($remoteResult.PerMachine.Keys -join ',')"
}
catch {
    Write-TestResult -TestName "Get-RemoteArtifacts (structure)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# ============================================================
# RULES MODULE TESTS
# ============================================================
Write-Section "RULES MODULE TESTS"

# Test: New-PublisherRule
try {
    $pubRule = New-PublisherRule -PublisherName 'O=MICROSOFT CORPORATION' -ProductName '*' -Action Allow
    $hasResult = $pubRule.Success -and ($pubRule.Data.RuleType -eq 'Publisher')
    Write-TestResult -TestName "New-PublisherRule" -Passed $hasResult -Message "Creates publisher rule" -Details "ID: $($pubRule.Data.Id)"
}
catch {
    Write-TestResult -TestName "New-PublisherRule" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: New-HashRule
try {
    $testHash = 'A' * 64
    $hashRule = New-HashRule -Hash $testHash -SourceFileName 'test.exe' -SourceFileLength 1024
    $hasResult = $hashRule.Success -and ($hashRule.Data.RuleType -eq 'Hash')
    Write-TestResult -TestName "New-HashRule" -Passed $hasResult -Message "Creates hash rule" -Details "ID: $($hashRule.Data.Id)"
}
catch {
    Write-TestResult -TestName "New-HashRule" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: New-PathRule
try {
    $pathRule = New-PathRule -Path '%PROGRAMFILES%\*' -Action Allow -CollectionType Exe
    $hasResult = $pathRule.Success -and ($pathRule.Data.RuleType -eq 'Path')
    Write-TestResult -TestName "New-PathRule" -Passed $hasResult -Message "Creates path rule" -Details "Path: $($pathRule.Data.Path)"
}
catch {
    Write-TestResult -TestName "New-PathRule" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: ConvertFrom-Artifact (with mock artifact)
try {
    $testHash2 = 'B' * 64
    $mockArtifact = [PSCustomObject]@{
        FilePath        = 'C:\Program Files\Test\test.exe'
        FileName        = 'test.exe'
        Extension       = '.exe'
        SHA256Hash      = $testHash2
        IsSigned        = $false
        SignerCertificate = $null
        Publisher       = $null
        ProductName     = 'Test Product'
        ProductVersion  = '1.0.0'
        SizeBytes       = 2048
    }
    $convertResult = ConvertFrom-Artifact -Artifact $mockArtifact
    $hasResult = $convertResult.Success -and ($convertResult.Data.Count -gt 0)
    Write-TestResult -TestName "ConvertFrom-Artifact" -Passed $hasResult -Message "Converts artifact to rule" -Details "Rules created: $($convertResult.Data.Count)"
}
catch {
    Write-TestResult -TestName "ConvertFrom-Artifact" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-AllRules
try {
    $allRules = Get-AllRules
    $hasResult = ($allRules -ne $null) -and ($allRules.PSObject.Properties.Name -contains 'Success')
    Write-TestResult -TestName "Get-AllRules" -Passed $hasResult -Message "Lists all rules" -Details "Count: $($allRules.Data.Count)"
}
catch {
    Write-TestResult -TestName "Get-AllRules" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# ============================================================
# GUI TESTS
# ============================================================
Write-Section "GUI TESTS"

# Test 23: XAML loads
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    $xamlPath = "$PSScriptRoot\GA-AppLocker\GUI\MainWindow.xaml"
    $xamlContent = Get-Content -Path $xamlPath -Raw
    $xaml = [xml]$xamlContent
    $xamlValid = ($xaml -ne $null) -and ($xaml.Window -ne $null)
    Write-TestResult -TestName "XAML file loads" -Passed $xamlValid -Message "MainWindow.xaml parses correctly"
}
catch {
    Write-TestResult -TestName "XAML file loads" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 24: Code-behind loads
try {
    $codeBehindPath = "$PSScriptRoot\GA-AppLocker\GUI\MainWindow.xaml.ps1"
    . $codeBehindPath
    $functionsExist = (Get-Command -Name 'Initialize-MainWindow' -ErrorAction SilentlyContinue) -and
                      (Get-Command -Name 'Set-ActivePanel' -ErrorAction SilentlyContinue) -and
                      (Get-Command -Name 'Invoke-ButtonAction' -ErrorAction SilentlyContinue)
    Write-TestResult -TestName "Code-behind loads" -Passed $functionsExist -Message "GUI functions available"
}
catch {
    Write-TestResult -TestName "Code-behind loads" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 25: Window can be created (without showing)
try {
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $windowCreated = ($window -ne $null) -and ($window.GetType().Name -eq 'Window')
    Write-TestResult -TestName "Window creation" -Passed $windowCreated -Message "WPF window instantiates"
}
catch {
    Write-TestResult -TestName "Window creation" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 26: Window initialization
try {
    Initialize-MainWindow -Window $window
    $initialized = ($script:MainWindow -ne $null) -or ($global:GA_MainWindow -ne $null)
    Write-TestResult -TestName "Window initialization" -Passed $initialized -Message "Initialize-MainWindow completes"
}
catch {
    Write-TestResult -TestName "Window initialization" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 27: Navigation works
try {
    $panels = @('NavDashboard', 'NavDiscovery', 'NavScanner', 'NavRules', 'NavPolicy', 'NavDeploy', 'NavSettings')
    $allWorked = $true
    foreach ($panel in $panels) {
        try {
            Invoke-ButtonAction -Action $panel
        }
        catch {
            $allWorked = $false
            break
        }
    }
    Write-TestResult -TestName "Navigation (all panels)" -Passed $allWorked -Message "All 7 panels navigate"
}
catch {
    Write-TestResult -TestName "Navigation (all panels)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host " TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $($script:PassCount + $script:FailCount)" -ForegroundColor White
Write-Host "Passed:      $($script:PassCount)" -ForegroundColor Green
Write-Host "Failed:      $($script:FailCount)" -ForegroundColor $(if ($script:FailCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($script:FailCount -gt 0) {
    Write-Host "FAILED TESTS:" -ForegroundColor Red
    $script:TestResults | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
        Write-Host "  - $($_.TestName): $($_.Details)" -ForegroundColor Red
    }
}

Write-Host ""
$overallResult = if ($script:FailCount -eq 0) { "ALL TESTS PASSED" } else { "SOME TESTS FAILED" }
$resultColor = if ($script:FailCount -eq 0) { 'Green' } else { 'Red' }
Write-Host $overallResult -ForegroundColor $resultColor
Write-Host ""

# Return exit code for CI/CD
exit $script:FailCount
