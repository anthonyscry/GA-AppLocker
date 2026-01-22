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
        # Try Storage layer first for fast duplicate detection
        if (Get-Command -Name 'Get-RulesFromDatabase' -ErrorAction SilentlyContinue) {
            $dbResult = Get-RulesFromDatabase -Take 100000 -FullPayload
            if ($dbResult.Success -and $dbResult.Data.Count -gt 0) {
                $allRules = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($rule in $dbResult.Data) {
                    $allRules.Add($rule)
                }
                Write-RuleLog -Message "Loaded $($allRules.Count) rules from storage index"
            }
            else {
                # Fall back to JSON scan
                $allRules = $null
            }
        }
        else {
            $allRules = $null
        }

        # Fallback: JSON file scan
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
                    $allRules.Add($rule)
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

        # Find duplicates by type using List<T> for O(n) performance
        $toRemove = [System.Collections.Generic.List[PSCustomObject]]::new()
        $keptRules = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Process Hash rules
        if ($RuleType -eq 'Hash' -or $RuleType -eq 'All') {
            $hashRules = $allRules | Where-Object { $_.RuleType -eq 'Hash' }
            $hashGroups = $hashRules | Group-Object { "$($_.Hash)_$($_.CollectionType)" }
            
            foreach ($group in ($hashGroups | Where-Object { $_.Count -gt 1 })) {
                $sorted = Sort-DuplicateGroup -Rules $group.Group -Strategy $Strategy
                $keep = $sorted[0]
                $duplicates = @($sorted | Select-Object -Skip 1)
                
                $result.HashDuplicates += $duplicates.Count
                foreach ($dup in $duplicates) { $toRemove.Add($dup) }
                $keptRules.Add([PSCustomObject]@{
                    Id = $keep.Id
                    Name = $keep.Name
                    Type = 'Hash'
                    Key = $keep.Hash
                })
            }
        }

        # Process Publisher rules
        if ($RuleType -eq 'Publisher' -or $RuleType -eq 'All') {
            $pubRules = $allRules | Where-Object { $_.RuleType -eq 'Publisher' }
            $pubGroups = $pubRules | Group-Object { "$($_.PublisherName)_$($_.ProductName)_$($_.CollectionType)" }
            
            foreach ($group in ($pubGroups | Where-Object { $_.Count -gt 1 })) {
                $sorted = Sort-DuplicateGroup -Rules $group.Group -Strategy $Strategy
                $keep = $sorted[0]
                $duplicates = @($sorted | Select-Object -Skip 1)
                
                $result.PublisherDuplicates += $duplicates.Count
                foreach ($dup in $duplicates) { $toRemove.Add($dup) }
                $keptRules.Add([PSCustomObject]@{
                    Id = $keep.Id
                    Name = $keep.Name
                    Type = 'Publisher'
                    Key = "$($keep.PublisherName) - $($keep.ProductName)"
                })
            }
        }

        # Process Path rules
        if ($RuleType -eq 'Path' -or $RuleType -eq 'All') {
            $pathRules = $allRules | Where-Object { $_.RuleType -eq 'Path' }
            $pathGroups = $pathRules | Group-Object { "$($_.Path)_$($_.CollectionType)" }
            
            foreach ($group in ($pathGroups | Where-Object { $_.Count -gt 1 })) {
                $sorted = Sort-DuplicateGroup -Rules $group.Group -Strategy $Strategy
                $keep = $sorted[0]
                $duplicates = @($sorted | Select-Object -Skip 1)
                
                $result.PathDuplicates += $duplicates.Count
                foreach ($dup in $duplicates) { $toRemove.Add($dup) }
                $keptRules.Add([PSCustomObject]@{
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
                    $removedRules.Add([PSCustomObject]@{
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
        # Try Storage layer first for fast duplicate detection
        if (Get-Command -Name 'Get-RulesFromDatabase' -ErrorAction SilentlyContinue) {
            $dbResult = Get-RulesFromDatabase -Take 100000
            if ($dbResult.Success -and $dbResult.Data.Count -gt 0) {
                $allRules = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($rule in $dbResult.Data) { $allRules.Add($rule) }
                $result.TotalRules = $allRules.Count
            }
            else {
                $allRules = $null
            }
        }
        else {
            $allRules = $null
        }

        # Fallback: JSON file scan
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
                    $allRules.Add($rule)
                }
                catch { }
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
                $duplicateGroups.Add([PSCustomObject]@{
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
                $duplicateGroups.Add([PSCustomObject]@{
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
                $duplicateGroups.Add([PSCustomObject]@{
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
        catch { }
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
        catch { }
    }

    return $null
}

<#
.SYNOPSIS
    Builds a fast lookup index of existing rule keys.

.DESCRIPTION
    Returns a HashSet of existing rule hashes and publisher keys for O(1) lookups.
    Uses Storage layer if available (already indexed), falls back to JSON scan.
    Use this to quickly filter artifacts that already have rules.

.EXAMPLE
    $index = Get-ExistingRuleIndex
    if ($index.Hashes.Contains($artifact.Hash)) { "Already has rule" }

.OUTPUTS
    [PSCustomObject] With Hashes (HashSet) and Publishers (HashSet) properties.
#>
function Get-ExistingRuleIndex {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Hashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Publishers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        HashCount = 0
        PublisherCount = 0
    }

    # Try Storage layer first - it already has indexed data
    if (Get-Command -Name 'Get-RulesFromDatabase' -ErrorAction SilentlyContinue) {
        try {
            # Get all rules from storage (metadata only, no full payload)
            $dbResult = Get-RulesFromDatabase -Take 100000
            
            if ($dbResult.Success -and $dbResult.Data) {
                foreach ($rule in $dbResult.Data) {
                    if ($rule.RuleType -eq 'Hash' -and $rule.Hash) {
                        [void]$result.Hashes.Add($rule.Hash.ToUpper())
                        $result.HashCount++
                    }
                    elseif ($rule.RuleType -eq 'Publisher' -and $rule.PublisherName) {
                        $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                        [void]$result.Publishers.Add($key)
                        $result.PublisherCount++
                    }
                }
                return $result
            }
        }
        catch {
            Write-RuleLog -Level Warning -Message "Storage layer index failed, falling back to JSON scan: $($_.Exception.Message)"
        }
    }

    # Fallback: JSON file scan (O(n))
    try {
        $rulePath = Get-RuleStoragePath
        $ruleFiles = Get-ChildItem -Path $rulePath -Filter '*.json' -File -ErrorAction SilentlyContinue

        foreach ($file in $ruleFiles) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $rule = $content | ConvertFrom-Json

                if ($rule.RuleType -eq 'Hash' -and $rule.Hash) {
                    [void]$result.Hashes.Add($rule.Hash.ToUpper())
                    $result.HashCount++
                }
                elseif ($rule.RuleType -eq 'Publisher' -and $rule.PublisherName) {
                    $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                    [void]$result.Publishers.Add($key)
                    $result.PublisherCount++
                }
            }
            catch { }
        }
    }
    catch {
        Write-RuleLog -Level Warning -Message "Failed to build rule index: $($_.Exception.Message)"
    }

    return $result
}
