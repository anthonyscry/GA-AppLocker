#Requires -Modules Pester

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:TestDataRoot = Join-Path $env:TEMP ("GA-AppLocker-E2E-" + [guid]::NewGuid().ToString('N'))

    function global:Get-AppLockerDataPath {
        return $script:TestDataRoot
    }

    function script:Reset-TestDataStore {
        if (Test-Path $script:TestDataRoot) {
            Remove-Item -Path $script:TestDataRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:TestDataRoot -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:TestDataRoot 'Rules') -ItemType Directory -Force | Out-Null
        Reset-RulesIndexCache
        Rebuild-RulesIndex -RulesPath (Join-Path $script:TestDataRoot 'Rules') | Out-Null
    }

    function script:New-TestHashRule {
        param(
            [string]$Name,
            [string]$Hash,
            [string]$Sid,
            [datetime]$CreatedDate
        )

        return [PSCustomObject]@{
            Id             = [guid]::NewGuid().ToString()
            Name           = $Name
            RuleType       = 'Hash'
            CollectionType = 'Exe'
            Action         = 'Allow'
            Status         = 'Pending'
            Hash           = $Hash
            UserOrGroupSid = $Sid
            CreatedDate    = $CreatedDate.ToString('o')
        }
    }
}

AfterAll {
    if (Test-Path $script:TestDataRoot) {
        Remove-Item -Path $script:TestDataRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -Path Function:\Get-AppLockerDataPath -Force -ErrorAction SilentlyContinue
}

Describe 'Meaningful E2E: critical workflows with edge cases' -Tag @('Behavioral','E2E') {
    BeforeEach {
        Reset-TestDataStore
    }

    It 'Converts mixed artifacts and saves both rule types end-to-end' {
        $artifacts = @(
            [PSCustomObject]@{
                FileName          = 'signed-app.exe'
                FilePath          = 'C:\Program Files\Contoso\signed-app.exe'
                Extension         = '.exe'
                ProductName       = 'Contoso App'
                ProductVersion    = '1.0.0.0'
                Publisher         = 'Contoso Ltd'
                PublisherName     = 'CN=Contoso Ltd'
                SignerCertificate = 'CN=Contoso Ltd'
                IsSigned          = $true
                SHA256Hash        = ('A' * 64)
                SizeBytes         = 12345
                CollectionType    = 'Exe'
            },
            [PSCustomObject]@{
                FileName          = 'unsigned-tool.exe'
                FilePath          = 'C:\Tools\unsigned-tool.exe'
                Extension         = '.exe'
                ProductName       = 'Unsigned Tool'
                ProductVersion    = '2.0.0.0'
                Publisher         = ''
                PublisherName     = ''
                SignerCertificate = ''
                IsSigned          = $false
                SHA256Hash        = ('B' * 64)
                SizeBytes         = 5555
                CollectionType    = 'Exe'
            }
        )

        $convert = ConvertFrom-Artifact -Artifact $artifacts -PreferredRuleType Auto -Save -UserOrGroupSid 'S-1-1-0'

        $convert.Success | Should -BeTrue
        $convert.Data.Count | Should -Be 2

        $types = @($convert.Data | ForEach-Object { $_.RuleType })
        $types | Should -Contain 'Publisher'
        $types | Should -Contain 'Hash'

        $stored = Get-AllRules -Take 100
        $stored.Success | Should -BeTrue
        $stored.Total | Should -Be 2
    }

    It 'Dedupes same-principal duplicates but keeps different principals even with missing index SID' {
        $hash = ('C' * 64)
        $r1 = New-TestHashRule -Name 'Rule-A-Old' -Hash $hash -Sid 'S-1-5-21-111' -CreatedDate (Get-Date).AddMinutes(-10)
        $r2 = New-TestHashRule -Name 'Rule-A-New' -Hash $hash -Sid 'S-1-5-21-111' -CreatedDate (Get-Date)
        $r3 = New-TestHashRule -Name 'Rule-B' -Hash $hash -Sid 'S-1-5-21-222' -CreatedDate (Get-Date).AddMinutes(-5)

        (Add-Rule -Rule $r1).Success | Should -BeTrue
        (Add-Rule -Rule $r2).Success | Should -BeTrue
        (Add-Rule -Rule $r3).Success | Should -BeTrue

        $indexPath = Join-Path $script:TestDataRoot 'rules-index.json'
        $index = Get-Content -Path $indexPath -Raw | ConvertFrom-Json
        foreach ($entry in $index.Rules) {
            if ($entry.Hash -eq $hash) {
                $entry.UserOrGroupSid = $null
            }
        }
        $index | ConvertTo-Json -Depth 10 | Set-Content -Path $indexPath -Encoding UTF8
        Reset-RulesIndexCache

        $dedupe = Remove-DuplicateRules -RuleType Hash -Strategy KeepOldest -Force

        $dedupe.Success | Should -BeTrue
        $dedupe.RemovedCount | Should -Be 1

        $remaining = Get-AllRules -Take 100 -FullPayload
        $remaining.Total | Should -Be 2

        $sids = @($remaining.Data | ForEach-Object { $_.UserOrGroupSid } | Sort-Object -Unique)
        $sids.Count | Should -Be 2
        $sids | Should -Contain 'S-1-5-21-111'
        $sids | Should -Contain 'S-1-5-21-222'
    }

    It 'Scans overlapping paths without duplicate artifacts' {
        $scanRoot = Join-Path $script:TestDataRoot 'ScanRoot'
        New-Item -Path $scanRoot -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $scanRoot 'a.ps1') -Value 'Write-Host a' -Encoding UTF8
        Set-Content -Path (Join-Path $scanRoot 'b.ps1') -Value 'Write-Host b' -Encoding UTF8

        $scan = Get-LocalArtifacts -Paths @($scanRoot, $scanRoot) -Extensions @('.ps1') -SkipDllScanning -SkipWshScanning

        $scan.Success | Should -BeTrue
        $scan.Data.Count | Should -Be 2

        $paths = @($scan.Data | ForEach-Object { $_.FilePath })
        (@($paths | Sort-Object -Unique)).Count | Should -Be $paths.Count
    }

    It 'Retains signer certificate in per-host CSV roundtrip so signed imports create publisher rules' {
        $scanPath = Join-Path $script:TestDataRoot 'Scans'
        if (-not (Test-Path $scanPath)) {
            New-Item -Path $scanPath -ItemType Directory -Force | Out-Null
        }

        $signedArtifact = [PSCustomObject]@{
            FileName          = 'signed-roundtrip.exe'
            FilePath          = 'C:\Program Files\Contoso\signed-roundtrip.exe'
            Extension         = '.exe'
            ArtifactType      = 'EXE'
            CollectionType    = 'Exe'
            Publisher         = 'Contoso Ltd'
            PublisherName     = 'CN=Contoso Publisher'
            ProductName       = 'Contoso RoundTrip'
            ProductVersion    = '1.2.3.4'
            FileVersion       = '1.2.3.4'
            IsSigned          = $true
            SignerCertificate = 'CN=Contoso Signer'
            SignatureStatus   = 'Valid'
            SHA256Hash        = ('D' * 64)
            FileSize          = 2048
            SizeBytes         = 2048
            ComputerName      = 'HOST1'
        }

        Mock Get-LocalArtifacts {
            return [PSCustomObject]@{
                Success = $true
                Data    = @($signedArtifact)
                Error   = $null
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Write-ScanLog { } -ModuleName GA-AppLocker.Scanning

        $scan = Start-ArtifactScan -ScanLocal

        $scan.Success | Should -BeTrue

        $csvMatches = @(
            Get-ChildItem -Path $scanPath -Filter '*_artifacts_*.csv' |
                Where-Object { $_.Name -like 'HOST1_artifacts_*.csv' } |
                Sort-Object -Property Name
        )
        $csvMatches.Count | Should -Be 1
        $csv = $csvMatches[0]
        $csv | Should -Not -BeNullOrEmpty

        $imported = @(Import-Csv -Path $csv.FullName)
        $normalizedImported = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($item in $imported) {
            [void]$normalizedImported.Add((Normalize-ArtifactRecord -Artifact $item))
        }

        $normalizedImported.Count | Should -Be 1
        $normalizedImported[0].SignerCertificate | Should -Be 'CN=Contoso Signer'
        $normalizedImported[0].PublisherName | Should -Be 'CN=Contoso Publisher'
        $normalizedImported[0].SignerCertificate | Should -Not -Be $normalizedImported[0].PublisherName

        $convert = ConvertFrom-Artifact -Artifact @($normalizedImported) -PreferredRuleType Auto
        $convert.Success | Should -BeTrue
        $convert.Data.Count | Should -Be 1
        $convert.Data[0].RuleType | Should -Be 'Publisher'
    }

    It 'Warns once on normalization exceptions during scan and keeps raw artifact fallback' {
        $artifacts = @(
            [PSCustomObject]@{
                FileName     = 'first-fail.exe'
                FilePath     = 'C:\Temp\first-fail.exe'
                Extension    = '.exe'
                ArtifactType = 'EXE'
                IsSigned     = $false
                SHA256Hash   = ('E' * 64)
                SizeBytes    = 111
            },
            [PSCustomObject]@{
                FileName     = 'second-fail.exe'
                FilePath     = 'C:\Temp\second-fail.exe'
                Extension    = '.exe'
                ArtifactType = 'EXE'
                IsSigned     = $false
                SHA256Hash   = ('F' * 64)
                SizeBytes    = 222
            }
        )

        Mock Get-LocalArtifacts {
            return [PSCustomObject]@{
                Success = $true
                Data    = $artifacts
                Error   = $null
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Normalize-ArtifactRecord { throw 'normalization blew up' } -ModuleName GA-AppLocker.Scanning
        Mock Write-ScanLog { } -ModuleName GA-AppLocker.Scanning

        $scan = Start-ArtifactScan -ScanLocal

        $scan.Success | Should -BeTrue
        $scan.Data.Count | Should -Be 2

        Assert-MockCalled Write-ScanLog -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and
            $Message -match 'Normalize-ArtifactRecord failed for artifact' -and
            $Message -match 'first-fail.exe' -and
            $Message -match 'C:\\Temp\\first-fail.exe'
        }

        Assert-MockCalled Write-ScanLog -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'DEBUG' -and
            $Message -match 'Normalize-ArtifactRecord failed; using raw artifact record' -and
            $Message -match 'second-fail.exe' -and
            $Message -match 'C:\\Temp\\second-fail.exe'
        }
    }

    It 'Uses MachineTypeTiers hashtable mapping when selecting credential tier for remote scan' {
        $machines = @(
            [PSCustomObject]@{ Hostname = 'server01'; MachineType = 'Server' }
        )

        $script:TierTestCredential = [PSCredential]::new(
            'CONTOSO\Tier1',
            (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force)
        )

        Mock Get-AppLockerConfig {
            [PSCustomObject]@{
                MachineTypeTiers = @{
                    DomainController = 0
                    Server           = 1
                    Workstation      = 2
                    Unknown          = 2
                }
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Get-CredentialForTier {
            [PSCustomObject]@{
                Success = $true
                Data    = $script:TierTestCredential
                Error   = $null
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Get-RemoteArtifacts {
            [PSCustomObject]@{
                Success    = $true
                Data       = @()
                Error      = $null
                PerMachine = @{
                    'server01' = [PSCustomObject]@{
                        Success       = $true
                        ArtifactCount = 0
                        Error         = $null
                    }
                }
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Write-ScanLog { } -ModuleName GA-AppLocker.Scanning

        $scan = Start-ArtifactScan -Machines $machines

        $scan.Success | Should -BeTrue
        Assert-MockCalled Get-CredentialForTier -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter { $Tier -eq 1 }
        Assert-MockCalled Get-RemoteArtifacts -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter { $Credential -eq $script:TierTestCredential }
    }

    It 'Uses MachineTypeTiers normalization for non-canonical DomainController values as tier 0' {
        $machines = @(
            [PSCustomObject]@{ Hostname = 'dc01'; MachineType = 'domain controller' }
        )

        $script:TierZeroCredential = [PSCredential]::new(
            'CONTOSO\Tier0',
            (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force)
        )

        Mock Get-AppLockerConfig {
            [PSCustomObject]@{
                MachineTypeTiers = @{
                    dc               = 'T0'
                    Server           = 1
                    Workstation      = 2
                    Unknown          = 2
                }
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Get-CredentialForTier {
            [PSCustomObject]@{
                Success = $true
                Data    = $script:TierZeroCredential
                Error   = $null
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Get-RemoteArtifacts {
            [PSCustomObject]@{
                Success    = $true
                Data       = @()
                Error      = $null
                PerMachine = @{
                    'dc01' = [PSCustomObject]@{
                        Success       = $true
                        ArtifactCount = 0
                        Error         = $null
                    }
                }
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Write-ScanLog { } -ModuleName GA-AppLocker.Scanning

        $scan = Start-ArtifactScan -Machines $machines

        $scan.Success | Should -BeTrue
        Assert-MockCalled Get-CredentialForTier -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter { $Tier -eq 0 }
        Assert-MockCalled Get-RemoteArtifacts -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter { $Credential -eq $script:TierZeroCredential }
        Assert-MockCalled Get-CredentialForTier -ModuleName GA-AppLocker.Scanning -Times 0 -Exactly -ParameterFilter { $Tier -eq 1 }
        Assert-MockCalled Get-CredentialForTier -ModuleName GA-AppLocker.Scanning -Times 0 -Exactly -ParameterFilter { $Tier -eq 2 }
    }

    It 'Accepts legacy T0/T1/T2 MachineTypeTiers values for credential selection' {
        $machines = @(
            [PSCustomObject]@{ Hostname = 'server02'; MachineType = 'Server' }
        )

        $script:TierStringCredential = [PSCredential]::new(
            'CONTOSO\Tier1',
            (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force)
        )

        Mock Get-AppLockerConfig {
            [PSCustomObject]@{
                MachineTypeTiers = [PSCustomObject]@{
                    DomainController = 'T0'
                    Server           = 'T1'
                    Workstation      = 'T2'
                    Unknown          = 'T2'
                }
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Get-CredentialForTier {
            [PSCustomObject]@{
                Success = $true
                Data    = $script:TierStringCredential
                Error   = $null
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Get-RemoteArtifacts {
            [PSCustomObject]@{
                Success    = $true
                Data       = @()
                Error      = $null
                PerMachine = @{
                    'server02' = [PSCustomObject]@{
                        Success       = $true
                        ArtifactCount = 0
                        Error         = $null
                    }
                }
            }
        } -ModuleName GA-AppLocker.Scanning
        Mock Write-ScanLog { } -ModuleName GA-AppLocker.Scanning

        $scan = Start-ArtifactScan -Machines $machines

        $scan.Success | Should -BeTrue
        Assert-MockCalled Get-CredentialForTier -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter { $Tier -eq 1 }
        Assert-MockCalled Get-RemoteArtifacts -ModuleName GA-AppLocker.Scanning -Times 1 -Exactly -ParameterFilter { $Credential -eq $script:TierStringCredential }
    }

    It 'Handles connectivity edge inputs without throwing and returns stable summary' {
        $machines = @(
            $null,
            [PSCustomObject]@{ Hostname = '' },
            [PSCustomObject]@{ Hostname = 'bad&name' },
            [PSCustomObject]@{ Hostname = 'bad&name' }
        )

        $connect = Test-MachineConnectivity -Machines $machines -TestWinRM:$false -TimeoutSeconds 1 -ThrottleLimit 4

        $connect.Success | Should -BeTrue
        $connect.Data.Count | Should -Be 3
        $connect.Summary.TotalMachines | Should -Be 3
        $connect.Data[0].PSObject.Properties.Name | Should -Contain 'IsOnline'
    }
}
