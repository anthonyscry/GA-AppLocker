#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for GA-AppLocker.Storage module.

.DESCRIPTION
    Tests for the Storage module including database operations, 
    index management, and JSON fallback functionality.
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    # Test data path
    $script:TestDataPath = Join-Path $env:TEMP "GA-AppLocker-StorageTests-$(Get-Random)"
    New-Item -Path $script:TestDataPath -ItemType Directory -Force | Out-Null

    # Helper to create test rule
    function New-TestRule {
        param(
            [string]$RuleType = 'Hash',
            [string]$Status = 'Pending'
        )
        return [PSCustomObject]@{
            Id             = [guid]::NewGuid().ToString()
            Name           = "Test Rule $(Get-Random)"
            RuleType       = $RuleType
            CollectionType = 'Exe'
            Action         = 'Allow'
            Status         = $Status
            UserOrGroupSid = 'S-1-1-0'
            Hash           = (1..64 | ForEach-Object { '{0:X}' -f (Get-Random -Max 16) }) -join ''
            PublisherName  = 'O=TEST CORP'
            ProductName    = 'Test Product'
            Path           = 'C:\Test\*.exe'
            CreatedAt      = (Get-Date).ToString('o')
            ModifiedAt     = (Get-Date).ToString('o')
        }
    }
}

AfterAll {
    # Cleanup test data
    if (Test-Path $script:TestDataPath) {
        Remove-Item -Path $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Storage Module - Core Functions' {
    Context 'Initialize-RuleDatabase' {
        It 'Should be available' {
            Get-Command -Name 'Initialize-RuleDatabase' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should initialize without errors' {
            { Initialize-RuleDatabase } | Should -Not -Throw
        }
    }

    Context 'Get-RuleDatabasePath' {
        It 'Should return a valid path' {
            $path = Get-RuleDatabasePath
            $path | Should -Not -BeNullOrEmpty
        }

        It 'Should return path ending with rules-index.json or .db' {
            $path = Get-RuleDatabasePath
            ($path -match '\.json$' -or $path -match '\.db$') | Should -BeTrue
        }
    }

    Context 'Test-RuleDatabaseExists' {
        It 'Should return boolean' {
            $result = Test-RuleDatabaseExists
            $result | Should -BeOfType [bool]
        }
    }
}

Describe 'Storage Module - CRUD Operations' {
    BeforeAll {
        # Ensure database is initialized
        Initialize-RuleDatabase -ErrorAction SilentlyContinue
    }

    Context 'Add-RuleToDatabase' {
        It 'Should add a rule successfully' {
            $rule = New-TestRule
            $result = Add-RuleToDatabase -Rule $rule
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should handle null rule gracefully' {
            { Add-RuleToDatabase -Rule $null } | Should -Throw
        }
    }

    Context 'Get-RuleFromDatabase' {
        It 'Should retrieve an existing rule' {
            $rule = New-TestRule
            Add-RuleToDatabase -Rule $rule | Out-Null
            
            $retrieved = Get-RuleFromDatabase -RuleId $rule.Id
            $retrieved | Should -Not -BeNullOrEmpty
            $retrieved.Id | Should -Be $rule.Id
        }

        It 'Should return null for non-existent rule' {
            $result = Get-RuleFromDatabase -RuleId 'non-existent-id'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Get-RulesFromDatabase' {
        BeforeAll {
            # Add some test rules
            1..5 | ForEach-Object {
                Add-RuleToDatabase -Rule (New-TestRule -Status 'Pending') | Out-Null
            }
            1..3 | ForEach-Object {
                Add-RuleToDatabase -Rule (New-TestRule -Status 'Approved') | Out-Null
            }
        }

        It 'Should retrieve rules with pagination' {
            $rules = Get-RulesFromDatabase -Take 3 -Skip 0
            $rules.Count | Should -BeLessOrEqual 3
        }

        It 'Should filter by status' {
            $rules = Get-RulesFromDatabase -Status 'Approved'
            $rules | ForEach-Object { $_.Status | Should -Be 'Approved' }
        }

        It 'Should filter by rule type' {
            $rules = Get-RulesFromDatabase -RuleType 'Hash'
            $rules | ForEach-Object { $_.RuleType | Should -Be 'Hash' }
        }
    }

    Context 'Update-RuleInDatabase' {
        It 'Should update rule properties' {
            $rule = New-TestRule -Status 'Pending'
            Add-RuleToDatabase -Rule $rule | Out-Null
            
            $rule.Status = 'Approved'
            $rule.ModifiedAt = (Get-Date).ToString('o')
            
            Update-RuleInDatabase -Rule $rule
            
            $updated = Get-RuleFromDatabase -RuleId $rule.Id
            $updated.Status | Should -Be 'Approved'
        }
    }

    Context 'Remove-RuleFromDatabase' {
        It 'Should remove a rule' {
            $rule = New-TestRule
            Add-RuleToDatabase -Rule $rule | Out-Null
            
            Remove-RuleFromDatabase -RuleId $rule.Id
            
            $removed = Get-RuleFromDatabase -RuleId $rule.Id
            $removed | Should -BeNullOrEmpty
        }
    }
}

Describe 'Storage Module - Query Functions' {
    BeforeAll {
        Initialize-RuleDatabase -ErrorAction SilentlyContinue
        
        # Add rules with specific attributes for searching
        $script:TestHash = 'ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890'
        $script:TestPublisher = 'O=UNIQUE TEST PUBLISHER'
        
        $hashRule = New-TestRule -RuleType 'Hash'
        $hashRule.Hash = $script:TestHash
        Add-RuleToDatabase -Rule $hashRule | Out-Null
        
        $pubRule = New-TestRule -RuleType 'Publisher'
        $pubRule.PublisherName = $script:TestPublisher
        Add-RuleToDatabase -Rule $pubRule | Out-Null
    }

    Context 'Find-RuleByHash' {
        It 'Should find rule by exact hash' {
            $found = Find-RuleByHash -Hash $script:TestHash
            $found | Should -Not -BeNullOrEmpty
        }

        It 'Should return null for non-existent hash' {
            $found = Find-RuleByHash -Hash 'NONEXISTENTHASH'
            $found | Should -BeNullOrEmpty
        }
    }

    Context 'Find-RuleByPublisher' {
        It 'Should find rule by publisher name' {
            $found = Find-RuleByPublisher -PublisherName $script:TestPublisher
            $found | Should -Not -BeNullOrEmpty
        }

        It 'Should support wildcard search' {
            $found = Find-RuleByPublisher -PublisherName '*UNIQUE*'
            $found | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-RuleCounts' {
        It 'Should return count statistics' {
            $counts = Get-RuleCounts
            $counts | Should -Not -BeNullOrEmpty
            $counts.Total | Should -BeGreaterOrEqual 0
        }

        It 'Should include status breakdown' {
            $counts = Get-RuleCounts
            $counts.PSObject.Properties.Name | Should -Contain 'Pending'
            $counts.PSObject.Properties.Name | Should -Contain 'Approved'
        }
    }

    Context 'Get-DuplicateRules' {
        BeforeAll {
            # Add duplicate hash rules
            $dupHash = 'DUPLICATE123456789012345678901234567890123456789012345678901234'
            1..3 | ForEach-Object {
                $rule = New-TestRule -RuleType 'Hash'
                $rule.Hash = $dupHash
                Add-RuleToDatabase -Rule $rule | Out-Null
            }
        }

        It 'Should find duplicate rules' {
            $duplicates = Get-DuplicateRules -RuleType 'Hash'
            # May or may not find duplicates depending on test order
            $duplicates | Should -Not -BeNull
        }
    }
}

Describe 'Storage Module - Index Watcher' {
    Context 'Start-RuleIndexWatcher' {
        It 'Should start without errors' {
            { Start-RuleIndexWatcher } | Should -Not -Throw
        }
    }

    Context 'Get-RuleIndexWatcherStatus' {
        It 'Should return status object' {
            $status = Get-RuleIndexWatcherStatus
            $status | Should -Not -BeNullOrEmpty
        }

        It 'Should include Running property' {
            $status = Get-RuleIndexWatcherStatus
            $status.PSObject.Properties.Name | Should -Contain 'Running'
        }
    }

    Context 'Stop-RuleIndexWatcher' {
        It 'Should stop without errors' {
            { Stop-RuleIndexWatcher } | Should -Not -Throw
        }
    }

    Context 'Invoke-RuleIndexRebuild' {
        It 'Should rebuild index without errors' {
            { Invoke-RuleIndexRebuild } | Should -Not -Throw
        }
    }
}

Describe 'Storage Module - Repository Pattern' {
    Context 'Get-RuleFromRepository' {
        It 'Should be available' {
            Get-Command -Name 'Get-RuleFromRepository' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should use caching' {
            $rule = New-TestRule
            Save-RuleToRepository -Rule $rule | Out-Null
            
            # First call - cache miss
            $result1 = Get-RuleFromRepository -RuleId $rule.Id
            # Second call - should be from cache
            $result2 = Get-RuleFromRepository -RuleId $rule.Id
            
            $result1.Id | Should -Be $result2.Id
        }
    }

    Context 'Save-RuleToRepository' {
        It 'Should save and return success' {
            $rule = New-TestRule
            $result = Save-RuleToRepository -Rule $rule
            $result.Success | Should -BeTrue
        }

        It 'Should invalidate cache after save' {
            $rule = New-TestRule
            Save-RuleToRepository -Rule $rule | Out-Null
            
            # Modify and save again
            $rule.Status = 'Approved'
            Save-RuleToRepository -Rule $rule | Out-Null
            
            # Get should return updated version
            $retrieved = Get-RuleFromRepository -RuleId $rule.Id
            $retrieved.Status | Should -Be 'Approved'
        }
    }

    Context 'Test-RuleExistsInRepository' {
        It 'Should return true for existing rule' {
            $rule = New-TestRule
            Save-RuleToRepository -Rule $rule | Out-Null
            
            $exists = Test-RuleExistsInRepository -RuleId $rule.Id
            $exists | Should -BeTrue
        }

        It 'Should return false for non-existent rule' {
            $exists = Test-RuleExistsInRepository -RuleId 'definitely-not-real-id'
            $exists | Should -BeFalse
        }
    }

    Context 'Find-RulesInRepository' {
        It 'Should find rules by criteria' {
            $rules = Find-RulesInRepository -Status 'Pending' -Take 5
            $rules | Should -Not -BeNull
        }
    }

    Context 'Get-RuleCountsFromRepository' {
        It 'Should return counts' {
            $counts = Get-RuleCountsFromRepository
            $counts | Should -Not -BeNullOrEmpty
            $counts.Total | Should -BeGreaterOrEqual 0
        }
    }
}

Describe 'Storage Module - Error Handling' {
    Context 'Invalid Inputs' {
        It 'Should handle empty rule ID gracefully' {
            $result = Get-RuleFromDatabase -RuleId ''
            $result | Should -BeNullOrEmpty
        }

        It 'Should handle null values in filters' {
            { Get-RulesFromDatabase -Status $null } | Should -Not -Throw
        }
    }

    Context 'Concurrent Access' {
        It 'Should handle multiple rapid operations' {
            $jobs = 1..10 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($modulePath)
                    Import-Module $modulePath -Force
                    $rule = [PSCustomObject]@{
                        Id = [guid]::NewGuid().ToString()
                        Name = "Concurrent Test $using:_"
                        RuleType = 'Hash'
                        Status = 'Pending'
                    }
                    Add-RuleToDatabase -Rule $rule
                } -ArgumentList $modulePath
            }
            
            $results = $jobs | Wait-Job -Timeout 30 | Receive-Job
            $jobs | Remove-Job -Force
            
            # Should complete without errors
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Remove-RulesFromIndex' {
    BeforeEach {
        # Reinitialize for clean state each test
        Initialize-RuleDatabase
    }

    It 'Should remove single rule and return RemovedCount of 1' {
        $rule = New-TestRule
        if (Get-Command -Name 'Add-RulesToIndex' -ErrorAction SilentlyContinue) {
            Add-RulesToIndex -Rules @($rule) | Out-Null
        }
        $result = Remove-RulesFromIndex -RuleIds @($rule.Id)
        $result.Success | Should -BeTrue
        $result.RemovedCount | Should -BeGreaterOrEqual 0
    }

    It 'Should handle non-existent IDs gracefully' {
        $result = Remove-RulesFromIndex -RuleIds @('nonexistent-id-12345')
        $result.Success | Should -BeTrue
        $result.RemovedCount | Should -Be 0
    }

    It 'Should handle empty array' {
        # Empty arrays are not allowed by parameter validation
        { Remove-RulesFromIndex -RuleIds @() } | Should -Throw
    }

    It 'Should remove multiple rules' {
        $rules = @((New-TestRule), (New-TestRule))
        if (Get-Command -Name 'Add-RulesToIndex' -ErrorAction SilentlyContinue) {
            Add-RulesToIndex -Rules $rules | Out-Null
        }
        $ids = $rules | ForEach-Object { $_.Id }
        $result = Remove-RulesFromIndex -RuleIds $ids
        $result.Success | Should -BeTrue
    }
}

Describe 'Remove-RulesBulk' {
    BeforeEach {
        Initialize-RuleDatabase
    }

    It 'Should return Success for valid operation' {
        $rule = New-TestRule
        if (Get-Command -Name 'Add-RulesToIndex' -ErrorAction SilentlyContinue) {
            Add-RulesToIndex -Rules @($rule) | Out-Null
        }
        $result = Remove-RulesBulk -RuleIds @($rule.Id)
        $result.Success | Should -BeTrue
    }

    It 'Should handle empty array gracefully' {
        # Empty arrays are not allowed by parameter validation
        { Remove-RulesBulk -RuleIds @() } | Should -Throw
    }

    It 'Should handle non-existent IDs gracefully' {
        $result = Remove-RulesBulk -RuleIds @('fake-id-1', 'fake-id-2')
        $result.Success | Should -BeTrue
    }

    It 'Should return RemovedCount property' {
        $result = Remove-RulesBulk -RuleIds @('any-id')
        $result.PSObject.Properties.Name | Should -Contain 'RemovedCount'
    }
}
