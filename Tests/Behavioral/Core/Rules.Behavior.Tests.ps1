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

    It 'creates hash rules for unsigned artifacts with explicit false values' {
        $artifact = [PSCustomObject]@{
            FileName = 'false-string.exe'
            FilePath = 'C:\temp\false-string.exe'
            Extension = '.exe'
            ProductName = 'FalseString'
            ProductVersion = '1.0.0'
            Publisher = 'Some Publisher'
            PublisherName = 'CN=Some Publisher'
            SignerCertificate = 'CN=Some Publisher'
            IsSigned = 'False'
            SHA256Hash = ('1' * 64)
            FileSize = 1111
            CollectionType = 'Exe'
        }

        $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType Auto

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

    It 'Normalizes IDictionary artifact input preserving source fields' {
        $artifact = [ordered]@{
            FileName = 'dict-input.exe'
            FilePath = 'C:\Temp\dict-input.exe'
            IsSigned = '1'
            ArtifactType = 'EXE'
            FileSize = '512'
        }

        $normalized = Normalize-ArtifactRecord -Artifact $artifact

        $normalized.FileName | Should -Be 'dict-input.exe'
        $normalized.FilePath | Should -Be 'C:\Temp\dict-input.exe'
        $normalized.ArtifactType | Should -Be 'EXE'
        $normalized.IsSigned | Should -BeTrue
        $normalized.IsSigned.GetType().Name | Should -Be 'Boolean'
    }

    It 'Falls back to FileSize when SizeBytes is invalid' {
        $artifact = [PSCustomObject]@{
            FileName = 'fallback-size.exe'
            FilePath = 'C:\Temp\fallback-size.exe'
            IsSigned = $false
            SizeBytes = 'not-a-number'
            FileSize = '4096'
        }

        $normalized = Normalize-ArtifactRecord -Artifact $artifact

        $normalized.SizeBytes | Should -Be 4096
        $normalized.SizeBytes.GetType().Name | Should -Be 'Int64'
    }
}
