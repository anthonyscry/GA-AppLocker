<#
.SYNOPSIS
    Functions for managing scheduled artifact scans.

.DESCRIPTION
    Provides functions to create, manage, and execute scheduled scans.
    Schedules are stored locally and executed via Windows Task Scheduler.


    .EXAMPLE
    New-ScheduledScan
    # New ScheduledScan
    #>

function New-ScheduledScan {
    <#
    .SYNOPSIS
        Creates a new scheduled scan configuration.

    .DESCRIPTION
        Creates a new scheduled scan configuration. Creates the object and returns a standard result object.

    .PARAMETER Name
        Name for the scheduled scan.

    .PARAMETER ScanPaths
        Paths to scan for artifacts.

    .PARAMETER Schedule
        Schedule type: Daily, Weekly, Monthly, or Once.

    .PARAMETER Time
        Time of day to run the scan (HH:mm format).

    .PARAMETER DaysOfWeek
        For Weekly schedule: days to run (Monday, Tuesday, etc.).

    .PARAMETER Enabled
        Whether the schedule is enabled.

    .EXAMPLE
        New-ScheduledScan -Name "Daily Scan" -ScanPaths @("C:\Program Files") -Schedule Daily -Time "02:00"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string[]]$ScanPaths,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Daily', 'Weekly', 'Monthly', 'Once')]
        [string]$Schedule,

        [Parameter(Mandatory = $true)]
        [string]$Time,

        [Parameter()]
        [string[]]$DaysOfWeek,

        [Parameter()]
        [switch]$SkipDllScanning,

        [Parameter()]
        [string[]]$TargetMachines,

        [Parameter()]
        [switch]$Enabled = $true
    )

    try {
        $schedulePath = Get-ScheduledScanStoragePath
        $scheduleId = [guid]::NewGuid().ToString()

        $scheduledScan = [PSCustomObject]@{
            Id             = $scheduleId
            Name           = $Name
            ScanPaths      = $ScanPaths
            Schedule       = $Schedule
            Time           = $Time
            DaysOfWeek     = $DaysOfWeek
            SkipDllScanning = $SkipDllScanning.IsPresent
            TargetMachines = $TargetMachines
            Enabled        = $Enabled.IsPresent
            CreatedAt      = Get-Date -Format 'o'
            LastRunAt      = $null
            NextRunAt      = Get-NextRunTime -Schedule $Schedule -Time $Time -DaysOfWeek $DaysOfWeek
            LastRunStatus  = $null
        }

        $filePath = Join-Path $schedulePath "$scheduleId.json"
        $scheduledScan | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8

        # Create Windows Task Scheduler task if enabled
        if ($Enabled) {
            $result = Register-ScheduledScanTask -ScheduledScan $scheduledScan
            if (-not $result.Success) {
                Write-Warning "Could not create Windows Task: $($result.Error)"
            }
        }

        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message "Created scheduled scan: $Name ($scheduleId)" -Level 'INFO'
        }

        return @{
            Success = $true
            Data    = $scheduledScan
            Message = "Scheduled scan '$Name' created successfully."
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Get-ScheduledScans {
    <#
    .SYNOPSIS
        Gets all scheduled scans.

    .DESCRIPTION
        Gets all scheduled scans. Returns the requested data in a standard result object.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$EnabledOnly
    )

    try {
        $schedulePath = Get-ScheduledScanStoragePath
        $schedules = @()

        $files = Get-ChildItem -Path $schedulePath -Filter '*.json' -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $schedule = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if (-not $EnabledOnly -or $schedule.Enabled) {
                $schedules += $schedule
            }
        }

        return @{
            Success = $true
            Data    = $schedules
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
            Data    = @()
        }
    }
}

function Remove-ScheduledScan {
    <#
    .SYNOPSIS
        Removes a scheduled scan.

    .DESCRIPTION
        Removes a scheduled scan. Permanently removes the item from storage.

    .PARAMETER Id
        ID of the scheduled scan to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    try {
        $schedulePath = Get-ScheduledScanStoragePath
        $filePath = Join-Path $schedulePath "$Id.json"

        if (-not (Test-Path $filePath)) {
            return @{
                Success = $false
                Error   = "Scheduled scan not found: $Id"
            }
        }

        # Remove Windows Task Scheduler task
        $taskName = "GA-AppLocker-Scan-$Id"
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        # Remove the schedule file
        Remove-Item -Path $filePath -Force

        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message "Removed scheduled scan: $Id" -Level 'INFO'
        }

        return @{
            Success = $true
            Message = "Scheduled scan removed."
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Set-ScheduledScanEnabled {
    <#
    .SYNOPSIS
        Enables or disables a scheduled scan.

    .DESCRIPTION
        Enables or disables a scheduled scan. Persists the change to the GA-AppLocker data store.

    .PARAMETER Id
        ID of the scheduled scan.

    .PARAMETER Enabled
        Whether to enable or disable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    try {
        $schedulePath = Get-ScheduledScanStoragePath
        $filePath = Join-Path $schedulePath "$Id.json"

        if (-not (Test-Path $filePath)) {
            return @{
                Success = $false
                Error   = "Scheduled scan not found: $Id"
            }
        }

        $schedule = Get-Content $filePath -Raw | ConvertFrom-Json
        $schedule.Enabled = $Enabled

        $schedule | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8

        # Update Windows Task Scheduler task
        $taskName = "GA-AppLocker-Scan-$Id"
        if ($Enabled) {
            $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($existingTask) {
                Enable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            }
            else {
                Register-ScheduledScanTask -ScheduledScan $schedule
            }
        }
        else {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        }

        return @{
            Success = $true
            Data    = $schedule
            Message = "Scheduled scan $(if ($Enabled) { 'enabled' } else { 'disabled' })."
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Invoke-ScheduledScan {
    <#
    .SYNOPSIS
        Manually triggers a scheduled scan.

    .DESCRIPTION
        Manually triggers a scheduled scan. Executes the operation and returns a result object.

    .PARAMETER Id
        ID of the scheduled scan to run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    try {
        $schedulePath = Get-ScheduledScanStoragePath
        $filePath = Join-Path $schedulePath "$Id.json"

        if (-not (Test-Path $filePath)) {
            return @{
                Success = $false
                Error   = "Scheduled scan not found: $Id"
            }
        }

        $schedule = Get-Content $filePath -Raw | ConvertFrom-Json

        # Build scan parameters matching Start-ArtifactScan's actual parameter names
        $scanParams = @{
            ScanLocal   = $true
            SaveResults = $true
            ScanName    = "Scheduled_$($schedule.Name)_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }

        if ($schedule.ScanPaths) {
            $scanParams.Paths = $schedule.ScanPaths
        }

        if ($schedule.SkipDllScanning) {
            $scanParams.SkipDllScanning = $true
        }

        if ($schedule.SkipWshScanning) {
            $scanParams.SkipWshScanning = $true
        }

        if ($schedule.SkipShellScanning) {
            $scanParams.SkipShellScanning = $true
        }

        if ($schedule.TargetMachines -and $schedule.TargetMachines.Count -gt 0) {
            # Start-ArtifactScan expects -Machines as array of objects with Hostname/MachineType,
            # not bare computer name strings. Convert strings to minimal machine objects.
            $scanParams.Machines = @($schedule.TargetMachines | ForEach-Object {
                [PSCustomObject]@{
                    Hostname    = $_
                    MachineType = 'Unknown'
                    IsOnline    = $null
                    WinRMStatus = $null
                }
            })
        }

        # Execute scan
        $result = Start-ArtifactScan @scanParams

        # Update last run info
        $schedule.LastRunAt = Get-Date -Format 'o'
        $schedule.LastRunStatus = if ($result.Success) { 'Success' } else { 'Failed' }
        $schedule.NextRunAt = Get-NextRunTime -Schedule $schedule.Schedule -Time $schedule.Time -DaysOfWeek $schedule.DaysOfWeek

        $schedule | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8

        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message "Executed scheduled scan: $($schedule.Name) - Status: $($schedule.LastRunStatus)" -Level 'INFO'
        }

        return $result
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

#region Helper Functions

function script:Get-ScheduledScanStoragePath {
    $dataPath = Get-AppLockerDataPath
    $schedulePath = Join-Path $dataPath 'ScheduledScans'

    if (-not (Test-Path $schedulePath)) {
        New-Item -Path $schedulePath -ItemType Directory -Force | Out-Null
    }

    return $schedulePath
}

function script:Get-NextRunTime {
    param(
        [string]$Schedule,
        [string]$Time,
        [string[]]$DaysOfWeek
    )

    try {
        $timeParts = $Time -split ':'
        $hour = [int]$timeParts[0]
        $minute = if ($timeParts.Count -gt 1) { [int]$timeParts[1] } else { 0 }

        $now = Get-Date
        $today = $now.Date.AddHours($hour).AddMinutes($minute)

        switch ($Schedule) {
            'Daily' {
                if ($today -gt $now) {
                    return $today.ToString('o')
                }
                else {
                    return $today.AddDays(1).ToString('o')
                }
            }
            'Weekly' {
                if (-not $DaysOfWeek -or $DaysOfWeek.Count -eq 0) {
                    $DaysOfWeek = @('Monday')
                }
                
                # Find next occurrence
                for ($i = 0; $i -le 7; $i++) {
                    $checkDate = $now.Date.AddDays($i).AddHours($hour).AddMinutes($minute)
                    $dayName = $checkDate.DayOfWeek.ToString()
                    if ($dayName -in $DaysOfWeek -and $checkDate -gt $now) {
                        return $checkDate.ToString('o')
                    }
                }
                return $today.AddDays(7).ToString('o')
            }
            'Monthly' {
                $firstOfMonth = [datetime]::new($now.Year, $now.Month, 1).AddHours($hour).AddMinutes($minute)
                if ($firstOfMonth -gt $now) {
                    return $firstOfMonth.ToString('o')
                }
                else {
                    return $firstOfMonth.AddMonths(1).ToString('o')
                }
            }
            'Once' {
                return $today.ToString('o')
            }
            default {
                return $null
            }
        }
    }
    catch {
        return $null
    }
}

function script:Register-ScheduledScanTask {
    param([PSCustomObject]$ScheduledScan)

    try {
        $taskName = "GA-AppLocker-Scan-$($ScheduledScan.Id)"
        
        # Build PowerShell command to run
        $scriptPath = "$env:LOCALAPPDATA\GA-AppLocker\Scripts\Run-ScheduledScan.ps1"
        $scriptDir = Split-Path $scriptPath -Parent
        
        if (-not (Test-Path $scriptDir)) {
            New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
        }

        # Create the runner script
        $runnerScript = @"
# GA-AppLocker Scheduled Scan Runner
# Auto-generated - Do not edit

`$ErrorActionPreference = 'Stop'

try {
    # Find GA-AppLocker module
    `$modulePath = `$null
    `$searchPaths = @(
        'C:\Projects\GA-AppLocker3\GA-AppLocker\GA-AppLocker.psd1',
        'C:\Projects\GA-AppLocker2\GA-AppLocker\GA-AppLocker.psd1',
        "`$env:ProgramFiles\GA-AppLocker\GA-AppLocker.psd1",
        "`$env:LOCALAPPDATA\GA-AppLocker\Module\GA-AppLocker.psd1"
    )
    
    foreach (`$path in `$searchPaths) {
        if (Test-Path `$path) {
            `$modulePath = `$path
            break
        }
    }
    
    if (-not `$modulePath) {
        throw 'GA-AppLocker module not found'
    }
    
    Import-Module `$modulePath -Force
    
    `$scanId = `$args[0]
    if (-not `$scanId) {
        throw 'Scan ID not provided'
    }
    
    Invoke-ScheduledScan -Id `$scanId
}
catch {
    Write-Error `$_.Exception.Message
    exit 1
}
"@

        $runnerScript | Set-Content -Path $scriptPath -Encoding UTF8

        # Parse time
        $timeParts = $ScheduledScan.Time -split ':'
        $hour = [int]$timeParts[0]
        $minute = if ($timeParts.Count -gt 1) { [int]$timeParts[1] } else { 0 }

        # Create trigger based on schedule type
        $trigger = switch ($ScheduledScan.Schedule) {
            'Daily' { New-ScheduledTaskTrigger -Daily -At "$($hour):$($minute.ToString('00'))" }
            'Weekly' { 
                $days = if ($ScheduledScan.DaysOfWeek) { $ScheduledScan.DaysOfWeek } else { @('Monday') }
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At "$($hour):$($minute.ToString('00'))"
            }
            'Monthly' { New-ScheduledTaskTrigger -Weekly -DaysOfWeek 'Monday' -At "$($hour):$($minute.ToString('00'))" }  # Fallback
            'Once' { New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) }
        }

        # Create action
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" `"$($ScheduledScan.Id)`""

        # Create principal (run as current user)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        # Register the task
        Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Principal $principal -Settings $settings -Force | Out-Null

        return @{ Success = $true }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

#endregion
