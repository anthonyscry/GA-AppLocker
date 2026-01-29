<#
.SYNOPSIS
    LDAP helper functions for AD Discovery without RSAT.
.DESCRIPTION
    PowerShell 5.1 compatible LDAP functions with centralized server
    resolution and robust error handling for air-gapped environments.
.NOTES
    Author: GA-AppLocker Team
#>

function Resolve-LdapServer {
    <#
    .SYNOPSIS
        Centralized LDAP server resolution. Single source of truth for all ViaLdap functions.
    .DESCRIPTION
        Resolution order:
        1. Explicit -Server parameter (highest priority)
        2. config.json LdapServer property
        3. $env:USERDNSDOMAIN (domain-joined machines)
        4. Returns $null with clear error (not 'localhost' which always fails silently)
    .OUTPUTS
        [PSCustomObject] with Server, Port, Source properties, or $null if unresolvable.
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [int]$Port = 0
    )

    # 1. Explicit parameter — highest priority
    if ($Server) {
        $resolvedPort = if ($Port -gt 0) { $Port } else { 389 }
        return [PSCustomObject]@{ Server = $Server; Port = $resolvedPort; Source = 'Parameter' }
    }

    # 2. Saved configuration
    try {
        $config = Get-AppLockerConfig
        if ($config.LdapServer) {
            $resolvedPort = if ($Port -gt 0) { $Port } elseif ($config.LdapPort) { [int]$config.LdapPort } else { 389 }
            return [PSCustomObject]@{ Server = $config.LdapServer; Port = $resolvedPort; Source = 'Config' }
        }
    }
    catch {
        Write-AppLockerLog -Level Warning -Message "Could not read config for LDAP resolution: $($_.Exception.Message)" -NoConsole
    }

    # 3. Environment variable (domain-joined machines)
    if ($env:USERDNSDOMAIN) {
        $resolvedPort = if ($Port -gt 0) { $Port } else { 389 }
        return [PSCustomObject]@{ Server = $env:USERDNSDOMAIN; Port = $resolvedPort; Source = 'Environment' }
    }

    # 4. No server found — return null (DO NOT default to 'localhost')
    Write-AppLockerLog -Level Warning -Message "No LDAP server configured. Use Set-LdapConfiguration to set a server, or join the machine to a domain." -NoConsole
    return $null
}

function Get-LdapConnection {
    <#
    .SYNOPSIS
        Creates an authenticated LDAP connection.
    .DESCRIPTION
        Establishes an LDAP connection using centralized server resolution.
        Validates server parameter before attempting connection to provide
        clear error messages instead of cryptic .NET exceptions.
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [int]$Port = 389,
        [pscredential]$Credential,
        [bool]$UseSSL = $false
    )
    
    try {
        # Resolve server if not explicitly provided
        if (-not $Server) {
            $resolved = Resolve-LdapServer -Port $Port
            if (-not $resolved) {
                Write-AppLockerLog -Level Error -Message "LDAP connection failed: No domain controller configured. Use Set-LdapConfiguration or join a domain."
                return $null
            }
            $Server = $resolved.Server
            $Port = $resolved.Port
        }

        # Validate server is not empty/whitespace after resolution
        if ([string]::IsNullOrWhiteSpace($Server)) {
            Write-AppLockerLog -Level Error -Message "LDAP connection failed: Server name is empty. Use Set-LdapConfiguration to configure a server."
            return $null
        }

        Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction Stop
        $ldapServer = if ($Port -ne 389) { "${Server}:${Port}" } else { $Server }
        $connection = New-Object System.DirectoryServices.Protocols.LdapConnection($ldapServer)
        $connection.SessionOptions.ProtocolVersion = 3
        $connection.SessionOptions.ReferralChasing = [System.DirectoryServices.Protocols.ReferralChasingOptions]::None
        if ($UseSSL) { $connection.SessionOptions.SecureSocketLayer = $true }
        if ($Credential) {
            # Validate credential before bind attempt (B8)
            $netCred = $Credential.GetNetworkCredential()
            if ([string]::IsNullOrWhiteSpace($netCred.UserName)) {
                Write-AppLockerLog -Level Error -Message "LDAP connection failed: Credential has empty username."
                return $null
            }
            # Warn about Basic auth without SSL
            if (-not $UseSSL) {
                Write-AppLockerLog -Level Warning -Message "LDAP: Using Basic authentication without SSL. Credentials transmitted base64-encoded. Consider enabling SSL (-UseSSL) for production deployments."
            }
            $connection.Credential = $netCred
            $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Basic
        } else {
            $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
        }
        $connection.Bind()
        return $connection
    }
    catch {
        Write-AppLockerLog -Level Error -Message "LDAP connection failed to '${Server}:${Port}': $($_.Exception.Message)"
        return $null
    }
}

function Get-LdapSearchResult {
    <#
    .SYNOPSIS
        Executes an LDAP search with paging support for large result sets.
    .DESCRIPTION
        Uses PageResultRequestControl to retrieve all results beyond the
        server's default size limit. Logs a warning when results exceed
        the initial page size to alert on large datasets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.DirectoryServices.Protocols.LdapConnection]$Connection,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SearchBase,
        [string]$Filter = "(objectClass=*)",
        [string[]]$Properties = @("*"),
        [System.DirectoryServices.Protocols.SearchScope]$Scope = "Subtree",
        [int]$PageSize = 1000
    )
    try {
        $request = New-Object System.DirectoryServices.Protocols.SearchRequest($SearchBase, $Filter, $Scope, $Properties)
        
        # Use paging to avoid silent truncation (B5)
        $pageControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($PageSize)
        [void]$request.Controls.Add($pageControl)
        
        $allEntries = [System.Collections.ArrayList]::new()
        $pageCount = 0
        
        do {
            $pageCount++
            $response = [System.DirectoryServices.Protocols.SearchResponse]$Connection.SendRequest($request)
            
            if ($response.Entries.Count -gt 0) {
                foreach ($entry in $response.Entries) {
                    [void]$allEntries.Add($entry)
                }
            }
            
            # Get the paging response control to check for more pages
            $pageResponseControl = $null
            foreach ($control in $response.Controls) {
                if ($control -is [System.DirectoryServices.Protocols.PageResultResponseControl]) {
                    $pageResponseControl = $control
                    break
                }
            }
            
            # Update the cookie for the next page
            if ($pageResponseControl -and $pageResponseControl.Cookie.Length -gt 0) {
                $pageControl.Cookie = $pageResponseControl.Cookie
            }
            else {
                break
            }
        } while ($true)
        
        # Warn if results exceeded a single page (indicates large dataset)
        if ($pageCount -gt 1) {
            Write-AppLockerLog -Level Warning -Message "LDAP search returned $($allEntries.Count) results across $pageCount pages (Base: '$SearchBase', Filter: '$Filter'). Consider narrowing your search." -NoConsole
        }
        
        return $allEntries.ToArray()
    }
    catch {
        Write-AppLockerLog -Level Error -Message "LDAP search failed (Base: '$SearchBase', Filter: '$Filter'): $($_.Exception.Message)"
        return @()
    }
}

function Get-DomainInfoViaLdap {
    <#
    .SYNOPSIS
        Retrieves domain info via LDAP (no RSAT required).
    .DESCRIPTION
        Uses centralized Resolve-LdapServer for server resolution.
    #>
    [CmdletBinding()]
    param([string]$Server, [int]$Port = 389, [pscredential]$Credential)
    
    $result = [PSCustomObject]@{ Success = $false; Data = $null; Error = $null }
    
    try {
        # Use centralized server resolution
        $resolved = Resolve-LdapServer -Server $Server -Port $Port
        if (-not $resolved) {
            $result.Error = "No LDAP server configured. Use Set-LdapConfiguration to set a server, or join the machine to a domain."
            return $result
        }
        $Server = $resolved.Server
        $Port = $resolved.Port
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if (-not $connection) {
            $result.Error = "Failed to connect to LDAP server: ${Server}:${Port}"
            return $result
        }
        
        $rootDse = Get-LdapSearchResult -Connection $connection -SearchBase "" -Filter "(objectClass=*)" -Scope Base
        if (-not $rootDse -or $rootDse.Count -eq 0) {
            $result.Error = "Failed to get RootDSE from ${Server}:${Port}"
            $connection.Dispose()
            return $result
        }
        
        # Null-safe RootDSE attribute access (B3)
        $ncAttr = $rootDse[0].Attributes["defaultNamingContext"]
        if (-not $ncAttr -or $ncAttr.Count -eq 0) {
            $result.Error = "RootDSE is missing 'defaultNamingContext' attribute. The LDAP server at ${Server}:${Port} may not be an Active Directory domain controller."
            $connection.Dispose()
            return $result
        }
        $defaultNC = $ncAttr[0]
        $dnsRoot = ($defaultNC -replace "DC=", "" -replace ",", ".").Trim(".")
        $domainName = ($defaultNC -split ",")[0] -replace "DC=", ""
        
        $result.Data = [PSCustomObject]@{
            Name = $domainName; DnsRoot = $dnsRoot; NetBIOSName = $domainName.ToUpper()
            DistinguishedName = $defaultNC; DomainControllers = @(); Forest = $dnsRoot
            ForestMode = "Unknown"; DomainMode = "Unknown"; PDCEmulator = $Server
            InfrastructureMaster = $Server; LdapServer = $Server; LdapPort = $Port
        }
        
        $connection.Dispose()
        $result.Success = $true
        Write-AppLockerLog -Message "Domain detected via LDAP: $dnsRoot" -NoConsole
    }
    catch {
        $result.Error = "LDAP domain query failed: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }
    return $result
}

function Get-OUTreeViaLdap {
    <#
    .SYNOPSIS
        Retrieves OU tree via LDAP (no RSAT required).
    .DESCRIPTION
        Uses centralized Resolve-LdapServer for server resolution.
    #>
    [CmdletBinding()]
    param([string]$Server, [int]$Port = 389, [pscredential]$Credential, [string]$SearchBase, [bool]$IncludeComputerCount = $true)
    
    $result = [PSCustomObject]@{ Success = $false; Data = $null; Error = $null }
    
    try {
        # Use centralized server resolution
        $resolved = Resolve-LdapServer -Server $Server -Port $Port
        if (-not $resolved) {
            $result.Error = "No LDAP server configured. Use Set-LdapConfiguration to set a server, or join the machine to a domain."
            return $result
        }
        $Server = $resolved.Server
        $Port = $resolved.Port
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if (-not $connection) {
            $result.Error = "Failed to connect to LDAP server: ${Server}:${Port}"
            return $result
        }
        
        if (-not $SearchBase) {
            $rootDse = Get-LdapSearchResult -Connection $connection -SearchBase "" -Filter "(objectClass=*)" -Scope Base
            if (-not $rootDse -or $rootDse.Count -eq 0) {
                $result.Error = "Failed to get RootDSE from ${Server}:${Port}"
                $connection.Dispose()
                return $result
            }
            # Null-safe RootDSE attribute access (B4)
            $ncAttr = $rootDse[0].Attributes["defaultNamingContext"]
            if (-not $ncAttr -or $ncAttr.Count -eq 0) {
                $result.Error = "RootDSE is missing 'defaultNamingContext' attribute. The LDAP server at ${Server}:${Port} may not be an Active Directory domain controller."
                $connection.Dispose()
                return $result
            }
            $SearchBase = $ncAttr[0]
        }
        
        $ouEntries = Get-LdapSearchResult -Connection $connection -SearchBase $SearchBase -Filter "(objectClass=organizationalUnit)" -Properties @("name", "distinguishedName")
        $ouList = [System.Collections.ArrayList]::new()
        
        foreach ($entry in $ouEntries) {
            $dn = $entry.DistinguishedName
            $name = $entry.Attributes["name"][0]
            $ouObject = [PSCustomObject]@{
                Name = $name; DistinguishedName = $dn; CanonicalName = $dn; Path = $dn
                Depth = ($dn -split ",OU=").Count - 1; ComputerCount = 0
                MachineType = Get-MachineTypeFromOU -OUPath $dn
            }
            if ($IncludeComputerCount) {
                $computers = Get-LdapSearchResult -Connection $connection -SearchBase $dn -Filter "(objectClass=computer)" -Properties @("name") -Scope OneLevel
                $ouObject.ComputerCount = $computers.Count
            }
            [void]$ouList.Add($ouObject)
        }
        
        $dnsRoot = ($SearchBase -replace "DC=", "" -replace ",", ".").Trim(".")
        $rootObject = [PSCustomObject]@{
            Name = ($SearchBase -split ",")[0] -replace "DC=", ""; DistinguishedName = $SearchBase
            CanonicalName = $dnsRoot; Path = $dnsRoot; Depth = 0; ComputerCount = 0; MachineType = "Mixed"
        }
        if ($IncludeComputerCount) {
            $rootComputers = Get-LdapSearchResult -Connection $connection -SearchBase $SearchBase -Filter "(objectClass=computer)" -Properties @("name") -Scope OneLevel
            $rootObject.ComputerCount = $rootComputers.Count
        }
        
        $connection.Dispose()
        $result.Data = @($rootObject) + ($ouList | Sort-Object DistinguishedName)
        $result.Success = $true
        Write-AppLockerLog -Message "Retrieved $($ouList.Count) OUs via LDAP" -NoConsole
    }
    catch {
        $result.Error = "LDAP OU query failed: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }
    return $result
}

function Get-ComputersByOUViaLdap {
    <#
    .SYNOPSIS
        Retrieves computers from OUs via LDAP (no RSAT required).
    .DESCRIPTION
        Uses centralized Resolve-LdapServer for server resolution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$OUDistinguishedNames,
        [string]$Server, [int]$Port = 389, [pscredential]$Credential, [bool]$IncludeNestedOUs = $true
    )
    
    $result = [PSCustomObject]@{ Success = $false; Data = $null; Error = $null }
    
    try {
        # Use centralized server resolution
        $resolved = Resolve-LdapServer -Server $Server -Port $Port
        if (-not $resolved) {
            $result.Error = "No LDAP server configured. Use Set-LdapConfiguration to set a server, or join the machine to a domain."
            return $result
        }
        $Server = $resolved.Server
        $Port = $resolved.Port
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if (-not $connection) {
            $result.Error = "Failed to connect to LDAP server: ${Server}:${Port}"
            return $result
        }
        
        $allComputers = [System.Collections.ArrayList]::new()
        $scope = if ($IncludeNestedOUs) { "Subtree" } else { "OneLevel" }
        
        foreach ($ouDN in $OUDistinguishedNames) {
            $computerEntries = Get-LdapSearchResult -Connection $connection -SearchBase $ouDN -Filter "(objectClass=computer)" -Properties @("name", "dNSHostName", "operatingSystem", "operatingSystemVersion", "distinguishedName") -Scope $scope
            
            foreach ($entry in $computerEntries) {
                $hostName = $entry.Attributes["name"][0]
                $dnsHost = if ($entry.Attributes["dNSHostName"]) { $entry.Attributes["dNSHostName"][0] } else { $hostName }
                $os = if ($entry.Attributes["operatingSystem"]) { $entry.Attributes["operatingSystem"][0] } else { "Unknown" }
                $osVer = if ($entry.Attributes["operatingSystemVersion"]) { $entry.Attributes["operatingSystemVersion"][0] } else { "" }
                
                $computer = [PSCustomObject]@{
                    Name = $hostName; Hostname = $hostName; DNSHostName = $dnsHost
                    DistinguishedName = $entry.DistinguishedName
                    OU = ($entry.DistinguishedName -split ",", 2)[1]
                    OperatingSystem = $os; OperatingSystemVersion = $osVer
                    MachineType = Get-MachineTypeFromOU -OUPath $entry.DistinguishedName
                    IsOnline = $false; WinRMStatus = "Unknown"
                }
                [void]$allComputers.Add($computer)
            }
        }
        
        $connection.Dispose()
        $result.Data = $allComputers | Sort-Object Hostname -Unique
        $result.Success = $true
        Write-AppLockerLog -Message "Found $($allComputers.Count) computers via LDAP" -NoConsole
    }
    catch {
        $result.Error = "LDAP computer query failed: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }
    return $result
}

function Set-LdapConfiguration {
    <#
    .SYNOPSIS
        Saves LDAP server settings to application config.
    .DESCRIPTION
        Persists the LDAP server, port, and SSL settings to config.json
        so Resolve-LdapServer can find them on subsequent calls.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server, [int]$Port = 389, [switch]$UseSSL)
    
    $settings = @{
        LdapServer = $Server
        LdapPort   = $Port
        LdapUseSSL = $UseSSL.IsPresent
    }
    Set-AppLockerConfig -Settings $settings
    Write-AppLockerLog -Message "LDAP configured: ${Server}:${Port} (SSL: $($UseSSL.IsPresent))"
}

function Test-LdapConnection {
    <#
    .SYNOPSIS
        Tests LDAP connectivity to a server.
    .DESCRIPTION
        Uses centralized Resolve-LdapServer for server resolution.
        Returns Success, Server, Port, Source, and Error.
    #>
    [CmdletBinding()]
    param([string]$Server, [int]$Port = 389, [pscredential]$Credential)
    
    $result = [PSCustomObject]@{ Success = $false; Server = $Server; Port = $Port; Source = 'Unknown'; Error = $null }
    
    try {
        # Use centralized server resolution
        $resolved = Resolve-LdapServer -Server $Server -Port $Port
        if (-not $resolved) {
            $result.Error = "No LDAP server configured. Use Set-LdapConfiguration to set a server, or join the machine to a domain."
            return $result
        }
        $Server = $resolved.Server
        $Port = $resolved.Port
        $result.Server = $Server
        $result.Port = $Port
        $result.Source = $resolved.Source
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if ($connection) {
            $connection.Dispose()
            $result.Success = $true
            Write-AppLockerLog -Message "LDAP connection test successful: ${Server}:${Port} (resolved via $($resolved.Source))"
        } else {
            $result.Error = "Connection returned null for ${Server}:${Port}"
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-AppLockerLog -Level Error -Message "LDAP connection test failed: $($result.Error)"
    }
    return $result
}
