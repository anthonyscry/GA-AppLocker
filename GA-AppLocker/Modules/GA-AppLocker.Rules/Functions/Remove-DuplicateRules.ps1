<#
.SYNOPSIS
    Finds and removes duplicate AppLocker rules.

.DESCRIPTION
    Identifies duplicate rules based on their key attributes and removes
    redundant copies while keeping one rule per unique combination.

    Duplicate detection logic:
    - Hash rules: Same Hash value
    - Publisher rules: Same PublisherName + ProductName + CollectionType
    - Path rules: Same Path + CollectionType

.PARAMETER RuleType
    Type of rules to check for duplicates: Hash, Publisher, Path, or All.

.PARAMETER Strategy
    Strategy for choosing which duplicate to keep:
    - KeepOldest: Keep the rule with earliest CreatedDate (default)
    - KeepNewest: Keep the rule with latest CreatedDate
    - KeepApproved: Keep approved rules over pending/rejected

.PARAMETER WhatIf
    Preview what would be removed without making changes.

.PARAMETER Force
    Skip confirmation prompt for large deletions.

.EXAMPLE
    Remove-DuplicateRules -RuleType Hash -WhatIf
    
    Shows what hash rule duplicates would be removed.

.EXAMPLE
    Remove-DuplicateRules -RuleType All -Strategy KeepOldest
    
    Removes all duplicate rules, keeping the oldest of each set.

.OUTPUTS
    [PSCustomObject] Result with Success, RemovedCount, and details.
#>
function Remove-DuplicateRules {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Hash', 'Publisher', 'Path', 'All')]
        [string]$RuleType = 'All',

        [Parameter()]
        [ValidateSet('KeepOldest', 'KeepNewest', 'KeepApproved')]
        [string]$Strategy = 'KeepOldest',

        [Parameter()]
        [switch]$Force
    )

    $result = [PSCustomObject]@{
        Success            = $false
        DuplicateCount     = 0
        RemovedCount       = 0
        HashDuplicates     = 0
        PublisherDuplicates = 0
        PathDuplicates     = 0
        KeptRules          = @()
        RemovedRules       = @()
        Error              = $null
    }

    try {
        # Use storage layer for fast duplicate detection
        # NOTE: Don't use -FullPayload - index data has all fields needed for duplicate detection
        # (Hash, PublisherName, ProductName, Path, CollectionType, CreatedDate, Status, Id)
        $dbResult = Get-AllRules -Take 100000
        if ($dbResult.Success -and $dbResult.Data.Count -gt 0) {
            $allRules = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($rule in $dbResult.Data) {
                [void]$allRules.Add($rule)
            }
            Write-RuleLog -Message "Loaded $($allRules.Count) rules from index"
        }
        else {
            $allRules = $null
        }

        # Fallback: Direct JSON file scan if index failed
        if ($null -eq $allRules) {
            $rulePath = Get-RuleStoragePath
            $ruleFiles = Get-ChildItem -Path $rulePath -Filter '*.json' -ErrorAction SilentlyContinue
            $totalFiles = $ruleFiles.Count

            if ($totalFiles -eq 0) {
                $result.Success = $true
                $result.Error = "No rules found in storage"
                return $result
            }

            Write-RuleLog -Message "Scanning $totalFiles rules for duplicates..."

            # Load all rules using List<T> for O(n) performance
            $allRules = [System.Collections.Generic.List[PSCustomObject]]::new()
            $processedCount = 0

            foreach ($file in $ruleFiles) {
                $processedCount++
                
                if ($processedCount % 1000 -eq 0) {
                    $pct = [math]::Round(($processedCount / $totalFiles) * 100)
                    Write-Progress -Activity "Loading rules" -Status "$processedCount of $totalFiles ($pct%)" -PercentComplete $pct
                }

                try {
                    $rule = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                    $rule | Add-Member -NotePropertyName '_FilePath' -NotePropertyValue $file.FullName -Force
                    [void]$allRules.Add($rule)
                }
                catch {
                    Write-RuleLog -Level Warning -Message "Failed to load rule file: $($file.Name)"
                }
            }

            Write-Progress -Activity "Loading rules" -Completed
        }

        if ($allRules.Count -eq 0) {
            $result.Success = $true
            $result.Error = "No rules found in storage"
            return $result
        }

        # Find duplicates using O(n) hashtable approach (NOT Group-Object which is slow)
        $toRemove = [System.Collections.Generic.List[PSCustomObject]]::new()
        $keptRules = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Build hashtables for O(1) duplicate detection
        $hashGroups = @{}      # key -> List of rules
        $pubGroups = @{}       # key -> List of rules  
        $pathGroups = @{}      # key -> List of rules

        # Single pass through all rules - O(n)
        foreach ($rule in $allRules) {
            switch ($rule.RuleType) {
                'Hash' {
                    if ($RuleType -eq 'Hash' -or $RuleType -eq 'All') {
                        $key = "$($rule.Hash)_$($rule.CollectionType)".ToLower()
                        if (-not $hashGroups.ContainsKey($key)) {
                            $hashGroups[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
                        }
                        $hashGroups[$key].Add($rule)
                    }
                }
                'Publisher' {
                    if ($RuleType -eq 'Publisher' -or $RuleType -eq 'All') {
                        $key = "$($rule.PublisherName)_$($rule.ProductName)_$($rule.CollectionType)".ToLower()
                        if (-not $pubGroups.ContainsKey($key)) {
                            $pubGroups[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
                        }
                        $pubGroups[$key].Add($rule)
                    }
                }
                'Path' {
                    if ($RuleType -eq 'Path' -or $RuleType -eq 'All') {
                        $key = "$($rule.Path)_$($rule.CollectionType)".ToLower()
                        if (-not $pathGroups.ContainsKey($key)) {
                            $pathGroups[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
                        }
                        $pathGroups[$key].Add($rule)
                    }
                }
            }
        }

        # Process Hash duplicates
        foreach ($key in $hashGroups.Keys) {
            $group = $hashGroups[$key]
            if ($group.Count -gt 1) {
                $sorted = Sort-DuplicateGroup -Rules $group -Strategy $Strategy
                $keep = $sorted[0]
                for ($i = 1; $i -lt $sorted.Count; $i++) {
                    [void]$toRemove.Add($sorted[$i])
                    $result.HashDuplicates++
                }
                [void]$keptRules.Add([PSCustomObject]@{
                    Id = $keep.Id
                    Name = $keep.Name
                    Type = 'Hash'
                    Key = $keep.Hash
                })
            }
        }

        # Process Publisher duplicates
        foreach ($key in $pubGroups.Keys) {
            $group = $pubGroups[$key]
            if ($group.Count -gt 1) {
                $sorted = Sort-DuplicateGroup -Rules $group -Strategy $Strategy
                $keep = $sorted[0]
                for ($i = 1; $i -lt $sorted.Count; $i++) {
                    [void]$toRemove.Add($sorted[$i])
                    $result.PublisherDuplicates++
                }
                [void]$keptRules.Add([PSCustomObject]@{
                    Id = $keep.Id
                    Name = $keep.Name
                    Type = 'Publisher'
                    Key = "$($keep.PublisherName) - $($keep.ProductName)"
                })
            }
        }

        # Process Path duplicates
        foreach ($key in $pathGroups.Keys) {
            $group = $pathGroups[$key]
            if ($group.Count -gt 1) {
                $sorted = Sort-DuplicateGroup -Rules $group -Strategy $Strategy
                $keep = $sorted[0]
                for ($i = 1; $i -lt $sorted.Count; $i++) {
                    [void]$toRemove.Add($sorted[$i])
                    $result.PathDuplicates++
                }
                [void]$keptRules.Add([PSCustomObject]@{
                    Id = $keep.Id
                    Name = $keep.Name
                    Type = 'Path'
                    Key = $keep.Path
                })
            }
        }

        $result.KeptRules = $keptRules.ToArray()
        $result.DuplicateCount = $toRemove.Count

        if ($toRemove.Count -eq 0) {
            $result.Success = $true
            Write-RuleLog -Message "No duplicate rules found"
            return $result
        }

        # WhatIf mode - just report
        if ($WhatIfPreference) {
            $result.Success = $true
            
            Write-Host "`nWhatIf: Would remove $($toRemove.Count) duplicate rules:" -ForegroundColor Cyan
            Write-Host "  - Hash duplicates: $($result.HashDuplicates)" -ForegroundColor Yellow
            Write-Host "  - Publisher duplicates: $($result.PublisherDuplicates)" -ForegroundColor Yellow
            Write-Host "  - Path duplicates: $($result.PathDuplicates)" -ForegroundColor Yellow
            Write-Host "`nStrategy: $Strategy (keeping one rule per unique key)`n" -ForegroundColor Gray
            
            return $result
        }

        # Actually remove duplicates
        Write-RuleLog -Message "Removing $($toRemove.Count) duplicate rules..."
        $removeCount = 0
        $removedRules = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($rule in $toRemove) {
            $removeCount++
            
            if ($removeCount % 500 -eq 0) {
                $pct = [math]::Round(($removeCount / $toRemove.Count) * 100)
                Write-Progress -Activity "Removing duplicates" -Status "$removeCount of $($toRemove.Count) ($pct%)" -PercentComplete $pct
            }

            try {
                # Try to get file path from rule or construct it
                $filePath = if ($rule._FilePath) { 
                    $rule._FilePath 
                } elseif ($rule.FilePath) {
                    $rule.FilePath
                } else {
                    $rulePath = Get-RuleStoragePath
                    Join-Path $rulePath "$($rule.Id).json"
                }
                
                if (Test-Path $filePath) {
                    Remove-Item -Path $filePath -Force
                    $result.RemovedCount++
                    [void]$removedRules.Add([PSCustomObject]@{
                        Id = $rule.Id
                        Name = $rule.Name
                        Type = $rule.RuleType
                    })
                }
            }
            catch {
                Write-RuleLog -Level Warning -Message "Failed to remove duplicate rule $($rule.Id): $($_.Exception.Message)"
            }
        }

        Write-Progress -Activity "Removing duplicates" -Completed
        $result.RemovedRules = $removedRules.ToArray()

        # Update the JSON index to reflect removed rules
        if ($result.RemovedCount -gt 0) {
            $removedIds = @($removedRules | ForEach-Object { $_.Id })
            if (Get-Command -Name 'Remove-RulesFromIndex' -ErrorAction SilentlyContinue) {
                $indexResult = Remove-RulesFromIndex -RuleIds $removedIds
                if (-not $indexResult.Success) {
                    Write-RuleLog -Level Warning -Message "Index sync warning: $($indexResult.Error)"
                }
            }
        }

        $result.Success = $true
        Write-RuleLog -Message "Removed $($result.RemovedCount) duplicate rules"
    }
    catch {
        $result.Error = "Failed to remove duplicates: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}

<#
.SYNOPSIS
    Sorts a group of duplicate rules based on the keep strategy.

.DESCRIPTION
    Sorts a group of duplicate rules based on the keep strategy.
#>
function Sort-DuplicateGroup {
    param(
        [Parameter(Mandatory)]
        [array]$Rules,
        
        [Parameter(Mandatory)]
        [ValidateSet('KeepOldest', 'KeepNewest', 'KeepApproved')]
        [string]$Strategy
    )

    switch ($Strategy) {
        'KeepOldest' {
            return $Rules | Sort-Object CreatedDate
        }
        'KeepNewest' {
            return $Rules | Sort-Object CreatedDate -Descending
        }
        'KeepApproved' {
            # Approved first, then by oldest
            return $Rules | Sort-Object @{Expression = { if ($_.Status -eq 'Approved') { 0 } else { 1 } }}, CreatedDate
        }
    }
}

<#
.SYNOPSIS
    Finds duplicate rules without removing them.

.DESCRIPTION
    Scans the rule database and returns information about duplicate rules.
    Use this to preview what would be affected by Remove-DuplicateRules.

.PARAMETER RuleType
    Type of rules to check: Hash, Publisher, Path, or All.

.EXAMPLE
    Find-DuplicateRules -RuleType Hash
    
    Returns all hash rule duplicates.

.OUTPUTS
    [PSCustomObject] Result with duplicate groups and counts.
#>
function Find-DuplicateRules {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Hash', 'Publisher', 'Path', 'All')]
        [string]$RuleType = 'All'
    )

    $result = [PSCustomObject]@{
        Success         = $false
        TotalRules      = 0
        DuplicateGroups = @()
        HashDuplicates  = 0
        PublisherDuplicates = 0
        PathDuplicates  = 0
        Error           = $null
    }

    try {
        # Use storage layer for fast duplicate detection
        $dbResult = Get-AllRules -Take 100000
        if ($dbResult.Success -and $dbResult.Data.Count -gt 0) {
            $allRules = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($rule in $dbResult.Data) { $allRules.Add($rule) }
            $result.TotalRules = $allRules.Count
        }
        else {
            $allRules = $null
        }

        # Fallback: Direct JSON file scan if index failed
        if ($null -eq $allRules) {
            $rulePath = Get-RuleStoragePath
            $ruleFiles = Get-ChildItem -Path $rulePath -Filter '*.json' -ErrorAction SilentlyContinue
            $result.TotalRules = $ruleFiles.Count

            if ($result.TotalRules -eq 0) {
                $result.Success = $true
                return $result
            }

            # Load all rules using List<T> for O(n) performance
            $allRules = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($file in $ruleFiles) {
                try {
                    $rule = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                    [void]$allRules.Add($rule)
                }
                catch { Write-RuleLog -Message "Failed to load rule file '$($file.FullName)': $($_.Exception.Message)" -Level 'DEBUG' }
            }
        }

        if ($allRules.Count -eq 0) {
            $result.Success = $true
            return $result
        }

        # Find duplicates using List<T> for O(n) performance
        $duplicateGroups = [System.Collections.Generic.List[PSCustomObject]]::new()

        if ($RuleType -eq 'Hash' -or $RuleType -eq 'All') {
            $hashRules = $allRules | Where-Object { $_.RuleType -eq 'Hash' }
            $hashGroups = $hashRules | Group-Object { "$($_.Hash)_$($_.CollectionType)" } | Where-Object { $_.Count -gt 1 }
            
            foreach ($group in $hashGroups) {
                $result.HashDuplicates += ($group.Count - 1)  # -1 because one will be kept
                [void]$duplicateGroups.Add([PSCustomObject]@{
                    Type = 'Hash'
                    Key = $group.Group[0].Hash
                    Count = $group.Count
                    Rules = $group.Group | Select-Object Id, Name, Status, CreatedDate
                })
            }
        }

        if ($RuleType -eq 'Publisher' -or $RuleType -eq 'All') {
            $pubRules = $allRules | Where-Object { $_.RuleType -eq 'Publisher' }
            $pubGroups = $pubRules | Group-Object { "$($_.PublisherName)_$($_.ProductName)_$($_.CollectionType)" } | Where-Object { $_.Count -gt 1 }
            
            foreach ($group in $pubGroups) {
                $result.PublisherDuplicates += ($group.Count - 1)
                [void]$duplicateGroups.Add([PSCustomObject]@{
                    Type = 'Publisher'
                    Key = "$($group.Group[0].PublisherName) - $($group.Group[0].ProductName)"
                    Count = $group.Count
                    Rules = $group.Group | Select-Object Id, Name, Status, CreatedDate
                })
            }
        }

        if ($RuleType -eq 'Path' -or $RuleType -eq 'All') {
            $pathRules = $allRules | Where-Object { $_.RuleType -eq 'Path' }
            $pathGroups = $pathRules | Group-Object { "$($_.Path)_$($_.CollectionType)" } | Where-Object { $_.Count -gt 1 }
            
            foreach ($group in $pathGroups) {
                $result.PathDuplicates += ($group.Count - 1)
                [void]$duplicateGroups.Add([PSCustomObject]@{
                    Type = 'Path'
                    Key = $group.Group[0].Path
                    Count = $group.Count
                    Rules = $group.Group | Select-Object Id, Name, Status, CreatedDate
                })
            }
        }

        $result.DuplicateGroups = $duplicateGroups.ToArray()
        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to find duplicates: $($_.Exception.Message)"
    }

    return $result
}

<#
.SYNOPSIS
    Checks if a hash rule already exists.

.DESCRIPTION
    Efficiently checks if a rule with the same hash already exists.
    Uses the Storage layer's indexed lookup for O(1) performance.
    Falls back to JSON file scan if Storage layer unavailable.

.PARAMETER Hash
    The SHA256 hash to check for.

.PARAMETER CollectionType
    The collection type (Exe, Dll, Msi, Script, Appx).

.OUTPUTS
    [PSCustomObject] Existing rule if found, $null otherwise.
#>
function Find-ExistingHashRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Hash,

        [Parameter()]
        [string]$CollectionType
    )

    # Try Storage layer first (O(1) hashtable lookup)
    if (Get-Command -Name 'Find-RuleByHash' -ErrorAction SilentlyContinue) {
        try {
            $params = @{ Hash = $Hash }
            if ($CollectionType) { $params.CollectionType = $CollectionType }
            
            $result = Find-RuleByHash @params
            if ($result) { return $result }
        }
        catch {
            Write-RuleLog -Level Warning -Message "Storage layer lookup failed, falling back to JSON scan: $($_.Exception.Message)"
        }
    }

    # Fallback: JSON file scan (O(n))
    $cleanHash = $Hash -replace '^0x', ''
    $cleanHash = $cleanHash.ToUpper()

    $rulePath = Get-RuleStoragePath
    $ruleFiles = Get-ChildItem -Path $rulePath -Filter '*.json' -ErrorAction SilentlyContinue

    foreach ($file in $ruleFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw
            
            # Quick string check before parsing JSON
            if ($content -notmatch $cleanHash) { continue }
            
            $rule = $content | ConvertFrom-Json
            
            if ($rule.RuleType -eq 'Hash' -and $rule.Hash -eq $cleanHash) {
                if (-not $CollectionType -or $rule.CollectionType -eq $CollectionType) {
                    return $rule
                }
            }
        }
        catch { Write-RuleLog -Message "Failed to parse rule file '$($file.FullName)' during hash check: $($_.Exception.Message)" -Level 'DEBUG' }
    }

    return $null
}

<#
.SYNOPSIS
    Checks if a publisher rule already exists.

.DESCRIPTION
    Efficiently checks if a rule with the same publisher/product combination exists.
    Uses the Storage layer's indexed lookup for O(1) performance.
    Falls back to JSON file scan if Storage layer unavailable.

.PARAMETER PublisherName
    The publisher certificate subject.

.PARAMETER ProductName
    The product name.

.PARAMETER CollectionType
    The collection type (Exe, Dll, Msi, Script, Appx).

.OUTPUTS
    [PSCustomObject] Existing rule if found, $null otherwise.
#>
function Find-ExistingPublisherRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PublisherName,

        [Parameter()]
        [string]$ProductName,

        [Parameter()]
        [string]$CollectionType
    )

    # Try Storage layer first (O(1) hashtable lookup)
    if (Get-Command -Name 'Find-RuleByPublisher' -ErrorAction SilentlyContinue) {
        try {
            $params = @{ PublisherName = $PublisherName }
            if ($ProductName) { $params.ProductName = $ProductName }
            if ($CollectionType) { $params.CollectionType = $CollectionType }
            
            $result = Find-RuleByPublisher @params
            if ($result) { return $result }
        }
        catch {
            Write-RuleLog -Level Warning -Message "Storage layer lookup failed, falling back to JSON scan: $($_.Exception.Message)"
        }
    }

    # Fallback: JSON file scan (O(n))
    $rulePath = Get-RuleStoragePath
    $ruleFiles = Get-ChildItem -Path $rulePath -Filter '*.json' -ErrorAction SilentlyContinue

    foreach ($file in $ruleFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw
            
            # Quick string check before parsing JSON
            if ($content -notmatch [regex]::Escape($PublisherName)) { continue }
            
            $rule = $content | ConvertFrom-Json
            
            if ($rule.RuleType -eq 'Publisher' -and
                $rule.PublisherName -eq $PublisherName -and
                $rule.ProductName -eq $ProductName) {
                
                if (-not $CollectionType -or $rule.CollectionType -eq $CollectionType) {
                    return $rule
                }
            }
        }
        catch { Write-RuleLog -Message "Failed to parse rule file '$($file.FullName)' during publisher check: $($_.Exception.Message)" -Level 'DEBUG' }
    }

    return $null
}

# NOTE: Get-ExistingRuleIndex is now provided by GA-AppLocker.Storage module
# See: GA-AppLocker.Storage\Functions\BulkOperations.ps1
# The Storage module version uses the pre-built in-memory JSON index for O(1) lookups.
