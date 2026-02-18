<#
.SYNOPSIS
    Collects bounded AppLocker event logs from local or remote machines.

.DESCRIPTION
    Retrieves AppLocker events for an explicit time window, event-id list,
    and bounded max-results cap. Unbounded requests are rejected.

.PARAMETER ComputerName
    Target computer. Defaults to local machine.

.PARAMETER Credential
    PSCredential for remote access.

.PARAMETER StartTime
    Required lower bound for event time.

.PARAMETER EndTime
    Required upper bound for event time.

.PARAMETER MaxEvents
    Required maximum number of total events to return.

.PARAMETER EventIds
    Explicit AppLocker event IDs to include.

.OUTPUTS
    [PSCustomObject] Result with Success, Data (events array), Error, and Summary.
#>
function Get-AppLockerEventLogs {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [Nullable[datetime]]$StartTime,

        [Parameter()]
        [Nullable[datetime]]$EndTime,

        [Parameter()]
        [int]$MaxEvents,

        [Parameter()]
        [int[]]$EventIds = $script:AppLockerEventIds
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
        Summary = $null
    }

    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        $ComputerName = 'localhost'
    }

    $validationError = Test-AppLockerEventQueryBounds -StartTime $StartTime -EndTime $EndTime -MaxEvents $MaxEvents -EventIds $EventIds
    if ($validationError) {
        $result.Error = $validationError
        return $result
    }

    # Ensure Get-WinEvent is available — bare runspaces may not auto-load
    # Microsoft.PowerShell.Diagnostics where it lives
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.PowerShell.Diagnostics -ErrorAction SilentlyContinue
    }

    $appLockerLogs = @(
        'Microsoft-Windows-AppLocker/EXE and DLL',
        'Microsoft-Windows-AppLocker/MSI and Script',
        'Microsoft-Windows-AppLocker/Packaged app-Deployment',
        'Microsoft-Windows-AppLocker/Packaged app-Execution'
    )

    $filterHash = @{
        LogName   = $appLockerLogs
        StartTime = $StartTime
        EndTime   = $EndTime
        Id        = $EventIds
    }

    $allEvents = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        Write-ScanLog -Message "Collecting bounded AppLocker events from $ComputerName"

        $events = $null
        $isRemote = ($ComputerName -and ($ComputerName -ne $env:COMPUTERNAME) -and ($ComputerName -ne '.') -and ($ComputerName -ne 'localhost'))

        if ($isRemote) {
            if ($Credential) {
                $scriptBlock = {
                    param($BoundFilterHash, $BoundMaxEvents)
                    $rawEvents = Get-WinEvent -FilterHashtable $BoundFilterHash -MaxEvents $BoundMaxEvents -ErrorAction Stop
                    foreach ($ev in @($rawEvents)) {
                        $xmlStr = ''
                        try { $xmlStr = $ev.ToXml() } catch { }
                        [PSCustomObject]@{
                            Id               = $ev.Id
                            LogName          = $ev.LogName
                            TimeCreated      = $ev.TimeCreated
                            Message          = $ev.Message
                            UserId           = $ev.UserId
                            LevelDisplayName = $ev.LevelDisplayName
                            RawXml           = $xmlStr
                        }
                    }
                }

                $events = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList @($filterHash, $MaxEvents) -ErrorAction Stop
            }
            else {
                $events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable $filterHash -MaxEvents $MaxEvents -ErrorAction Stop
            }
        }
        else {
            $events = Get-WinEvent -FilterHashtable $filterHash -MaxEvents $MaxEvents -ErrorAction Stop
        }

        foreach ($event in @($events)) {
            $eventData = ConvertTo-AppLockerEventRecord -Event $event -ComputerName $ComputerName
            [void]$allEvents.Add($eventData)
        }

        $result.Success = $true
        $result.Data = @($allEvents)
        $result.Summary = New-AppLockerEventSummary -ComputerName $ComputerName -StartTime $StartTime -EndTime $EndTime -MaxEvents $MaxEvents -EventList $allEvents -EventIds $EventIds -LogNames $appLockerLogs

        Write-ScanLog -Message "Collected $($allEvents.Count) bounded AppLocker event(s) from $ComputerName"
    }
    catch {
        $result.Error = "Event log collection failed: $($_.Exception.Message)"
        Write-ScanLog -Level Error -Message $result.Error
    }

    return $result
}

#region ===== HELPER FUNCTIONS =====
function script:Test-AppLockerEventQueryBounds {
    param(
        [Nullable[datetime]]$StartTime,
        [Nullable[datetime]]$EndTime,
        [int]$MaxEvents,
        [int[]]$EventIds
    )

    if ($null -eq $StartTime) {
        return 'Bounded query requires StartTime.'
    }

    if ($null -eq $EndTime) {
        return 'Bounded query requires EndTime.'
    }

    if ($EndTime -le $StartTime) {
        return 'EndTime must be greater than StartTime.'
    }

    if ($MaxEvents -le 0) {
        return 'Bounded query requires MaxEvents greater than zero.'
    }

    if ($EventIds.Count -eq 0) {
        return 'Bounded query requires explicit EventIds.'
    }

    return $null
}

function script:ConvertTo-AppLockerEventRecord {
    param(
        [Parameter(Mandatory)]
        $Event,

        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $classification = Get-AppLockerEventClassification -EventId $Event.Id

    $rawXml = ''
    try {
        if ($Event -is [System.Diagnostics.Eventing.Reader.EventLogRecord]) {
            $rawXml = $Event.ToXml()
        }
        elseif ($Event.PSObject.Properties.Name -contains 'RawXml') {
            $rawXml = [string]$Event.RawXml
        }
    }
    catch { }

    return [PSCustomObject]@{
        ComputerName    = $ComputerName
        LogName         = $Event.LogName
        EventId         = $Event.Id
        EventType       = $classification.EventType
        TimeCreated     = $Event.TimeCreated
        Message         = $Event.Message
        FilePath        = Get-EventFilePath -Message $Event.Message
        UserSid         = $Event.UserId
        Level           = $Event.LevelDisplayName
        Action          = $classification.Action
        EnforcementMode = $classification.EnforcementMode
        IsBlocked       = $classification.IsBlocked
        IsAudit         = $classification.IsAudit
        RawXml          = $rawXml
    }
}

function script:New-AppLockerEventSummary {
    param(
        [string]$ComputerName,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [int]$MaxEvents,
        [System.Collections.Generic.List[PSCustomObject]]$EventList,
        [int[]]$EventIds,
        [string[]]$LogNames
    )

    return [PSCustomObject]@{
        ComputerName   = $ComputerName
        CollectionDate = Get-Date
        LogScope       = @($LogNames)
        EventIds       = @($EventIds)
        StartTime      = $StartTime
        EndTime        = $EndTime
        MaxEvents      = $MaxEvents
        TotalEvents    = $EventList.Count
        BlockedEvents  = @($EventList | Where-Object { $_.IsBlocked }).Count
        AuditEvents    = @($EventList | Where-Object { $_.IsAudit }).Count
        AllowedEvents  = @($EventList | Where-Object { $_.Action -eq 'Allow' }).Count
        EventsByType   = @($EventList | Group-Object EventType | Select-Object Name, Count)
    }
}

function script:Get-AppLockerEventClassification {
    param([int]$EventId)

    switch ($EventId) {
        8001 { return [PSCustomObject]@{ EventType = 'EXE/DLL Allowed'; Action = 'Allow'; EnforcementMode = 'Enforce'; IsBlocked = $false; IsAudit = $false } }
        8002 { return [PSCustomObject]@{ EventType = 'EXE/DLL Blocked'; Action = 'Deny'; EnforcementMode = 'Enforce'; IsBlocked = $true; IsAudit = $false } }
        8003 { return [PSCustomObject]@{ EventType = 'EXE/DLL Would Block (Audit)'; Action = 'Deny'; EnforcementMode = 'Audit'; IsBlocked = $false; IsAudit = $true } }
        8004 { return [PSCustomObject]@{ EventType = 'EXE/DLL Blocked (No Rule)'; Action = 'Deny'; EnforcementMode = 'Enforce'; IsBlocked = $true; IsAudit = $false } }
        8005 { return [PSCustomObject]@{ EventType = 'Script Allowed'; Action = 'Allow'; EnforcementMode = 'Enforce'; IsBlocked = $false; IsAudit = $false } }
        8006 { return [PSCustomObject]@{ EventType = 'Script Blocked'; Action = 'Deny'; EnforcementMode = 'Enforce'; IsBlocked = $true; IsAudit = $false } }
        8007 { return [PSCustomObject]@{ EventType = 'Script Would Block (Audit)'; Action = 'Deny'; EnforcementMode = 'Audit'; IsBlocked = $false; IsAudit = $true } }
        8020 { return [PSCustomObject]@{ EventType = 'Packaged App Allowed'; Action = 'Allow'; EnforcementMode = 'Enforce'; IsBlocked = $false; IsAudit = $false } }
        8021 { return [PSCustomObject]@{ EventType = 'Packaged App Blocked'; Action = 'Deny'; EnforcementMode = 'Enforce'; IsBlocked = $true; IsAudit = $false } }
        8022 { return [PSCustomObject]@{ EventType = 'Packaged App Would Block (Audit)'; Action = 'Deny'; EnforcementMode = 'Audit'; IsBlocked = $false; IsAudit = $true } }
        8023 { return [PSCustomObject]@{ EventType = 'MSI/MSP Allowed'; Action = 'Allow'; EnforcementMode = 'Enforce'; IsBlocked = $false; IsAudit = $false } }
        8024 { return [PSCustomObject]@{ EventType = 'MSI/MSP Blocked'; Action = 'Deny'; EnforcementMode = 'Enforce'; IsBlocked = $true; IsAudit = $false } }
        8025 { return [PSCustomObject]@{ EventType = 'MSI/MSP Would Block (Audit)'; Action = 'Deny'; EnforcementMode = 'Audit'; IsBlocked = $false; IsAudit = $true } }
        default { return [PSCustomObject]@{ EventType = "Unknown ($EventId)"; Action = 'Unknown'; EnforcementMode = 'Unknown'; IsBlocked = $false; IsAudit = $false } }
    }
}

function script:Get-EventFilePath {
    param([string]$Message)

    if ($Message -match '([A-Z]:\\[^\r\n"]+\.(exe|dll|msi|msp|ps1|bat|cmd|vbs|js|wsf|appx|msix))') {
        return $Matches[1]
    }

    return $null
}
#endregion
