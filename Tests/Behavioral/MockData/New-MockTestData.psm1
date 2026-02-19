#Requires -Version 5.1
<#
.SYNOPSIS
    Mock data generator for GA-AppLocker automated testing.
.DESCRIPTION
    Generates fake domain, OUs, computers, artifacts, rules, and policies
    for testing without requiring a real AD environment.
#>

#region Domain & OU Functions
function New-MockDomainInfo {
    param([string]$DomainName = 'TESTLAB.LOCAL')
    @{
        Success = $true
        Data = @{
            DomainName = $DomainName
            NetBIOSName = $DomainName.Split('.')[0]
            DomainDN = "DC=$($DomainName.Replace('.', ',DC='))"
            ForestName = $DomainName
            DomainMode = 'Windows2016Domain'
        }
        Error = $null
    }
}

function New-MockOUTree {
    param([string]$BaseDN = 'DC=testlab,DC=local')
    @{
        Success = $true
        Data = @(
            @{ Name = 'Domain Controllers'; DN = "OU=Domain Controllers,$BaseDN"; Tier = 'T0'; MachineType = 'DomainController' }
            @{ Name = 'Tier 0 Servers'; DN = "OU=Tier 0 Servers,$BaseDN"; Tier = 'T0'; MachineType = 'Server' }
            @{ Name = 'Servers'; DN = "OU=Servers,$BaseDN"; Tier = 'T1'; MachineType = 'Server' }
            @{ Name = 'Member Servers'; DN = "OU=Member Servers,OU=Servers,$BaseDN"; Tier = 'T1'; MachineType = 'Server' }
            @{ Name = 'Application Servers'; DN = "OU=Application Servers,OU=Servers,$BaseDN"; Tier = 'T1'; MachineType = 'Server' }
            @{ Name = 'Workstations'; DN = "OU=Workstations,$BaseDN"; Tier = 'T2'; MachineType = 'Workstation' }
            @{ Name = 'IT Workstations'; DN = "OU=IT,OU=Workstations,$BaseDN"; Tier = 'T2'; MachineType = 'Workstation' }
            @{ Name = 'User Workstations'; DN = "OU=Users,OU=Workstations,$BaseDN"; Tier = 'T2'; MachineType = 'Workstation' }
        )
        Error = $null
    }
}
#endregion

#region Computer Functions
function New-MockComputers {
    param([int]$Count = 20)
    $comps = @()
    
    # Domain Controllers (T0)
    1..2 | ForEach-Object {
        $comps += @{
            Name = "DC0$_"
            DNSHostName = "DC0$_.testlab.local"
            MachineType = 'DomainController'
            Tier = 'T0'
            OperatingSystem = 'Windows Server 2022'
            Enabled = $true
            LastLogon = (Get-Date).AddDays(-$_)
        }
    }
    
    # Servers (T1) - 30% of remaining
    $serverCount = [math]::Floor(($Count - 2) * 0.3)
    1..$serverCount | ForEach-Object {
        $comps += @{
            Name = "SRV$($_.ToString('D3'))"
            DNSHostName = "SRV$($_.ToString('D3')).testlab.local"
            MachineType = 'Server'
            Tier = 'T1'
            OperatingSystem = 'Windows Server 2022'
            Enabled = $true
            LastLogon = (Get-Date).AddDays(-$_)
        }
    }
    
    # Workstations (T2) - remaining
    $wksCount = $Count - $comps.Count
    1..$wksCount | ForEach-Object {
        $comps += @{
            Name = "WKS$($_.ToString('D3'))"
            DNSHostName = "WKS$($_.ToString('D3')).testlab.local"
            MachineType = 'Workstation'
            Tier = 'T2'
            OperatingSystem = 'Windows 11 Enterprise'
            Enabled = $true
            LastLogon = (Get-Date).AddDays(-$_)
        }
    }
    
    @{ Success = $true; Data = $comps; Error = $null }
}
#endregion

#region Credential Functions
function New-MockCredentialProfile {
    param(
        [string]$Tier = 'T2',
        [string]$Name
    )
    
    $profileName = if ($Name) { $Name } else { "Mock-$Tier-Admin" }
    
    @{
        Success = $true
        Data = @{
            Id = [guid]::NewGuid().ToString()
            Name = $profileName
            Tier = $Tier
            Username = "$($profileName.ToLower())@testlab.local"
            IsDefault = $true
            Created = (Get-Date).ToString('o')
            LastUsed = (Get-Date).ToString('o')
        }
        Error = $null
    }
}
#endregion

#region Artifact Functions
function New-MockArtifacts {
    param(
        [int]$Count = 50,
        [string]$ComputerName = 'WKS001'
    )
    
    $publishers = @(
        'Microsoft Corporation',
        'Adobe Inc.',
        'Google LLC',
        'Mozilla Foundation',
        'Oracle Corporation'
    )
    
    $exeNames = @('notepad', 'calc', 'chrome', 'firefox', 'code', 'explorer', 'cmd', 'powershell', 'msiexec', 'setup')
    $dllNames = @('kernel32', 'user32', 'ntdll', 'msvcrt', 'shell32', 'advapi32', 'gdi32', 'ole32')
    
    $arts = @()
    1..$Count | ForEach-Object {
        $type = @('EXE', 'DLL', 'MSI', 'PS1') | Get-Random
        $fileName = switch ($type) {
            'EXE' { "$($exeNames | Get-Random)$_.exe" }
            'DLL' { "$($dllNames | Get-Random)$_.dll" }
            'MSI' { "setup$_.msi" }
            'PS1' { "script$_.ps1" }
        }
        
        $arts += @{
            Id = [guid]::NewGuid().ToString()
            FileName = $fileName
            FilePath = "C:\Program Files\TestApp\$fileName"
            ArtifactType = $type
            ComputerName = $ComputerName
            FileSize = Get-Random -Minimum 10000 -Maximum 10000000
            SHA256Hash = [guid]::NewGuid().ToString().Replace('-', '').ToUpper() + [guid]::NewGuid().ToString().Replace('-', '').ToUpper()
            Publisher = $publishers | Get-Random
            ProductName = "Test Application $_"
            ProductVersion = "1.0.$_"
            Signed = ($_ % 3 -ne 0)  # 2/3 are signed
            ScanDate = (Get-Date).ToString('o')
        }
    }
    
    @{ Success = $true; Data = $arts; Error = $null }
}

function New-MockScanResult {
    param(
        [string]$ComputerName = 'WKS001',
        [int]$ArtifactCount = 25
    )
    
    $artifacts = (New-MockArtifacts -Count $ArtifactCount -ComputerName $ComputerName).Data
    
    @{
        Success = $true
        Data = @{
            Id = [guid]::NewGuid().ToString()
            ComputerName = $ComputerName
            ScanDate = (Get-Date).ToString('o')
            Duration = Get-Random -Minimum 5 -Maximum 120
            TotalArtifacts = $artifacts.Count
            Artifacts = $artifacts
            Paths = @('C:\Program Files', 'C:\Program Files (x86)', 'C:\Windows\System32')
            Status = 'Completed'
        }
        Error = $null
    }
}
#endregion

#region Rule Functions
function New-MockRules {
    param(
        [array]$Artifacts,
        [string]$RuleType = 'Hash',  # Hash, Publisher, Path
        [int]$MaxRules = 20
    )
    
    $rules = @()
    $artifactsToProcess = $Artifacts | Select-Object -First $MaxRules
    
    foreach ($art in $artifactsToProcess) {
        $collectionType = switch ($art.ArtifactType) {
            'EXE' { 'Exe' }
            'DLL' { 'Dll' }
            'MSI' { 'Msi' }
            default { 'Script' }
        }
        
        $rule = @{
            Id = [guid]::NewGuid().ToString()
            Name = "Allow $($art.FileName)"
            Description = "Auto-generated rule for $($art.FileName)"
            CollectionType = $collectionType
            RuleType = $RuleType
            Action = 'Allow'
            Status = @('Pending', 'Approved', 'Approved') | Get-Random  # Bias toward approved
            SourceArtifactId = $art.Id
            SourceFileName = $art.FileName
            SourceFilePath = $art.FilePath
            Created = (Get-Date).ToString('o')
        }
        
        # Add type-specific properties
        switch ($RuleType) {
            'Hash' {
                $rule.FileHash = $art.FileHash
                $rule.HashType = 'SHA256'
            }
            'Publisher' {
                $rule.Publisher = $art.Publisher
                $rule.ProductName = $art.ProductName
                $rule.MinVersion = '0.0.0.0'
                $rule.MaxVersion = '*'
            }
            'Path' {
                $rule.Path = $art.FilePath
            }
        }
        
        $rules += $rule
    }
    
    @{ Success = $true; Data = $rules; Error = $null }
}
#endregion

#region Policy Functions
function New-MockPolicy {
    param(
        [string]$Name = 'TestPolicy',
        [string]$Description,
        [string]$MachineType = 'Workstation',
        [array]$Rules = @()
    )
    
    $desc = if ($Description) { $Description } else { "Auto-generated test policy for $MachineType" }
    
    @{
        Success = $true
        Data = @{
            Id = [guid]::NewGuid().ToString()
            Name = $Name
            Description = $desc
            MachineType = $MachineType
            Phase = 'Audit'
            Status = 'Draft'
            Rules = $Rules
            RuleCount = $Rules.Count
            ExeRuleCount = ($Rules | Where-Object { $_.CollectionType -eq 'Exe' }).Count
            DllRuleCount = ($Rules | Where-Object { $_.CollectionType -eq 'Dll' }).Count
            MsiRuleCount = ($Rules | Where-Object { $_.CollectionType -eq 'Msi' }).Count
            ScriptRuleCount = ($Rules | Where-Object { $_.CollectionType -eq 'Script' }).Count
            Created = (Get-Date).ToString('o')
            Modified = (Get-Date).ToString('o')
        }
        Error = $null
    }
}
#endregion

#region Complete Environment
function New-MockTestEnvironment {
    param(
        [int]$ComputerCount = 20,
        [int]$ArtifactsPerComputer = 10,
        [switch]$IncludeCredentials,
        [switch]$IncludeRules,
        [switch]$IncludePolicies
    )
    
    Write-Verbose "Creating mock test environment..."
    
    # Core data
    $domain = New-MockDomainInfo
    $ous = New-MockOUTree
    $comps = New-MockComputers -Count $ComputerCount
    
    # Scan results and artifacts
    $allArts = @()
    $scanResults = @()
    foreach ($c in $comps.Data) {
        $scan = New-MockScanResult -ComputerName $c.Name -ArtifactCount $ArtifactsPerComputer
        $allArts += $scan.Data.Artifacts
        $scanResults += $scan.Data
    }
    
    $result = @{
        DomainInfo = $domain.Data
        OUTree = $ous.Data
        Computers = $comps.Data
        Artifacts = $allArts
        ScanResults = $scanResults
    }
    
    # Optional credentials
    if ($IncludeCredentials) {
        $result.Credentials = @(
            (New-MockCredentialProfile -Tier 'T0').Data
            (New-MockCredentialProfile -Tier 'T1').Data
            (New-MockCredentialProfile -Tier 'T2').Data
        )
    }
    
    # Optional rules
    if ($IncludeRules -or $IncludePolicies) {
        $result.Rules = (New-MockRules -Artifacts $allArts -MaxRules 30).Data
    }
    
    # Optional policies
    if ($IncludePolicies) {
        $rules = $result.Rules
        $result.Policies = @(
            (New-MockPolicy -Name 'Workstation-Audit' -MachineType 'Workstation' -Rules ($rules | Where-Object { $_.CollectionType -eq 'Exe' })).Data
            (New-MockPolicy -Name 'Server-Audit' -MachineType 'Server' -Rules ($rules | Where-Object { $_.CollectionType -in @('Exe', 'Dll') })).Data
        )
    }
    
    return $result
}
#endregion

#region Phase 13 Workflow Fixtures
function New-MockScannerRuleWorkflowFixtures {
    param(
        [int]$ComputerCount = 3,
        [int]$ArtifactsPerComputer = 12
    )

    $computers = @((New-MockComputers -Count $ComputerCount).Data)
    $artifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
    $rules = [System.Collections.Generic.List[PSCustomObject]]::new()

    $counter = 1
    foreach ($computer in $computers) {
        for ($i = 0; $i -lt $ArtifactsPerComputer; $i++) {
            $typeCycle = @('EXE', 'DLL', 'MSI', 'PS1', 'APPX')
            $artifactType = $typeCycle[$i % $typeCycle.Count]
            $isSigned = (($counter % 2) -eq 0)

            $fileName = "artifact-$counter"
            switch ($artifactType) {
                'EXE' { $fileName = "artifact-$counter.exe" }
                'DLL' { $fileName = "artifact-$counter.dll" }
                'MSI' { $fileName = "artifact-$counter.msi" }
                'PS1' { $fileName = "artifact-$counter.ps1" }
                'APPX' { $fileName = "artifact-$counter.appx" }
            }

            $publisher = if ($isSigned) { 'Contoso Software Ltd' } else { '' }
            $productName = if ($isSigned) { 'Contoso Suite' } else { 'Unsigned Utility' }

            $artifact = [PSCustomObject]@{
                Id = [guid]::NewGuid().ToString()
                FileName = $fileName
                FilePath = "C:\Program Files\Phase13\$fileName"
                ArtifactType = $artifactType
                CollectionType = switch ($artifactType) {
                    'EXE' { 'Exe' }
                    'DLL' { 'Dll' }
                    'MSI' { 'Msi' }
                    'APPX' { 'Appx' }
                    default { 'Script' }
                }
                ComputerName = $computer.Name
                Tier = $computer.Tier
                Publisher = $publisher
                PublisherName = if ($publisher) { "CN=$publisher" } else { '' }
                SignerCertificate = if ($publisher) { "CN=$publisher" } else { '' }
                ProductName = $productName
                ProductVersion = "1.0.$counter"
                IsSigned = $isSigned
                Signed = $isSigned
                SHA256Hash = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')).ToUpperInvariant()
                FileSize = 10000 + ($counter * 10)
                Status = 'Collected'
            }
            [void]$artifacts.Add($artifact)

            $ruleStatusCycle = @('Pending', 'Approved', 'Rejected', 'Review')
            $ruleStatus = $ruleStatusCycle[$counter % $ruleStatusCycle.Count]
            $ruleType = if ($isSigned) { 'Publisher' } else { 'Hash' }

            [void]$rules.Add([PSCustomObject]@{
                Id = [guid]::NewGuid().ToString()
                Name = "Rule for $fileName"
                Description = "Generated from $($computer.Name)"
                RuleType = $ruleType
                CollectionType = $artifact.CollectionType
                Status = $ruleStatus
                Action = 'Allow'
                UserOrGroupSid = 'S-1-5-11'
                GroupName = 'Authenticated Users'
                GroupVendor = 'BuiltIn'
                PublisherName = $artifact.PublisherName
                Publisher = $artifact.Publisher
                SHA256Hash = $artifact.SHA256Hash
                HashValue = $artifact.SHA256Hash
                Path = $artifact.FilePath
                CreatedDate = (Get-Date).AddMinutes(-$counter).ToString('o')
                ModifiedDate = (Get-Date).ToString('o')
            })

            $counter++
        }
    }

    return [PSCustomObject]@{
        Computers = @($computers)
        Artifacts = @($artifacts)
        Rules = @($rules)
    }
}

function New-MockWorkflowStageFixtures {
    param(
        [ValidateSet('HappyPath', 'PartialScanFailure', 'DeployPrecheckFailure')]
        [string]$Scenario = 'HappyPath'
    )

    $base = New-MockScannerRuleWorkflowFixtures -ComputerCount 8 -ArtifactsPerComputer 10
    $selectedMachines = @($base.Computers | Select-Object -First 3)
    $artifactList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $artifactsByMachine = @($base.Artifacts | Group-Object ComputerName)
    foreach ($machineGroup in $artifactsByMachine) {
        foreach ($artifact in @($machineGroup.Group | Select-Object -First 3)) {
            [void]$artifactList.Add($artifact)
        }
    }
    $artifacts = @($artifactList | Select-Object -First 18)
    $rules = @($base.Rules | Where-Object { $_.Status -in @('Approved', 'Pending') } | Select-Object -First 14)

    $events = @(
        [PSCustomObject]@{ FilePath = $artifacts[0].FilePath; ComputerName = $selectedMachines[0].Name; EventType = 'EXE/DLL Blocked'; IsBlocked = $true; IsAudit = $false; TimeCreated = (Get-Date).AddMinutes(-3) },
        [PSCustomObject]@{ FilePath = $artifacts[1].FilePath; ComputerName = $selectedMachines[1].Name; EventType = 'EXE/DLL Would Block (Audit)'; IsBlocked = $false; IsAudit = $true; TimeCreated = (Get-Date).AddMinutes(-2) },
        [PSCustomObject]@{ FilePath = $artifacts[2].FilePath; ComputerName = $selectedMachines[2].Name; EventType = 'Script Allowed'; IsBlocked = $false; IsAudit = $false; TimeCreated = (Get-Date).AddMinutes(-1) }
    )

    $result = [ordered]@{
        Scenario = $Scenario
        Discovery = [PSCustomObject]@{
            Success = $true
            Machines = $selectedMachines
            SelectedCount = $selectedMachines.Count
        }
        Scan = [PSCustomObject]@{
            Success = $true
            Artifacts = $artifacts
            Events = $events
            FailedMachines = @()
            ArtifactCount = $artifacts.Count
        }
        Rules = [PSCustomObject]@{
            Success = $true
            Data = $rules
            ApprovedCount = @($rules | Where-Object { $_.Status -eq 'Approved' }).Count
            PendingCount = @($rules | Where-Object { $_.Status -eq 'Pending' }).Count
        }
        Policy = [PSCustomObject]@{
            Success = $true
            Data = [PSCustomObject]@{
                PolicyId = 'phase13-policy-001'
                Name = 'Phase13 Policy'
                Status = 'Draft'
                Phase = 3
                TargetGPO = 'AppLocker-Servers'
                RuleIds = @($rules | Select-Object -First 10 | ForEach-Object { $_.Id })
            }
        }
        Deploy = [PSCustomObject]@{
            Success = $true
            PrecheckPassed = $true
            Data = [PSCustomObject]@{
                JobId = 'phase13-job-001'
                Status = 'Completed'
                Message = 'Deployment completed successfully.'
                Checkpoints = @('Discovered', 'Scanned', 'RulesGenerated', 'PolicyBuilt', 'Deployed')
            }
            Error = $null
        }
    }

    if ($Scenario -eq 'PartialScanFailure') {
        $result.Scan.FailedMachines = @($selectedMachines[2].Name)
        $result.Scan.Success = $true
        $result.Scan.Artifacts = @($artifacts | Where-Object { $_.ComputerName -ne $selectedMachines[2].Name })
        $result.Scan.ArtifactCount = $result.Scan.Artifacts.Count
        $result.Deploy.Data.Message = 'Deployment completed after partial scan results.'
    }

    if ($Scenario -eq 'DeployPrecheckFailure') {
        $result.Deploy.Success = $false
        $result.Deploy.PrecheckPassed = $false
        $result.Deploy.Error = 'Target GPO is not linked or enabled.'
        $result.Deploy.Data.Status = 'Blocked'
        $result.Deploy.Data.Message = 'Deployment blocked at precheck stage.'
        $result.Deploy.Data.Checkpoints = @('Discovered', 'Scanned', 'RulesGenerated', 'PolicyBuilt', 'DeployBlocked')
    }

    return [PSCustomObject]$result
}
#endregion

# Export all functions
Export-ModuleMember -Function *
