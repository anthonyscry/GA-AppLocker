#Requires -Modules Pester

BeforeAll {
    $categorizePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Invoke-AppLockerEventCategorization.ps1'
    $candidatesPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Get-AppLockerRuleCandidates.ps1'

    if (Test-Path $categorizePath) {
        . $categorizePath
    }

    if (Test-Path $candidatesPath) {
        . $candidatesPath
    }

    if (-not (Get-Command -Name 'Write-ScanLog' -ErrorAction SilentlyContinue)) {
        function global:Write-ScanLog {
            param([string]$Message, [string]$Level = 'Info')
        }
    }

    function script:New-TestEvent {
        param(
            [string]$FilePath,
            [string]$ComputerName = 'WS01',
            [string]$Hash,
            [string]$PublisherName,
            [string]$ProductName,
            [bool]$IsBlocked = $false,
            [bool]$IsAudit = $false,
            [int]$EventId = 8002,
            [datetime]$TimeCreated = (Get-Date)
        )

        [PSCustomObject]@{
            FilePath      = $FilePath
            ComputerName  = $ComputerName
            SHA256Hash    = $Hash
            PublisherName = $PublisherName
            Publisher     = $PublisherName
            ProductName   = $ProductName
            BinaryName    = [System.IO.Path]::GetFileName($FilePath)
            FileName      = [System.IO.Path]::GetFileName($FilePath)
            IsBlocked     = $IsBlocked
            IsAudit       = $IsAudit
            EventId       = $EventId
            TimeCreated   = $TimeCreated
            Action        = if ($IsBlocked -or $IsAudit) { 'Deny' } else { 'Allow' }
            SignatureStatus = if ($PublisherName) { 'Valid' } else { 'NotSigned' }
            IsSigned      = [bool]$PublisherName
        }
    }
}

Describe 'Behavioral Bundle B: Event categorization foundations' -Tag @('Behavioral', 'Core') {
    It 'Categorizes covered blocked events as KnownGood' {
        $events = @(
            New-TestEvent -FilePath 'C:\Windows\System32\cmd.exe' -Hash ('A' * 64) -PublisherName 'O=MICROSOFT' -ProductName 'Windows' -IsBlocked $true -EventId 8002
        )

        $rules = @(
            [PSCustomObject]@{
                Id             = 'rule-allow-hash'
                RuleType       = 'Hash'
                Hash           = ('A' * 64)
                Action         = 'Allow'
                CollectionType = 'Exe'
                UserOrGroupSid = 'S-1-1-0'
                Status         = 'Approved'
            }
        )

        $result = Invoke-AppLockerEventCategorization -Events $events -Rules $rules

        $result.Success | Should -BeTrue
        $result.Data.Events[0].CoverageStatus | Should -Be 'Covered'
        $result.Data.Events[0].Category | Should -Be 'KnownGood'
    }

    It 'Categorizes uncovered blocked events as KnownBad' {
        $events = @(
            New-TestEvent -FilePath 'C:\Temp\unknown.exe' -Hash ('B' * 64) -IsBlocked $true -EventId 8002
        )

        $result = Invoke-AppLockerEventCategorization -Events $events -Rules @()

        $result.Success | Should -BeTrue
        $result.Data.Events[0].CoverageStatus | Should -Be 'Uncovered'
        $result.Data.Events[0].Category | Should -Be 'KnownBad'
        $result.Data.Summary.KnownBadCount | Should -Be 1
    }

    It 'Categorizes uncovered audit events as NeedsReview' {
        $events = @(
            New-TestEvent -FilePath 'C:\Users\bob\Downloads\newtool.exe' -Hash ('C' * 64) -IsAudit $true -EventId 8003
        )

        $result = Invoke-AppLockerEventCategorization -Events $events -Rules @()

        $result.Success | Should -BeTrue
        $result.Data.Events[0].Category | Should -Be 'NeedsReview'
        $result.Data.Summary.NeedsReviewCount | Should -Be 1
    }
}

Describe 'Behavioral Bundle B: Rule candidate scoring foundations' -Tag @('Behavioral', 'Core') {
    It 'Groups recurring events into a single candidate with recurrence and machine counts' {
        $events = @(
            (New-TestEvent -FilePath 'C:\Program Files\Contoso\agent.exe' -Hash ('D' * 64) -PublisherName 'O=CONTOSO' -ProductName 'Agent' -IsBlocked $true -ComputerName 'WS01')
            (New-TestEvent -FilePath 'C:\Program Files\Contoso\agent.exe' -Hash ('D' * 64) -PublisherName 'O=CONTOSO' -ProductName 'Agent' -IsBlocked $true -ComputerName 'WS02')
            (New-TestEvent -FilePath 'C:\Program Files\Contoso\agent.exe' -Hash ('D' * 64) -PublisherName 'O=CONTOSO' -ProductName 'Agent' -IsBlocked $true -ComputerName 'WS03')
        )

        $result = Get-AppLockerRuleCandidates -Events $events -MinimumRecurrenceCount 2 -MinimumConfidenceScore 0

        $result.Success | Should -BeTrue
        $result.Data.Candidates.Count | Should -Be 1
        $result.Data.Candidates[0].RecurrenceCount | Should -Be 3
        $result.Data.Candidates[0].MachineCount | Should -Be 3
    }

    It 'Skips covered candidates when SkipCoveredCandidates is enabled' {
        $events = @(
            [PSCustomObject](New-TestEvent -FilePath 'C:\Windows\System32\notepad.exe' -Hash ('E' * 64) -PublisherName 'O=MICROSOFT' -ProductName 'Windows' -IsBlocked $true -ComputerName 'WS01' | Select-Object *),
            [PSCustomObject](New-TestEvent -FilePath 'C:\Temp\tool.exe' -Hash ('F' * 64) -IsBlocked $true -ComputerName 'WS01' | Select-Object *)
        )

        $events[0] | Add-Member -NotePropertyName CoverageStatus -NotePropertyValue 'Covered' -Force
        $events[1] | Add-Member -NotePropertyName CoverageStatus -NotePropertyValue 'Uncovered' -Force

        $result = Get-AppLockerRuleCandidates -Events $events -SkipCoveredCandidates -MinimumRecurrenceCount 1 -MinimumConfidenceScore 0

        $result.Success | Should -BeTrue
        $result.Data.Candidates.Count | Should -Be 1
        $result.Data.Candidates[0].CorrelationKey | Should -Match 'F'
    }
}
