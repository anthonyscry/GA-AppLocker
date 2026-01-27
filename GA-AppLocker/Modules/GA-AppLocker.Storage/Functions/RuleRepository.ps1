<#
.SYNOPSIS
    Repository pattern implementation for rule data access.

.DESCRIPTION
    Provides a high-level abstraction layer over the JSON storage backend.
    Implements the Repository pattern for clean separation between business logic
    and data persistence. Features:
    - Unified CRUD operations
    - Query builder with fluent interface
    - Automatic caching integration
    - Event publishing on data changes
    - Transaction-like batch operations

.NOTES
    Author: GA-AppLocker Team
    Version: 2.0.0 - JSON-only storage
#>

#region ===== REPOSITORY CLASS =====

<#
.SYNOPSIS
    Gets a rule by its ID from the repository.

.DESCRIPTION
    Retrieves a single rule by ID, using cache if available.

.PARAMETER RuleId
    The unique identifier of the rule.

.PARAMETER BypassCache
    If specified, bypasses the cache and reads from storage.

.EXAMPLE
    $rule = Get-RuleFromRepository -RuleId 'rule-123'

.OUTPUTS
    [PSCustomObject] The rule object, or $null if not found
#>
function Get-RuleFromRepository {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId,

        [Parameter()]
        [switch]$BypassCache
    )

    $cacheKey = "Rule_$RuleId"

    if (-not $BypassCache) {
        # Try cache first
        if (Get-Command -Name 'Get-CachedValue' -ErrorAction SilentlyContinue) {
            $cached = Get-CachedValue -Key $cacheKey -MaxAgeSeconds 300
            if ($cached) { return $cached }
        }
    }

    # Get from storage
    $rule = Get-RuleFromDatabase -RuleId $RuleId

    # Cache the result
    if ($rule -and (Get-Command -Name 'Set-CachedValue' -ErrorAction SilentlyContinue)) {
        Set-CachedValue -Key $cacheKey -Value $rule -TTLSeconds 300
    }

    return $rule
}

<#
.SYNOPSIS
    Saves a rule to the repository.

.DESCRIPTION
    Creates or updates a rule in the repository. Handles cache invalidation
    and event publishing.

.PARAMETER Rule
    The rule object to save.

.PARAMETER IsNew
    If specified, treats this as a new rule (for event publishing).

.EXAMPLE
    Save-RuleToRepository -Rule $rule

.EXAMPLE
    Save-RuleToRepository -Rule $newRule -IsNew

.OUTPUTS
    [PSCustomObject] Result object with Success and Data properties
#>
function Save-RuleToRepository {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Rule,

        [Parameter()]
        [switch]$IsNew
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data = $null
        Error = $null
    }

    try {
        # Validate rule has required properties
        if (-not $Rule.RuleId) {
            throw "Rule must have a RuleId property"
        }

        # Determine if this is create or update
        $existing = $null
        if (-not $IsNew) {
            $existing = Get-RuleFromDatabase -RuleId $Rule.RuleId
        }

        if ($existing) {
            # Update existing rule
            $updateResult = Update-RuleInDatabase -RuleId $Rule.RuleId -UpdatedRule $Rule
            if (-not $updateResult.Success) {
                throw $updateResult.Error
            }
            $eventName = 'RuleUpdated'
        }
        else {
            # Create new rule
            $addResult = Add-RuleToDatabase -Rule $Rule
            if (-not $addResult.Success) {
                throw $addResult.Error
            }
            $eventName = 'RuleCreated'
        }

        # Invalidate cache
        $cacheKey = "Rule_$($Rule.RuleId)"
        if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
            Clear-AppLockerCache -Key $cacheKey
            Clear-AppLockerCache -Pattern 'RuleCounts*'
            Clear-AppLockerCache -Pattern 'RuleQuery*'
        }

        # Publish event
        if (Get-Command -Name 'Publish-AppLockerEvent' -ErrorAction SilentlyContinue) {
            Publish-AppLockerEvent -EventName $eventName -EventData @{
                RuleId = $Rule.RuleId
                RuleType = $Rule.RuleType
                Status = $Rule.Status
            }
        }

        $result.Success = $true
        $result.Data = $Rule
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-StorageLog -Message "Save-RuleToRepository failed: $($_.Exception.Message)" -Level 'ERROR'
    }

    return $result
}

<#
.SYNOPSIS
    Removes a rule from the repository.

.DESCRIPTION
    Deletes a rule and handles cache invalidation and event publishing.

.PARAMETER RuleId
    The ID of the rule to remove.

.EXAMPLE
    Remove-RuleFromRepository -RuleId 'rule-123'

.OUTPUTS
    [PSCustomObject] Result object with Success property
#>
function Remove-RuleFromRepository {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId
    )

    $result = [PSCustomObject]@{
        Success = $false
        Error = $null
    }

    try {
        # Get rule info before deletion for event
        $rule = Get-RuleFromDatabase -RuleId $RuleId

        # Delete from storage
        $deleteResult = Remove-RuleFromDatabase -RuleId $RuleId
        if (-not $deleteResult.Success) {
            throw $deleteResult.Error
        }

        # Invalidate cache
        if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
            Clear-AppLockerCache -Key "Rule_$RuleId"
            Clear-AppLockerCache -Pattern 'RuleCounts*'
            Clear-AppLockerCache -Pattern 'RuleQuery*'
        }

        # Publish event
        if ($rule -and (Get-Command -Name 'Publish-AppLockerEvent' -ErrorAction SilentlyContinue)) {
            Publish-AppLockerEvent -EventName 'RuleDeleted' -EventData @{
                RuleId = $RuleId
                RuleType = $rule.RuleType
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-StorageLog -Message "Remove-RuleFromRepository failed: $($_.Exception.Message)" -Level 'ERROR'
    }

    return $result
}

<#
.SYNOPSIS
    Finds rules in the repository with filtering.

.DESCRIPTION
    Queries rules with flexible filtering options. Results are cached
    for repeated queries with same parameters.

.PARAMETER Filter
    Hashtable of filter conditions. Supports:
    - Status: Rule status (Pending, Approved, etc.)
    - RuleType: Hash, Publisher, Path
    - CollectionType: Exe, Dll, Msi, Script, Appx
    - PublisherPattern: Wildcard pattern for publisher name
    - Search: Text search across name/description

.PARAMETER Take
    Maximum number of results to return.

.PARAMETER Skip
    Number of results to skip (for pagination).

.PARAMETER OrderBy
    Property to sort by.

.PARAMETER Descending
    Sort in descending order.

.PARAMETER BypassCache
    Skip cache and query storage directly.

.EXAMPLE
    $pendingRules = Find-RulesInRepository -Filter @{ Status = 'Pending' } -Take 100

.EXAMPLE
    $msRules = Find-RulesInRepository -Filter @{ PublisherPattern = '*MICROSOFT*' }

.OUTPUTS
    [PSCustomObject[]] Array of matching rules
#>
function Find-RulesInRepository {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [hashtable]$Filter = @{},

        [Parameter()]
        [int]$Take = 1000,

        [Parameter()]
        [int]$Skip = 0,

        [Parameter()]
        [string]$OrderBy = 'CreatedDate',

        [Parameter()]
        [switch]$Descending,

        [Parameter()]
        [switch]$BypassCache
    )

    # Build cache key from parameters
    $filterJson = $Filter | ConvertTo-Json -Compress -Depth 2
    $cacheKey = "RuleQuery_$([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$filterJson|$Take|$Skip|$OrderBy|$Descending")))"

    if (-not $BypassCache) {
        if (Get-Command -Name 'Get-CachedValue' -ErrorAction SilentlyContinue) {
            $cached = Get-CachedValue -Key $cacheKey -MaxAgeSeconds 60
            if ($cached) { return $cached }
        }
    }

    # Build query parameters for Get-RulesFromDatabase
    $queryParams = @{
        Take = $Take
        Skip = $Skip
    }

    if ($Filter.Status) { $queryParams.Status = $Filter.Status }
    if ($Filter.RuleType) { $queryParams.RuleType = $Filter.RuleType }
    if ($Filter.CollectionType) { $queryParams.CollectionType = $Filter.CollectionType }

    # Execute query
    $rules = Get-RulesFromDatabase @queryParams

    # Apply additional filters that aren't supported by storage layer
    if ($Filter.PublisherPattern -and $rules) {
        $rules = @($rules | Where-Object { 
            $_.PublisherName -like $Filter.PublisherPattern -or
            $_.Publisher -like $Filter.PublisherPattern
        })
    }

    if ($Filter.Search -and $rules) {
        $searchTerm = $Filter.Search
        $rules = @($rules | Where-Object {
            $_.Name -like "*$searchTerm*" -or
            $_.Description -like "*$searchTerm*" -or
            $_.FileName -like "*$searchTerm*"
        })
    }

    # Sort if OrderBy specified
    if ($OrderBy -and $rules) {
        if ($Descending) {
            $rules = @($rules | Sort-Object -Property $OrderBy -Descending)
        }
        else {
            $rules = @($rules | Sort-Object -Property $OrderBy)
        }
    }

    # Cache results
    if ($rules -and (Get-Command -Name 'Set-CachedValue' -ErrorAction SilentlyContinue)) {
        Set-CachedValue -Key $cacheKey -Value $rules -TTLSeconds 60
    }

    return $rules
}

<#
.SYNOPSIS
    Gets rule counts with caching.

.DESCRIPTION
    Returns counts of rules by status, using cache for performance.

.PARAMETER BypassCache
    Skip cache and query storage directly.

.EXAMPLE
    $counts = Get-RuleCountsFromRepository

.OUTPUTS
    [PSCustomObject] Counts by status
#>
function Get-RuleCountsFromRepository {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$BypassCache
    )

    $cacheKey = 'RuleCounts_All'

    if (-not $BypassCache) {
        if (Get-Command -Name 'Get-CachedValue' -ErrorAction SilentlyContinue) {
            $cached = Get-CachedValue -Key $cacheKey -MaxAgeSeconds 120
            if ($cached) { return $cached }
        }
    }

    $counts = Get-RuleCounts

    if ($counts -and (Get-Command -Name 'Set-CachedValue' -ErrorAction SilentlyContinue)) {
        Set-CachedValue -Key $cacheKey -Value $counts -TTLSeconds 120
    }

    return $counts
}

<#
.SYNOPSIS
    Performs a batch operation on multiple rules.

.DESCRIPTION
    Executes an operation on multiple rules efficiently, with single
    cache invalidation and event at the end.

.PARAMETER RuleIds
    Array of rule IDs to operate on.

.PARAMETER Operation
    The operation to perform: 'UpdateStatus', 'Delete'

.PARAMETER Parameters
    Hashtable of operation parameters.

.EXAMPLE
    Invoke-RuleBatchOperation -RuleIds @('r1','r2','r3') -Operation 'UpdateStatus' -Parameters @{ Status = 'Approved' }

.EXAMPLE
    Invoke-RuleBatchOperation -RuleIds $duplicateIds -Operation 'Delete'

.OUTPUTS
    [PSCustomObject] Result with success count and errors
#>
function Invoke-RuleBatchOperation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RuleIds,

        [Parameter(Mandatory)]
        [ValidateSet('UpdateStatus', 'Delete')]
        [string]$Operation,

        [Parameter()]
        [hashtable]$Parameters = @{}
    )

    $result = [PSCustomObject]@{
        Success = $false
        Processed = 0
        Failed = 0
        Errors = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($ruleId in $RuleIds) {
        try {
            switch ($Operation) {
                'UpdateStatus' {
                    $rule = Get-RuleFromDatabase -RuleId $ruleId
                    if ($rule) {
                        $rule.Status = $Parameters.Status
                        $rule.ModifiedDate = (Get-Date).ToString('o')
                        Update-RuleInDatabase -RuleId $ruleId -UpdatedRule $rule | Out-Null
                        $result.Processed++
                    }
                }
                'Delete' {
                    Remove-RuleFromDatabase -RuleId $ruleId | Out-Null
                    $result.Processed++
                }
            }
        }
        catch {
            $result.Failed++
            $result.Errors.Add("Rule $ruleId`: $($_.Exception.Message)")
        }
    }

    # Bulk cache invalidation
    if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
        Clear-AppLockerCache -Pattern 'Rule*'
    }

    # Single bulk event
    if (Get-Command -Name 'Publish-AppLockerEvent' -ErrorAction SilentlyContinue) {
        Publish-AppLockerEvent -EventName 'RuleBulkUpdated' -EventData @{
            Operation = $Operation
            Count = $result.Processed
            RuleIds = $RuleIds
        }
    }

    $result.Success = ($result.Failed -eq 0)
    return $result
}

<#
.SYNOPSIS
    Checks if a rule exists in the repository.

.DESCRIPTION
    Efficiently checks for rule existence without loading the full rule.

.PARAMETER RuleId
    The rule ID to check.

.PARAMETER Hash
    Alternative: check by hash value.

.EXAMPLE
    if (Test-RuleExistsInRepository -RuleId 'rule-123') { ... }

.EXAMPLE
    if (Test-RuleExistsInRepository -Hash 'ABC123...') { ... }

.OUTPUTS
    [bool] True if rule exists
#>
function Test-RuleExistsInRepository {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [string]$RuleId,

        [Parameter(ParameterSetName = 'ByHash')]
        [string]$Hash
    )

    if ($RuleId) {
        $rule = Get-RuleFromDatabase -RuleId $RuleId
        return ($null -ne $rule)
    }

    if ($Hash) {
        $rule = Find-RuleByHash -Hash $Hash
        return ($null -ne $rule)
    }

    return $false
}

#endregion
