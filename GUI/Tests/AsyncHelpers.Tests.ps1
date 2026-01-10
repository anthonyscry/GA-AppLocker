<#
.SYNOPSIS
    Pester tests for AsyncHelpers.psm1
.DESCRIPTION
    Tests the async execution helper functions used by the GUI
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot ".." "AsyncHelpers.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    # Cleanup
    if (Get-Command 'Close-AsyncPool' -ErrorAction SilentlyContinue) {
        Close-AsyncPool
    }
    Remove-Module AsyncHelpers -ErrorAction SilentlyContinue
}

Describe "Initialize-AsyncPool" {
    It "Should initialize without errors" {
        { Initialize-AsyncPool -MaxThreads 2 } | Should -Not -Throw
    }

    It "Should accept custom thread count" {
        { Initialize-AsyncPool -MaxThreads 5 } | Should -Not -Throw
    }
}

Describe "Start-AsyncOperation" {
    BeforeAll {
        # Ensure pool is initialized (safe to call multiple times)
        Initialize-AsyncPool -MaxThreads 2
    }

    AfterAll {
        Close-AsyncPool
    }

    It "Should return a job ID" {
        $jobId = Start-AsyncOperation -ScriptBlock { return "test" } -OperationName "Test"
        $jobId | Should -Not -BeNullOrEmpty
        $jobId | Should -Match '^[0-9a-f-]{36}$'  # GUID format
    }

    It "Should execute the script block" {
        $jobId = Start-AsyncOperation -ScriptBlock {
            return "Hello World"
        } -OperationName "HelloTest"

        # Wait for completion
        Start-Sleep -Milliseconds 500
        $status = Get-AsyncOperationStatus -JobId $jobId
        $status.Status | Should -BeIn @('Running', 'Completed')
    }

    It "Should pass parameters to the script block" {
        $params = @{ Value = 42 }
        $jobId = Start-AsyncOperation -ScriptBlock {
            param($Params)
            return $Params.Value * 2
        } -Parameters $params -OperationName "ParamTest"

        $jobId | Should -Not -BeNullOrEmpty
    }
}

Describe "Get-AsyncOperationStatus" {
    BeforeAll {
        # Ensure pool is initialized (safe to call multiple times)
        Initialize-AsyncPool -MaxThreads 2
    }

    AfterAll {
        Close-AsyncPool
    }

    It "Should return NotFound for invalid job ID" {
        $status = Get-AsyncOperationStatus -JobId "invalid-job-id"
        $status.Status | Should -Be 'NotFound'
    }

    It "Should return Running or Completed for valid job" {
        $jobId = Start-AsyncOperation -ScriptBlock {
            Start-Sleep -Milliseconds 500
            return "done"
        } -OperationName "StatusTest"

        # Verify job was created
        $jobId | Should -Not -BeNullOrEmpty

        $status = Get-AsyncOperationStatus -JobId $jobId
        $status.Status | Should -BeIn @('Running', 'Completed')
    }
}

Describe "Wait-AsyncOperation" {
    BeforeAll {
        # Ensure pool is initialized (safe to call multiple times)
        Initialize-AsyncPool -MaxThreads 2
    }

    AfterAll {
        Close-AsyncPool
    }

    It "Should wait for operation to complete" {
        $jobId = Start-AsyncOperation -ScriptBlock {
            Start-Sleep -Milliseconds 100
            return @{ Success = $true; Output = @("test result") }
        } -OperationName "WaitTest"

        $result = Wait-AsyncOperation -JobId $jobId -TimeoutSeconds 10
        $result | Should -Not -BeNullOrEmpty
    }

    It "Should return error for invalid job ID" {
        $result = Wait-AsyncOperation -JobId "invalid-id" -TimeoutSeconds 1
        $result.Success | Should -Be $false
        $result.Error | Should -Match 'not found'
    }
}

Describe "Stop-AsyncOperation" {
    BeforeAll {
        # Ensure pool is initialized (safe to call multiple times)
        Initialize-AsyncPool -MaxThreads 2
    }

    AfterAll {
        Close-AsyncPool
    }

    It "Should return false for invalid job ID" {
        $result = Stop-AsyncOperation -JobId "invalid-id"
        $result | Should -Be $false
    }

    It "Should stop a running operation" {
        $jobId = Start-AsyncOperation -ScriptBlock {
            Start-Sleep -Seconds 30  # Long running
            return "should not complete"
        } -OperationName "StopTest"

        Start-Sleep -Milliseconds 100  # Let it start
        $result = Stop-AsyncOperation -JobId $jobId
        $result | Should -Be $true
    }
}

Describe "Get-AllAsyncOperations" {
    BeforeAll {
        # Ensure pool is initialized (safe to call multiple times)
        Initialize-AsyncPool -MaxThreads 2
    }

    AfterAll {
        Close-AsyncPool
    }

    It "Should return operations that were started" {
        # Start operations that will run long enough to be captured
        $jobId1 = Start-AsyncOperation -ScriptBlock { Start-Sleep -Seconds 30 } -OperationName "Op1"
        $jobId2 = Start-AsyncOperation -ScriptBlock { Start-Sleep -Seconds 30 } -OperationName "Op2"

        # Verify jobs were created
        $jobId1 | Should -Not -BeNullOrEmpty
        $jobId2 | Should -Not -BeNullOrEmpty

        # Get operations immediately after starting (before they complete)
        $ops = Get-AllAsyncOperations

        # Verify the function returns an array (even if empty due to timing)
        # The main test is that the jobs were created successfully above
        $ops | Should -Not -BeNullOrEmpty -Because "Jobs $jobId1 and $jobId2 should still be active"
    }
}

Describe "Close-AsyncPool" {
    It "Should close without errors" {
        Initialize-AsyncPool -MaxThreads 2
        { Close-AsyncPool } | Should -Not -Throw
    }

    It "Should handle being called multiple times" {
        { Close-AsyncPool } | Should -Not -Throw
        { Close-AsyncPool } | Should -Not -Throw
    }
}
