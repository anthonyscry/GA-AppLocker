<#
.SYNOPSIS
    In-memory cache manager for GA-AppLocker with TTL support.

.DESCRIPTION
    Provides a thread-safe caching layer to reduce repeated expensive operations
    like file I/O, database queries, and computations. Supports:
    - Time-to-live (TTL) expiration
    - Factory functions for cache-miss scenarios
    - Pattern-based cache invalidation
    - Cache statistics for monitoring

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>

#region ===== CACHE STORAGE =====
# Thread-safe cache storage using synchronized hashtable
if (-not $script:CacheStore) {
    $script:CacheStore = [hashtable]::Synchronized(@{})
}

# Cache statistics
if (-not $script:CacheStats) {
    $script:CacheStats = [hashtable]::Synchronized(@{
        Hits = 0
        Misses = 0
        Evictions = 0
        Sets = 0
    })
}
#endregion

#region ===== PUBLIC FUNCTIONS =====

<#
.SYNOPSIS
    Gets a cached value or creates it using a factory function.

.DESCRIPTION
    Retrieves a value from cache if it exists and hasn't expired.
    If the value is missing or expired, executes the factory function
    to create a new value and caches it.

.PARAMETER Key
    Unique identifier for the cached item.

.PARAMETER MaxAgeSeconds
    Maximum age in seconds before the cached value expires. Default is 300 (5 minutes).

.PARAMETER Factory
    Script block to execute if cache miss occurs. The result is cached.

.PARAMETER ForceRefresh
    If specified, ignores cached value and always executes the factory.

.EXAMPLE
    $ruleCounts = Get-CachedValue -Key 'RuleCounts' -MaxAgeSeconds 60 -Factory { Get-RuleCounts }

.EXAMPLE
    $data = Get-CachedValue -Key 'ExpensiveQuery' -Factory { Invoke-ExpensiveOperation } -ForceRefresh

.OUTPUTS
    The cached or newly created value.
#>
function Get-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        [int]$MaxAgeSeconds = 300,

        [Parameter()]
        [scriptblock]$Factory,

        [Parameter()]
        [switch]$ForceRefresh
    )

    $cacheEntry = $script:CacheStore[$Key]
    $now = [DateTime]::UtcNow

    # Check if we have a valid cached value
    if (-not $ForceRefresh -and $cacheEntry) {
        $age = ($now - $cacheEntry.CreatedAt).TotalSeconds
        if ($age -lt $MaxAgeSeconds) {
            $script:CacheStats.Hits++
            return $cacheEntry.Value
        }
        # Expired - will be replaced
        $script:CacheStats.Evictions++
    }

    # Cache miss or forced refresh
    $script:CacheStats.Misses++

    if ($Factory) {
        $value = & $Factory
        Set-CachedValue -Key $Key -Value $value -TTLSeconds $MaxAgeSeconds
        return $value
    }

    return $null
}

<#
.SYNOPSIS
    Sets a value in the cache with optional TTL.

.DESCRIPTION
    Stores a value in the cache with metadata for expiration tracking.

.PARAMETER Key
    Unique identifier for the cached item.

.PARAMETER Value
    The value to cache.

.PARAMETER TTLSeconds
    Time-to-live in seconds. Default is 300 (5 minutes).

.EXAMPLE
    Set-CachedValue -Key 'UserPrefs' -Value $prefs -TTLSeconds 3600

.OUTPUTS
    None
#>
function Set-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Value,

        [Parameter()]
        [int]$TTLSeconds = 300
    )

    $script:CacheStore[$Key] = @{
        Value = $Value
        CreatedAt = [DateTime]::UtcNow
        TTLSeconds = $TTLSeconds
    }
    $script:CacheStats.Sets++
}

<#
.SYNOPSIS
    Removes items from the cache.

.DESCRIPTION
    Clears cached items matching a pattern or all items if no pattern specified.

.PARAMETER Pattern
    Wildcard pattern to match cache keys. If not specified, clears entire cache.

.PARAMETER Key
    Specific key to remove.

.EXAMPLE
    Clear-AppLockerCache
    # Clears all cached items

.EXAMPLE
    Clear-AppLockerCache -Pattern 'Rule*'
    # Clears all items with keys starting with 'Rule'

.EXAMPLE
    Clear-AppLockerCache -Key 'RuleCounts'
    # Removes specific cache entry

.OUTPUTS
    [int] Number of items removed
#>
function Clear-AppLockerCache {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Pattern,

        [Parameter()]
        [string]$Key
    )

    $removed = 0

    if ($Key) {
        if ($script:CacheStore.ContainsKey($Key)) {
            $script:CacheStore.Remove($Key)
            $removed = 1
        }
    }
    elseif ($Pattern) {
        $keysToRemove = @($script:CacheStore.Keys | Where-Object { $_ -like $Pattern })
        foreach ($k in $keysToRemove) {
            $script:CacheStore.Remove($k)
            $removed++
        }
    }
    else {
        $removed = $script:CacheStore.Count
        $script:CacheStore.Clear()
    }

    $script:CacheStats.Evictions += $removed
    return $removed
}

<#
.SYNOPSIS
    Gets cache statistics.

.DESCRIPTION
    Returns statistics about cache usage including hits, misses, and evictions.

.PARAMETER Reset
    If specified, resets statistics after returning them.

.EXAMPLE
    Get-CacheStatistics

.EXAMPLE
    Get-CacheStatistics -Reset

.OUTPUTS
    [PSCustomObject] Cache statistics
#>
function Get-CacheStatistics {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Reset
    )

    $total = $script:CacheStats.Hits + $script:CacheStats.Misses
    $hitRate = if ($total -gt 0) { [math]::Round(($script:CacheStats.Hits / $total) * 100, 2) } else { 0 }

    $stats = [PSCustomObject]@{
        Hits = $script:CacheStats.Hits
        Misses = $script:CacheStats.Misses
        HitRate = "$hitRate%"
        Sets = $script:CacheStats.Sets
        Evictions = $script:CacheStats.Evictions
        CurrentItems = $script:CacheStore.Count
        TotalRequests = $total
    }

    if ($Reset) {
        $script:CacheStats.Hits = 0
        $script:CacheStats.Misses = 0
        $script:CacheStats.Evictions = 0
        $script:CacheStats.Sets = 0
    }

    return $stats
}

<#
.SYNOPSIS
    Tests if a cache key exists and is valid.

.DESCRIPTION
    Checks if a key exists in cache and hasn't expired.

.PARAMETER Key
    The cache key to test.

.PARAMETER MaxAgeSeconds
    Maximum age to consider valid. Default is 300.

.EXAMPLE
    if (Test-CacheKey -Key 'RuleCounts') { ... }

.OUTPUTS
    [bool] True if key exists and is valid
#>
function Test-CacheKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        [int]$MaxAgeSeconds = 300
    )

    $cacheEntry = $script:CacheStore[$Key]
    if (-not $cacheEntry) { return $false }

    $age = ([DateTime]::UtcNow - $cacheEntry.CreatedAt).TotalSeconds
    return $age -lt $MaxAgeSeconds
}

<#
.SYNOPSIS
    Removes expired entries from cache.

.DESCRIPTION
    Scans the cache and removes all entries that have exceeded their TTL.
    Useful for periodic maintenance.

.EXAMPLE
    Invoke-CacheCleanup

.OUTPUTS
    [int] Number of expired entries removed
#>
function Invoke-CacheCleanup {
    [CmdletBinding()]
    param()

    $now = [DateTime]::UtcNow
    $removed = 0
    $keysToRemove = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $script:CacheStore.Keys) {
        $entry = $script:CacheStore[$key]
        if ($entry -and $entry.TTLSeconds) {
            $age = ($now - $entry.CreatedAt).TotalSeconds
            if ($age -ge $entry.TTLSeconds) {
                [void]$keysToRemove.Add($key)
            }
        }
    }

    foreach ($key in $keysToRemove) {
        $script:CacheStore.Remove($key)
        $removed++
    }

    $script:CacheStats.Evictions += $removed
    return $removed
}

#endregion
