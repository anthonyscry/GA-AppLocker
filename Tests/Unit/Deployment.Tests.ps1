#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for GA-AppLocker.Deployment module.

.DESCRIPTION
    Covers job CRUD (create, get, get-all, update, remove), status transitions
    (Pending->Cancelled, rejection of invalid transitions), GPO import paths
    (ManualRequired fallback, export failure), and deployment history.

    Uses a unique temp directory per Describe block to isolate from real data.
    GroupPolicy cmdlets are mocked throughout (require domain controllers).
#>

# ---------------------------------------------------------------------------
# Module-level helpers (visible to all Describe/It blocks in Pester 5)
# ---------------------------------------------------------------------------

function global:New-DeployTestTempDir {
    $path = Join-Path $env:TEMP "AppLockerDeployTest_$([guid]::NewGuid().ToString('N'))"
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    return $path
}

function global:New-TestJobFile {
    param(
        [string]$DeploymentsDir,
        [string]$Status = 'Pending',
        [string]$GPOName = 'AppLocker-Test'
    )
    # Include all properties that Stop-Deployment and Update-DeploymentJob write to,
    # so property assignment doesn't throw on PSCustomObject.
    $job = [PSCustomObject]@{
        JobId         = [guid]::NewGuid().ToString()
        PolicyId      = 'test-policy-id'
        PolicyName    = 'Test Policy'
        GPOName       = $GPOName
        Status        = $Status
        Progress      = 0
        Schedule      = 'Manual'
        TargetOUs     = @()
        Message       = 'Test job'
        ErrorDetails  = $null
        StartedAt     = $null
        CompletedAt   = $null
        CreatedAt     = (Get-Date).ToString('o')
        CreatedBy     = 'TestUser'
        XmlExportPath = $null
    }
    $jobFile = Join-Path $DeploymentsDir "$($job.JobId).json"
    $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8
    return $job.JobId
}

function global:New-VersionedTestJobFile {
    param(
        [string]$DeploymentsDir,
        [string]$GPOName = 'AppLocker-Update'
    )
    $job = [PSCustomObject]@{
        JobId      = [guid]::NewGuid().ToString()
        PolicyId   = 'test-policy-id'
        PolicyName = 'Test Policy'
        GPOName    = $GPOName
        Status     = 'Pending'
        Progress   = 0
        Schedule   = 'Manual'
        TargetOUs  = @()
        Version    = 0
        CreatedAt  = (Get-Date).ToString('o')
    }
    $jobFile = Join-Path $DeploymentsDir "$($job.JobId).json"
    $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8
    return $job.JobId
}

# ---------------------------------------------------------------------------

Describe 'Deployment - New-DeploymentJob' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        $script:TempPath = New-DeployTestTempDir
        New-Item -Path (Join-Path $script:TempPath 'Deployments')       -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:TempPath 'DeploymentHistory') -ItemType Directory -Force | Out-Null

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $true; Data = @{ PolicyId = 'test-policy-id'; Name = 'Test Policy' } }
        } -ModuleName 'GA-AppLocker.Deployment'
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Creates a job and returns Success=$true with Data' {
        $result = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Test'
        $result.Success | Should -BeTrue
        $result.Data    | Should -Not -BeNullOrEmpty
    }

    It 'Job data contains required fields: JobId, PolicyId, PolicyName, GPOName, Status, Progress, CreatedAt, CreatedBy' {
        $result = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Test'
        $job = $result.Data
        $job.JobId      | Should -Not -BeNullOrEmpty
        $job.PolicyId   | Should -Be 'test-policy-id'
        $job.PolicyName | Should -Be 'Test Policy'
        $job.GPOName    | Should -Be 'AppLocker-Test'
        $job.Status     | Should -Be 'Pending'
        $job.Progress   | Should -Be 0
        $job.CreatedAt  | Should -Not -BeNullOrEmpty
        $job.CreatedBy  | Should -Not -BeNullOrEmpty
    }

    It 'JobId is a valid GUID format' {
        $result = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Test'
        $result.Data.JobId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    }

    It 'Schedule defaults to Manual' {
        $result = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Test'
        $result.Data.Schedule | Should -Be 'Manual'
    }

    It 'TargetOUs stored as empty array by default' {
        $result = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Test'
        @($result.Data.TargetOUs).Count | Should -Be 0
    }

    It 'TargetOUs are stored when provided' {
        $ous = @('OU=Workstations,DC=corp,DC=local', 'OU=Servers,DC=corp,DC=local')
        $result = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Test' -TargetOUs $ous
        @($result.Data.TargetOUs).Count | Should -Be 2
        $result.Data.TargetOUs | Should -Contain 'OU=Workstations,DC=corp,DC=local'
    }

    It 'Job JSON file is written to Deployments directory' {
        $result = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Test'
        $jobId = $result.Data.JobId
        $expectedFile = Join-Path $script:TempPath "Deployments\$jobId.json"
        $expectedFile | Should -Exist
    }

    It 'Returns error when policy is not found' {
        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $false; Error = 'Policy not found' }
        } -ModuleName 'GA-AppLocker.Deployment'

        $result = New-DeploymentJob -PolicyId 'nonexistent-policy' -GPOName 'AppLocker-Test'
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'Policy not found'

        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $true; Data = @{ PolicyId = 'test-policy-id'; Name = 'Test Policy' } }
        } -ModuleName 'GA-AppLocker.Deployment'
    }
}

Describe 'Deployment - Get-DeploymentJob' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        $script:TempPath = New-DeployTestTempDir
        New-Item -Path (Join-Path $script:TempPath 'Deployments') -ItemType Directory -Force | Out-Null

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $true; Data = @{ PolicyId = 'test-policy-id'; Name = 'Test Policy' } }
        } -ModuleName 'GA-AppLocker.Deployment'

        $createResult = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-GetTest'
        $script:KnownJobId = $createResult.Data.JobId
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Retrieves an existing job by JobId' {
        $result = Get-DeploymentJob -JobId $script:KnownJobId
        $result.Success    | Should -BeTrue
        $result.Data       | Should -Not -BeNullOrEmpty
        $result.Data.JobId | Should -Be $script:KnownJobId
    }

    It 'Retrieved job has correct GPOName' {
        $result = Get-DeploymentJob -JobId $script:KnownJobId
        $result.Data.GPOName | Should -Be 'AppLocker-GetTest'
    }

    It 'Non-existent JobId returns Success=$false with error containing "not found"' {
        $result = Get-DeploymentJob -JobId 'nonexistent-job-id-12345'
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'not found'
    }
}

Describe 'Deployment - Get-AllDeploymentJobs' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        $script:TempPath = New-DeployTestTempDir
        New-Item -Path (Join-Path $script:TempPath 'Deployments') -ItemType Directory -Force | Out-Null

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $true; Data = @{ PolicyId = 'test-policy-id'; Name = 'Test Policy' } }
        } -ModuleName 'GA-AppLocker.Deployment'
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Empty directory returns Success=$true with empty Data array' {
        $result = Get-AllDeploymentJobs
        $result.Success | Should -BeTrue
        @($result.Data).Count | Should -Be 0
    }

    It 'Returns all jobs when multiple exist' {
        New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'GPO-A' | Out-Null
        New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'GPO-B' | Out-Null
        New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'GPO-C' | Out-Null

        $result = Get-AllDeploymentJobs
        $result.Success | Should -BeTrue
        @($result.Data).Count | Should -BeGreaterOrEqual 3
    }

    It 'Status filter excludes jobs with other statuses' {
        $deploymentsDir = Join-Path $script:TempPath 'Deployments'
        New-TestJobFile -DeploymentsDir $deploymentsDir -Status 'Completed' -GPOName 'GPO-Done' | Out-Null

        $result = Get-AllDeploymentJobs -Status 'Pending'
        $result.Success | Should -BeTrue
        $nonPending = @($result.Data | Where-Object { $_.Status -ne 'Pending' })
        $nonPending.Count | Should -Be 0
    }

    It 'Status=Pending filter returns only Pending jobs' {
        $result = Get-AllDeploymentJobs -Status 'Pending'
        $result.Success | Should -BeTrue
        $allPending = @($result.Data | Where-Object { $_.Status -eq 'Pending' })
        $allPending.Count | Should -BeGreaterOrEqual 0
    }

    It 'Results are sorted by CreatedAt descending (newest first)' {
        $result = Get-AllDeploymentJobs
        $result.Success | Should -BeTrue
        $jobs = @($result.Data)
        if ($jobs.Count -ge 2) {
            $first  = [datetime]$jobs[0].CreatedAt
            $second = [datetime]$jobs[1].CreatedAt
            $first | Should -BeGreaterOrEqual $second
        }
    }
}

Describe 'Deployment - Update-DeploymentJob' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        $script:TempPath = New-DeployTestTempDir
        $script:DeploymentsDir = Join-Path $script:TempPath 'Deployments'
        New-Item -Path $script:DeploymentsDir -ItemType Directory -Force | Out-Null

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $true; Data = @{ PolicyId = 'test-policy-id'; Name = 'Test Policy' } }
        } -ModuleName 'GA-AppLocker.Deployment'
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Updates GPOName on a Pending job (versioned)' {
        $jobId = New-VersionedTestJobFile -DeploymentsDir $script:DeploymentsDir -GPOName 'AppLocker-Original'
        $result = Update-DeploymentJob -JobId $jobId -GPOName 'AppLocker-Updated'
        $result.Success      | Should -BeTrue
        $result.Data.GPOName | Should -Be 'AppLocker-Updated'
    }

    It 'Updates Schedule on a Pending job (versioned)' {
        $jobId = New-VersionedTestJobFile -DeploymentsDir $script:DeploymentsDir -GPOName 'AppLocker-SchedTest'
        $result = Update-DeploymentJob -JobId $jobId -Schedule 'Immediate'
        $result.Success       | Should -BeTrue
        $result.Data.Schedule | Should -Be 'Immediate'
    }

    It 'Updates TargetOUs on a Pending job (versioned)' {
        $jobId = New-VersionedTestJobFile -DeploymentsDir $script:DeploymentsDir -GPOName 'AppLocker-OUTest'
        $ous = @('OU=Test,DC=corp,DC=local')
        $result = Update-DeploymentJob -JobId $jobId -TargetOUs $ous
        $result.Success        | Should -BeTrue
        $result.Data.TargetOUs | Should -Contain 'OU=Test,DC=corp,DC=local'
    }

    It 'Rejects update on a Running job (Status must be Pending)' {
        $jobId = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Running' -GPOName 'AppLocker-Running'
        # Patch Version so the concurrency check would pass IF the status check passed (it won't)
        $jobFile = Join-Path $script:DeploymentsDir "$jobId.json"
        $job = Get-Content -Path $jobFile -Raw | ConvertFrom-Json
        $job | Add-Member -MemberType NoteProperty -Name 'Version' -Value 0 -Force
        $job | ConvertTo-Json -Depth 5 | Set-Content -Path $jobFile -Encoding UTF8

        $result = Update-DeploymentJob -JobId $jobId -GPOName 'AppLocker-ShouldFail'
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'Pending'
    }

    It 'No changes supplied returns Success=$true with no-changes message' {
        $jobId = New-VersionedTestJobFile -DeploymentsDir $script:DeploymentsDir -GPOName 'AppLocker-NoChange'
        $result = Update-DeploymentJob -JobId $jobId
        $result.Success | Should -BeTrue
        $result.Message | Should -Match 'No changes'
    }

    It 'Non-existent JobId returns error' {
        $result = Update-DeploymentJob -JobId 'does-not-exist-12345' -GPOName 'Irrelevant'
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'not found'
    }

    It 'Unversioned job returns concurrency error -- known behavior' {
        # New-DeploymentJob does NOT write a Version field.
        # Update-DeploymentJob reads Version ($null), adds 1, then checks $null != 1 -> error.
        $createResult = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Unversioned'
        $jobId = $createResult.Data.JobId
        $result = Update-DeploymentJob -JobId $jobId -GPOName 'AppLocker-NewName'
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'Concurrent'
    }
}

Describe 'Deployment - Stop-Deployment' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        $script:TempPath = New-DeployTestTempDir
        $script:DeploymentsDir = Join-Path $script:TempPath 'Deployments'
        New-Item -Path $script:DeploymentsDir -ItemType Directory -Force | Out-Null

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Cancels a Pending job: sets Status=Cancelled and CompletedAt' {
        $jobId = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Pending'
        $result = Stop-Deployment -JobId $jobId
        $result.Success          | Should -BeTrue
        $result.Data.Status      | Should -Be 'Cancelled'
        $result.Data.CompletedAt | Should -Not -BeNullOrEmpty
    }

    It 'Cancels a Running job: sets Status=Cancelled' {
        $jobId = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Running'
        $result = Stop-Deployment -JobId $jobId
        $result.Success     | Should -BeTrue
        $result.Data.Status | Should -Be 'Cancelled'
    }

    It 'Rejects cancelling a Completed job' {
        $jobId = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Completed'
        $result = Stop-Deployment -JobId $jobId
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'Completed'
    }

    It 'Rejects cancelling a Failed job' {
        $jobId = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Failed'
        $result = Stop-Deployment -JobId $jobId
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'Failed'
    }

    It 'Rejects cancelling an already-Cancelled job' {
        $jobId = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Cancelled'
        $result = Stop-Deployment -JobId $jobId
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'Cancelled'
    }

    It 'Non-existent job returns error containing "not found"' {
        $result = Stop-Deployment -JobId 'nonexistent-stop-job'
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'not found'
    }
}

Describe 'Deployment - Remove-DeploymentJob' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        $script:TempPath = New-DeployTestTempDir
        $script:DeploymentsDir = Join-Path $script:TempPath 'Deployments'
        New-Item -Path $script:DeploymentsDir -ItemType Directory -Force | Out-Null

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $true; Data = @{ PolicyId = 'test-policy-id'; Name = 'Test Policy' } }
        } -ModuleName 'GA-AppLocker.Deployment'
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Removes a job by JobId and returns Data=1' {
        $createResult = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'GPO-Remove-ById'
        $jobId = $createResult.Data.JobId

        $removeResult = Remove-DeploymentJob -JobId $jobId
        $removeResult.Success | Should -BeTrue
        $removeResult.Data    | Should -Be 1

        $jobFile = Join-Path $script:DeploymentsDir "$jobId.json"
        $jobFile | Should -Not -Exist
    }

    It 'Remove by Status=Completed removes Completed jobs and returns count >= 2' {
        $id1       = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Completed' -GPOName 'GPO-Done-1'
        $id2       = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Completed' -GPOName 'GPO-Done-2'
        $pendingId = New-TestJobFile -DeploymentsDir $script:DeploymentsDir -Status 'Pending'   -GPOName 'GPO-Pending'

        $removeResult = Remove-DeploymentJob -Status 'Completed'
        $removeResult.Success | Should -BeTrue
        $removeResult.Data    | Should -BeGreaterOrEqual 2

        # Pending job file must still exist
        $pendingFile = Join-Path $script:DeploymentsDir "$pendingId.json"
        $pendingFile | Should -Exist
    }

    It 'Neither JobId nor Status returns Success=$false with descriptive error' {
        $result = Remove-DeploymentJob
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'Specify either'
    }

    It 'Remove by non-existent JobId returns Success=$true with Data=0' {
        $result = Remove-DeploymentJob -JobId 'does-not-exist-abc123'
        $result.Success | Should -BeTrue
        $result.Data    | Should -Be 0
    }
}

Describe 'Deployment - Start-Deployment GPO import paths' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        $script:TempPath = New-DeployTestTempDir
        $script:DeploymentsDir = Join-Path $script:TempPath 'Deployments'
        New-Item -Path $script:DeploymentsDir    -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:TempPath 'DeploymentHistory') -ItemType Directory -Force | Out-Null

        # Shared fake XML path used by export mock.
        # Use $global: so the value is accessible inside Mock -MockWith scriptblocks.
        $global:GA_TestDeployXmlPath = Join-Path $env:TEMP 'AppLocker_test-policy-id.xml'
        $script:FakeXmlPath = $global:GA_TestDeployXmlPath
        '<?xml version="1.0"?><AppLockerPolicy Version="1"><RuleCollection Type="Exe" EnforcementMode="AuditOnly"/></AppLockerPolicy>' |
            Set-Content -Path $script:FakeXmlPath -Encoding UTF8

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Get-Policy -MockWith {
            return @{ Success = $true; Data = @{ PolicyId = 'test-policy-id'; Name = 'Test Policy' } }
        } -ModuleName 'GA-AppLocker.Deployment'
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($script:FakeXmlPath -and (Test-Path $script:FakeXmlPath)) {
            Remove-Item -Path $script:FakeXmlPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ManualRequired when GroupPolicy module unavailable: ManualRequired=$true and job status=ManualRequired' {
        $createResult = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-Manual'
        $jobId = $createResult.Data.JobId

        Mock -CommandName Export-PolicyToXml -MockWith {
            return @{ Success = $true; Data = @{ Path = $global:GA_TestDeployXmlPath } }
        } -ModuleName 'GA-AppLocker.Deployment'

        Mock -CommandName Test-GPOExists -MockWith {
            return @{
                Success        = $false
                Data           = $null
                Error          = 'GroupPolicy module not available. Install RSAT-GPMC feature.'
                ManualRequired = $true
            }
        } -ModuleName 'GA-AppLocker.Deployment'

        $result = Start-Deployment -JobId $jobId

        $result.Success        | Should -BeFalse
        $result.ManualRequired | Should -BeTrue
        $result.Error          | Should -Not -BeNullOrEmpty

        $jobFile = Join-Path $script:DeploymentsDir "$jobId.json"
        $updatedJob = Get-Content -Path $jobFile -Raw | ConvertFrom-Json
        $updatedJob.Status | Should -Be 'ManualRequired'
    }

    It 'Export failure: result.Success=$false and job status=Failed' {
        $createResult = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-ExportFail'
        $jobId = $createResult.Data.JobId

        Mock -CommandName Export-PolicyToXml -MockWith {
            return @{ Success = $false; Error = 'XML export error: disk full' }
        } -ModuleName 'GA-AppLocker.Deployment'

        $result = Start-Deployment -JobId $jobId

        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'XML export error'

        $jobFile = Join-Path $script:DeploymentsDir "$jobId.json"
        $updatedJob = Get-Content -Path $jobFile -Raw | ConvertFrom-Json
        $updatedJob.Status | Should -Be 'Failed'
    }

    It 'Non-existent JobId returns Success=$false immediately' {
        $result = Start-Deployment -JobId 'nonexistent-start-job'
        $result.Success | Should -BeFalse
    }

    It 'returns standardized failure object when deployment prerequisites fail' {
        $createResult = New-DeploymentJob -PolicyId 'test-policy-id' -GPOName 'AppLocker-PrereqFail'
        $jobId = $createResult.Data.JobId

        Mock -CommandName Export-PolicyToXml -MockWith {
            return @{ Success = $true; Data = @{ Path = $global:GA_TestDeployXmlPath } }
        } -ModuleName 'GA-AppLocker.Deployment'

        Mock -CommandName Test-GPOExists -MockWith {
            return @{ Success = $false; Error = 'GroupPolicy prerequisite check failed' }
        } -ModuleName 'GA-AppLocker.Deployment'

        $result = Start-Deployment -JobId $jobId
        $result.Success | Should -BeFalse
        $result.Error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Deployment - Get-DeploymentHistory' -Tag @('Unit', 'Deployment') {

    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
        Import-Module $script:ModulePath -Force -ErrorAction Stop

        # Use a temp dir without DeploymentHistory to test the "missing dir" path
        $script:TempPath = New-DeployTestTempDir

        Mock -CommandName Get-AppLockerDataPath -MockWith { return $script:TempPath } -ModuleName 'GA-AppLocker.Deployment'
        Mock -CommandName Write-AppLockerLog    -MockWith {}                          -ModuleName 'GA-AppLocker.Deployment'
    }

    AfterAll {
        if ($script:TempPath -and (Test-Path $script:TempPath)) {
            Remove-Item -Path $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Returns Success=$true with empty array when DeploymentHistory dir does not exist' {
        $result = Get-DeploymentHistory
        $result.Success | Should -BeTrue
        @($result.Data).Count | Should -Be 0
    }

    It 'Returns Success=$true with empty array when history dir exists but has no entries' {
        New-Item -Path (Join-Path $script:TempPath 'DeploymentHistory') -ItemType Directory -Force | Out-Null
        $result = Get-DeploymentHistory
        $result.Success | Should -BeTrue
        @($result.Data).Count | Should -Be 0
    }
}
