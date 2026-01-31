<#
.SYNOPSIS
    Creates and configures the WinRM GPO for remote management.

.DESCRIPTION
    Creates a GPO named 'AppLocker-EnableWinRM' that configures everything
    needed for PowerShell remoting (Invoke-Command) to work across the domain:

    1. WinRM Service auto-start
    2. WinRM listener policy (AllowAutoConfig) with IPv4/IPv6 filters
    3. LocalAccountTokenFilterPolicy (allows local admin remote access)
    4. Firewall rule for WinRM HTTP (port 5985)

    When linked to domain root with -Enforced, overrides ALL lower-level GPOs.
    When unlinked/removed, policy-based settings revert on next gpupdate.

    NOTE: The WinRM service Start type (auto-start) is written to the service
    registry directly and persists after GPO removal. Use Remove-WinRMGPO for
    full cleanup including tattooed settings.

.PARAMETER GPOName
    Name of the GPO to create. Default is 'AppLocker-EnableWinRM'.

.PARAMETER LinkToRoot
    Link the GPO to domain root (all computers). Default is $true.

.PARAMETER Enforced
    Enforce the GPO link so it overrides all lower-level GPOs.
    Recommended for AppLocker scanning to work reliably. Default is $true.

.EXAMPLE
    Initialize-WinRMGPO
    Creates the WinRM GPO enforced at domain root.

.EXAMPLE
    Initialize-WinRMGPO -Enforced:$false
    Creates the WinRM GPO at domain root without enforcement.

.OUTPUTS
    [PSCustomObject] Result with Success, Data, and Error properties.
#>
function Initialize-WinRMGPO {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$GPOName = 'AppLocker-EnableWinRM',

        [Parameter()]
        [switch]$LinkToRoot = $true,

        [Parameter()]
        [switch]$Enforced = $true
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        Write-SetupLog -Message "Initializing WinRM GPO: $GPOName (Enforced: $($Enforced.IsPresent))"

        # Check for GroupPolicy module
        if (-not (Test-ModuleAvailable -ModuleName 'GroupPolicy')) {
            throw "GroupPolicy module not available. Install RSAT features."
        }

        Import-Module GroupPolicy -ErrorAction Stop

        # Check if GPO already exists
        $existingGPO = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
        if ($existingGPO) {
            Write-SetupLog -Message "GPO '$GPOName' already exists. Updating configuration."
            $gpo = $existingGPO
        }
        else {
            $gpo = New-GPO -Name $GPOName -Comment "Enables WinRM for AppLocker remote scanning and policy deployment. Created by GA-AppLocker." -ErrorAction Stop
            Write-SetupLog -Message "Created GPO: $GPOName"
        }

        $settingsApplied = @()

        #region --- 1. WinRM Service Auto-Start ---
        # Sets the WinRM service to start automatically on boot.
        # NOTE: This writes to HKLM\SYSTEM (not Policies) so it persists after GPO removal.
        # Use Remove-WinRMGPO for full cleanup.
        $svcRegPath = 'HKLM\SYSTEM\CurrentControlSet\Services\WinRM'
        Set-GPRegistryValue -Name $GPOName -Key $svcRegPath -ValueName 'Start' -Type DWord -Value 2 -ErrorAction SilentlyContinue
        $settingsApplied += 'WinRM Service Auto-Start'
        Write-SetupLog -Message "Set WinRM service to auto-start"
        #endregion

        #region --- 2. WinRM Listener Policy (AllowAutoConfig) ---
        # Equivalent to: Computer Config > Admin Templates > Windows Components >
        #   Windows Remote Management (WinRM) > WinRM Service >
        #   "Allow remote server management through WinRM" = Enabled
        # This creates an HTTP listener and allows WinRM to accept connections.
        # Policy-based: reverts when GPO is removed.
        $winrmPolicyPath = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
        Set-GPRegistryValue -Name $GPOName -Key $winrmPolicyPath -ValueName 'AllowAutoConfig' -Type DWord -Value 1 -ErrorAction SilentlyContinue
        Set-GPRegistryValue -Name $GPOName -Key $winrmPolicyPath -ValueName 'IPv4Filter' -Type String -Value '*' -ErrorAction SilentlyContinue
        Set-GPRegistryValue -Name $GPOName -Key $winrmPolicyPath -ValueName 'IPv6Filter' -Type String -Value '*' -ErrorAction SilentlyContinue
        $settingsApplied += 'WinRM AllowAutoConfig (IPv4/IPv6: *)'
        Write-SetupLog -Message "Configured WinRM listener policy (AllowAutoConfig, IPv4/IPv6 filter: *)"
        #endregion

        #region --- 3. LocalAccountTokenFilterPolicy ---
        # Without this, local admin accounts get a filtered (non-elevated) UAC token
        # over remote connections and cannot perform admin operations.
        # This is the #1 cause of "Access Denied" when credentials are correct.
        # Policy-based path: reverts when GPO is removed.
        $uacPolicyPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        Set-GPRegistryValue -Name $GPOName -Key $uacPolicyPath -ValueName 'LocalAccountTokenFilterPolicy' -Type DWord -Value 1 -ErrorAction SilentlyContinue
        $settingsApplied += 'LocalAccountTokenFilterPolicy (UAC remote admin)'
        Write-SetupLog -Message "Set LocalAccountTokenFilterPolicy = 1 (enables remote admin for local accounts)"
        #endregion

        #region --- 4. Firewall Rules ---
        # Open port 5985 (WinRM HTTP) inbound.
        # Policy-based: reverts when GPO is removed.
        $firewallRegPath = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules'
        $winrmHttpRule = 'v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=5985|Name=Windows Remote Management (HTTP-In)|Desc=Allow WinRM HTTP for AppLocker remote management|'
        Set-GPRegistryValue -Name $GPOName -Key $firewallRegPath -ValueName 'WinRM-HTTP-In' -Type String -Value $winrmHttpRule -ErrorAction SilentlyContinue
        $settingsApplied += 'Firewall: Port 5985 (WinRM HTTP) Inbound Allow'
        Write-SetupLog -Message "Configured firewall rule: WinRM HTTP (port 5985) inbound allow"
        #endregion

        #region --- Link to Domain Root ---
        $linkedTo = $null
        if ($LinkToRoot) {
            $domainDN = Get-DomainDN
            if ($domainDN) {
                try {
                    New-GPLink -Name $GPOName -Target $domainDN -ErrorAction SilentlyContinue
                    Write-SetupLog -Message "Linked GPO to domain root: $domainDN"
                }
                catch {
                    if ($_.Exception.Message -notmatch 'already linked') {
                        Write-SetupLog -Message "Warning linking GPO: $($_.Exception.Message)" -Level Warning
                    }
                }

                # Enforce the link so it overrides all lower-level GPOs
                if ($Enforced) {
                    try {
                        Set-GPLink -Name $GPOName -Target $domainDN -Enforced Yes -ErrorAction Stop
                        $settingsApplied += "GPO Link: Enforced at domain root"
                        Write-SetupLog -Message "Enforced GPO link at domain root (overrides all lower-level GPOs)"
                    }
                    catch {
                        Write-SetupLog -Message "Warning enforcing GPO link: $($_.Exception.Message)" -Level Warning
                        $settingsApplied += "GPO Link: Linked to domain root (enforcement failed)"
                    }
                }
                else {
                    $settingsApplied += "GPO Link: Linked to domain root (not enforced)"
                }
                $linkedTo = $domainDN
            }
        }
        #endregion

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            GPOName          = $GPOName
            GPOId            = $gpo.Id
            LinkedTo         = $linkedTo
            Enforced         = $Enforced.IsPresent
            SettingsApplied  = $settingsApplied
            Status           = 'Created'
            CreatedDate      = Get-Date
        }

        Write-SetupLog -Message "WinRM GPO initialization complete. Settings: $($settingsApplied -join '; ')"
    }
    catch {
        $result.Error = "Failed to initialize WinRM GPO: $($_.Exception.Message)"
        Write-SetupLog -Message $result.Error -Level Error
    }

    return $result
}

function Enable-WinRMGPO {
    <#
    .SYNOPSIS
        Enables the WinRM GPO link.
    .DESCRIPTION
        Re-enables the WinRM GPO link at domain root. Preserves enforcement state.
    #>
    [CmdletBinding()]
    param([string]$GPOName = 'AppLocker-EnableWinRM')

    $result = [PSCustomObject]@{ Success = $false; Error = $null }

    try {
        if (-not (Test-ModuleAvailable -ModuleName 'GroupPolicy')) {
            throw "GroupPolicy module not available."
        }
        Import-Module GroupPolicy -ErrorAction Stop

        $domainDN = Get-DomainDN
        Set-GPLink -Name $GPOName -Target $domainDN -LinkEnabled Yes -ErrorAction Stop
        
        $result.Success = $true
        Write-SetupLog -Message "Enabled WinRM GPO link"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-SetupLog -Message "Failed to enable WinRM GPO: $($result.Error)" -Level Error
    }

    return $result
}

function Disable-WinRMGPO {
    <#
    .SYNOPSIS
        Disables the WinRM GPO link.
    .DESCRIPTION
        Disables the WinRM GPO link at domain root. GPO still exists but is not applied.
        Re-enable with Enable-WinRMGPO. Policy settings revert on next gpupdate.
    #>
    [CmdletBinding()]
    param([string]$GPOName = 'AppLocker-EnableWinRM')

    $result = [PSCustomObject]@{ Success = $false; Error = $null }

    try {
        if (-not (Test-ModuleAvailable -ModuleName 'GroupPolicy')) {
            throw "GroupPolicy module not available."
        }
        Import-Module GroupPolicy -ErrorAction Stop

        $domainDN = Get-DomainDN
        Set-GPLink -Name $GPOName -Target $domainDN -LinkEnabled No -ErrorAction Stop
        
        $result.Success = $true
        Write-SetupLog -Message "Disabled WinRM GPO link"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-SetupLog -Message "Failed to disable WinRM GPO: $($result.Error)" -Level Error
    }

    return $result
}

function Remove-WinRMGPO {
    <#
    .SYNOPSIS
        Completely removes the WinRM GPO and cleans up tattooed settings.
    .DESCRIPTION
        Removes the GPO, its link, and any registry settings that persist after
        GPO removal (like WinRM service auto-start). Run gpupdate /force on
        target machines after removal for immediate effect.
    #>
    [CmdletBinding()]
    param([string]$GPOName = 'AppLocker-EnableWinRM')

    $result = [PSCustomObject]@{ Success = $false; Data = $null; Error = $null }

    try {
        if (-not (Test-ModuleAvailable -ModuleName 'GroupPolicy')) {
            throw "GroupPolicy module not available."
        }
        Import-Module GroupPolicy -ErrorAction Stop

        $gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $result.Error = "GPO '$GPOName' not found"
            return $result
        }

        # Remove GPO (also removes all links)
        Remove-GPO -Name $GPOName -ErrorAction Stop
        Write-SetupLog -Message "Removed GPO: $GPOName"

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            GPOName    = $GPOName
            Status     = 'Removed'
            Note       = 'Run gpupdate /force on target machines. WinRM service auto-start may persist until manually changed.'
        }
        Write-SetupLog -Message "WinRM GPO removed. Policy settings will revert on next gpupdate cycle."
    }
    catch {
        $result.Error = "Failed to remove WinRM GPO: $($_.Exception.Message)"
        Write-SetupLog -Message $result.Error -Level Error
    }

    return $result
}
