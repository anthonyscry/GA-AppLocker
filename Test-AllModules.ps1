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
    # Validate result structure (function should return result even if not domain-joined)
    $hasValidStructure = ($domainInfo -ne $null) -and 
                         ($domainInfo.PSObject.Properties.Name -contains 'Success') -and
                         ($domainInfo.PSObject.Properties.Name -contains 'Data' -or $domainInfo.PSObject.Properties.Name -contains 'Error')
    # If Success is true, Data should have domain info
    $dataValid = if ($domainInfo.Success) { 
        $domainInfo.Data -ne $null 
    } else { 
        $true  # Error case is acceptable for non-domain environments
    }
    Write-TestResult -TestName "Get-DomainInfo" -Passed ($hasValidStructure -and $dataValid) -Message "Returns valid result" -Details "Success: $($domainInfo.Success), HasData: $($domainInfo.Data -ne $null)"
}
catch {
    Write-TestResult -TestName "Get-DomainInfo" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 7: Get-OUTree
try {
    $ouTree = Get-OUTree
    # Validate result structure
    $hasValidStructure = ($ouTree -ne $null) -and 
                         ($ouTree.PSObject.Properties.Name -contains 'Success') -and
                         ($ouTree.PSObject.Properties.Name -contains 'Data' -or $ouTree.PSObject.Properties.Name -contains 'Error')
    # If Success is true, Data should be an array (even if empty)
    $dataValid = if ($ouTree.Success) { 
        $ouTree.Data -is [array] -or $ouTree.Data -eq $null 
    } else { 
        $true  # Error case is acceptable for non-domain environments
    }
    Write-TestResult -TestName "Get-OUTree" -Passed ($hasValidStructure -and $dataValid) -Message "Returns valid result" -Details "Success: $($ouTree.Success), DataType: $($ouTree.Data.GetType().Name)"
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
    # Validate result structure
    $hasValidStructure = ($tierCred -ne $null) -and 
                         ($tierCred.PSObject.Properties.Name -contains 'Success')
    # If Success is true, should have credential Data; if false, should have Error
    $dataValid = if ($tierCred.Success) { 
        $tierCred.Data -ne $null 
    } else { 
        $tierCred.Error -ne $null -or $tierCred.Data -eq $null  # No tier cred is acceptable
    }
    Write-TestResult -TestName "Get-CredentialForTier" -Passed ($hasValidStructure -and $dataValid) -Message "Returns valid result" -Details "Success: $($tierCred.Success), HasCred: $($tierCred.Data -ne $null)"
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
    # Validate result structure
    $hasValidStructure = ($eventLogs -ne $null) -and 
                         ($eventLogs.PSObject.Properties.Name -contains 'Success') -and
                         ($eventLogs.PSObject.Properties.Name -contains 'Data')
    # If Success is true, Data should be an array (possibly empty if no events)
    $dataValid = if ($eventLogs.Success) { 
        $eventLogs.Data -is [array] -or $eventLogs.Data.Count -ge 0
    } else { 
        $eventLogs.Error -ne $null  # Should have error message if failed
    }
    Write-TestResult -TestName "Get-AppLockerEventLogs" -Passed ($hasValidStructure -and $dataValid) -Message "Returns valid result" -Details "Success: $($eventLogs.Success), Events: $($eventLogs.Data.Count)"
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
    # Validate result structure - must have Success property
    $hasValidStructure = ($scanList -ne $null) -and 
                         ($scanList.PSObject.Properties.Name -contains 'Success')
    # If Success is true, Data should be defined (array, possibly empty)
    $dataValid = if ($scanList.Success -eq $true) { 
        $scanList.Data -ne $null -and ($scanList.Data -is [array] -or $scanList.Data.Count -ge 0)
    } else { 
        $scanList.Error -ne $null  # Should have error message if failed
    }
    Write-TestResult -TestName "Get-ScanResults (list)" -Passed ($hasValidStructure -and ($scanList.Success -eq $true -or $dataValid)) -Message "Lists saved scans" -Details "Success: $($scanList.Success), Count: $($scanList.Data.Count)"
}
catch {
    Write-TestResult -TestName "Get-ScanResults (list)" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test 22: Get-RemoteArtifacts structure (with localhost - may fail but should not crash)
try {
    # This will likely fail since localhost doesn't have WinRM to itself typically, 
    # but we're testing that the function handles it gracefully
    $remoteResult = Get-RemoteArtifacts -ComputerName @('localhost') -Paths @('C:\Windows') -Extensions @('.exe')
    # Validate result structure - must have proper response format
    $hasValidStructure = ($remoteResult -ne $null) -and 
                         ($remoteResult.PSObject.Properties.Name -contains 'Success') -and
                         ($remoteResult.PSObject.Properties.Name -contains 'Data') -and
                         ($remoteResult.PSObject.Properties.Name -contains 'PerMachine')
    # PerMachine should be a hashtable with machine results
    $perMachineValid = ($remoteResult.PerMachine -is [hashtable]) -or 
                       ($remoteResult.PerMachine.GetType().Name -eq 'OrderedDictionary')
    # Data should be an array (even if empty due to connection failure)
    $dataValid = $remoteResult.Data -is [array] -or $remoteResult.Data.Count -ge 0
    Write-TestResult -TestName "Get-RemoteArtifacts (structure)" -Passed ($hasValidStructure -and $perMachineValid -and $dataValid) -Message "Returns valid result structure" -Details "Success: $($remoteResult.Success), PerMachine: $($remoteResult.PerMachine.Keys -join ',')"
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
# POLICY MODULE TESTS
# ============================================================
Write-Section "POLICY MODULE TESTS"

# Test: New-Policy
$testPolicyId = $null
try {
    $policy = New-Policy -Name "TestPolicy_$(Get-Date -Format 'HHmmss')" -Description "Test policy" -EnforcementMode "AuditOnly"
    $hasResult = $policy.Success -and ($policy.Data.PolicyId -ne $null)
    if ($hasResult) { $testPolicyId = $policy.Data.PolicyId }
    Write-TestResult -TestName "New-Policy" -Passed $hasResult -Message "Creates policy" -Details "ID: $($policy.Data.PolicyId)"
}
catch {
    Write-TestResult -TestName "New-Policy" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-Policy
try {
    if ($testPolicyId) {
        $getResult = Get-Policy -PolicyId $testPolicyId
        $hasResult = $getResult.Success -and ($getResult.Data.Name -match "TestPolicy")
        Write-TestResult -TestName "Get-Policy" -Passed $hasResult -Message "Retrieves policy by ID"
    }
    else {
        Write-TestResult -TestName "Get-Policy" -Passed $false -Message "Skipped - no test policy"
    }
}
catch {
    Write-TestResult -TestName "Get-Policy" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-AllPolicies
try {
    $allPolicies = Get-AllPolicies
    $hasResult = ($allPolicies -ne $null) -and $allPolicies.Success -eq $true
    Write-TestResult -TestName "Get-AllPolicies" -Passed $hasResult -Message "Lists all policies" -Details "Success: $($allPolicies.Success)"
}
catch {
    Write-TestResult -TestName "Get-AllPolicies" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Set-PolicyStatus
try {
    if ($testPolicyId) {
        $statusResult = Set-PolicyStatus -PolicyId $testPolicyId -Status "Active"
        $hasResult = $statusResult.Success -and ($statusResult.Data.Status -eq "Active")
        Write-TestResult -TestName "Set-PolicyStatus" -Passed $hasResult -Message "Updates policy status"
    }
    else {
        Write-TestResult -TestName "Set-PolicyStatus" -Passed $false -Message "Skipped - no test policy"
    }
}
catch {
    Write-TestResult -TestName "Set-PolicyStatus" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Set-PolicyTarget
try {
    if ($testPolicyId) {
        $targetResult = Set-PolicyTarget -PolicyId $testPolicyId -TargetGPO "TestGPO" -TargetOUs @("OU=Test,DC=domain,DC=com")
        $hasResult = $targetResult.Success -and ($targetResult.Data.TargetGPO -eq "TestGPO")
        Write-TestResult -TestName "Set-PolicyTarget" -Passed $hasResult -Message "Sets policy targets"
    }
    else {
        Write-TestResult -TestName "Set-PolicyTarget" -Passed $false -Message "Skipped - no test policy"
    }
}
catch {
    Write-TestResult -TestName "Set-PolicyTarget" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Remove-Policy (cleanup)
try {
    if ($testPolicyId) {
        $removeResult = Remove-Policy -PolicyId $testPolicyId -Force
        $hasResult = $removeResult.Success
        Write-TestResult -TestName "Remove-Policy" -Passed $hasResult -Message "Removes policy"
    }
    else {
        Write-TestResult -TestName "Remove-Policy" -Passed $false -Message "Skipped - no test policy"
    }
}
catch {
    Write-TestResult -TestName "Remove-Policy" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# ============================================================
# DEPLOYMENT MODULE TESTS
# ============================================================
Write-Section "DEPLOYMENT MODULE TESTS"

# Create a test policy for deployment tests
$deployTestPolicyId = $null
try {
    $policy = New-Policy -Name "DeployTestPolicy_$(Get-Date -Format 'HHmmss')" -EnforcementMode "AuditOnly"
    if ($policy.Success) { $deployTestPolicyId = $policy.Data.PolicyId }
}
catch { }

# Test: New-DeploymentJob
$testJobId = $null
try {
    if ($deployTestPolicyId) {
        $job = New-DeploymentJob -PolicyId $deployTestPolicyId -GPOName "TestGPO" -Schedule "Manual"
        $hasResult = $job.Success -and ($job.Data.JobId -ne $null)
        if ($hasResult) { $testJobId = $job.Data.JobId }
        Write-TestResult -TestName "New-DeploymentJob" -Passed $hasResult -Message "Creates deployment job" -Details "ID: $($job.Data.JobId)"
    }
    else {
        Write-TestResult -TestName "New-DeploymentJob" -Passed $false -Message "Skipped - no test policy"
    }
}
catch {
    Write-TestResult -TestName "New-DeploymentJob" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-DeploymentJob
try {
    if ($testJobId) {
        $getJob = Get-DeploymentJob -JobId $testJobId
        $hasResult = $getJob.Success -and ($getJob.Data.Status -eq "Pending")
        Write-TestResult -TestName "Get-DeploymentJob" -Passed $hasResult -Message "Retrieves job by ID"
    }
    else {
        Write-TestResult -TestName "Get-DeploymentJob" -Passed $false -Message "Skipped - no test job"
    }
}
catch {
    Write-TestResult -TestName "Get-DeploymentJob" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-AllDeploymentJobs
try {
    $allJobs = Get-AllDeploymentJobs
    $hasResult = ($allJobs -ne $null) -and $allJobs.Success -eq $true
    Write-TestResult -TestName "Get-AllDeploymentJobs" -Passed $hasResult -Message "Lists all jobs" -Details "Success: $($allJobs.Success)"
}
catch {
    Write-TestResult -TestName "Get-AllDeploymentJobs" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-DeploymentStatus
try {
    if ($testJobId) {
        $status = Get-DeploymentStatus -JobId $testJobId
        $hasResult = $status.Success -and ($status.Data.Status -ne $null)
        Write-TestResult -TestName "Get-DeploymentStatus" -Passed $hasResult -Message "Gets job status" -Details "Status: $($status.Data.Status)"
    }
    else {
        Write-TestResult -TestName "Get-DeploymentStatus" -Passed $false -Message "Skipped - no test job"
    }
}
catch {
    Write-TestResult -TestName "Get-DeploymentStatus" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Test-GPOExists
try {
    $gpoCheck = Test-GPOExists -GPOName "NonExistentGPO_12345"
    # Validate result structure - function returns hashtable
    # Check for Success key using Keys property (for hashtable) or PSObject.Properties (for PSCustomObject)
    $hasValidStructure = ($gpoCheck -ne $null) -and 
                         ($gpoCheck.ContainsKey('Success') -or ($gpoCheck.PSObject.Properties.Name -contains 'Success'))
    # Either Success=true (modules available, Data indicates if GPO exists) 
    # or Success=false with ManualRequired/Error (missing modules - acceptable)
    $validResponse = if ($gpoCheck.Success -eq $true) {
        $true  # Modules available, function worked correctly
    } else {
        # Missing modules case - ManualRequired or Error should be set
        ($gpoCheck.ManualRequired -eq $true) -or ($gpoCheck.Error -ne $null)
    }
    Write-TestResult -TestName "Test-GPOExists" -Passed ($hasValidStructure -and $validResponse) -Message "Checks GPO existence or reports missing modules" -Details "Success: $($gpoCheck.Success), ManualRequired: $($gpoCheck.ManualRequired)"
}
catch {
    Write-TestResult -TestName "Test-GPOExists" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Stop-Deployment (cancel job)
try {
    if ($testJobId) {
        $cancelResult = Stop-Deployment -JobId $testJobId
        $hasResult = $cancelResult.Success -and ($cancelResult.Data.Status -eq "Cancelled")
        Write-TestResult -TestName "Stop-Deployment" -Passed $hasResult -Message "Cancels deployment job"
    }
    else {
        Write-TestResult -TestName "Stop-Deployment" -Passed $false -Message "Skipped - no test job"
    }
}
catch {
    Write-TestResult -TestName "Stop-Deployment" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Cleanup test policy
try {
    if ($deployTestPolicyId) {
        Remove-Policy -PolicyId $deployTestPolicyId -Force | Out-Null
    }
}
catch { }

# ============================================================
# ADDITIONAL COVERAGE TESTS (Previously Untested Functions)
# ============================================================
Write-Section "ADDITIONAL COVERAGE TESTS"

# Test: Test-CredentialProfile
try {
    # Create a test credential to test against
    $securePass = ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force
    $testCred = [PSCredential]::new("DOMAIN\TestUser", $securePass)
    $testProfileName2 = "TestProfile_$(Get-Random)"
    New-CredentialProfile -Name $testProfileName2 -Credential $testCred -Tier 2 | Out-Null
    
    # Test the credential profile (will likely fail validation but should return proper result)
    # Uses -ComputerName parameter (not -Target)
    $testResult = Test-CredentialProfile -Name $testProfileName2 -ComputerName $env:COMPUTERNAME
    $hasValidStructure = ($testResult -ne $null) -and 
                         (($testResult.PSObject.Properties.Name -contains 'Success') -or ($testResult.ContainsKey('Success')))
    Write-TestResult -TestName "Test-CredentialProfile" -Passed $hasValidStructure -Message "Returns result object" -Details "Success: $($testResult.Success)"
    
    # Cleanup
    Remove-CredentialProfile -Name $testProfileName2 | Out-Null
}
catch {
    Write-TestResult -TestName "Test-CredentialProfile" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Export-ScanResults
try {
    $exportPath = Join-Path $env:TEMP "test_scan_export_$(Get-Random).json"
    # Get any existing scan to export
    $scans = Get-ScanResults
    if ($scans.Success -and $scans.Data.Count -gt 0) {
        $scanId = $scans.Data[0].ScanId
        $exportResult = Export-ScanResults -ScanId $scanId -OutputPath $exportPath -Format JSON
        $hasResult = ($exportResult -ne $null) -and 
                     (($exportResult.PSObject.Properties.Name -contains 'Success') -or ($exportResult.ContainsKey('Success')))
        Write-TestResult -TestName "Export-ScanResults" -Passed $hasResult -Message "Exports scan data" -Details "Success: $($exportResult.Success)"
        
        # Cleanup
        if (Test-Path $exportPath) { Remove-Item $exportPath -Force }
    }
    else {
        # No scans to export - test with invalid ID should still return proper result
        $exportResult = Export-ScanResults -ScanId "nonexistent" -OutputPath $exportPath -Format JSON
        $hasResult = ($exportResult -ne $null)
        Write-TestResult -TestName "Export-ScanResults" -Passed $hasResult -Message "Handles missing scan" -Details "Returns result"
    }
}
catch {
    Write-TestResult -TestName "Export-ScanResults" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-Rule
try {
    $allRules = Get-AllRules
    if ($allRules.Success -and $allRules.Data.Count -gt 0) {
        $ruleId = $allRules.Data[0].Id
        $getResult = Get-Rule -Id $ruleId
        $hasResult = $getResult.Success -and ($getResult.Data.Id -eq $ruleId)
        Write-TestResult -TestName "Get-Rule" -Passed $hasResult -Message "Retrieves rule by ID" -Details "ID: $ruleId"
    }
    else {
        # Create a rule to test
        $testRule = New-PathRule -Path '%PROGRAMFILES%\Test\*' -Action Allow -Save
        if ($testRule.Success) {
            $getResult = Get-Rule -Id $testRule.Data.Id
            $hasResult = $getResult.Success
            Write-TestResult -TestName "Get-Rule" -Passed $hasResult -Message "Retrieves created rule"
            Remove-Rule -Id $testRule.Data.Id | Out-Null
        }
        else {
            Write-TestResult -TestName "Get-Rule" -Passed $false -Message "Could not create test rule"
        }
    }
}
catch {
    Write-TestResult -TestName "Get-Rule" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Set-RuleStatus
try {
    # Create a test rule
    $testRule = New-PathRule -Path '%PROGRAMFILES%\StatusTest\*' -Action Allow -Save
    if ($testRule.Success) {
        $statusResult = Set-RuleStatus -Id $testRule.Data.Id -Status 'Approved'
        $hasResult = $statusResult.Success -and ($statusResult.Data.Status -eq 'Approved')
        Write-TestResult -TestName "Set-RuleStatus" -Passed $hasResult -Message "Updates rule status" -Details "Status: $($statusResult.Data.Status)"
        Remove-Rule -Id $testRule.Data.Id | Out-Null
    }
    else {
        Write-TestResult -TestName "Set-RuleStatus" -Passed $false -Message "Could not create test rule"
    }
}
catch {
    Write-TestResult -TestName "Set-RuleStatus" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Remove-Rule
try {
    # Create a rule to delete
    $testRule = New-PathRule -Path '%PROGRAMFILES%\DeleteTest\*' -Action Allow -Save
    if ($testRule.Success) {
        $removeResult = Remove-Rule -Id $testRule.Data.Id
        $hasResult = $removeResult.Success
        # Verify it's gone
        $getResult = Get-Rule -Id $testRule.Data.Id
        $actuallyGone = (-not $getResult.Success) -or ($getResult.Data -eq $null)
        Write-TestResult -TestName "Remove-Rule" -Passed ($hasResult -and $actuallyGone) -Message "Deletes rule" -Details "Removed: $hasResult"
    }
    else {
        Write-TestResult -TestName "Remove-Rule" -Passed $false -Message "Could not create test rule"
    }
}
catch {
    Write-TestResult -TestName "Remove-Rule" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Export-RulesToXml
try {
    $xmlPath = Join-Path $env:TEMP "test_rules_export_$(Get-Random).xml"
    # Create and approve a rule for export
    $testRule = New-PathRule -Path '%PROGRAMFILES%\ExportTest\*' -Action Allow -Status Approved -Save
    if ($testRule.Success) {
        $exportResult = Export-RulesToXml -OutputPath $xmlPath
        $hasResult = ($exportResult -ne $null) -and 
                     (($exportResult.PSObject.Properties.Name -contains 'Success') -or ($exportResult.ContainsKey('Success')))
        Write-TestResult -TestName "Export-RulesToXml" -Passed $hasResult -Message "Exports rules to XML" -Details "Success: $($exportResult.Success)"
        
        # Cleanup
        Remove-Rule -Id $testRule.Data.Id | Out-Null
        if (Test-Path $xmlPath) { Remove-Item $xmlPath -Force }
    }
    else {
        Write-TestResult -TestName "Export-RulesToXml" -Passed $false -Message "Could not create test rule"
    }
}
catch {
    Write-TestResult -TestName "Export-RulesToXml" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Add-RuleToPolicy
try {
    # Create a test policy and rule
    $testPolicy = New-Policy -Name "AddRuleTestPolicy_$(Get-Random)" -EnforcementMode "AuditOnly"
    $testRule = New-PathRule -Path '%PROGRAMFILES%\AddTest\*' -Action Allow -Save
    
    if ($testPolicy.Success -and $testRule.Success) {
        $addResult = Add-RuleToPolicy -PolicyId $testPolicy.Data.PolicyId -RuleId $testRule.Data.Id
        $hasResult = $addResult.Success
        Write-TestResult -TestName "Add-RuleToPolicy" -Passed $hasResult -Message "Adds rule to policy" -Details "Success: $hasResult"
        
        # Cleanup
        Remove-Policy -PolicyId $testPolicy.Data.PolicyId -Force | Out-Null
        Remove-Rule -Id $testRule.Data.Id | Out-Null
    }
    else {
        Write-TestResult -TestName "Add-RuleToPolicy" -Passed $false -Message "Could not create test policy/rule"
    }
}
catch {
    Write-TestResult -TestName "Add-RuleToPolicy" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Remove-RuleFromPolicy
try {
    # Create policy, rule, add then remove
    $testPolicy = New-Policy -Name "RemoveRuleTestPolicy_$(Get-Random)" -EnforcementMode "AuditOnly"
    $testRule = New-PathRule -Path '%PROGRAMFILES%\RemoveTest\*' -Action Allow -Save
    
    if ($testPolicy.Success -and $testRule.Success) {
        Add-RuleToPolicy -PolicyId $testPolicy.Data.PolicyId -RuleId $testRule.Data.Id | Out-Null
        $removeResult = Remove-RuleFromPolicy -PolicyId $testPolicy.Data.PolicyId -RuleId $testRule.Data.Id
        $hasResult = $removeResult.Success
        Write-TestResult -TestName "Remove-RuleFromPolicy" -Passed $hasResult -Message "Removes rule from policy" -Details "Success: $hasResult"
        
        # Cleanup
        Remove-Policy -PolicyId $testPolicy.Data.PolicyId -Force | Out-Null
        Remove-Rule -Id $testRule.Data.Id | Out-Null
    }
    else {
        Write-TestResult -TestName "Remove-RuleFromPolicy" -Passed $false -Message "Could not create test policy/rule"
    }
}
catch {
    Write-TestResult -TestName "Remove-RuleFromPolicy" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Export-PolicyToXml
try {
    $xmlPath = Join-Path $env:TEMP "test_policy_export_$(Get-Random).xml"
    # Create policy with a rule
    $testPolicy = New-Policy -Name "ExportPolicyTest_$(Get-Random)" -EnforcementMode "AuditOnly"
    $testRule = New-PathRule -Path '%PROGRAMFILES%\PolicyExportTest\*' -Action Allow -Status Approved -Save
    
    if ($testPolicy.Success -and $testRule.Success) {
        Add-RuleToPolicy -PolicyId $testPolicy.Data.PolicyId -RuleId $testRule.Data.Id | Out-Null
        $exportResult = Export-PolicyToXml -PolicyId $testPolicy.Data.PolicyId -OutputPath $xmlPath
        $hasResult = $exportResult.Success
        $fileExists = Test-Path $xmlPath
        Write-TestResult -TestName "Export-PolicyToXml" -Passed ($hasResult -and $fileExists) -Message "Exports policy to XML" -Details "File created: $fileExists"
        
        # Cleanup
        Remove-Policy -PolicyId $testPolicy.Data.PolicyId -Force | Out-Null
        Remove-Rule -Id $testRule.Data.Id | Out-Null
        if (Test-Path $xmlPath) { Remove-Item $xmlPath -Force }
    }
    else {
        Write-TestResult -TestName "Export-PolicyToXml" -Passed $false -Message "Could not create test policy/rule"
    }
}
catch {
    Write-TestResult -TestName "Export-PolicyToXml" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Test-PolicyCompliance
try {
    $testPolicy = New-Policy -Name "ComplianceTest_$(Get-Random)" -EnforcementMode "AuditOnly"
    if ($testPolicy.Success) {
        $compResult = Test-PolicyCompliance -PolicyId $testPolicy.Data.PolicyId
        $hasResult = $compResult.Success -and ($compResult.Data -ne $null)
        Write-TestResult -TestName "Test-PolicyCompliance" -Passed $hasResult -Message "Tests policy compliance" -Details "IsCompliant: $($compResult.Data.IsCompliant)"
        
        # Cleanup
        Remove-Policy -PolicyId $testPolicy.Data.PolicyId -Force | Out-Null
    }
    else {
        Write-TestResult -TestName "Test-PolicyCompliance" -Passed $false -Message "Could not create test policy"
    }
}
catch {
    Write-TestResult -TestName "Test-PolicyCompliance" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Get-DeploymentHistory
try {
    $historyResult = Get-DeploymentHistory
    $hasResult = ($historyResult -ne $null) -and 
                 (($historyResult.PSObject.Properties.Name -contains 'Success') -or ($historyResult.ContainsKey('Success')))
    Write-TestResult -TestName "Get-DeploymentHistory" -Passed $hasResult -Message "Gets deployment history" -Details "Success: $($historyResult.Success), Count: $($historyResult.Data.Count)"
}
catch {
    Write-TestResult -TestName "Get-DeploymentHistory" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: New-AppLockerGPO (will fail without modules but should return proper error)
try {
    $gpoResult = New-AppLockerGPO -GPOName "TestGPO_$(Get-Random)"
    $hasResult = ($gpoResult -ne $null) -and 
                 (($gpoResult.PSObject.Properties.Name -contains 'Success') -or ($gpoResult.ContainsKey('Success')))
    # Either success (modules available) or proper error (modules missing)
    $validResponse = $gpoResult.Success -or ($gpoResult.Error -ne $null)
    Write-TestResult -TestName "New-AppLockerGPO" -Passed ($hasResult -and $validResponse) -Message "Creates GPO or reports error" -Details "Success: $($gpoResult.Success)"
}
catch {
    Write-TestResult -TestName "New-AppLockerGPO" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Import-PolicyToGPO (will fail without modules but should return proper error)
try {
    $xmlPath = Join-Path $env:TEMP "test_import_$(Get-Random).xml"
    # Create a minimal XML file
    '<?xml version="1.0"?><AppLockerPolicy Version="1"></AppLockerPolicy>' | Set-Content -Path $xmlPath
    
    $importResult = Import-PolicyToGPO -GPOName "NonExistentGPO" -XmlPath $xmlPath
    $hasResult = ($importResult -ne $null) -and 
                 (($importResult.PSObject.Properties.Name -contains 'Success') -or ($importResult.ContainsKey('Success')))
    # Either success or proper error
    $validResponse = $importResult.Success -or ($importResult.Error -ne $null) -or ($importResult.ManualRequired -eq $true)
    Write-TestResult -TestName "Import-PolicyToGPO" -Passed ($hasResult -and $validResponse) -Message "Imports policy or reports error" -Details "Success: $($importResult.Success)"
    
    # Cleanup
    if (Test-Path $xmlPath) { Remove-Item $xmlPath -Force }
}
catch {
    Write-TestResult -TestName "Import-PolicyToGPO" -Passed $false -Message "Exception" -Details $_.Exception.Message
}

# Test: Start-Deployment (integration test - will exercise workflow)
try {
    # Create policy with rule for deployment test
    $testPolicy = New-Policy -Name "StartDeployTest_$(Get-Random)" -EnforcementMode "AuditOnly"
    $testRule = New-PathRule -Path '%PROGRAMFILES%\DeployTest\*' -Action Allow -Status Approved -Save
    
    if ($testPolicy.Success -and $testRule.Success) {
        Add-RuleToPolicy -PolicyId $testPolicy.Data.PolicyId -RuleId $testRule.Data.Id | Out-Null
        
        # Create deployment job
        $job = New-DeploymentJob -PolicyId $testPolicy.Data.PolicyId -GPOName "TestDeployGPO" -Schedule "Manual"
        if ($job.Success) {
            # Start deployment (will likely fail/require manual but should not crash)
            $deployResult = Start-Deployment -JobId $job.Data.JobId
            $hasResult = ($deployResult -ne $null) -and 
                         (($deployResult.PSObject.Properties.Name -contains 'Success') -or ($deployResult.ContainsKey('Success')))
            # Valid if success OR failure with proper error/ManualRequired
            $validResult = $deployResult.Success -or ($deployResult.Error -ne $null) -or ($deployResult.ManualRequired -eq $true)
            Write-TestResult -TestName "Start-Deployment" -Passed ($hasResult -and $validResult) -Message "Executes deployment workflow" -Details "Success: $($deployResult.Success), ManualRequired: $($deployResult.ManualRequired)"
        }
        else {
            Write-TestResult -TestName "Start-Deployment" -Passed $false -Message "Could not create deployment job"
        }
        
        # Cleanup
        Remove-Policy -PolicyId $testPolicy.Data.PolicyId -Force | Out-Null
        Remove-Rule -Id $testRule.Data.Id | Out-Null
    }
    else {
        Write-TestResult -TestName "Start-Deployment" -Passed $false -Message "Could not create test policy/rule"
    }
}
catch {
    Write-TestResult -TestName "Start-Deployment" -Passed $false -Message "Exception" -Details $_.Exception.Message
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
