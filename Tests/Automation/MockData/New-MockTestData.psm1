#Requires -Version 5.1
function New-MockDomainInfo {
    param([string]$DomainName = 'TESTLAB.LOCAL')
    @{ Success = $true; Data = @{ DomainName = $DomainName; NetBIOSName = $DomainName.Split('.')[0] }; Error = $null }
}
function New-MockOUTree {
    param([string]$BaseDN = 'DC=testlab,DC=local')
    @{ Success = $true; Data = @(
        @{ Name = 'Domain Controllers'; DN = "OU=Domain Controllers,$BaseDN"; Tier = 'T0' }
        @{ Name = 'Servers'; DN = "OU=Servers,$BaseDN"; Tier = 'T1' }
        @{ Name = 'Workstations'; DN = "OU=Workstations,$BaseDN"; Tier = 'T2' }
    ); Error = $null }
}
function New-MockComputers {
    param([int]$Count = 20)
    $comps = @()
    1..2 | ForEach-Object { $comps += @{ Name = "DC0$_"; MachineType = 'DomainController'; Tier = 'T0' } }
    1..([math]::Floor($Count*0.3)) | ForEach-Object { $comps += @{ Name = "SRV$($_.ToString('D3'))"; MachineType = 'Server'; Tier = 'T1' } }
    1..($Count - $comps.Count) | ForEach-Object { $comps += @{ Name = "WKS$($_.ToString('D3'))"; MachineType = 'Workstation'; Tier = 'T2' } }
    @{ Success = $true; Data = $comps; Error = $null }
}
function New-MockArtifacts {
    param([int]$Count = 50, [string]$ComputerName = 'WKS001')
    $arts = @()
    1..$Count | ForEach-Object {
        $type = @('EXE','DLL','MSI','PS1') | Get-Random
        $arts += @{ Id = [guid]::NewGuid().ToString(); FileName = "App$_.$type"; ArtifactType = $type; ComputerName = $ComputerName }
    }
    @{ Success = $true; Data = $arts; Error = $null }
}
function New-MockTestEnvironment {
    param([int]$ComputerCount = 20, [int]$ArtifactsPerComputer = 10)
    $domain = New-MockDomainInfo; $ous = New-MockOUTree; $comps = New-MockComputers -Count $ComputerCount
    $allArts = @(); foreach ($c in $comps.Data) { $allArts += (New-MockArtifacts -Count $ArtifactsPerComputer -ComputerName $c.Name).Data }
    @{ DomainInfo = $domain.Data; OUTree = $ous.Data; Computers = $comps.Data; Artifacts = $allArts }
}
Export-ModuleMember -Function *