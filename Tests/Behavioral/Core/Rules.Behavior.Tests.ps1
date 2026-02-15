#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Behavioral Rules: ConvertFrom-Artifact' -Tag @('Behavioral','Core') {
    It 'Creates publisher rule for signed artifact' {
        $artifact = [PSCustomObject]@{
            FileName = 'signed.exe'
            FilePath = 'C:\Program Files\Test\signed.exe'
            Extension = '.exe'
            ProductName = 'SignedApp'
            ProductVersion = '1.0.0'
            Publisher = 'Test Publisher'
            PublisherName = 'O=TEST PUBLISHER'
            SignerCertificate = 'O=TEST PUBLISHER'
            IsSigned = $true
            SHA256Hash = ('A' * 64)
            FileSize = 1234
        }

        $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType Auto

        $result.Success | Should -BeTrue
        $result.Data.Count | Should -Be 1
        $result.Data[0].RuleType | Should -Be 'Publisher'
    }

    It 'Creates hash rule for unsigned artifact' {
        $artifact = [PSCustomObject]@{
            FileName = 'unsigned.exe'
            FilePath = 'C:\Program Files\Test\unsigned.exe'
            Extension = '.exe'
            ProductName = 'UnsignedApp'
            ProductVersion = '1.0.0'
            Publisher = 'Unknown'
            PublisherName = $null
            SignerCertificate = $null
            IsSigned = $false
            SHA256Hash = ('B' * 64)
            FileSize = 4321
            CollectionType = 'Exe'
        }

        $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType Auto

        if (-not $result.Success) { Write-Host "Convert Failed: $($result.Error)" }
        if ($result.Success -and $result.Data.Count -eq 0) { Write-Host "Convert Succeeded but 0 rules. Summary: $($result.Summary | Out-String)" }

        $result.Success | Should -BeTrue
        $result.Data.Count | Should -Be 1
        $result.Data[0].RuleType | Should -Be 'Hash'
    }

    It 'Normalizes legacy artifact fields into publisher-ready contract' {
        $legacy = [PSCustomObject]@{
            FileName = 'signed-app.exe'
            FilePath = 'C:\Program Files\Contoso\signed-app.exe'
            IsSigned = 'True'
            FileSize = '2048'
            SignerCertificate = 'CN=Contoso Ltd'
            PublisherName = ''
            ArtifactType = 'EXE'
        }

        $normalized = Normalize-ArtifactRecord -Artifact $legacy

        $normalized.IsSigned | Should -BeTrue
        $normalized.SizeBytes | Should -Be 2048
        $normalized.SignerCertificate | Should -Be 'CN=Contoso Ltd'
        $normalized.IsSigned.GetType().Name | Should -Be 'Boolean'
    }
}
