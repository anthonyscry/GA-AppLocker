<#
.SYNOPSIS
    Collects AppLocker event logs from local or remote machines.

.DESCRIPTION
    Retrieves AppLocker-related events (Event IDs 8001-8025) from the
    Microsoft-Windows-AppLocker operational logs.

    Event ID Reference:
    - 8001: EXE/DLL allowed
    - 8002: EXE/DLL would be blocked (audit mode)
    - 8003: EXE/DLL blocked
    - 8004: EXE/DLL blocked (no rule)
    - 8005: Script allowed
    - 8006: Script would be blocked (audit mode)
    - 8007: Script blocked
    - 8020: Packaged app allowed
    - 8021: Packaged app would be blocked
    - 8022: Packaged app blocked
    - 8023: MSI/MSP allowed
    - 8024: MSI/MSP would be blocked
    - 8025: MSI/MSP blocked

.PARAMETER ComputerName
    Target computer. Defaults to local machine.

.PARAMETER Credential
    PSCredential for remote access.

.PARAMETER StartTime
    Only collect events after this time.

.PARAMETER MaxEvents
    Maximum number of events to collect per log.

.EXAMPLE
    Get-AppLockerEventLogs

.EXAMPLE
    Get-AppLockerEventLogs -ComputerName 'Server01' -StartTime (Get-Date).AddDays(-7)

.OUTPUTS
    [PSCustomObject] Result with Success, Data (events array), and Summary.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
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
        [datetime]$StartTime,

        [Parameter()]
        [int]$MaxEvents = 1000
    )

    $result = [PSCustomObject]@{
        Success  = $false
        Data     = @()
        Error    = $null
        Summary  = $null
    }

    try {
        Write-ScanLog -Message "Collecting AppLocker events from $ComputerName"

        #region --- Define log names ---
        $logNames = @(
            'Microsoft-Windows-AppLocker/EXE and DLL',
            'Microsoft-Windows-AppLocker/MSI and Script',
            'Microsoft-Windows-AppLocker/Packaged app-Deployment',
            'Microsoft-Windows-AppLocker/Packaged app-Execution'
        )
        #endregion

        $allEvents = @()
        $isRemote = ($ComputerName -ne $env:COMPUTERNAME)

        foreach ($logName in $logNames) {
            try {
                #region --- Build query parameters ---
                $getEventParams = @{
                    LogName      = $logName
                    ErrorAction  = 'SilentlyContinue'
                }

                if ($MaxEvents -gt 0) {
                    $getEventParams.MaxEvents = $MaxEvents
                }

                if ($StartTime) {
                    $filterHash = @{
                        LogName   = $logName
                        StartTime = $StartTime
                        Id        = $script:AppLockerEventIds
                    }
                    $getEventParams = @{
                        FilterHashtable = $filterHash
                        ErrorAction     = 'SilentlyContinue'
                    }
                    if ($MaxEvents -gt 0) {
                        $getEventParams.MaxEvents = $MaxEvents
                    }
                }
                #endregion

                #region --- Collect events ---
                $events = $null

                if ($isRemote) {
                    $scriptBlock = {
                        param($Params)
                        Get-WinEvent @Params
                    }

                    $invokeParams = @{
                        ComputerName = $ComputerName
                        ScriptBlock  = $scriptBlock
                        ArgumentList = @($getEventParams)
                        ErrorAction  = 'SilentlyContinue'
                    }

                    if ($Credential) {
                        $invokeParams.Credential = $Credential
                    }

                    $events = Invoke-Command @invokeParams
                }
                else {
                    $events = Get-WinEvent @getEventParams
                }
                #endregion

                #region --- Process events ---
                if ($events) {
                    foreach ($event in $events) {
                        $eventData = [PSCustomObject]@{
                            ComputerName = $ComputerName
                            LogName      = $logName
                            EventId      = $event.Id
                            EventType    = Get-EventTypeName -EventId $event.Id
                            TimeCreated  = $event.TimeCreated
                            Message      = $event.Message
                            FilePath     = Get-EventFilePath -Message $event.Message
                            UserSid      = $event.UserId
                            Level        = $event.LevelDisplayName
                            IsBlocked    = ($event.Id -in @(8003, 8004, 8007, 8022, 8025))
                            IsAudit      = ($event.Id -in @(8002, 8006, 8021, 8024))
                        }
                        $allEvents += $eventData
                    }
                }
                #endregion
            }
            catch {
                Write-ScanLog -Level Warning -Message "Failed to query log '$logName': $($_.Exception.Message)"
            }
        }

        #region --- Build summary ---
        $result.Success = $true
        $result.Data = $allEvents
        $result.Summary = [PSCustomObject]@{
            ComputerName    = $ComputerName
            CollectionDate  = Get-Date
            TotalEvents     = $allEvents.Count
            BlockedEvents   = ($allEvents | Where-Object { $_.IsBlocked }).Count
            AuditEvents     = ($allEvents | Where-Object { $_.IsAudit }).Count
            AllowedEvents   = ($allEvents | Where-Object { -not $_.IsBlocked -and -not $_.IsAudit }).Count
            EventsByType    = $allEvents | Group-Object EventType | Select-Object Name, Count
        }
        #endregion

        Write-ScanLog -Message "Collected $($allEvents.Count) AppLocker events from $ComputerName"
    }
    catch {
        $result.Error = "Event log collection failed: $($_.Exception.Message)"
        Write-ScanLog -Level Error -Message $result.Error
    }

    return $result
}

#region ===== HELPER FUNCTIONS =====
function script:Get-EventTypeName {
    param([int]$EventId)

    switch ($EventId) {
        8001 { 'EXE/DLL Allowed' }
        8002 { 'EXE/DLL Would Block (Audit)' }
        8003 { 'EXE/DLL Blocked' }
        8004 { 'EXE/DLL Blocked (No Rule)' }
        8005 { 'Script Allowed' }
        8006 { 'Script Would Block (Audit)' }
        8007 { 'Script Blocked' }
        8020 { 'Packaged App Allowed' }
        8021 { 'Packaged App Would Block (Audit)' }
        8022 { 'Packaged App Blocked' }
        8023 { 'MSI/MSP Allowed' }
        8024 { 'MSI/MSP Would Block (Audit)' }
        8025 { 'MSI/MSP Blocked' }
        default { "Unknown ($EventId)" }
    }
}

function script:Get-EventFilePath {
    param([string]$Message)

    # AppLocker event messages typically contain the file path
    # Format varies but usually includes the full path
    if ($Message -match '([A-Z]:\\[^\r\n"]+\.(exe|dll|msi|msp|ps1|bat|cmd|vbs|js))') {
        return $Matches[1]
    }
    return $null
}
#endregion
