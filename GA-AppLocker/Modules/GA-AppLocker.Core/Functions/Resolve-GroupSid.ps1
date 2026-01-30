<#
.SYNOPSIS
    Resolves an AD group name to its SID, with graceful fallback.

.DESCRIPTION
    Attempts to resolve a group name to a Security Identifier (SID) using
    .NET NTAccount translation. If the machine is not domain-joined or the
    group doesn't exist, returns a placeholder SID pattern.

    This function is designed for air-gapped environments where AD modules
    may not be available. It uses pure .NET calls (no ActiveDirectory module).

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

    # Try .NET NTAccount translation (works for domain and local groups)
    try {
        $ntAccount = [System.Security.Principal.NTAccount]::new($GroupName)
        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        
        if ($sid) {
            try {
                Write-AppLockerLog -Message "Resolved group '$GroupName' to SID: $($sid.Value)" -Level 'INFO'
            } catch { }
            return $sid.Value
        }
    }
    catch {
        # NTAccount translation failed - group may not exist or not domain-joined
        try {
            Write-AppLockerLog -Message "Could not resolve group '$GroupName' via NTAccount: $($_.Exception.Message)" -Level 'WARNING'
        } catch { }
    }

    # Try with domain prefix (DOMAIN\GroupName)
    try {
        $domain = $env:USERDOMAIN
        if ($domain -and $domain -ne $env:COMPUTERNAME) {
            $ntAccount = [System.Security.Principal.NTAccount]::new("$domain\$GroupName")
            $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
            
            if ($sid) {
                try {
                    Write-AppLockerLog -Message "Resolved group '$domain\$GroupName' to SID: $($sid.Value)" -Level 'INFO'
                } catch { }
                return $sid.Value
            }
        }
    }
    catch {
        # Also failed with domain prefix
        try {
            Write-AppLockerLog -Message "Could not resolve group '$env:USERDOMAIN\$GroupName': $($_.Exception.Message)" -Level 'WARNING'
        } catch { }
    }

    # Fallback: return placeholder or null
    if ($FallbackToPlaceholder) {
        # Use a wildcard SID pattern that indicates this needs resolution at deployment time
        # S-1-5-21-*-<hash> - the * indicates a domain SID that wasn't resolved
        return "UNRESOLVED:$GroupName"
    }

    return $null
}
