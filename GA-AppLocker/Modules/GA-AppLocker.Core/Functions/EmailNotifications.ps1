# DEAD CODE — These functions are never called from the GUI or any module.
# Retained for potential future CLI usage. Removed from module exports.
#region ===== EMAIL NOTIFICATIONS (UNUSED) =====
<#
.SYNOPSIS
    Email notification system for GA-AppLocker.

.DESCRIPTION
    Sends email notifications for important events like policy deployments,
    rule approvals, and scan completions. Works with on-premises SMTP servers
    for air-gapped environments.


    .EXAMPLE
    Get-EmailSettings
    # Get EmailSettings
    #>

function Get-EmailSettings {
    <#
    .SYNOPSIS
        Gets the current email notification settings.

    .DESCRIPTION
        Gets the current email notification settings. Returns the requested data in a standard result object.
    #>
    try {
        $settingsPath = Join-Path (Get-AppLockerDataPath) 'Config\email-settings.json'
        
        if (Test-Path $settingsPath) {
            $content = Get-Content $settingsPath -Raw | ConvertFrom-Json
            return @{
                Success = $true
                Data = $content
                Error = $null
            }
        }
        
        # Return defaults
        return @{
            Success = $true
            Data = [PSCustomObject]@{
                Enabled = $false
                SmtpServer = ''
                SmtpPort = 25
                UseSsl = $false
                FromAddress = ''
                ToAddresses = @()
                Credential = $null
                NotifyOn = @{
                    PolicyDeployed = $true
                    RulesApproved = $true
                    ScanCompleted = $false
                    SystemErrors = $true
                }
            }
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Set-EmailSettings {
    <#
    .SYNOPSIS
        Configures email notification settings.

    .DESCRIPTION
        Configures email notification settings. Persists the change to the GA-AppLocker data store.

    .PARAMETER SmtpServer
        SMTP server hostname or IP address.

    .PARAMETER SmtpPort
        SMTP port (default: 25).

    .PARAMETER UseSsl
        Use SSL/TLS for SMTP connection.

    .PARAMETER FromAddress
        Email address to send from.

    .PARAMETER ToAddresses
        Array of email addresses to send notifications to.

    .PARAMETER Credential
        PSCredential for SMTP authentication (optional).

    .PARAMETER Enabled
        Enable or disable email notifications.

    .EXAMPLE
        Set-EmailSettings -SmtpServer 'mail.corp.local' -FromAddress 'applocker@corp.local' -ToAddresses @('admin@corp.local')
    #>
    [CmdletBinding()]
    param(
        [string]$SmtpServer,
        [int]$SmtpPort = 25,
        [switch]$UseSsl,
        [string]$FromAddress,
        [string[]]$ToAddresses,
        [PSCredential]$Credential,
        [switch]$Enabled
    )

    try {
        $settingsPath = Join-Path (Get-AppLockerDataPath) 'Config\email-settings.json'
        $configDir = Split-Path $settingsPath -Parent
        
        if (-not (Test-Path $configDir)) {
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        }
        
        # Load existing settings
        $existing = Get-EmailSettings
        $settings = if ($existing.Success -and $existing.Data) { $existing.Data } else { @{} }
        
        # Update with new values
        if ($PSBoundParameters.ContainsKey('SmtpServer')) { $settings.SmtpServer = $SmtpServer }
        if ($PSBoundParameters.ContainsKey('SmtpPort')) { $settings.SmtpPort = $SmtpPort }
        if ($PSBoundParameters.ContainsKey('UseSsl')) { $settings.UseSsl = $UseSsl.IsPresent }
        if ($PSBoundParameters.ContainsKey('FromAddress')) { $settings.FromAddress = $FromAddress }
        if ($PSBoundParameters.ContainsKey('ToAddresses')) { $settings.ToAddresses = $ToAddresses }
        if ($PSBoundParameters.ContainsKey('Enabled')) { $settings.Enabled = $Enabled.IsPresent }
        
        # Store credential securely (encrypted with DPAPI)
        if ($Credential) {
            $settings.Credential = @{
                Username = $Credential.UserName
                Password = $Credential.Password | ConvertFrom-SecureString
            }
        }
        
        $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Force
        
        # Audit log
        if (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue) {
            Write-AuditLog -Action 'EmailSettingsUpdated' -Category 'Config' `
                -Details "SMTP: $SmtpServer, Enabled: $($settings.Enabled)" | Out-Null
        }
        
        return @{
            Success = $true
            Data = $settings
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Set-EmailNotifyOn {
    <#
    .SYNOPSIS
        Configures which events trigger email notifications.

    .DESCRIPTION
        Configures which events trigger email notifications. Persists the change to the GA-AppLocker data store.

    .PARAMETER PolicyDeployed
        Notify when a policy is deployed.

    .PARAMETER RulesApproved
        Notify when rules are approved.

    .PARAMETER ScanCompleted
        Notify when a scan completes.

    .PARAMETER SystemErrors
        Notify on system errors.

    .EXAMPLE
        Set-EmailNotifyOn -PolicyDeployed $true -SystemErrors $true
    #>
    [CmdletBinding()]
    param(
        [bool]$PolicyDeployed,
        [bool]$RulesApproved,
        [bool]$ScanCompleted,
        [bool]$SystemErrors
    )

    try {
        $settingsResult = Get-EmailSettings
        if (-not $settingsResult.Success) { return $settingsResult }
        
        $settings = $settingsResult.Data
        
        if (-not $settings.NotifyOn) {
            $settings.NotifyOn = @{}
        }
        
        if ($PSBoundParameters.ContainsKey('PolicyDeployed')) { $settings.NotifyOn.PolicyDeployed = $PolicyDeployed }
        if ($PSBoundParameters.ContainsKey('RulesApproved')) { $settings.NotifyOn.RulesApproved = $RulesApproved }
        if ($PSBoundParameters.ContainsKey('ScanCompleted')) { $settings.NotifyOn.ScanCompleted = $ScanCompleted }
        if ($PSBoundParameters.ContainsKey('SystemErrors')) { $settings.NotifyOn.SystemErrors = $SystemErrors }
        
        $settingsPath = Join-Path (Get-AppLockerDataPath) 'Config\email-settings.json'
        $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Force
        
        return @{
            Success = $true
            Data = $settings.NotifyOn
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Send-AppLockerNotification {
    <#
    .SYNOPSIS
        Sends an email notification.

    .DESCRIPTION
        Sends an email notification. Uses the configured email transport settings.

    .PARAMETER Subject
        Email subject line.

    .PARAMETER Body
        Email body content.

    .PARAMETER EventType
        Type of event: PolicyDeployed, RulesApproved, ScanCompleted, SystemErrors.

    .PARAMETER Priority
        Email priority: Low, Normal, High.

    .EXAMPLE
        Send-AppLockerNotification -Subject 'Policy Deployed' -Body 'Policy XYZ was deployed successfully.' -EventType 'PolicyDeployed'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subject,

        [Parameter(Mandatory)]
        [string]$Body,

        [ValidateSet('PolicyDeployed', 'RulesApproved', 'ScanCompleted', 'SystemErrors', 'General')]
        [string]$EventType = 'General',

        [ValidateSet('Low', 'Normal', 'High')]
        [string]$Priority = 'Normal'
    )

    try {
        $settingsResult = Get-EmailSettings
        if (-not $settingsResult.Success) {
            return $settingsResult
        }
        
        $settings = $settingsResult.Data
        
        # Check if enabled
        if (-not $settings.Enabled) {
            return @{
                Success = $true
                Data = @{ Skipped = $true; Reason = 'Email notifications disabled' }
                Error = $null
            }
        }
        
        # Check if this event type is enabled
        if ($EventType -ne 'General' -and $settings.NotifyOn) {
            if (-not $settings.NotifyOn.$EventType) {
                return @{
                    Success = $true
                    Data = @{ Skipped = $true; Reason = "Notifications for $EventType are disabled" }
                    Error = $null
                }
            }
        }
        
        # Validate settings
        if ([string]::IsNullOrWhiteSpace($settings.SmtpServer)) {
            return @{
                Success = $false
                Data = $null
                Error = 'SMTP server not configured'
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($settings.FromAddress)) {
            return @{
                Success = $false
                Data = $null
                Error = 'From address not configured'
            }
        }
        
        if (-not $settings.ToAddresses -or $settings.ToAddresses.Count -eq 0) {
            return @{
                Success = $false
                Data = $null
                Error = 'No recipient addresses configured'
            }
        }
        
        # Build message parameters
        $mailParams = @{
            From = $settings.FromAddress
            To = $settings.ToAddresses
            Subject = "[GA-AppLocker] $Subject"
            Body = @"
$Body

---
Sent from GA-AppLocker Dashboard
Server: $env:COMPUTERNAME
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
            SmtpServer = $settings.SmtpServer
            Port = $settings.SmtpPort
            Priority = $Priority
        }
        
        if ($settings.UseSsl) {
            $mailParams.UseSsl = $true
        }
        
        # Add credential if configured
        if ($settings.Credential -and $settings.Credential.Username) {
            $securePassword = $settings.Credential.Password | ConvertTo-SecureString
            $credential = New-Object PSCredential($settings.Credential.Username, $securePassword)
            $mailParams.Credential = $credential
        }
        
        # Send the email
        Send-MailMessage @mailParams -ErrorAction Stop
        
        # Audit log
        if (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue) {
            Write-AuditLog -Action 'EmailSent' -Category 'System' `
                -Target $Subject -Details "To: $($settings.ToAddresses -join ', '); Type: $EventType" | Out-Null
        }
        
        return @{
            Success = $true
            Data = @{
                Subject = $Subject
                Recipients = $settings.ToAddresses
                SentAt = Get-Date
            }
            Error = $null
        }
    }
    catch {
        # Log error but don't fail the calling operation
        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Level Warning -Message "Email notification failed: $($_.Exception.Message)"
        }
        
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Test-EmailSettings {
    <#
    .SYNOPSIS
        Tests email settings by sending a test email.

    .DESCRIPTION
        Tests email settings by sending a test email. Returns a result object with Success, Data, and Error properties.

    .EXAMPLE
        Test-EmailSettings
    #>
    [CmdletBinding()]
    param()

    $result = Send-AppLockerNotification `
        -Subject 'Test Email from GA-AppLocker' `
        -Body "This is a test email to verify email notification settings.`n`nIf you received this email, your configuration is working correctly." `
        -EventType 'General' `
        -Priority 'Normal'
    
    return $result
}

#endregion
