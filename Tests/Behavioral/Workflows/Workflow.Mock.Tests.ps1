#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $mockPath = Join-Path $PSScriptRoot '..\MockData\New-MockTestData.psm1'
    Import-Module $mockPath -Force -ErrorAction Stop
}

Describe 'Behavioral Workflow: mock artifacts to rules' -Tag @('Behavioral','Workflow') {
    It 'Groups signed artifacts into fewer publisher rules' {
        $mockArtifacts = (New-MockArtifacts -Count 12 -ComputerName 'WKS001').Data
        $artifacts = @()
        foreach ($art in $mockArtifacts) {
            $artifacts += [PSCustomObject]@{
                FileName = $art.FileName
                FilePath = $art.FilePath
                Extension = [System.IO.Path]::GetExtension($art.FileName)
                ProductName = $art.ProductName
                ProductVersion = $art.ProductVersion
                Publisher = $art.Publisher
                PublisherName = $art.Publisher
                SignerCertificate = $art.Publisher
                IsSigned = [bool]$art.Signed
                SHA256Hash = $art.SHA256Hash
                FileSize = $art.FileSize
            }
        }

        # Force array type to match param
        $artArray = [PSCustomObject[]]@($artifacts)
        $result = ConvertFrom-Artifact -Artifact $artArray -PreferredRuleType Auto

        $result.Success | Should -BeTrue
        ($result.Data.Count -le $artifacts.Count) | Should -BeTrue
        ($result.Data | Where-Object { $_.RuleType -eq 'Publisher' }).Count | Should -BeGreaterThan 0
    }
}
