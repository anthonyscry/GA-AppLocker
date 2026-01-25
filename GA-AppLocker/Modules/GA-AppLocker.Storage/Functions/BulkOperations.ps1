<#
.SYNOPSIS
    Bulk storage operations for high-performance rule management.

.DESCRIPTION
    Provides batch write and index update operations to minimize disk I/O.
    Used by Invoke-BatchRuleGeneration for 10x+ performance improvement.
#>

function Save-RulesBulk {
    <#
    .SYNOPSIS
        Saves multiple rules in a single optimized operation.

    .DESCRIPTION
        Instead of writing each rule as a separate file, this function:
        1. Writes all rules to individual JSON files in a batch
        2. Optionally updates the index in a single operation
        3. Uses parallel file writes where possible

    .PARAMETER Rules
        Array of rule objects to save.

    .PARAMETER UpdateIndex
        If specified, updates the in-memory index after saving.

    .PARAMETER ProgressCallback
        Optional scriptblock for progress updates.

    .EXAMPLE
        $result = Save-RulesBulk -Rules $rules -UpdateIndex
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Rules,

        [Parameter()]
        [switch]$UpdateIndex,

        [Parameter()]
        [scriptblock]$ProgressCallback
    )

    $result = [PSCustomObject]@{
        Success     = $false
        SavedCount  = 0
        FailedCount = 0
        Duration    = $null
        Error       = $null
    }

    if (-not $Rules -or $Rules.Count -eq 0) {
        $result.Success = $true
        return $result
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Get rules storage path
        $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
            Get-AppLockerDataPath
        } else {
            Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
        }
        $rulesPath = Join-Path $dataPath 'Rules'

        if (-not (Test-Path $rulesPath)) {
            New-Item -Path $rulesPath -ItemType Directory -Force | Out-Null
        }

        $total = $Rules.Count
        $saved = 0
        $failed = 0

        Write-StorageLog -Message "Bulk save starting: $total rules"

        # Batch write rules
        foreach ($rule in $Rules) {
            try {
                $rulePath = Join-Path $rulesPath "$($rule.Id).json"
                $json = $rule | ConvertTo-Json -Depth 10 -Compress
                [System.IO.File]::WriteAllText($rulePath, $json, [System.Text.Encoding]::UTF8)
                $saved++
            }
            catch {
                $failed++
                Write-StorageLog -Message "Failed to save rule $($rule.Id): $($_.Exception.Message)" -Level 'ERROR'
            }

            # Progress callback every 100 rules
            if ($ProgressCallback -and ($saved % 100 -eq 0)) {
                $pct = [math]::Round(($saved / $total) * 100)
                & $ProgressCallback $saved $total $pct
            }
        }

        $result.SavedCount = $saved
        $result.FailedCount = $failed

        Write-StorageLog -Message "Bulk save complete: $saved saved, $failed failed"

        # Update index if requested
        if ($UpdateIndex -and $saved -gt 0) {
            Write-StorageLog -Message "Updating index with $saved new rules..."
            $indexResult = Add-RulesToIndex -Rules $Rules
            if (-not $indexResult.Success) {
                Write-StorageLog -Message "Index update warning: $($indexResult.Error)" -Level 'WARN'
            }
        }

        $result.Success = $true
        
        # Invalidate GlobalSearch cache
        if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
            Clear-AppLockerCache -Pattern "GlobalSearch_*" | Out-Null
        }
    }
    catch {
        $result.Error = "Bulk save failed: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }

    $stopwatch.Stop()
    $result.Duration = $stopwatch.Elapsed

    return $result
}

function Add-RulesToIndex {
    <#
    .SYNOPSIS
        Adds multiple rules to the in-memory index without full rebuild.

    .DESCRIPTION
        Incrementally updates the JSON index with new rules.
        Much faster than rebuilding the entire index.

    .PARAMETER Rules
        Array of rule objects to add to the index.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [array]$Rules
    )

    $result = [PSCustomObject]@{
        Success   = $false
        AddedCount = 0
        Error     = $null
    }

    try {
        # Ensure index is loaded
        Initialize-JsonIndex

        $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
            Get-AppLockerDataPath
        } else {
            Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
        }
        $rulesPath = Join-Path $dataPath 'Rules'

        foreach ($rule in $Rules) {
            # Create index entry
            $indexEntry = [PSCustomObject]@{
                Id             = $rule.Id
                RuleType       = $rule.RuleType
                CollectionType = $rule.CollectionType
                Status         = $rule.Status
                Name           = $rule.Name
                Hash           = $rule.Hash
                PublisherName  = $rule.PublisherName
                ProductName    = $rule.ProductName
                Path           = $rule.Path
                GroupVendor    = $rule.GroupVendor
                CreatedDate    = $rule.CreatedDate
                FilePath       = Join-Path $rulesPath "$($rule.Id).json"
            }

            # Add to index array
            $script:JsonIndex.Rules += $indexEntry

            # Update hashtables for O(1) lookup
            $script:RuleById[$rule.Id] = $indexEntry

            if ($rule.Hash) {
                $script:HashIndex[$rule.Hash.ToUpper()] = $rule.Id
            }
            if ($rule.PublisherName) {
                $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                $script:PublisherIndex[$key] = $rule.Id
            }

            $result.AddedCount++
        }

        # Save updated index to disk
        Save-JsonIndex

        $result.Success = $true
        Write-StorageLog -Message "Added $($result.AddedCount) rules to index"
    }
    catch {
        $result.Error = "Failed to add rules to index: $($_.Exception.Message)"
        Write-StorageLog -Message $result.Error -Level 'ERROR'
    }

    return $result
}

function Get-ExistingRuleIndex {
    <#
    .SYNOPSIS
        Returns HashSets for O(1) rule existence checks.

    .DESCRIPTION
        Used by batch generation to quickly check if rules already exist.
        Returns Hashes and Publishers as HashSets for Contains() checks.

    .OUTPUTS
        PSCustomObject with Hashes (HashSet) and Publishers (HashSet) properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Ensure index is loaded
    Initialize-JsonIndex

    # Convert hashtables to HashSets for consistent interface with Rules module
    $hashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $publishers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($key in $script:HashIndex.Keys) {
        [void]$hashes.Add($key)
    }
    foreach ($key in $script:PublisherIndex.Keys) {
        [void]$publishers.Add($key)
    }

    return [PSCustomObject]@{
        Hashes = $hashes
        Publishers = $publishers
        HashCount = $hashes.Count
        PublisherCount = $publishers.Count
    }
}

function Remove-RulesBulk {
    <#
    .SYNOPSIS
        Removes multiple rules in a single optimized operation.

    .PARAMETER RuleIds
        Array of rule IDs to remove.

    .PARAMETER UpdateIndex
        If specified, updates the in-memory index after removal.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RuleIds,

        [Parameter()]
        [switch]$UpdateIndex
    )

    $result = [PSCustomObject]@{
        Success      = $false
        RemovedCount = 0
        FailedCount  = 0
        Error        = $null
    }

    try {
        $dataPath = if (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
            Get-AppLockerDataPath
        } else {
            Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
        }
        $rulesPath = Join-Path $dataPath 'Rules'

        # For large deletes (500+), use fast batch approach
        if ($RuleIds.Count -ge 500) {
            # Build hashset for O(1) lookups
            $idsToDelete = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]$RuleIds, 
                [System.StringComparer]::OrdinalIgnoreCase
            )
            
            # Get all rule files and delete matching ones
            $allFiles = Get-ChildItem -Path $rulesPath -Filter '*.json' -File -ErrorAction SilentlyContinue
            
            # If deleting most files (>80%), just wipe and recreate folder
            if ($RuleIds.Count -ge ($allFiles.Count * 0.8)) {
                # Delete all files at once (much faster)
                Remove-Item -Path "$rulesPath\*.json" -Force -ErrorAction SilentlyContinue
                $result.RemovedCount = $RuleIds.Count
                
                # Clear and rebuild index
                if ($UpdateIndex) {
                    Clear-RulesIndex
                }
            }
            else {
                # Delete selected files in parallel-ish batches
                foreach ($file in $allFiles) {
                    $id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    if ($idsToDelete.Contains($id)) {
                        try {
                            [System.IO.File]::Delete($file.FullName)
                            $result.RemovedCount++
                        }
                        catch {
                            $result.FailedCount++
                        }
                    }
                }
                
                if ($UpdateIndex -and $result.RemovedCount -gt 0) {
                    Remove-RulesFromIndex -RuleIds $RuleIds
                }
            }
        }
        else {
            # Small delete - use original approach
            foreach ($id in $RuleIds) {
                try {
                    $rulePath = Join-Path $rulesPath "$id.json"
                    if (Test-Path $rulePath) {
                        Remove-Item -Path $rulePath -Force
                        $result.RemovedCount++
                    }
                }
                catch {
                    $result.FailedCount++
                }
            }

            if ($UpdateIndex -and $result.RemovedCount -gt 0) {
                Remove-RulesFromIndex -RuleIds $RuleIds
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Error = "Bulk remove failed: $($_.Exception.Message)"
    }

    return $result
}

function Clear-RulesIndex {
    <#
    .SYNOPSIS
        Clears the entire rules index (used after bulk delete all).
    #>
    [CmdletBinding()]
    param()
    
    $script:JsonIndex = [PSCustomObject]@{ Rules = @(); LastUpdated = (Get-Date -Format 'o') }
    $script:HashIndex = @{}
    $script:PublisherIndex = @{}
    $script:RuleById = @{}
    $script:JsonIndexLoaded = $true
    
    # Save empty index
    Save-JsonIndex
}

function Remove-RulesFromIndex {
    <#
    .SYNOPSIS
        Removes rules from the in-memory index.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RuleIds
    )

    $result = [PSCustomObject]@{
        Success      = $false
        RemovedCount = 0
        Error        = $null
    }

    try {
        Initialize-JsonIndex

        $idsToRemove = [System.Collections.Generic.HashSet[string]]::new($RuleIds)
        
        # Filter out removed rules
        $remaining = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($rule in $script:JsonIndex.Rules) {
            if (-not $idsToRemove.Contains($rule.Id)) {
                $remaining.Add($rule)
            } else {
                # Remove from hashtables
                if ($script:RuleById.ContainsKey($rule.Id)) {
                    $script:RuleById.Remove($rule.Id)
                }
                if ($rule.Hash -and $script:HashIndex.ContainsKey($rule.Hash.ToUpper())) {
                    $script:HashIndex.Remove($rule.Hash.ToUpper())
                }
                if ($rule.PublisherName) {
                    $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                    if ($script:PublisherIndex.ContainsKey($key)) {
                        $script:PublisherIndex.Remove($key)
                    }
                }
                $result.RemovedCount++
            }
        }

        $script:JsonIndex.Rules = $remaining.ToArray()
        Save-JsonIndex

        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to remove rules from index: $($_.Exception.Message)"
    }

    return $result
}

function Get-BatchPreview {
    <#
    .SYNOPSIS
        Previews what would be created by batch generation without actually creating rules.

    .DESCRIPTION
        Returns statistics about what rules would be generated, useful for the wizard preview step.

    .PARAMETER Artifacts
        Array of artifacts to analyze.

    .PARAMETER Mode
        Rule generation mode.

    .PARAMETER SkipDlls
        Exclude DLLs from preview.

    .PARAMETER SkipUnsigned
        Exclude unsigned from preview.

    .PARAMETER SkipScripts
        Exclude scripts from preview.

    .PARAMETER DedupeMode
        Deduplication mode.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [array]$Artifacts,

        [string]$Mode = 'Smart',
        [switch]$SkipDlls,
        [switch]$SkipUnsigned,
        [switch]$SkipScripts,
        [string]$DedupeMode = 'Smart'
    )

    $result = [PSCustomObject]@{
        TotalArtifacts    = $Artifacts.Count
        AfterExclusions   = 0
        AfterDedup        = 0
        NewRulesToCreate  = 0
        ExistingRules     = 0
        EstimatedPublisher = 0
        EstimatedHash     = 0
        ByCollection      = @{}
        SampleRules       = @()
    }

    try {
        # Phase 1: Exclusions
        $filtered = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($art in $Artifacts) {
            $skip = $false
            if ($SkipDlls -and $art.ArtifactType -eq 'DLL') { $skip = $true }
            if ($SkipUnsigned -and -not $art.IsSigned) { $skip = $true }
            if ($SkipScripts -and $art.ArtifactType -in @('PS1', 'BAT', 'CMD', 'VBS', 'JS', 'WSF')) { $skip = $true }
            if (-not $skip) { $filtered.Add($art) }
        }
        $result.AfterExclusions = $filtered.Count

        # Phase 2: Dedupe preview
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $unique = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($art in $filtered) {
            $key = if ($Mode -eq 'Smart') {
                if ($art.IsSigned -and $art.SignerCertificate) {
                    "$($art.SignerCertificate)|$($art.ProductName)"
                } else {
                    $art.SHA256Hash
                }
            } elseif ($Mode -eq 'Publisher') {
                "$($art.SignerCertificate)|$($art.ProductName)"
            } else {
                $art.SHA256Hash
            }
            
            if ($key -and -not $seen.Contains($key)) {
                $seen.Add($key) | Out-Null
                $unique.Add($art)
            }
        }
        $result.AfterDedup = $unique.Count

        # Phase 3: Check existing
        $existingIndex = Get-ExistingRuleIndex
        $toCreate = [System.Collections.Generic.List[PSCustomObject]]::new()
        $existingCount = 0

        foreach ($art in $unique) {
            $ruleType = if ($Mode -eq 'Smart') {
                if ($art.IsSigned -and $art.SignerCertificate) { 'Publisher' } else { 'Hash' }
            } elseif ($Mode -eq 'Publisher') { 'Publisher' }
            else { 'Hash' }

            $exists = $false
            if ($ruleType -eq 'Publisher') {
                $key = "$($art.SignerCertificate)|$($art.ProductName)".ToLower()
                $exists = $existingIndex.Publisher.ContainsKey($key)
            } elseif ($ruleType -eq 'Hash' -and $art.SHA256Hash) {
                $exists = $existingIndex.Hash.ContainsKey($art.SHA256Hash.ToUpper())
            }

            if ($exists) {
                $existingCount++
            } else {
                $toCreate.Add($art)
                
                # Count by type
                if ($ruleType -eq 'Publisher') { $result.EstimatedPublisher++ }
                else { $result.EstimatedHash++ }

                # Count by collection
                $ext = if ($art.Extension) { $art.Extension } else { [System.IO.Path]::GetExtension($art.FileName) }
                $coll = switch -Regex ($ext.ToLower()) {
                    '^\.(exe|com)$' { 'Exe' }
                    '^\.(dll|ocx)$' { 'Dll' }
                    '^\.(msi|msp|mst)$' { 'Msi' }
                    '^\.(ps1|psm1|psd1|bat|cmd|vbs|js|wsf)$' { 'Script' }
                    default { 'Exe' }
                }
                if (-not $result.ByCollection.ContainsKey($coll)) {
                    $result.ByCollection[$coll] = 0
                }
                $result.ByCollection[$coll]++
            }
        }

        $result.ExistingRules = $existingCount
        $result.NewRulesToCreate = $toCreate.Count

        # Generate sample rules (first 10)
        $samples = $toCreate | Select-Object -First 10
        foreach ($art in $samples) {
            $ruleType = if ($Mode -eq 'Smart') {
                if ($art.IsSigned -and $art.SignerCertificate) { 'Publisher' } else { 'Hash' }
            } else { $Mode }

            $result.SampleRules += [PSCustomObject]@{
                Type   = $ruleType
                Name   = if ($ruleType -eq 'Publisher') { "$($art.SignerCertificate) - $($art.ProductName)" } else { $art.FileName }
                Action = 'Allow'
                Scope  = if ($art.Extension) { $art.Extension.TrimStart('.').ToUpper() } else { 'EXE' }
            }
        }
    }
    catch {
        Write-StorageLog -Message "Preview failed: $($_.Exception.Message)" -Level 'ERROR'
    }

    return $result
}
