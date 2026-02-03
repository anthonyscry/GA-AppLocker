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

    .DESCRIPTION
        Gets the path to the rules storage directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    # Use try-catch instead of Get-Command (Get-Command fails in WPF context)
    $dataPath = try { Get-AppLockerDataPath } catch { Join-Path $env:LOCALAPPDATA 'GA-AppLocker' }
    return Join-Path $dataPath 'Rules'
}

function script:Get-JsonIndexPath {
    if (-not $script:JsonIndexPath) {
        # Use try-catch instead of Get-Command (Get-Command fails in WPF context)
        $dataPath = try { Get-AppLockerDataPath } catch { Join-Path $env:LOCALAPPDATA 'GA-AppLocker' }
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

    .DESCRIPTION
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

# Changed from script: to regular function so BulkOperations.ps1 can call it
function Initialize-JsonIndex {
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
                $null = $script:RuleById[$rule.Id] = $rule
                
                if ($rule.Hash) {
                    $null = $script:HashIndex[$rule.Hash.ToUpper()] = $rule.Id
                }
                if ($rule.PublisherName) {
                    $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                    $null = $script:PublisherIndex[$key] = $rule.Id
                    $pubOnlyKey = $rule.PublisherName.ToLower()
                    $null = $script:PublisherOnlyIndex[$pubOnlyKey] = $rule.Id
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
    
    $now = Get-Date -Format 'o'
    $script:JsonIndex.LastUpdated = $now
    
    # Performance: Use StringBuilder for index serialization
    # ConvertTo-Json has O(n^2) internal string concatenation for large arrays in PS 5.1
    # StringBuilder is 10-50x faster for 3000+ rule indexes
    $rules = $script:JsonIndex.Rules
    $count = if ($rules) { @($rules).Count } else { 0 }
    
    if ($count -eq 0) {
        # Fast path for empty index
        [System.IO.File]::WriteAllText($indexPath, "{`"LastUpdated`":`"$now`",`"Rules`":[]}", [System.Text.Encoding]::UTF8)
        return
    }
    
    $sb = [System.Text.StringBuilder]::new($count * 400 + 200)
    [void]$sb.Append("{`"LastUpdated`":`"$now`",`"Rules`":[")
    
    $first = $true
    foreach ($r in $rules) {
        if (-not $first) { [void]$sb.Append(',') }
        $first = $false
        
        # Safe values (GUIDs, enums, ISO dates) - no JSON escaping needed
        [void]$sb.Append('{"Id":"')
        [void]$sb.Append($r.Id)
        [void]$sb.Append('","RuleType":"')
        [void]$sb.Append($r.RuleType)
        [void]$sb.Append('","CollectionType":"')
        [void]$sb.Append($r.CollectionType)
        [void]$sb.Append('","Status":"')
        [void]$sb.Append($r.Status)
        
        # Nullable safe values (no special chars possible)
        [void]$sb.Append('","Action":')
        if ($r.Action) { [void]$sb.Append('"'); [void]$sb.Append($r.Action); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"UserOrGroupSid":')
        if ($r.UserOrGroupSid) { [void]$sb.Append('"'); [void]$sb.Append($r.UserOrGroupSid); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"Hash":')
        if ($r.Hash) { [void]$sb.Append('"'); [void]$sb.Append($r.Hash); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"CreatedDate":')
        if ($r.CreatedDate) { [void]$sb.Append('"'); [void]$sb.Append($r.CreatedDate); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        
        # Values that may contain backslashes or quotes - must JSON-escape
        # Escape order: backslash FIRST, then quotes (adding \ before " must not re-escape the \)
        [void]$sb.Append(',"Name":')
        if ($null -ne $r.Name) { [void]$sb.Append('"'); [void]$sb.Append($r.Name.Replace('\','\\').Replace('"','\"')); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"PublisherName":')
        if ($null -ne $r.PublisherName) { [void]$sb.Append('"'); [void]$sb.Append($r.PublisherName.Replace('\','\\').Replace('"','\"')); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"ProductName":')
        if ($null -ne $r.ProductName) { [void]$sb.Append('"'); [void]$sb.Append($r.ProductName.Replace('\','\\').Replace('"','\"')); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"Path":')
        if ($null -ne $r.Path) { [void]$sb.Append('"'); [void]$sb.Append($r.Path.Replace('\','\\').Replace('"','\"')); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"GroupVendor":')
        if ($null -ne $r.GroupVendor) { [void]$sb.Append('"'); [void]$sb.Append($r.GroupVendor.Replace('\','\\').Replace('"','\"')); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        [void]$sb.Append(',"FilePath":')
        if ($null -ne $r.FilePath) { [void]$sb.Append('"'); [void]$sb.Append($r.FilePath.Replace('\','\\').Replace('"','\"')); [void]$sb.Append('"') } else { [void]$sb.Append('null') }
        
        [void]$sb.Append('}')
    }
    
    [void]$sb.Append(']}')
    [System.IO.File]::WriteAllText($indexPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
}

function Rebuild-RulesIndex {
    <#
    .SYNOPSIS
        Rebuilds the JSON index from rule files on disk.

    .DESCRIPTION
        Rebuilds the JSON index from rule files on disk. Reconstructs from source files. May take time for large datasets.
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
        foreach ($f in $files) { [void]$fileList.Add($f) }
        
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
                        Action = if ($rule.Action) { $rule.Action } else { 'Allow' }
                        UserOrGroupSid = if ($rule.UserOrGroupSid) { $rule.UserOrGroupSid } else { 'S-1-1-0' }
                        Name = $rule.Name
                        Hash = $rule.Hash
                        PublisherName = $rule.PublisherName
                        ProductName = $rule.ProductName
                        Path = $rule.Path
                        GroupVendor = $rule.GroupVendor
                        CreatedDate = $rule.CreatedDate
                        FilePath = $filePath
                    }
                    [void]$rules.Add($indexEntry)
                }
            }
            catch { Write-StorageLog -Message "Failed to parse rule file '$filePath': $($_.Exception.Message)" -Level 'DEBUG' }
            
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
            $null = $script:RuleById[$rule.Id] = $rule
            if ($rule.Hash) {
                $null = $script:HashIndex[$rule.Hash.ToUpper()] = $rule.Id
            }
            if ($rule.PublisherName) {
                $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                $null = $script:PublisherIndex[$key] = $rule.Id
                $pubOnlyKey = $rule.PublisherName.ToLower()
                $null = $script:PublisherOnlyIndex[$pubOnlyKey] = $rule.Id
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

function Get-ExistingRuleIndex {
    <#
    .SYNOPSIS
        Returns the existing rule index for O(1) duplicate checking.
    .DESCRIPTION
        Used by Invoke-BatchRuleGeneration to check if rules already exist
        before creating new ones. Returns hashtables for hash and publisher lookups.
    .OUTPUTS
        PSCustomObject with Hashes, Publishers, and PublishersOnly HashSets for O(1) lookups.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    Initialize-JsonIndex
    
    # Convert hashtable keys to HashSets for O(1) Contains() checks
    $hashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $script:HashIndex.Keys) {
        $hashSet.Add($key) | Out-Null
    }
    
    $pubSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $script:PublisherIndex.Keys) {
        $pubSet.Add($key) | Out-Null
    }
    
    $pubOnlySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $script:PublisherOnlyIndex.Keys) {
        $pubOnlySet.Add($key) | Out-Null
    }
    
    return [PSCustomObject]@{
        Hashes = $hashSet
        Publishers = $pubSet
        PublishersOnly = $pubOnlySet
        TotalRules = if ($script:JsonIndex -and $script:JsonIndex.Rules) { $script:JsonIndex.Rules.Count } else { 0 }
        HashCount = $hashSet.Count
        PublisherCount = $pubSet.Count
    }
}
#endregion

#region ===== CRUD OPERATIONS =====
function Get-RuleById {
    <#
    .SYNOPSIS
        Gets a rule by its ID.

    .DESCRIPTION
        Gets a rule by its ID. Returns the requested data in a standard result object.
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

    .DESCRIPTION
        Gets rules with optional filtering. Returns the requested data in a standard result object.
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
    
    $null = Initialize-JsonIndex
    
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

    .DESCRIPTION
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
        
        # Ensure rule has an ID (accept either Id or RuleId property)
        $ruleId = if ($Rule.Id) { $Rule.Id } elseif ($Rule.RuleId) { $Rule.RuleId } else { $null }
        if (-not $ruleId) {
            $ruleId = [guid]::NewGuid().ToString()
        }
        # Ensure both Id and RuleId are set for compatibility
        $Rule | Add-Member -NotePropertyName 'Id' -NotePropertyValue $ruleId -Force
        $Rule | Add-Member -NotePropertyName 'RuleId' -NotePropertyValue $ruleId -Force
        
        # Save to individual file
        $rulesPath = Get-RuleStoragePath
        if (-not (Test-Path $rulesPath)) {
            New-Item -Path $rulesPath -ItemType Directory -Force | Out-Null
        }
        
        $filePath = Join-Path $rulesPath "$($Rule.Id).json"
        $Rule | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8
        
        # Add to index
        $indexEntry = [PSCustomObject]@{
            Id = $Rule.Id
            RuleType = $Rule.RuleType
            CollectionType = $Rule.CollectionType
            Status = if ($Rule.Status) { $Rule.Status } else { 'Pending' }
            Action = if ($Rule.Action) { $Rule.Action } else { 'Allow' }
            UserOrGroupSid = if ($Rule.UserOrGroupSid) { $Rule.UserOrGroupSid } else { 'S-1-1-0' }
            Name = $Rule.Name
            Hash = $Rule.Hash
            PublisherName = $Rule.PublisherName
            ProductName = $Rule.ProductName
            Path = $Rule.Path
            GroupVendor = $Rule.GroupVendor
            CreatedDate = $Rule.CreatedDate
            FilePath = $filePath
        }
        
        # Update in-memory structures (use List.Add to avoid O(n) array copy)
        if ($script:JsonIndex.Rules -isnot [System.Collections.Generic.List[PSCustomObject]]) {
            $rulesList = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($r in @($script:JsonIndex.Rules)) { [void]$rulesList.Add($r) }
            $script:JsonIndex.Rules = $rulesList
        }
        [void]$script:JsonIndex.Rules.Add($indexEntry)
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

    .DESCRIPTION
        Updates an existing rule. Modifies the existing item in the data store.
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
            $UpdatedRule | ConvertTo-Json -Depth 5 | Set-Content -Path $indexEntry.FilePath -Encoding UTF8
        }
        
        # Update index entry
        $indexEntry.Status = if ($UpdatedRule.Status) { $UpdatedRule.Status } else { $indexEntry.Status }
        $indexEntry.Name = if ($UpdatedRule.Name) { $UpdatedRule.Name } else { $indexEntry.Name }
        $indexEntry.GroupVendor = if ($UpdatedRule.GroupVendor) { $UpdatedRule.GroupVendor } else { $indexEntry.GroupVendor }
        if ($UpdatedRule.Action) { $indexEntry.Action = $UpdatedRule.Action }
        if ($UpdatedRule.UserOrGroupSid) { $indexEntry.UserOrGroupSid = $UpdatedRule.UserOrGroupSid }
        
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

    .DESCRIPTION
        Removes a rule from storage. Permanently removes the item from storage.
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

    .DESCRIPTION
        Finds a rule by its hash value (O(1) lookup). Uses indexed lookups for O(1) performance.
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
        Finds a rule by publisher name and product. Supports wildcards.

    .DESCRIPTION
        Finds a rule by publisher name and product. Supports wildcards. Uses indexed lookups for O(1) performance.
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
    
    # Check if wildcard search is needed
    $isWildcard = $PublisherName -match '\*' -or $PublisherName -match '\?'
    
    if (-not $isWildcard) {
        # O(1) exact match lookup
        $ruleId = $null
        
        if ($ProductName) {
            # Look up by publisher+product
            $key = "$PublisherName|$ProductName".ToLower()
            if ($script:PublisherIndex.ContainsKey($key)) {
                $ruleId = $script:PublisherIndex[$key]
            }
        } else {
            # Look up by publisher only
            $pubOnlyKey = $PublisherName.ToLower()
            if ($script:PublisherOnlyIndex.ContainsKey($pubOnlyKey)) {
                $ruleId = $script:PublisherOnlyIndex[$pubOnlyKey]
            }
        }
        
        if ($ruleId) {
            $indexEntry = $script:RuleById[$ruleId]
            
            if ($CollectionType -and $indexEntry.CollectionType -ne $CollectionType) {
                return $null
            }
            
            if ($indexEntry.FilePath -and (Test-Path $indexEntry.FilePath)) {
                return Get-Content $indexEntry.FilePath -Raw | ConvertFrom-Json
            }
            return $indexEntry
        }
    } else {
        # Wildcard search - iterate through rules
        $rules = $script:JsonIndex.Rules | Where-Object {
            $_.RuleType -eq 'Publisher' -and
            $_.PublisherName -like $PublisherName
        }
        
        if ($ProductName) {
            $rules = $rules | Where-Object { $_.ProductName -like $ProductName }
        }
        if ($CollectionType) {
            $rules = $rules | Where-Object { $_.CollectionType -eq $CollectionType }
        }
        
        $match = $rules | Select-Object -First 1
        if ($match) {
            if ($match.FilePath -and (Test-Path $match.FilePath)) {
                return Get-Content $match.FilePath -Raw | ConvertFrom-Json
            }
            return $match
        }
    }
    
    return $null
}

function Get-RuleCounts {
    <#
    .SYNOPSIS
        Gets rule counts grouped by status, type, and collection.

    .DESCRIPTION
        Gets rule counts grouped by status, type, and collection. Returns the requested data in a standard result object.
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
        Updates rule fields in the JSON index without full rebuild.

    .DESCRIPTION
        Updates rule Status, Action, and/or UserOrGroupSid in the JSON index without full rebuild.
        At least one field to update must be provided (Status, Action, or UserOrGroupSid).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RuleIds,

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [string]$Action,

        [Parameter()]
        [string]$UserOrGroupSid
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
        $fieldLog = @()

        foreach ($rule in $script:JsonIndex.Rules) {
            if ($idsToUpdate.Contains($rule.Id)) {
                if ($Status) {
                    $rule.Status = $Status
                }
                if ($Action) {
                    $rule.Action = $Action
                }
                if ($UserOrGroupSid) {
                    $rule.UserOrGroupSid = $UserOrGroupSid
                }
                $updated++

                if ($script:RuleById.ContainsKey($rule.Id)) {
                    if ($Status) { $script:RuleById[$rule.Id].Status = $Status }
                    if ($Action) { $script:RuleById[$rule.Id].Action = $Action }
                    if ($UserOrGroupSid) { $script:RuleById[$rule.Id].UserOrGroupSid = $UserOrGroupSid }
                }
            }
        }

        if ($updated -gt 0) {
            Save-JsonIndex
            if ($Status) { $fieldLog += "Status='$Status'" }
            if ($Action) { $fieldLog += "Action='$Action'" }
            if ($UserOrGroupSid) { $fieldLog += "UserOrGroupSid='$UserOrGroupSid'" }
            Write-StorageLog -Message "Updated $updated rule(s) in index: $($fieldLog -join ', ')"
        }

        $result.Success = $true
        $result.UpdatedCount = $updated
    }
    catch {
        $result.Error = "Failed to update fields in index: $($_.Exception.Message)"
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
    $result = Get-AllRules @PSBoundParameters
    # Return just the rules array for backwards compatibility
    if ($result.Success) {
        return $result.Data
    }
    return @()
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

function Remove-OrphanedRuleFiles {
    <#
    .SYNOPSIS
        Removes rule files that are not in the index.
    
    .DESCRIPTION
        Scans the Rules directory for JSON files that don't have a corresponding
        entry in the rules index. These orphaned files take up disk space and
        can slow down directory operations.
    
    .PARAMETER WhatIf
        Show what would be deleted without actually deleting.
    
    .PARAMETER Force
        Skip confirmation prompt.
    
    .EXAMPLE
        Remove-OrphanedRuleFiles -WhatIf
        # Shows orphaned files without deleting
    
    .EXAMPLE
        Remove-OrphanedRuleFiles -Force
        # Deletes orphaned files without prompting
    
    .OUTPUTS
        [PSCustomObject] Result with count of files removed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [switch]$Force
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        OrphanedCount = 0
        RemovedCount = 0
        BytesFreed = 0
        OrphanedFiles = @()
        Error = $null
    }
    
    try {
        # Ensure index is loaded
        Initialize-JsonIndex
        
        $rulesPath = Get-RuleStoragePath
        if (-not (Test-Path $rulesPath)) {
            $result.Success = $true
            $result.Error = "Rules directory does not exist"
            return $result
        }
        
        # Get all rule IDs from index
        $indexedIds = @{}
        if ($script:JsonIndex.Rules) {
            foreach ($rule in $script:JsonIndex.Rules) {
                $indexedIds[$rule.Id] = $true
            }
        }
        
        Write-StorageLog -Message "Index contains $($indexedIds.Count) rules"
        
        # Enumerate files in rules directory using .NET for performance
        # (Get-ChildItem can be slow with many files)
        $files = [System.IO.Directory]::EnumerateFiles($rulesPath, '*.json', [System.IO.SearchOption]::TopDirectoryOnly)
        
        $orphanedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
        $totalBytes = 0
        $fileCount = 0
        
        foreach ($filePath in $files) {
            $fileCount++
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
            
            # Check if file ID is in index
            if (-not $indexedIds.ContainsKey($fileName)) {
                try {
                    $fileInfo = [System.IO.FileInfo]::new($filePath)
                    [void]$orphanedFiles.Add([PSCustomObject]@{
                        Path = $filePath
                        Name = $fileName
                        Size = $fileInfo.Length
                    })
                    $totalBytes += $fileInfo.Length
                }
                catch {
                    # Skip files we can't access
                }
            }
            
            # Log progress every 10000 files
            if ($fileCount % 10000 -eq 0) {
                Write-StorageLog -Message "Scanned $fileCount files, found $($orphanedFiles.Count) orphaned..."
            }
        }
        
        $result.OrphanedCount = $orphanedFiles.Count
        $result.OrphanedFiles = $orphanedFiles.ToArray()
        $result.BytesFreed = $totalBytes
        
        Write-StorageLog -Message "Found $($orphanedFiles.Count) orphaned files ($([math]::Round($totalBytes/1MB, 2)) MB)"
        
        if ($orphanedFiles.Count -eq 0) {
            $result.Success = $true
            return $result
        }
        
        # Confirm deletion unless -Force or -WhatIf
        if (-not $Force -and -not $WhatIfPreference) {
            $sizeMB = [math]::Round($totalBytes / 1MB, 2)
            if (-not $PSCmdlet.ShouldContinue(
                "Delete $($orphanedFiles.Count) orphaned rule files ($sizeMB MB)?",
                'Confirm Orphaned Rule File Cleanup')) {
                $result.Success = $true
                $result.Error = "Cancelled by user"
                return $result
            }
        }
        
        # Delete orphaned files
        $removedCount = 0
        foreach ($orphan in $orphanedFiles) {
            if ($PSCmdlet.ShouldProcess($orphan.Path, "Delete orphaned rule file")) {
                try {
                    [System.IO.File]::Delete($orphan.Path)
                    $removedCount++
                }
                catch {
                    Write-StorageLog -Message "Failed to delete $($orphan.Path): $($_.Exception.Message)" -Level 'WARNING'
                }
            }
        }
        
        $result.RemovedCount = $removedCount
        $result.Success = $true
        
        Write-StorageLog -Message "Removed $removedCount orphaned rule files"
    }
    catch {
        $result.Error = "Cleanup failed: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }
    
    return $result
}
#endregion
