#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Import-RulesFromXml filename resolution and Export->Import roundtrip.

.DESCRIPTION
    Tests the v1.2.15 fixes for "Unknown (Hash)" rule names:
    - Import-RulesFromXml robust filename fallback chain
    - Export-PolicyToXml SourceFileName extraction from Name field
    - Export -> Import roundtrip preserves filenames

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\ImportExport.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Test data path
    $script:TestDataPath = Join-Path $env:TEMP "GA-AppLocker-ImportExportTests-$(Get-Random)"
    New-Item -Path $script:TestDataPath -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup test data
    if (Test-Path $script:TestDataPath) {
        Remove-Item -Path $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Import-RulesFromXml - Filename Fallback Chain (v1.2.15)' -Tag 'Unit', 'Rules', 'Import' {

    Context 'When SourceFileName is empty but Rule Name has filename' {
        It 'Should extract filename from FileHashRule Name attribute' {
            $xmlContent = @'
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FileHashRule Id="{11111111-1111-1111-1111-111111111111}" Name="notepad.exe" Description="Test" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" SourceFileName="" SourceFileLength="1024" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
</AppLockerPolicy>
'@
            $xmlPath = Join-Path $script:TestDataPath 'test-name-fallback.xml'
            $xmlContent | Set-Content -Path $xmlPath -Encoding UTF8

            $result = Import-RulesFromXml -Path $xmlPath
            $result.Success | Should -BeTrue
            # Data is a List of imported rule objects
            @($result.Data).Count | Should -BeGreaterThan 0

            # The rule should have extracted "notepad.exe" from the Name attribute
            $importedRule = @($result.Data) | Select-Object -First 1
            $importedRule.SourceFileName | Should -Be 'notepad.exe'
            $importedRule.Name | Should -Be 'notepad.exe (Hash)'
        }
    }

    Context 'When SourceFileName is "Unknown" in XML' {
        It 'Should fall back to Rule Name attribute instead of using Unknown' {
            $xmlContent = @'
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FileHashRule Id="{22222222-2222-2222-2222-222222222222}" Name="calc.exe (Hash)" Description="Imported rule" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB" SourceFileName="Unknown" SourceFileLength="2048" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
</AppLockerPolicy>
'@
            $xmlPath = Join-Path $script:TestDataPath 'test-unknown-fallback.xml'
            $xmlContent | Set-Content -Path $xmlPath -Encoding UTF8

            $result = Import-RulesFromXml -Path $xmlPath
            $result.Success | Should -BeTrue

            $importedRule = @($result.Data) | Select-Object -First 1
            # Should have extracted "calc.exe" from "calc.exe (Hash)" in the Name
            $importedRule.SourceFileName | Should -Not -Be 'Unknown'
        }
    }

    Context 'When both SourceFileName and Name are empty/missing' {
        It 'Should fall back to hash prefix display name' {
            $xmlContent = @'
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FileHashRule Id="{33333333-3333-3333-3333-333333333333}" Name="" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC" SourceFileName="" SourceFileLength="512" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
</AppLockerPolicy>
'@
            $xmlPath = Join-Path $script:TestDataPath 'test-empty-fallback.xml'
            $xmlContent | Set-Content -Path $xmlPath -Encoding UTF8

            $result = Import-RulesFromXml -Path $xmlPath
            $result.Success | Should -BeTrue

            $importedRule = @($result.Data) | Select-Object -First 1
            # Name should be hash-prefix, not "Unknown (Hash)"
            $importedRule.Name | Should -Match '^Hash:[A-Fa-f0-9]{12}\.\.\.'
        }
    }

    Context 'When Description contains filename' {
        It 'Should extract filename from Description as last resort' {
            $xmlContent = @'
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FileHashRule Id="{44444444-4444-4444-4444-444444444444}" Name="Unknown" Description="C:\Windows\setup.msi" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD" SourceFileName="" SourceFileLength="4096" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
</AppLockerPolicy>
'@
            $xmlPath = Join-Path $script:TestDataPath 'test-desc-fallback.xml'
            $xmlContent | Set-Content -Path $xmlPath -Encoding UTF8

            $result = Import-RulesFromXml -Path $xmlPath
            $result.Success | Should -BeTrue

            $importedRule = @($result.Data) | Select-Object -First 1
            # Regex extracts filename portion after path separator from description
            $importedRule.SourceFileName | Should -Be 'setup.msi'
        }
    }
}

Describe 'Export->Import Roundtrip - Filename Preservation (v1.2.15)' -Tag 'Unit', 'Rules', 'Roundtrip' {

    Context 'Hash rule with real filename survives export and re-import' {
        It 'Should preserve filename through Export-PolicyToXml and Import-RulesFromXml' {
            # Step 1: Create a hash rule with a real filename
            $hash = '1234567890ABCDEF' * 4
            $createResult = New-HashRule -Hash $hash -SourceFileName 'myapp.exe' -SourceFileLength 8192 -Name 'myapp.exe (Hash)' -Action 'Allow' -CollectionType 'Exe' -Status 'Approved' -Save

            $createResult.Success | Should -BeTrue

            # Step 2: Create a policy and add the rule
            $policyResult = New-Policy -Name "RoundtripTest_$(Get-Random)" -Phase 1
            $policyResult.Success | Should -BeTrue
            $policyId = $policyResult.Data.PolicyId

            $addResult = Add-RuleToPolicy -PolicyId $policyId -RuleId $createResult.Data.Id
            $addResult.Success | Should -BeTrue

            # Step 3: Export to XML
            $exportPath = Join-Path $script:TestDataPath 'roundtrip-export.xml'
            $exportResult = Export-PolicyToXml -PolicyId $policyId -OutputPath $exportPath -SkipValidation

            $exportResult.Success | Should -BeTrue
            Test-Path $exportPath | Should -BeTrue

            # Step 4: Verify the XML contains the real filename, not "Unknown"
            $xmlContent = Get-Content $exportPath -Raw
            $xmlContent | Should -Match 'SourceFileName="myapp.exe"'
            $xmlContent | Should -Not -Match 'SourceFileName="Unknown"'

            # Step 5: Import it back
            $importResult = Import-RulesFromXml -Path $exportPath
            $importResult.Success | Should -BeTrue

            # Step 6: Verify the re-imported rule has the correct filename
            $reimported = @($importResult.Data) | Where-Object { $_.Hash -eq $hash.ToUpper() } | Select-Object -First 1
            $reimported | Should -Not -BeNullOrEmpty
            $reimported.SourceFileName | Should -Be 'myapp.exe'
            $reimported.Name | Should -Be 'myapp.exe (Hash)'

            # Cleanup
            Remove-Policy -PolicyId $policyId -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

Describe 'Import-RulesFromXml - Basic Functionality' -Tag 'Unit', 'Rules', 'Import' {

    Context 'Valid XML import' {
        It 'Should import publisher rules from XML' {
            $xmlContent = @'
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FilePublisherRule Id="{55555555-5555-5555-5555-555555555555}" Name="Test Publisher" Description="Test" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=TEST CORP" ProductName="Test Product" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
'@
            $xmlPath = Join-Path $script:TestDataPath 'test-publisher-import.xml'
            $xmlContent | Set-Content -Path $xmlPath -Encoding UTF8

            $result = Import-RulesFromXml -Path $xmlPath
            $result.Success | Should -BeTrue
            @($result.Data).Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Invalid XML file' {
        It 'Should handle malformed XML gracefully' {
            $xmlPath = Join-Path $script:TestDataPath 'test-malformed.xml'
            'This is not valid XML <>' | Set-Content -Path $xmlPath -Encoding UTF8

            $result = Import-RulesFromXml -Path $xmlPath
            $result.Success | Should -BeFalse
        }
    }
}
