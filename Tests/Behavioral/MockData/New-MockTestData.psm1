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

# Export all functions
Export-ModuleMember -Function *
