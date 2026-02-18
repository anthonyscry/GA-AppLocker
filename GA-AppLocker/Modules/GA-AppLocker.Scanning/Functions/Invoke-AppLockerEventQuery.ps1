<#
.SYNOPSIS
    Executes bounded AppLocker event retrieval across selected hosts.

.DESCRIPTION
    Fans out bounded event retrieval to one or more targets and returns one
    status envelope per requested host. Failed hosts are surfaced as explicit
    failure envelopes and are never collapsed into successful empty results.
#>
function Invoke-AppLockerEventQuery {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory)]
        [datetime]$StartTime,

        [Parameter(Mandatory)]
        [datetime]$EndTime,

        [Parameter(Mandatory)]
        [int]$MaxEvents,

        [Parameter()]
        [int[]]$EventIds = $script:AppLockerEventIds
    )

    $envelopes = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($target in @($ComputerName)) {
        $startedAt = [System.Diagnostics.Stopwatch]::StartNew()
        $errorCategory = $null
        $errorMessage = $null
        $eventData = @()
        $success = $false

        try {
            $query = Get-AppLockerEventLogs -ComputerName $target -Credential $Credential -StartTime $StartTime -EndTime $EndTime -MaxEvents $MaxEvents -EventIds $EventIds

            if ($query.Success) {
                $success = $true
                $eventData = @($query.Data)
            }
            else {
                $success = $false
                $errorMessage = $query.Error
                $errorCategory = Get-AppLockerEventErrorCategory -Message $errorMessage
            }
        }
        catch {
            $success = $false
            $errorMessage = $_.Exception.Message
            $errorCategory = Get-AppLockerEventErrorCategory -Message $errorMessage -Exception $_.Exception
        }

        $startedAt.Stop()

        $envelope = [PSCustomObject]@{
            Host          = $target
            Success       = $success
            Count         = @($eventData).Count
            DurationMs    = [int]$startedAt.ElapsedMilliseconds
            ErrorCategory = if ($success) { $null } else { $errorCategory }
            Error         = if ($success) { $null } else { $errorMessage }
            Data          = if ($success) { $eventData } else { @() }
        }

        [void]$envelopes.Add($envelope)
    }

    return @($envelopes)
}

function script:Get-AppLockerEventErrorCategory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Message,

        [Parameter()]
        [System.Exception]$Exception
    )

    $text = [string]$Message
    if ([string]::IsNullOrWhiteSpace($text) -and $Exception) {
        $text = [string]$Exception.Message
    }

    if ($text -match 'Access is denied|0x80070005|Unauthorized|credential') {
        return 'auth'
    }

    if ($text -match 'WinRM cannot process|The client cannot connect|RPC server is unavailable|No such host|Name or service not known|network path was not found') {
        return 'connectivity'
    }

    if ($text -match 'The specified channel could not be found|No events were found that match the specified selection criteria|The event log file is corrupt|event log') {
        return 'channel'
    }

    if ($text -match 'timed out|timeout') {
        return 'timeout'
    }

    if ($text -match 'permission|privilege|not authorized') {
        return 'access'
    }

    return 'unknown'
}
