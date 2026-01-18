#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for Session State persistence functions in GA-AppLocker.

.DESCRIPTION
    Tests the Save-SessionState, Restore-SessionState, and Clear-SessionState
    functions which handle application state persistence across sessions.
    - Save-SessionState: Persists session to %LOCALAPPDATA%\GA-AppLocker\session.json
    - Restore-SessionState: Loads session with 7-day expiry (configurable)
    - Clear-SessionState: Removes the session file

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\SessionState.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Get the session file path for verification
    $script:DataPath = Get-AppLockerDataPath
    $script:SessionPath = Join-Path $script:DataPath 'session.json'

    # Backup existing session if present
    $script:BackupPath = Join-Path $script:DataPath 'session.json.backup'
    if (Test-Path $script:SessionPath) {
        Copy-Item -Path $script:SessionPath -Destination $script:BackupPath -Force
    }
}

AfterAll {
    # Restore original session if it was backed up
    if (Test-Path $script:BackupPath) {
        Move-Item -Path $script:BackupPath -Destination $script:SessionPath -Force
    }
    elseif (Test-Path $script:SessionPath) {
        # Clean up test session if no backup existed
        Remove-Item -Path $script:SessionPath -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Save-SessionState Function' -Tag 'Unit', 'SessionState' {

    BeforeEach {
        # Clean slate for each test
        Clear-SessionState | Out-Null
    }

    Context 'Basic Save Operations' {
        It 'Saves a simple state hashtable successfully' {
            $state = @{
                discoveredMachines = @('PC001', 'PC002', 'PC003')
                selectedOU         = 'OU=Workstations,DC=corp,DC=local'
            }

            $result = Save-SessionState -State $state

            $result.Success | Should -BeTrue
            $result.Data.Path | Should -Be $script:SessionPath
            $result.Data.Timestamp | Should -Not -BeNullOrEmpty
            Test-Path $script:SessionPath | Should -BeTrue
        }

        It 'Adds lastSaved metadata to the state' {
            $state = @{ testKey = 'testValue' }

            Save-SessionState -State $state | Out-Null

            # Use Restore-SessionState to read encrypted data
            $restored = Restore-SessionState
            $restored.Success | Should -BeTrue
            $restored.Data.lastSaved | Should -Not -BeNullOrEmpty
            $restored.Data.version | Should -Be '1.0'
        }

        It 'Saves complex nested state structures' {
            $state = @{
                machines = @(
                    @{ Name = 'PC001'; Status = 'Online'; ArtifactCount = 150 }
                    @{ Name = 'PC002'; Status = 'Offline'; ArtifactCount = 0 }
                )
                scanResults = @{
                    TotalFiles  = 500
                    SignedFiles = 450
                    StartTime   = (Get-Date).ToString('o')
                }
                uiState = @{
                    ActivePanel    = 'PanelScanner'
                    SelectedTab    = 2
                    FilterSettings = @{ ShowSigned = $true; ShowUnsigned = $false }
                }
            }

            $result = Save-SessionState -State $state

            $result.Success | Should -BeTrue

            # Use Restore-SessionState to read encrypted data
            $restored = Restore-SessionState
            $restored.Success | Should -BeTrue
            $restored.Data.machines.Count | Should -Be 2
            $restored.Data.scanResults.TotalFiles | Should -Be 500
            $restored.Data.uiState.ActivePanel | Should -Be 'PanelScanner'
        }

        It 'Overwrites existing session file' {
            $state1 = @{ version1 = 'first' }
            $state2 = @{ version2 = 'second' }

            Save-SessionState -State $state1 | Out-Null
            Save-SessionState -State $state2 | Out-Null

            # Use Restore-SessionState to read encrypted data
            $restored = Restore-SessionState
            $restored.Success | Should -BeTrue
            $restored.Data.version1 | Should -BeNullOrEmpty
            $restored.Data.version2 | Should -Be 'second'
        }
    }

    Context 'Input Validation' {
        It 'Requires State parameter' {
            { Save-SessionState } | Should -Throw
        }

        It 'Handles empty hashtable gracefully' {
            $result = Save-SessionState -State @{}

            $result.Success | Should -BeTrue

            # Use Restore-SessionState to read encrypted data
            $restored = Restore-SessionState
            $restored.Success | Should -BeTrue
            $restored.Data.lastSaved | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Restore-SessionState Function' -Tag 'Unit', 'SessionState' {

    BeforeEach {
        Clear-SessionState | Out-Null
    }

    Context 'Basic Restore Operations' {
        It 'Restores a previously saved state' {
            $original = @{
                discoveredMachines = @('PC001', 'PC002')
                activePanel        = 'PanelRules'
                ruleCount          = 42
            }
            Save-SessionState -State $original | Out-Null

            $result = Restore-SessionState

            $result.Success | Should -BeTrue
            $result.Data.discoveredMachines | Should -Contain 'PC001'
            $result.Data.activePanel | Should -Be 'PanelRules'
            $result.Data.ruleCount | Should -Be 42
        }

        It 'Returns hashtable format for easy use' {
            Save-SessionState -State @{ key = 'value' } | Out-Null

            $result = Restore-SessionState

            $result.Data | Should -BeOfType [hashtable]
            $result.Data['key'] | Should -Be 'value'
        }

        It 'Includes metadata in restored state' {
            Save-SessionState -State @{ data = 'test' } | Out-Null

            $result = Restore-SessionState

            $result.Data.lastSaved | Should -Not -BeNullOrEmpty
            $result.Data.version | Should -Be '1.0'
        }
    }

    Context 'Missing Session File' {
        It 'Returns failure when no session file exists' {
            $result = Restore-SessionState

            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'No saved session'
            $result.Data | Should -BeNullOrEmpty
        }
    }

    Context 'Session Expiry' {
        It 'Rejects sessions older than default 7 days' {
            # Create an old session by manipulating the JSON directly
            $oldSession = @{
                lastSaved = (Get-Date).AddDays(-10).ToString('o')
                version   = '1.0'
                testData  = 'old'
            }
            $oldSession | ConvertTo-Json | Set-Content -Path $script:SessionPath

            $result = Restore-SessionState

            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'expired'
            # Expired session should be deleted
            Test-Path $script:SessionPath | Should -BeFalse
        }

        It 'Accepts sessions within expiry window' {
            $recentSession = @{
                lastSaved = (Get-Date).AddDays(-3).ToString('o')
                version   = '1.0'
                testData  = 'recent'
            }
            $recentSession | ConvertTo-Json | Set-Content -Path $script:SessionPath

            $result = Restore-SessionState

            $result.Success | Should -BeTrue
            $result.Data.testData | Should -Be 'recent'
        }

        It 'Respects custom ExpiryDays parameter' {
            $session = @{
                lastSaved = (Get-Date).AddDays(-20).ToString('o')
                version   = '1.0'
                testData  = 'custom'
            }
            $session | ConvertTo-Json | Set-Content -Path $script:SessionPath

            # 7-day default should reject
            $result1 = Restore-SessionState
            $result1.Success | Should -BeFalse

            # Recreate the file (it was deleted)
            $session | ConvertTo-Json | Set-Content -Path $script:SessionPath

            # 30-day expiry should accept
            $result2 = Restore-SessionState -ExpiryDays 30

            $result2.Success | Should -BeTrue
            $result2.Data.testData | Should -Be 'custom'
        }

        It 'Force parameter bypasses expiry check' {
            $veryOldSession = @{
                lastSaved = (Get-Date).AddDays(-100).ToString('o')
                version   = '1.0'
                testData  = 'ancient'
            }
            $veryOldSession | ConvertTo-Json | Set-Content -Path $script:SessionPath

            $result = Restore-SessionState -Force

            $result.Success | Should -BeTrue
            $result.Data.testData | Should -Be 'ancient'
        }
    }

    Context 'Error Handling' {
        It 'Handles corrupted JSON gracefully' {
            Set-Content -Path $script:SessionPath -Value 'not valid json {'

            $result = Restore-SessionState

            $result.Success | Should -BeFalse
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Clear-SessionState Function' -Tag 'Unit', 'SessionState' {

    Context 'Basic Clear Operations' {
        It 'Removes existing session file' {
            Save-SessionState -State @{ data = 'test' } | Out-Null
            Test-Path $script:SessionPath | Should -BeTrue

            $result = Clear-SessionState

            $result.Success | Should -BeTrue
            Test-Path $script:SessionPath | Should -BeFalse
        }

        It 'Succeeds even when no session file exists' {
            # Ensure no file exists
            if (Test-Path $script:SessionPath) {
                Remove-Item $script:SessionPath -Force
            }

            $result = Clear-SessionState

            $result.Success | Should -BeTrue
        }
    }
}

Describe 'Session State Round-Trip' -Tag 'Unit', 'SessionState', 'Integration' {

    BeforeEach {
        Clear-SessionState | Out-Null
    }

    Context 'Full Workflow' {
        It 'Preserves all data types through save/restore cycle' {
            $original = @{
                stringValue  = 'hello'
                intValue     = 42
                boolValue    = $true
                arrayValue   = @('a', 'b', 'c')
                nestedHash   = @{
                    inner = 'value'
                    count = 10
                }
                dateString   = (Get-Date).ToString('o')
            }

            Save-SessionState -State $original | Out-Null
            $restored = Restore-SessionState

            $restored.Success | Should -BeTrue
            $restored.Data.stringValue | Should -Be 'hello'
            $restored.Data.intValue | Should -Be 42
            $restored.Data.boolValue | Should -BeTrue
            $restored.Data.arrayValue | Should -Contain 'b'
            $restored.Data.nestedHash.inner | Should -Be 'value'
        }

        It 'Handles typical GA-AppLocker session state' {
            $typicalState = @{
                discoveredMachines      = @('WKS001', 'WKS002', 'SRV001')
                selectedMachines        = @('WKS001')
                scanArtifacts           = @(
                    @{ Path = 'C:\Program Files\App\app.exe'; Hash = 'ABC123'; Signed = $true }
                )
                generatedRules          = @('rule-001', 'rule-002')
                approvedRules           = @('rule-001')
                currentPanel            = 'PanelScanner'
                workflowStage           = 2
                discoveryCount          = 3
                scanCount               = 150
                ruleCount               = 2
                policyCount             = 0
            }

            Save-SessionState -State $typicalState | Out-Null
            $restored = Restore-SessionState

            $restored.Success | Should -BeTrue
            $restored.Data.discoveredMachines.Count | Should -Be 3
            $restored.Data.workflowStage | Should -Be 2
            $restored.Data.scanArtifacts[0].Signed | Should -BeTrue
        }
    }
}
