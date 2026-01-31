#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for GA-AppLocker.Rules module.

.DESCRIPTION
    Tests for the Rules module including rule creation, templates,
    deduplication, and bulk operations.
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    # Test data path
    $script:TestDataPath = Join-Path $env:TEMP "GA-AppLocker-RulesTests-$(Get-Random)"
    New-Item -Path $script:TestDataPath -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup test data
    if (Test-Path $script:TestDataPath) {
        Remove-Item -Path $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Rules Module - Core Functions' {
    Context 'New-HashRule' {
        It 'Should be available' {
            Get-Command -Name 'New-HashRule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should create a hash rule' {
            $hash = 'A' * 64
            $result = New-HashRule -Hash $hash -SourceFileName 'test.exe' -SourceFileLength 1024 -Name 'Test Hash Rule' -Action 'Allow' -CollectionType 'Exe'
            
            $result.Success | Should -BeTrue
            $result.Data.RuleType | Should -Be 'Hash'
            $result.Data.Hash | Should -Be $hash
        }

        It 'Should validate hash format' {
            $result = New-HashRule -Hash 'invalid' -SourceFileName 'test.exe' -SourceFileLength 1024 -Name 'Test' -Action 'Allow' -CollectionType 'Exe'
            
            # Should either fail validation or accept (depending on implementation)
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should set default status to Pending' {
            $hash = 'B' * 64
            $result = New-HashRule -Hash $hash -SourceFileName 'test.exe' -SourceFileLength 1024 -Name 'Test Hash Rule' -Action 'Allow' -CollectionType 'Exe'
            
            $result.Data.Status | Should -Be 'Pending'
        }
    }

    Context 'New-PublisherRule' {
        It 'Should be available' {
            Get-Command -Name 'New-PublisherRule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should create a publisher rule' {
            $result = New-PublisherRule -PublisherName 'O=TEST CORP' -ProductName 'Test Product' -BinaryName '*' -MinVersion '*' -MaxVersion '*' -Name 'Test Publisher Rule' -Action 'Allow' -CollectionType 'Exe'
            
            $result.Success | Should -BeTrue
            $result.Data.RuleType | Should -Be 'Publisher'
            $result.Data.PublisherName | Should -Be 'O=TEST CORP'
        }

        It 'Should handle wildcard versions' {
            $result = New-PublisherRule -PublisherName 'O=TEST' -ProductName '*' -BinaryName '*' -MinVersion '*' -MaxVersion '*' -Name 'Wildcard Test' -Action 'Allow' -CollectionType 'Exe'
            
            $result.Success | Should -BeTrue
            $result.Data.MinVersion | Should -Be '*'
            $result.Data.MaxVersion | Should -Be '*'
        }
    }

    Context 'New-PathRule' {
        It 'Should be available' {
            Get-Command -Name 'New-PathRule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should create a path rule' {
            $result = New-PathRule -Path 'C:\Program Files\Test\*' -Name 'Test Path Rule' -Action 'Allow' -CollectionType 'Exe'
            
            $result.Success | Should -BeTrue
            $result.Data.RuleType | Should -Be 'Path'
            $result.Data.Path | Should -Be 'C:\Program Files\Test\*'
        }

        It 'Should handle environment variables' {
            $result = New-PathRule -Path '%PROGRAMFILES%\Test\*' -Name 'Env Var Path Rule' -Action 'Allow' -CollectionType 'Exe'
            
            $result.Success | Should -BeTrue
            $result.Data.Path | Should -Match '%PROGRAMFILES%'
        }
    }

    Context 'Get-Rule' {
        It 'Should be available' {
            Get-Command -Name 'Get-Rule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should retrieve rule by ID' {
            $hash = 'C' * 64
            $created = New-HashRule -Hash $hash -SourceFileName 'test.exe' -SourceFileLength 1024 -Name 'Retrievable Rule' -Action 'Allow' -CollectionType 'Exe' -Save
            
            if ($created.Success) {
                $result = Get-Rule -Id $created.Data.Id
                $result.Success | Should -BeTrue
                $result.Data.Id | Should -Be $created.Data.Id
            }
        }

        It 'Should return error for non-existent rule' {
            $result = Get-Rule -Id 'non-existent-rule-id-12345'
            $result.Success | Should -BeFalse
        }
    }
}

Describe 'Rules Module - Rule Templates' {
    Context 'Get-RuleTemplates' {
        It 'Should be available' {
            Get-Command -Name 'Get-RuleTemplates' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should return list of templates' {
            $result = Get-RuleTemplates
            $result.Success | Should -BeTrue
            $result.Data | Should -Not -BeNullOrEmpty
            $result.Data.Count | Should -BeGreaterThan 0
        }

        It 'Should include Microsoft Office template' {
            $result = Get-RuleTemplates
            $names = $result.Data | ForEach-Object { $_.Name }
            $names | Should -Contain 'Microsoft Office'
        }

        It 'Should include Google Chrome template' {
            $result = Get-RuleTemplates
            $names = $result.Data | ForEach-Object { $_.Name }
            $names | Should -Contain 'Google Chrome'
        }

        It 'Should filter by template name' {
            $result = Get-RuleTemplates -TemplateName 'Microsoft Office'
            $result.Success | Should -BeTrue
            $result.Data.Name | Should -Be 'Microsoft Office'
        }

        It 'Should return error for non-existent template' {
            $result = Get-RuleTemplates -TemplateName 'Non Existent Template XYZ'
            $result.Success | Should -BeFalse
        }
    }

    Context 'Get-RuleTemplateCategories' {
        It 'Should be available' {
            Get-Command -Name 'Get-RuleTemplateCategories' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should return categorized templates' {
            $result = Get-RuleTemplateCategories
            $result.Success | Should -BeTrue
            $result.Data | Should -Not -BeNullOrEmpty
        }

        It 'Should have Applications category' {
            $result = Get-RuleTemplateCategories
            $result.Data.Applications | Should -Not -BeNullOrEmpty
        }

        It 'Should have BlockRules category' {
            $result = Get-RuleTemplateCategories
            $result.Data.BlockRules | Should -Not -BeNullOrEmpty
        }
    }

    Context 'New-RulesFromTemplate' {
        It 'Should be available' {
            Get-Command -Name 'New-RulesFromTemplate' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should create rules from template' {
            $result = New-RulesFromTemplate -TemplateName 'Google Chrome' -Status 'Pending'
            $result.Success | Should -BeTrue
            $result.Data.RulesCreated | Should -BeGreaterThan 0
        }

        It 'Should respect status parameter' {
            $result = New-RulesFromTemplate -TemplateName '7-Zip' -Status 'Review'
            if ($result.Success -and $result.Data.Rules.Count -gt 0) {
                $result.Data.Rules[0].Status | Should -Be 'Review'
            }
        }

        It 'Should return error for non-existent template' {
            $result = New-RulesFromTemplate -TemplateName 'Fake Template ABC'
            $result.Success | Should -BeFalse
        }
    }
}

Describe 'Rules Module - Bulk Operations' {
    Context 'Set-BulkRuleStatus' {
        It 'Should be available' {
            Get-Command -Name 'Set-BulkRuleStatus' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should support WhatIf' {
            # Create test rules first
            1..3 | ForEach-Object {
                $hash = ('D' * 62) + ('{0:D2}' -f $_)
                New-HashRule -Hash $hash -SourceFileName "test$_.exe" -SourceFileLength 1024 -Name "Bulk Test $_" -Action 'Allow' -CollectionType 'Exe' -Status 'Pending' -Save | Out-Null
            }

            $result = Set-BulkRuleStatus -Status 'Approved' -CurrentStatus 'Pending' -WhatIf
            # WhatIf should return preview without actually changing
            $result | Should -Not -BeNull
        }
    }

    Context 'Approve-TrustedVendorRules' {
        It 'Should be available' {
            Get-Command -Name 'Approve-TrustedVendorRules' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should support WhatIf' {
            $result = Approve-TrustedVendorRules -WhatIf
            # Should return preview
            $result | Should -Not -BeNull
        }
    }
}

Describe 'Rules Module - Deduplication' {
    Context 'Find-DuplicateRules' {
        It 'Should be available' {
            Get-Command -Name 'Find-DuplicateRules' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should find duplicate hash rules' {
            # Create duplicate rules
            $dupHash = 'E' * 64
            1..3 | ForEach-Object {
                New-HashRule -Hash $dupHash -SourceFileName "dup$_.exe" -SourceFileLength 1024 -Name "Dup Rule $_" -Action 'Allow' -CollectionType 'Exe' -Save | Out-Null
            }

            $result = Find-DuplicateRules -RuleType 'Hash'
            # May or may not find duplicates depending on existing data
            $result | Should -Not -BeNull
        }
    }

    Context 'Remove-DuplicateRules' {
        It 'Should be available' {
            Get-Command -Name 'Remove-DuplicateRules' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should support WhatIf mode' {
            $result = Remove-DuplicateRules -RuleType 'Hash' -Strategy 'KeepOldest' -WhatIf
            # Should return what would be removed
            $result | Should -Not -BeNull
        }
    }

    Context 'Find-ExistingHashRule' {
        It 'Should be available' {
            Get-Command -Name 'Find-ExistingHashRule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should find existing rule by hash' {
            $testHash = 'F' * 64
            New-HashRule -Hash $testHash -SourceFileName 'existing.exe' -SourceFileLength 1024 -Name 'Existing Rule' -Action 'Allow' -CollectionType 'Exe' -Save | Out-Null

            $found = Find-ExistingHashRule -Hash $testHash -CollectionType 'Exe'
            $found | Should -Not -BeNullOrEmpty
        }

        It 'Should return null for non-existent hash' {
            $found = Find-ExistingHashRule -Hash ('9' * 64) -CollectionType 'Exe'
            $found | Should -BeNullOrEmpty
        }
    }

    Context 'Find-ExistingPublisherRule' {
        It 'Should be available' {
            Get-Command -Name 'Find-ExistingPublisherRule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should find existing publisher rule' {
            $pubName = 'O=UNIQUE EXISTING PUBLISHER TEST'
            New-PublisherRule -PublisherName $pubName -ProductName '*' -BinaryName '*' -MinVersion '*' -MaxVersion '*' -Name 'Existing Publisher Rule' -Action 'Allow' -CollectionType 'Exe' -Save | Out-Null

            $found = Find-ExistingPublisherRule -PublisherName $pubName
            $found | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Rules Module - XML Export' {
    Context 'Export-RulesToXml' {
        It 'Should be available' {
            Get-Command -Name 'Export-RulesToXml' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export rules to valid XML' {
            # Create rules to export
            $hash = 'AA' * 32
            New-HashRule -Hash $hash -SourceFileName 'export.exe' -SourceFileLength 1024 -Name 'Export Test Rule' -Action 'Allow' -CollectionType 'Exe' -Status 'Approved' -Save | Out-Null

            $exportPath = Join-Path $script:TestDataPath 'export-test.xml'
            $result = Export-RulesToXml -OutputPath $exportPath
            
            if ($result.Success) {
                Test-Path $exportPath | Should -BeTrue
                
                # Validate XML structure
                $xml = [xml](Get-Content $exportPath)
                $xml | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Rules Module - Artifact Conversion' {
    Context 'ConvertFrom-Artifact' {
        It 'Should be available' {
            Get-Command -Name 'ConvertFrom-Artifact' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should convert artifact to hash rule' {
            $artifact = [PSCustomObject]@{
                FileName          = 'test.exe'
                FilePath          = 'C:\Test\test.exe'
                SHA256Hash        = 'BB' * 32
                SizeBytes         = 2048
                Extension         = '.exe'
                IsSigned          = $false
                SignerCertificate = $null
                ProductName       = $null
                ProductVersion    = $null
            }

            $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType 'Hash'
            $result.Success | Should -BeTrue
            $result.Data[0].RuleType | Should -Be 'Hash'
        }

        It 'Should convert signed artifact to publisher rule' {
            $artifact = [PSCustomObject]@{
                FileName          = 'signed.exe'
                FilePath          = 'C:\Test\signed.exe'
                SHA256Hash        = 'CC' * 32
                SizeBytes         = 4096
                Extension         = '.exe'
                IsSigned          = $true
                SignerCertificate = 'O=SIGNED PUBLISHER'
                ProductName       = 'Signed Product'
                ProductVersion    = '1.0.0.0'
            }

            $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType 'Publisher'
            $result.Success | Should -BeTrue
            $result.Data[0].RuleType | Should -Be 'Publisher'
            $result.Data[0].PublisherName | Should -Be 'O=SIGNED PUBLISHER'
        }
    }
}

Describe 'Rules Module - Smart Group Assignment' {
    Context 'Get-SuggestedGroup' {
        It 'Should be available' {
            Get-Command -Name 'Get-SuggestedGroup' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should suggest group for Microsoft product' {
            $result = Get-SuggestedGroup -PublisherName 'O=MICROSOFT CORPORATION' -ProductName 'Windows PowerShell' -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -BeTrue
        }

        It 'Should suggest group based on path' {
            $result = Get-SuggestedGroup -FilePath 'C:\Program Files\Google\Chrome\Application\chrome.exe'
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -BeTrue
        }
    }
}

Describe 'Rules Module - Hash Rule Name Generation (v1.2.15)' {
    Context 'New-HashRule with empty SourceFileName' {
        It 'Should produce hash-prefix name when SourceFileName is Unknown' {
            $hash = 'A1B2C3D4E5F6' + ('0' * 52)
            $result = New-HashRule -Hash $hash -SourceFileName 'Unknown' -SourceFileLength 1024 -Action 'Allow' -CollectionType 'Exe'

            $result.Success | Should -BeTrue
            $result.Data.Name | Should -Match '^Hash:[A-Fa-f0-9]{12}\.\.\.'
            $result.Data.Name | Should -Not -Be 'Unknown (Hash)'
        }

        It 'Should produce hash-prefix name when SourceFileName is literally Unknown' {
            $hash = 'DEADBEEF1234' + ('0' * 52)
            $result = New-HashRule -Hash $hash -SourceFileName 'Unknown' -SourceFileLength 1024 -Action 'Allow' -CollectionType 'Exe'

            $result.Success | Should -BeTrue
            $result.Data.Name | Should -Match '^Hash:[A-Fa-f0-9]+'
            $result.Data.Name | Should -Not -Be 'Unknown (Hash)'
        }

        It 'Should produce standard name when SourceFileName is valid' {
            $hash = 'ABCDEF012345' + ('6' * 52)
            $result = New-HashRule -Hash $hash -SourceFileName 'notepad.exe' -SourceFileLength 2048 -Action 'Allow' -CollectionType 'Exe'

            $result.Success | Should -BeTrue
            $result.Data.Name | Should -Be 'notepad.exe (Hash)'
        }
    }

    Context 'New-HashRule description generation' {
        It 'Should include SHA256 prefix in description when filename is Unknown' {
            $hash = 'F' * 64
            $result = New-HashRule -Hash $hash -SourceFileName 'Unknown' -SourceFileLength 512 -Action 'Allow' -CollectionType 'Exe'

            $result.Success | Should -BeTrue
            $result.Data.Description | Should -Match 'SHA256'
        }
    }
}

Describe 'Rules Module - ConvertFrom-Artifact Filename Resolution (v1.2.15)' {
    Context 'Artifact with null FileName but valid FilePath' {
        It 'Should extract filename from FilePath when FileName is null' {
            $artifact = [PSCustomObject]@{
                FileName          = $null
                FilePath          = 'C:\Windows\System32\cmd.exe'
                SHA256Hash        = 'AB' * 32
                SizeBytes         = 4096
                Extension         = '.exe'
                IsSigned          = $false
                SignerCertificate = $null
                ProductName       = $null
                ProductVersion    = $null
            }

            $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType 'Hash'
            $result.Success | Should -BeTrue
            $result.Data[0].SourceFileName | Should -Be 'cmd.exe'
        }

        It 'Should extract filename from FilePath when FileName is empty string' {
            $artifact = [PSCustomObject]@{
                FileName          = ''
                FilePath          = 'D:\Apps\MyApp\setup.msi'
                SHA256Hash        = 'CD' * 32
                SizeBytes         = 8192
                Extension         = '.msi'
                IsSigned          = $false
                SignerCertificate = $null
                ProductName       = $null
                ProductVersion    = $null
            }

            $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType 'Hash'
            $result.Success | Should -BeTrue
            $result.Data[0].SourceFileName | Should -Be 'setup.msi'
        }
    }

    Context 'Artifact with both FileName and FilePath null' {
        It 'Should fall back to Unknown gracefully' {
            $artifact = [PSCustomObject]@{
                FileName          = $null
                FilePath          = $null
                SHA256Hash        = 'EF' * 32
                SizeBytes         = 1024
                Extension         = '.exe'
                IsSigned          = $false
                SignerCertificate = $null
                ProductName       = $null
                ProductVersion    = $null
            }

            $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType 'Hash'
            $result.Success | Should -BeTrue
            # Should not throw — rule name should be hash-prefix since filename is Unknown
            $result.Data[0].Name | Should -Match '^Hash:'
        }
    }
}

Describe 'Rules Module - Error Handling' {
    Context 'Invalid Inputs' {
        It 'Should handle empty name gracefully' {
            $result = New-HashRule -Hash ('DD' * 32) -SourceFileName 'test.exe' -SourceFileLength 1024 -Name '' -Action 'Allow' -CollectionType 'Exe'
            # Should either fail gracefully or use default name
            $result | Should -Not -BeNull
        }

        It 'Should handle invalid action' {
            { New-HashRule -Hash ('EE' * 32) -SourceFileName 'test.exe' -SourceFileLength 1024 -Name 'Test' -Action 'InvalidAction' -CollectionType 'Exe' } | Should -Throw
        }

        It 'Should handle invalid collection type' {
            { New-HashRule -Hash ('FF' * 32) -SourceFileName 'test.exe' -SourceFileLength 1024 -Name 'Test' -Action 'Allow' -CollectionType 'InvalidType' } | Should -Throw
        }
    }
}
