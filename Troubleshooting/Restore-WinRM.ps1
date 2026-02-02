<#
.SYNOPSIS
    Restores WinRM service when WSMAN registry keys are missing or corrupted.

.DESCRIPTION
    This script repairs WinRM when the service fails to start due to missing
    or corrupted WSMAN registry configuration. Common symptoms include:
    - WinRM service stops immediately after starting
    - Event log shows "The system cannot find the file specified"
    - winrm commands return error 0x80338012
    
    Designed for air-gapped environments with no internet access.

.NOTES
    Author: GA-ASI ISSO
    Date: January 2026
    Requires: Administrator privileges
    
.EXAMPLE
    .\Restore-WinRM.ps1
    
.EXAMPLE
    .\Restore-WinRM.ps1 -Verbose
#>

[CmdletBinding()]
param()

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-WinRMHealth {
    <#
    .SYNOPSIS
        Checks WinRM service and configuration health.
    #>
    $results = @{
        ServiceExists  = $false
        ServiceRunning = $false
        WSMANKeyExists = $false
        ListenerExists = $false
        DLLsPresent    = $false
    }
    
    # Check service
    $service = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    if ($service) {
        $results.ServiceExists = $true
        $results.ServiceRunning = $service.Status -eq 'Running'
    }
    
    # Check WSMAN registry
    $results.WSMANKeyExists = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN'
    
    # Check listener config
    $listenerPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener'
    if (Test-Path $listenerPath) {
        $listeners = Get-ChildItem $listenerPath -ErrorAction SilentlyContinue
        $results.ListenerExists = ($null -ne $listeners -and @($listeners).Count -gt 0)
    }
    
    # Check required DLLs
    $requiredDLLs = @(
        'C:\Windows\System32\WsmSvc.dll',
        'C:\Windows\System32\WsmWmiPl.dll',
        'C:\Windows\System32\pwrshplugin.dll'
    )
    $results.DLLsPresent = @($requiredDLLs | Where-Object { Test-Path $_ }).Count -eq $requiredDLLs.Count
    
    return $results
}

function Restore-WSMANRegistry {
    <#
    .SYNOPSIS
        Recreates the WSMAN registry structure.
    #>
    Write-Log 'Creating WSMAN registry keys...'
    
    $wsmanPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Plugin',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Client',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Service',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\WinRS'
    )
    
    foreach ($path in $wsmanPaths) {
        if (-not (Test-Path $path)) {
            [void](New-Item -Path $path -Force)
            Write-Verbose "Created: $path"
        } else {
            Write-Verbose "Exists: $path"
        }
    }
    
    Write-Log 'WSMAN registry structure created' -Level SUCCESS
}

function Start-WinRMService {
    <#
    .SYNOPSIS
        Attempts to start the WinRM service.
    #>
    Write-Log 'Starting WinRM service...'
    
    $service = Get-Service -Name WinRM
    
    if ($service.StartType -eq 'Disabled') {
        Write-Log 'WinRM is disabled, setting to Automatic...' -Level WARNING
        Set-Service -Name WinRM -StartupType Automatic
    }
    
    if ($service.Status -ne 'Running') {
        Start-Service -Name WinRM
        Start-Sleep -Seconds 2
        
        $service.Refresh()
        if ($service.Status -eq 'Running') {
            Write-Log 'WinRM service started successfully' -Level SUCCESS
            return $true
        } else {
            Write-Log 'WinRM service failed to start' -Level ERROR
            return $false
        }
    } else {
        Write-Log 'WinRM service already running' -Level SUCCESS
        return $true
    }
}

function Invoke-WinRMQuickConfig {
    <#
    .SYNOPSIS
        Runs winrm quickconfig to complete setup.
    #>
    Write-Log 'Running winrm quickconfig...'
    
    $output = winrm quickconfig -force 2>&1
    
    if ($LASTEXITCODE -eq 0 -or $output -match 'already set up') {
        Write-Log 'WinRM quickconfig completed' -Level SUCCESS
        return $true
    } else {
        Write-Log 'WinRM quickconfig returned warnings/errors' -Level WARNING
        Write-Verbose ($output | Out-String)
        return $false
    }
}

function Get-WinRMEventErrors {
    <#
    .SYNOPSIS
        Gets recent WinRM-related errors from event log.
    #>
    param([int]$Hours = 1)
    
    $startTime = (Get-Date).AddHours(-$Hours)
    
    $events = Get-WinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'Service Control Manager'
        Level        = 2  # Error
        StartTime    = $startTime
    } -ErrorAction SilentlyContinue | Where-Object {
        $_.Message -like '*WinRM*' -or $_.Message -like '*Remote Management*'
    }
    
    return $events
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

$separator = '=' * 60
$divider = '-' * 60

Write-Log $separator
Write-Log 'WinRM Restore Script - Air-Gapped Environment'
Write-Log $separator
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log $divider

# Step 1: Health check
Write-Log 'Step 1: Checking WinRM health...'
$health = Test-WinRMHealth

Write-Log "  Service Exists:    $($health.ServiceExists)"
Write-Log "  Service Running:   $($health.ServiceRunning)"
Write-Log "  WSMAN Key Exists:  $($health.WSMANKeyExists)"
Write-Log "  Listener Exists:   $($health.ListenerExists)"
Write-Log "  DLLs Present:      $($health.DLLsPresent)"

if (-not $health.ServiceExists) {
    Write-Log 'WinRM service not found - this may require OS repair' -Level ERROR
    exit 1
}

if (-not $health.DLLsPresent) {
    Write-Log "Required WinRM DLLs missing - run 'sfc /scannow' first" -Level ERROR
    exit 1
}

# Step 2: Check for recent errors
Write-Log ''
Write-Log 'Step 2: Checking recent event log errors...'
$errors = Get-WinRMEventErrors -Hours 1
if ($errors) {
    Write-Log "Found $(@($errors).Count) recent WinRM error(s):" -Level WARNING
    @($errors) | Select-Object -First 3 | ForEach-Object {
        $msgPreview = $_.Message.Substring(0, [Math]::Min(80, $_.Message.Length))
        Write-Log "  $($_.TimeCreated): $msgPreview..." -Level WARNING
    }
}

# Step 3: Restore registry if needed
if (-not $health.WSMANKeyExists) {
    Write-Log ''
    Write-Log 'Step 3: WSMAN registry missing - restoring...'
    Restore-WSMANRegistry
} else {
    Write-Log ''
    Write-Log 'Step 3: WSMAN registry exists - skipping restore'
}

# Step 4: Start service
Write-Log ''
Write-Log 'Step 4: Starting WinRM service...'
$serviceStarted = Start-WinRMService

if (-not $serviceStarted) {
    Write-Log 'Attempting registry restore and retry...' -Level WARNING
    Restore-WSMANRegistry
    $serviceStarted = Start-WinRMService
}

if (-not $serviceStarted) {
    Write-Log 'WinRM service will not start - check event logs' -Level ERROR
    exit 1
}

# Step 5: Run quickconfig
Write-Log ''
Write-Log 'Step 5: Configuring WinRM...'
Invoke-WinRMQuickConfig

# Step 6: Final verification
Write-Log ''
Write-Log 'Step 6: Final verification...'
$finalHealth = Test-WinRMHealth

if ($finalHealth.ServiceRunning) {
    Write-Log $divider
    Write-Log 'WinRM RESTORE COMPLETED SUCCESSFULLY' -Level SUCCESS
    Write-Log $divider
    
    # Show listener info
    Write-Log ''
    Write-Log 'Active listeners:'
    winrm enumerate winrm/config/listener 2>&1 | ForEach-Object { Write-Log "  $_" }
    
    # Test connectivity
    Write-Log ''
    Write-Log 'Testing local connectivity...'
    $testResult = Test-WSMan -ComputerName localhost -ErrorAction SilentlyContinue
    if ($testResult) {
        Write-Log 'WSMan test: PASSED' -Level SUCCESS
    } else {
        Write-Log 'WSMan test: FAILED (may need firewall rules)' -Level WARNING
    }
} else {
    Write-Log 'WinRM restore FAILED - manual intervention required' -Level ERROR
    exit 1
}

Write-Log ''
Write-Log "Script completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
