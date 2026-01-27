<#
.SYNOPSIS
    JSON-based rule storage for GA-AppLocker.

.DESCRIPTION
    Uses a single rules-index.json file with in-memory hashtables for O(1) lookups.
    Individual rules are stored as separate JSON files in the Rules directory.
    
.NOTES
    Version 2.0.0 - Primary storage (no longer a fallback)
#>

#region ===== MODULE STATE =====
$script:JsonIndexPath = $null
$script:JsonIndex = $null
$script:JsonIndexLoaded = $false
$script:HashIndex = @{}
$script:PublisherIndex = @{}
$script:PublisherOnlyIndex = @{}
$script:RuleById = @{}
#endregion

#region ===== PATH HELPERS =====
function Get-RuleStoragePath {
    <#
    .SYNOPSIS
        Gets the path to the rules storage directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
        Get-AppLockerDataPath
    } else {
        Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
    }
    
    return Join-Path $dataPath 'Rules'
}

function script:Get-JsonIndexPath {
    if (-not $script:JsonIndexPath) {
        $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
            Get-AppLockerDataPath
        } else {
            Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
        }
        $script:JsonIndexPath = Join-Path $dataPath 'rules-index.json'
    }
    return $script:JsonIndexPath
}
#endregion

#region ===== INDEX MANAGEMENT =====
function Reset-RulesIndexCache {
    <#
    .SYNOPSIS
        Forces the rules index to be reloaded from disk on next access.
    #>
    [CmdletBinding()]
    param()
    
    $script:JsonIndexLoaded = $false
    $script:JsonIndex = $null
    $script:HashIndex = @{}
    $script:PublisherIndex = @{}
    $script:PublisherOnlyIndex = @{}
    $script:RuleById = @{}
    Write-Verbose "Rules index cache reset - will reload from disk on next access"
}

function script:Initialize-JsonIndex {
    [CmdletBinding()]
    param([switch]$Force)
    
    if ($script:JsonIndexLoaded -and -not $Force) { return }
    
    $indexPath = Get-JsonIndexPath
    
    if (Test-Path $indexPath) {
        try {
            $content = [System.IO.File]::ReadAllText($indexPath)
            $script:JsonIndex = $content | ConvertFrom-Json
            
            # Convert to hashtables for O(1) lookup
            $script:HashIndex = @{}
            $script:PublisherIndex = @{}
            $script:PublisherOnlyIndex = @{}
            $script:RuleById = @{}
            
            foreach ($rule in $script:JsonIndex.Rules) {
                $script:RuleById[$rule.Id] = $rule
                
                if ($rule.Hash) {
                    $script:HashIndex[$rule.Hash.ToUpper()] = $rule.Id
                }
                if ($rule.PublisherName) {
                    $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                    $script:PublisherIndex[$key] = $rule.Id
                    $pubOnlyKey = $rule.PublisherName.ToLower()
                    $script:PublisherOnlyIndex[$pubOnlyKey] = $rule.Id
                }
            }
            
            $script:JsonIndexLoaded = $true
            Write-StorageLog -Message "Loaded JSON index with $($script:JsonIndex.Rules.Count) rules"
        }
        catch {
            Write-StorageLog -Message "Failed to load JSON index: $($_.Exception.Message)" -Level 'ERROR'
            $script:JsonIndex = [PSCustomObject]@{ Rules = @(); LastUpdated = (Get-Date -Format 'o') }
        }
    }
    else {
        # Index doesn't exist - check for rule files to rebuild from
        $rulesPath = Get-RuleStoragePath
        
        if ((Test-Path $rulesPath) -and (Get-ChildItem $rulesPath -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            Write-StorageLog -Message "Index missing but rules exist - rebuilding..."
            $buildResult = Rebuild-RulesIndex -RulesPath $rulesPath
            if ($buildResult.Success) {
                Write-StorageLog -Message "Index rebuilt with $($buildResult.RuleCount) rules"
                $script:JsonIndexLoaded = $false
                Initialize-JsonIndex
                return
            }
        }
        
        # No rules or rebuild failed - use empty index
        $script:JsonIndex = [PSCustomObject]@{ Rules = @(); LastUpdated = (Get-Date -Format 'o') }
        $script:HashIndex = @{}
        $script:PublisherIndex = @{}
        $script:PublisherOnlyIndex = @{}
        $script:RuleById = @{}
        $script:JsonIndexLoaded = $true
    }
}

function script:Save-JsonIndex {
    [CmdletBinding()]
    param()
    
    $indexPath = Get-JsonIndexPath
    $dir = Split-Path -Parent $indexPath
    
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    
    $script:JsonIndex.LastUpdated = Get-Date -Format 'o'
    $script:JsonIndex | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $indexPath -Encoding UTF8
}

function Rebuild-RulesIndex {
    <#
    .SYNOPSIS
        Rebuilds the JSON index from rule files on disk.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$RulesPath,
        [scriptblock]$ProgressCallback
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        RuleCount = 0
        Duration = $null
        Error = $null
    }
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    if (-not $RulesPath) {
        $RulesPath = Get-RuleStoragePath
    }
    
    if (-not (Test-Path $RulesPath)) {
        $result.Success = $true
        $result.Error = "No rules directory at: $RulesPath"
        return $result
    }
    
    try {
        $rules = [System.Collections.Generic.List[PSCustomObject]]::new()
        $files = [System.IO.Directory]::EnumerateFiles($RulesPath, '*.json', [System.IO.SearchOption]::TopDirectoryOnly)
        $fileList = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $files) { $fileList.Add($f) }
        
        $totalFiles = $fileList.Count
        $processed = 0
        
        Write-StorageLog -Message "Building index from $totalFiles JSON files..."
        
        foreach ($filePath in $fileList) {
            $processed++
            
            try {
                $content = [System.IO.File]::ReadAllText($filePath)
                $rule = $content | ConvertFrom-Json
                
                if ($rule.Id) {
                    $indexEntry = [PSCustomObject]@{
                        Id = $rule.Id
                        RuleType = $rule.RuleType
                        CollectionType = $rule.CollectionType
                        Status = if ($rule.Status) { $rule.Status } else { 'Pending' }
                        Name = $rule.Name
                        Hash = $rule.Hash
                        PublisherName = $rule.PublisherName
                        ProductName = $rule.ProductName
                        Path = $rule.Path
                        GroupVendor = $rule.GroupVendor
                        CreatedDate = $rule.CreatedDate
                        FilePath = $filePath
                    }
                    $rules.Add($indexEntry)
                }
            }
            catch { }
            
            if ($ProgressCallback -and ($processed % 1000 -eq 0)) {
                $pct = [math]::Round(($processed / $totalFiles) * 100)
                & $ProgressCallback $processed $totalFiles $pct
            }
        }
        
        $script:JsonIndex = [PSCustomObject]@{
            Rules = $rules.ToArray()
            LastUpdated = Get-Date -Format 'o'
            SourcePath = $RulesPath
        }
        
        # Rebuild hashtables
        $script:HashIndex = @{}
        $script:PublisherIndex = @{}
        $script:PublisherOnlyIndex = @{}
        $script:RuleById = @{}
        
        foreach ($rule in $rules) {
            $script:RuleById[$rule.Id] = $rule
            if ($rule.Hash) {
                $script:HashIndex[$rule.Hash.ToUpper()] = $rule.Id
            }
            if ($rule.PublisherName) {
                $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                $script:PublisherIndex[$key] = $rule.Id
                $pubOnlyKey = $rule.PublisherName.ToLower()
                $script:PublisherOnlyIndex[$pubOnlyKey] = $rule.Id
            }
        }
        
        Save-JsonIndex
        $script:JsonIndexLoaded = $true
        
        $stopwatch.Stop()
        $result.Success = $true
        $result.RuleCount = $rules.Count
        $result.Duration = $stopwatch.Elapsed
        
        Write-StorageLog -Message "Built JSON index: $($rules.Count) rules in $($stopwatch.Elapsed.TotalSeconds.ToString('F1'))s"
    }
    catch {
        $result.Error = "Failed to build index: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }
    
    return $result
}
#endregion

#region ===== CRUD OPERATIONS =====
function Get-RuleById {
    <#
    .SYNOPSIS
        Gets a rule by its ID.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )
    
    Initialize-JsonIndex
    
    # O(1) lookup using hashtable
    if ($script:RuleById.ContainsKey($Id)) {
        $indexEntry = $script:RuleById[$Id]
        
        # Return full rule from file if available
        if ($indexEntry.FilePath -and (Test-Path $indexEntry.FilePath)) {
            return Get-Content $indexEntry.FilePath -Raw | ConvertFrom-Json
        }
        return $indexEntry
    }
    
    return $null
}

function Get-AllRules {
    <#
    .SYNOPSIS
        Gets rules with optional filtering.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Status,
        [string]$RuleType,
        [string]$CollectionType,
        [string]$SearchText,
        [string]$GroupVendor,
        [int]$Skip = 0,
        [int]$Take = 1000,
        [switch]$CountOnly,
        [switch]$FullPayload
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        Data = @()
        Total = 0
        Error = $null
    }
    
    Initialize-JsonIndex
    
    $rules = $script:JsonIndex.Rules
    if (-not $rules) {
        $result.Success = $true
        return $result
    }
    
    try {
        $filtered = @($rules)
        
        if ($Status) {
            $filtered = @($filtered | Where-Object { $_.Status -eq $Status })
        }
        if ($RuleType) {
            $filtered = @($filtered | Where-Object { $_.RuleType -eq $RuleType })
        }
        if ($CollectionType) {
            $filtered = @($filtered | Where-Object { $_.CollectionType -eq $CollectionType })
        }
        if ($GroupVendor) {
            $filtered = @($filtered | Where-Object { $_.GroupVendor -like "*$GroupVendor*" })
        }
        if ($SearchText) {
            $filtered = @($filtered | Where-Object {
                $_.Name -like "*$SearchText*" -or
                $_.PublisherName -like "*$SearchText*" -or
                $_.Path -like "*$SearchText*" -or
                $_.Hash -like "*$SearchText*"
            })
        }
        
        $result.Total = $filtered.Count
        
        if (-not $CountOnly) {
            if ($FullPayload) {
                $paged = $filtered | Select-Object -Skip $Skip -First $Take
                $result.Data = @($paged | ForEach-Object {
                    if ($_.FilePath -and (Test-Path $_.FilePath)) {
                        Get-Content $_.FilePath -Raw | ConvertFrom-Json
                    } else { $_ }
                })
            } else {
                $result.Data = @($filtered | Select-Object -Skip $Skip -First $Take)
            }
        }
        
        $result.Success = $true
    }
    catch {
        $result.Error = "Query failed: $($_.Exception.Message)"
    }
    
    return $result
}

function Add-Rule {
    <#
    .SYNOPSIS
        Adds a new rule to storage.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Rule
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        RuleId = $null
        Error = $null
    }
    
    try {
        Initialize-JsonIndex
        
        # Ensure rule has an ID
        if (-not $Rule.Id) {
            $Rule | Add-Member -NotePropertyName 'Id' -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
        }
        
        # Save to individual file
        $rulesPath = Get-RuleStoragePath
        if (-not (Test-Path $rulesPath)) {
            New-Item -Path $rulesPath -ItemType Directory -Force | Out-Null
        }
        
        $filePath = Join-Path $rulesPath "$($Rule.Id).json"
        $Rule | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
        
        # Add to index
        $indexEntry = [PSCustomObject]@{
            Id = $Rule.Id
            RuleType = $Rule.RuleType
            CollectionType = $Rule.CollectionType
            Status = if ($Rule.Status) { $Rule.Status } else { 'Pending' }
            Name = $Rule.Name
            Hash = $Rule.Hash
            PublisherName = $Rule.PublisherName
            ProductName = $Rule.ProductName
            Path = $Rule.Path
            GroupVendor = $Rule.GroupVendor
            CreatedDate = $Rule.CreatedDate
            FilePath = $filePath
        }
        
        # Update in-memory structures
        $script:JsonIndex.Rules = @($script:JsonIndex.Rules) + @($indexEntry)
        $script:RuleById[$Rule.Id] = $indexEntry
        
        if ($Rule.Hash) {
            $script:HashIndex[$Rule.Hash.ToUpper()] = $Rule.Id
        }
        if ($Rule.PublisherName) {
            $key = "$($Rule.PublisherName)|$($Rule.ProductName)".ToLower()
            $script:PublisherIndex[$key] = $Rule.Id
            $pubOnlyKey = $Rule.PublisherName.ToLower()
            $script:PublisherOnlyIndex[$pubOnlyKey] = $Rule.Id
        }
        
        Save-JsonIndex
        
        $result.Success = $true
        $result.RuleId = $Rule.Id
    }
    catch {
        $result.Error = "Failed to add rule: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }
    
    return $result
}

function Update-Rule {
    <#
    .SYNOPSIS
        Updates an existing rule.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$UpdatedRule
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        Error = $null
    }
    
    try {
        Initialize-JsonIndex
        
        if (-not $script:RuleById.ContainsKey($RuleId)) {
            $result.Error = "Rule not found: $RuleId"
            return $result
        }
        
        $indexEntry = $script:RuleById[$RuleId]
        
        # Update file
        if ($indexEntry.FilePath -and (Test-Path $indexEntry.FilePath)) {
            $UpdatedRule | ConvertTo-Json -Depth 10 | Set-Content -Path $indexEntry.FilePath -Encoding UTF8
        }
        
        # Update index entry
        $indexEntry.Status = if ($UpdatedRule.Status) { $UpdatedRule.Status } else { $indexEntry.Status }
        $indexEntry.Name = if ($UpdatedRule.Name) { $UpdatedRule.Name } else { $indexEntry.Name }
        $indexEntry.GroupVendor = if ($UpdatedRule.GroupVendor) { $UpdatedRule.GroupVendor } else { $indexEntry.GroupVendor }
        
        Save-JsonIndex
        
        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to update rule: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }
    
    return $result
}

function Remove-Rule {
    <#
    .SYNOPSIS
        Removes a rule from storage.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RuleIds
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        RemovedCount = 0
        Error = $null
    }
    
    try {
        Initialize-JsonIndex
        
        $idsToRemove = [System.Collections.Generic.HashSet[string]]::new($RuleIds, [System.StringComparer]::OrdinalIgnoreCase)
        $originalCount = $script:JsonIndex.Rules.Count
        
        # Remove files and update indexes
        foreach ($id in $RuleIds) {
            if ($script:RuleById.ContainsKey($id)) {
                $rule = $script:RuleById[$id]
                
                # Delete file
                if ($rule.FilePath -and (Test-Path $rule.FilePath)) {
                    Remove-Item $rule.FilePath -Force -ErrorAction SilentlyContinue
                }
                
                # Remove from hashtables
                $script:RuleById.Remove($id)
                if ($rule.Hash) {
                    $script:HashIndex.Remove($rule.Hash.ToUpper())
                }
                if ($rule.PublisherName) {
                    $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                    $script:PublisherIndex.Remove($key)
                    $pubOnlyKey = $rule.PublisherName.ToLower()
                    if ($script:PublisherOnlyIndex.ContainsKey($pubOnlyKey)) {
                        $script:PublisherOnlyIndex.Remove($pubOnlyKey)
                    }
                }
            }
        }
        
        # Filter out removed rules from index
        $script:JsonIndex.Rules = @($script:JsonIndex.Rules | Where-Object { -not $idsToRemove.Contains($_.Id) })
        
        $removedCount = $originalCount - $script:JsonIndex.Rules.Count
        
        if ($removedCount -gt 0) {
            Save-JsonIndex
            Write-StorageLog -Message "Removed $removedCount rule(s) from storage"
        }
        
        $result.Success = $true
        $result.RemovedCount = $removedCount
    }
    catch {
        $result.Error = "Failed to remove rules: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }
    
    return $result
}
#endregion

#region ===== QUERY HELPERS =====
function Find-RuleByHash {
    <#
    .SYNOPSIS
        Finds a rule by its hash value (O(1) lookup).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Hash,
        [string]$CollectionType
    )
    
    Initialize-JsonIndex
    
    $cleanHash = ($Hash -replace '^0x', '').ToUpper()
    
    if ($script:HashIndex.ContainsKey($cleanHash)) {
        $ruleId = $script:HashIndex[$cleanHash]
        $indexEntry = $script:RuleById[$ruleId]
        
        if ($CollectionType -and $indexEntry.CollectionType -ne $CollectionType) {
            return $null
        }
        
        if ($indexEntry.FilePath -and (Test-Path $indexEntry.FilePath)) {
            return Get-Content $indexEntry.FilePath -Raw | ConvertFrom-Json
        }
        return $indexEntry
    }
    
    return $null
}

function Find-RuleByPublisher {
    <#
    .SYNOPSIS
        Finds a rule by publisher name and product (O(1) lookup).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PublisherName,
        [string]$ProductName,
        [string]$CollectionType
    )
    
    Initialize-JsonIndex
    
    $key = "$PublisherName|$ProductName".ToLower()
    
    if ($script:PublisherIndex.ContainsKey($key)) {
        $ruleId = $script:PublisherIndex[$key]
        $indexEntry = $script:RuleById[$ruleId]
        
        if ($CollectionType -and $indexEntry.CollectionType -ne $CollectionType) {
            return $null
        }
        
        if ($indexEntry.FilePath -and (Test-Path $indexEntry.FilePath)) {
            return Get-Content $indexEntry.FilePath -Raw | ConvertFrom-Json
        }
        return $indexEntry
    }
    
    return $null
}

function Get-RuleCounts {
    <#
    .SYNOPSIS
        Gets rule counts grouped by status, type, and collection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    $result = [PSCustomObject]@{
        Success = $false
        Total = 0
        ByStatus = @{}
        ByRuleType = @{}
        ByCollection = @{}
        Error = $null
    }
    
    Initialize-JsonIndex
    
    $rules = $script:JsonIndex.Rules
    if (-not $rules) {
        $result.Success = $true
        return $result
    }
    
    try {
        $result.Total = $rules.Count
        
        $rules | Group-Object Status | ForEach-Object {
            if ($_.Name) { $result.ByStatus[$_.Name] = $_.Count }
        }
        
        $rules | Group-Object RuleType | ForEach-Object {
            if ($_.Name) { $result.ByRuleType[$_.Name] = $_.Count }
        }
        
        $rules | Group-Object CollectionType | ForEach-Object {
            if ($_.Name) { $result.ByCollection[$_.Name] = $_.Count }
        }
        
        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to get counts: $($_.Exception.Message)"
    }
    
    return $result
}
#endregion

#region ===== INDEX UPDATE HELPERS =====
function Update-RuleStatusInIndex {
    <#
    .SYNOPSIS
        Updates rule status in the JSON index without full rebuild.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RuleIds,

        [Parameter(Mandatory)]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status
    )

    $result = [PSCustomObject]@{
        Success = $false
        UpdatedCount = 0
        Error = $null
    }

    try {
        Initialize-JsonIndex

        $idsToUpdate = [System.Collections.Generic.HashSet[string]]::new($RuleIds, [System.StringComparer]::OrdinalIgnoreCase)
        $updated = 0

        foreach ($rule in $script:JsonIndex.Rules) {
            if ($idsToUpdate.Contains($rule.Id)) {
                $rule.Status = $Status
                $updated++

                if ($script:RuleById.ContainsKey($rule.Id)) {
                    $script:RuleById[$rule.Id].Status = $Status
                }
            }
        }

        if ($updated -gt 0) {
            Save-JsonIndex
            Write-StorageLog -Message "Updated $updated rule(s) status to '$Status' in index"
        }

        $result.Success = $true
        $result.UpdatedCount = $updated
    }
    catch {
        $result.Error = "Failed to update status in index: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }

    return $result
}

function Remove-RulesFromIndex {
    <#
    .SYNOPSIS
        Removes rules from the JSON index by ID.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RuleIds
    )

    $result = [PSCustomObject]@{
        Success = $false
        RemovedCount = 0
        Error = $null
    }

    try {
        Initialize-JsonIndex

        $idsToRemove = [System.Collections.Generic.HashSet[string]]::new($RuleIds, [System.StringComparer]::OrdinalIgnoreCase)
        $originalCount = $script:JsonIndex.Rules.Count
        
        $script:JsonIndex.Rules = @($script:JsonIndex.Rules | Where-Object { -not $idsToRemove.Contains($_.Id) })
        
        $removedCount = $originalCount - $script:JsonIndex.Rules.Count
        
        foreach ($id in $RuleIds) {
            if ($script:RuleById.ContainsKey($id)) {
                $rule = $script:RuleById[$id]
                $script:RuleById.Remove($id)
                
                if ($rule.Hash) {
                    $script:HashIndex.Remove($rule.Hash.ToUpper())
                }
                if ($rule.PublisherName) {
                    $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                    $script:PublisherIndex.Remove($key)
                    $pubOnlyKey = $rule.PublisherName.ToLower()
                    if ($script:PublisherOnlyIndex.ContainsKey($pubOnlyKey)) {
                        $script:PublisherOnlyIndex.Remove($pubOnlyKey)
                    }
                }
            }
        }

        if ($removedCount -gt 0) {
            Save-JsonIndex
            Write-StorageLog -Message "Removed $removedCount rule(s) from JSON index"
        }

        $result.Success = $true
        $result.RemovedCount = $removedCount
    }
    catch {
        $result.Error = "Failed to remove rules from index: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }

    return $result
}
#endregion

#region ===== BACKWARD COMPATIBILITY ALIASES =====
# These aliases maintain compatibility with code that uses the old SQLite-style function names

function Get-RuleFromDatabase {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RuleId)
    return Get-RuleById -Id $RuleId
}

function Get-RulesFromDatabase {
    [CmdletBinding()]
    param(
        [string]$Status,
        [string]$RuleType,
        [string]$CollectionType,
        [string]$SearchText,
        [string]$GroupVendor,
        [int]$Skip = 0,
        [int]$Take = 1000,
        [switch]$CountOnly,
        [switch]$FullPayload
    )
    return Get-AllRules @PSBoundParameters
}

function Add-RuleToDatabase {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSCustomObject]$Rule)
    return Add-Rule -Rule $Rule
}

function Update-RuleInDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuleId,
        [Parameter(Mandatory)][PSCustomObject]$UpdatedRule
    )
    return Update-Rule -RuleId $RuleId -UpdatedRule $UpdatedRule
}

function Remove-RuleFromDatabase {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$RuleId)
    return Remove-Rule -RuleIds $RuleId
}

function Initialize-RuleDatabase {
    [CmdletBinding()]
    param([switch]$Force)
    
    $result = [PSCustomObject]@{
        Success = $false
        DatabasePath = Get-JsonIndexPath
        Created = $false
        Mode = 'JsonIndex'
        Error = $null
    }
    
    try {
        if ($Force) {
            Reset-RulesIndexCache
        }
        
        Initialize-JsonIndex -Force:$Force
        
        $rules = $script:JsonIndex.Rules
        if (-not $rules -or $rules.Count -eq 0) {
            $rulesPath = Get-RuleStoragePath
            if (Test-Path $rulesPath) {
                $buildResult = Rebuild-RulesIndex -RulesPath $rulesPath
                if ($buildResult.Success -and $buildResult.RuleCount -gt 0) {
                    $result.Created = $true
                }
            }
        }
        
        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to initialize JSON index: $($_.Exception.Message)"
    }
    
    return $result
}

function Get-RuleDatabasePath {
    return Get-JsonIndexPath
}

function Test-RuleDatabaseExists {
    return Test-Path (Get-JsonIndexPath)
}
#endregion
