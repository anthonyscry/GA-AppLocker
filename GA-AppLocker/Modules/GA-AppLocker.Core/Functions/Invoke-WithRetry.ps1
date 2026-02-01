# DEAD CODE — This function is never called from any production code path.
# Retained as a tested utility. Removed from module exports.
<#
.SYNOPSIS
    Executes a script block with automatic retry logic for transient failures.

.DESCRIPTION
    Wraps a script block execution with configurable retry logic, including
    exponential backoff and filtering for transient vs permanent errors.
    Particularly useful for WinRM and network operations.

.PARAMETER ScriptBlock
    The script block to execute.

.PARAMETER MaxRetries
    Maximum number of retry attempts. Default is 3.

.PARAMETER InitialDelayMs
    Initial delay between retries in milliseconds. Default is 1000.

.PARAMETER MaxDelayMs
    Maximum delay between retries in milliseconds. Default is 10000.

.PARAMETER UseExponentialBackoff
    If true, delay doubles after each retry. Default is true.

.PARAMETER TransientErrorPatterns
    Array of regex patterns to identify transient errors that should trigger retry.
    Default includes common WinRM and network error patterns.

.PARAMETER OperationName
    Name of the operation for logging purposes.

.EXAMPLE
    Invoke-WithRetry -ScriptBlock { Invoke-Command -ComputerName 'Server01' -ScriptBlock { Get-Process } }

.EXAMPLE
    Invoke-WithRetry -ScriptBlock { Test-WSMan -ComputerName 'Server01' } -MaxRetries 5 -OperationName 'WinRM Test'

.OUTPUTS
    Returns the result of the successful script block execution, or throws if all retries exhausted.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$InitialDelayMs = 1000,

        [Parameter()]
        [int]$MaxDelayMs = 10000,

        [Parameter()]
        [switch]$UseExponentialBackoff = $true,

        [Parameter()]
        [string[]]$TransientErrorPatterns = @(
            'The WinRM client cannot process the request',
            'The client cannot connect to the destination',
            'WinRM cannot complete the operation',
            'The network path was not found',
            'Access is denied',
            'The RPC server is unavailable',
            'The remote computer is not available',
            'A connection attempt failed',
            'The operation has timed out',
            'The semaphore timeout period has expired',
            'The network name cannot be found',
            'The server is not operational'
        ),

        [Parameter()]
        [string]$OperationName = 'Operation'
    )

    $attempt = 0
    $currentDelay = $InitialDelayMs
    $lastError = $null

    while ($attempt -le $MaxRetries) {
        $attempt++
        
        try {
            Write-AppLockerLog -Message "$OperationName - Attempt $attempt of $($MaxRetries + 1)" -NoConsole
            $result = & $ScriptBlock
            
            if ($attempt -gt 1) {
                Write-AppLockerLog -Message "$OperationName succeeded on attempt $attempt"
            }
            
            return $result
        }
        catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message
            
            # Check if error is transient
            $isTransient = $false
            foreach ($pattern in $TransientErrorPatterns) {
                if ($errorMessage -match $pattern) {
                    $isTransient = $true
                    break
                }
            }
            
            if (-not $isTransient) {
                # Permanent error - don't retry
                Write-AppLockerLog -Level Warning -Message "$OperationName failed with permanent error: $errorMessage"
                throw $_
            }
            
            if ($attempt -gt $MaxRetries) {
                # All retries exhausted
                Write-AppLockerLog -Level Error -Message "$OperationName failed after $attempt attempts: $errorMessage"
                throw $_
            }
            
            # Transient error - retry with delay
            Write-AppLockerLog -Level Warning -Message "$OperationName attempt $attempt failed (transient): $errorMessage. Retrying in $currentDelay ms..."
            
            Start-Sleep -Milliseconds $currentDelay
            
            # Calculate next delay
            if ($UseExponentialBackoff) {
                $currentDelay = [Math]::Min($currentDelay * 2, $MaxDelayMs)
            }
        }
    }
    
    # Should not reach here, but just in case
    if ($lastError) {
        throw $lastError
    }
}
