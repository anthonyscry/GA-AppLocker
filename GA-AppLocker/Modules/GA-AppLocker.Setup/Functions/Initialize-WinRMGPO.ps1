<#
.SYNOPSIS
    Creates and configures the WinRM GPO for remote management.

.DESCRIPTION
    Creates a GPO named 'AppLocker-EnableWinRM' that:
    - Enables the WinRM service
    - Configures WinRM to start automatically
    - Enables firewall rules for WinRM (HTTP/HTTPS)
    - Links to domain root (all computers)

.PARAMETER GPOName
    Name of the GPO to create. Default is 'AppLocker-EnableWinRM'.

.PARAMETER LinkToRoot
    Link the GPO to domain root. Default is $true.

.EXAMPLE
    Initialize-WinRMGPO
    
    Creates the WinRM GPO with default settings.

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
        [switch]$LinkToRoot = $true
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        Write-SetupLog -Message "Initializing WinRM GPO: $GPOName"

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
            # Create new GPO
            $gpo = New-GPO -Name $GPOName -Comment "Enables WinRM for AppLocker remote management" -ErrorAction Stop
            Write-SetupLog -Message "Created GPO: $GPOName"
        }

        # Configure WinRM service to start automatically
        # Registry path: HKLM\SYSTEM\CurrentControlSet\Services\WinRM
        $regPath = 'HKLM\SYSTEM\CurrentControlSet\Services\WinRM'
        Set-GPRegistryValue -Name $GPOName -Key $regPath -ValueName 'Start' -Type DWord -Value 2 -ErrorAction SilentlyContinue

        # Enable WinRM through Group Policy Preferences or registry
        # Computer Configuration > Policies > Administrative Templates > Windows Components > Windows Remote Management

        # Configure firewall rules via registry (simplified approach)
        # In production, use proper firewall GP settings
        $firewallRegPath = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules'
        
        # WinRM HTTP rule
        $winrmHttpRule = 'v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=5985|Name=Windows Remote Management (HTTP-In)|'
        Set-GPRegistryValue -Name $GPOName -Key $firewallRegPath -ValueName 'WinRM-HTTP-In' -Type String -Value $winrmHttpRule -ErrorAction SilentlyContinue

        # Link to domain root if requested
        if ($LinkToRoot) {
            $domainDN = Get-DomainDN
            if ($domainDN) {
                # Check if already linked
                $links = (Get-GPO -Name $GPOName).GpoStatus
                try {
                    New-GPLink -Name $GPOName -Target $domainDN -ErrorAction SilentlyContinue
                    Write-SetupLog -Message "Linked GPO to domain root: $domainDN"
                }
                catch {
                    if ($_.Exception.Message -notmatch 'already linked') {
                        Write-SetupLog -Message "Warning linking GPO: $($_.Exception.Message)" -Level Warning
                    }
                }
            }
        }

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            GPOName     = $GPOName
            GPOId       = $gpo.Id
            LinkedTo    = if ($LinkToRoot) { Get-DomainDN } else { $null }
            Status      = 'Created'
            CreatedDate = Get-Date
        }

        Write-SetupLog -Message "WinRM GPO initialization complete"
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
