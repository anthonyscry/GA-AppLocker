<#
.SYNOPSIS
    Resolves an AD group name to its SID, with graceful fallback.

.DESCRIPTION
    Attempts to resolve a group name to a Security Identifier (SID) using
    multiple methods in order: well-known SIDs, .NET NTAccount translation,
    domain-prefixed NTAccount, and ADSI/LDAP query fallback.

    This function is designed for air-gapped environments where AD modules
    may not be available. It uses pure .NET and ADSI calls (no ActiveDirectory module).

.PARAMETER GroupName
    The name of the group to resolve (e.g., 'AppLocker-Users').

.PARAMETER FallbackToPlaceholder
    If $true (default), returns a wildcard SID pattern when resolution fails.
    If $false, returns $null on failure.

.EXAMPLE
    Resolve-GroupSid -GroupName 'AppLocker-Users'
    # Returns: S-1-5-21-1234567890-1234567890-1234567890-1234

.EXAMPLE
    Resolve-GroupSid -GroupName 'RESOLVE:AppLocker-Admins'
    # Strips RESOLVE: prefix and resolves 'AppLocker-Admins'

.OUTPUTS
    [string] The resolved SID, or a placeholder pattern on failure.
#>
function Resolve-GroupSid {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,

        [Parameter()]
        [switch]$FallbackToPlaceholder = $true
    )

    # Strip RESOLVE: prefix if present
    if ($GroupName.StartsWith('RESOLVE:')) {
        $GroupName = $GroupName.Substring(8)
    }

    # If it already looks like a SID, return as-is
    if ($GroupName -match '^S-1-\d+(-\d+)+$') {
        return $GroupName
    }

    # Well-known SIDs - return immediately without lookup
    $wellKnown = @{
        'Everyone'            = 'S-1-1-0'
        'Administrators'      = 'S-1-5-32-544'
        'Users'               = 'S-1-5-32-545'
        'Authenticated Users' = 'S-1-5-11'
    }

    if ($wellKnown.ContainsKey($GroupName)) {
        return $wellKnown[$GroupName]
    }

    # Cache for resolved groups (avoid repeated lookups and warning spam)
    # NOTE: Only cache SUCCESSFUL resolutions. UNRESOLVED values are NOT cached
    # so retries can succeed if domain connectivity is restored.
    if (-not $script:ResolvedGroupCache) {
        $script:ResolvedGroupCache = @{}
    }
    if ($script:ResolvedGroupCache.ContainsKey($GroupName)) {
        $cached = $script:ResolvedGroupCache[$GroupName]
        # Only return cached value if it's a valid SID (not UNRESOLVED)
        if ($cached -match '^S-1-') {
            return $cached
        }
    }

    # Method 1: .NET NTAccount translation (works for domain and local groups)
    try {
        $ntAccount = [System.Security.Principal.NTAccount]::new($GroupName)
        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])

        if ($sid) {
            try {
                Write-AppLockerLog -Message "Resolved group '$GroupName' to SID: $($sid.Value)" -Level 'INFO'
            } catch {
                # Intentional: prevent recursive logging failure (Write-AppLockerLog may not be available in all scopes)
            }
            $script:ResolvedGroupCache[$GroupName] = $sid.Value
            return $sid.Value
        }
    }
    catch {
        # NTAccount translation failed - fallback chain continues to next resolution method
        Write-AppLockerLog -Message "[Resolve-GroupSid] NTAccount translation failed for '$GroupName': $_" -Level DEBUG
    }

    # Method 2: Try with domain prefix (DOMAIN\GroupName)
    try {
        $domain = $env:USERDOMAIN
        if ($domain -and $domain -ne $env:COMPUTERNAME) {
            $ntAccount = [System.Security.Principal.NTAccount]::new("$domain\$GroupName")
            $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
            
            if ($sid) {
                try {
                    Write-AppLockerLog -Message "Resolved group '$domain\$GroupName' to SID: $($sid.Value)" -Level 'INFO'
                } catch {
                    # Intentional: prevent recursive logging failure (Write-AppLockerLog may not be available in all scopes)
                }
                $script:ResolvedGroupCache[$GroupName] = $sid.Value
                return $sid.Value
            }
        }
    }
    catch {
        # Domain-prefix NTAccount translation failed - fallback chain continues to ADSI
        Write-AppLockerLog -Message "[Resolve-GroupSid] Domain-prefix NTAccount translation failed for '$GroupName': $_" -Level DEBUG
    }

    # Method 3: ADSI/LDAP query fallback (works in air-gapped environments without AD module)
    try {
        $searcher = [ADSISearcher]"(&(objectClass=group)(name=$GroupName))"
        $searcher.PropertiesToLoad.AddRange(@('objectSid', 'name'))
        $result = $searcher.FindOne()
        if ($result) {
            $sidBytes = $result.Properties['objectsid'][0]
            if ($sidBytes) {
                $sidObj = [System.Security.Principal.SecurityIdentifier]::new($sidBytes, 0)
                $sidValue = $sidObj.Value
                try {
                    Write-AppLockerLog -Message "Resolved group '$GroupName' to SID via ADSI: $sidValue" -Level 'INFO'
                } catch {
                    # Intentional: prevent recursive logging failure (Write-AppLockerLog may not be available in all scopes)
                }
                $script:ResolvedGroupCache[$GroupName] = $sidValue
                return $sidValue
            }
        }
    }
    catch {
        # ADSI query failed - machine may not be domain-joined or LDAP unreachable; fallback chain continues
        Write-AppLockerLog -Message "[Resolve-GroupSid] ADSI query failed for '$GroupName': $_" -Level DEBUG
    }

    # Method 4: Try ADSI with explicit domain root
    try {
        $rootDSE = [ADSI]'LDAP://RootDSE'
        $defaultNC = $rootDSE.defaultNamingContext
        if ($defaultNC) {
            $searcher2 = [ADSISearcher]::new([ADSI]"LDAP://$defaultNC", "(&(objectClass=group)(name=$GroupName))")
            $searcher2.PropertiesToLoad.AddRange(@('objectSid', 'name'))
            $result2 = $searcher2.FindOne()
            if ($result2) {
                $sidBytes2 = $result2.Properties['objectsid'][0]
                if ($sidBytes2) {
                    $sidObj2 = [System.Security.Principal.SecurityIdentifier]::new($sidBytes2, 0)
                    $sidValue2 = $sidObj2.Value
                    try {
                        Write-AppLockerLog -Message "Resolved group '$GroupName' to SID via explicit LDAP: $sidValue2" -Level 'INFO'
                    } catch {
                        # Intentional: prevent recursive logging failure (Write-AppLockerLog may not be available in all scopes)
                    }
                    $script:ResolvedGroupCache[$GroupName] = $sidValue2
                    return $sidValue2
                }
            }
        }
    }
    catch {
        # Explicit LDAP also failed - all 4 resolution methods exhausted
        Write-AppLockerLog -Message "[Resolve-GroupSid] Explicit LDAP query failed for '$GroupName': $_" -Level DEBUG
    }

    # Log warning only once per group name
    try {
        Write-AppLockerLog -Message "Could not resolve group '$GroupName' - using UNRESOLVED placeholder (all 4 methods failed: NTAccount, domain-prefix, ADSI, explicit LDAP)" -Level 'WARNING'
    } catch {
        # Intentional: prevent recursive logging failure (Write-AppLockerLog may not be available in all scopes)
    }

    # Fallback: return placeholder or null
    # NOTE: Do NOT cache UNRESOLVED values so retries can succeed later
    if ($FallbackToPlaceholder) {
        return "UNRESOLVED:$GroupName"
    }

    return $null
}
