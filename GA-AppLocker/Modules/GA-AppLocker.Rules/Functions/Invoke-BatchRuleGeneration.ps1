<#
.SYNOPSIS
    High-performance batch rule generation from artifacts.

.DESCRIPTION
    Converts artifacts to AppLocker rules using an optimized pipeline:
    1. Pre-filter (exclusions) - O(n)
    2. Deduplicate in memory - O(n)
    3. Check existing rules (single index lookup) - O(1)
    4. Generate rule objects in memory (no disk I/O) - O(n)
    5. Bulk write all rules at once - Single I/O operation
    6. Single index rebuild

    This is 10x+ faster than the sequential ConvertFrom-Artifact approach.

.PARAMETER Artifacts
    Array of artifact objects from scanning module.

.PARAMETER Mode
    Rule type preference: Smart, Publisher, Hash, Path.
    Smart = Publisher for signed, Hash for unsigned.

.PARAMETER Action
    Rule action: Allow or Deny.

.PARAMETER Status
    Initial rule status: Pending, Approved, Rejected, Review.

.PARAMETER SkipDlls
    Exclude DLL artifacts from rule generation.

.PARAMETER SkipUnsigned
    Exclude unsigned artifacts (requires hash rules).

.PARAMETER SkipScripts
    Exclude script artifacts (PS1, BAT, CMD, VBS, JS).

.PARAMETER DedupeMode
    Deduplication strategy: Smart, Publisher, Hash, None.

.PARAMETER PublisherLevel
    Granularity for publisher rules: PublisherOnly, PublisherProduct, PublisherProductFile, Exact.

.PARAMETER OnProgress
    Scriptblock callback for progress updates. Receives (percent, message).

.EXAMPLE
    $result = Invoke-BatchRuleGeneration -Artifacts $scanResult.Data.Artifacts -SkipDlls -OnProgress {
        param($pct, $msg)
        Write-Host "$pct% - $msg"
    }

.OUTPUTS
    [PSCustomObject] with Success, RulesCreated, Skipped, Duplicates, Errors, Duration.
#>
function Invoke-BatchRuleGeneration {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [array]$Artifacts,

        [Parameter()]
        [ValidateSet('Smart', 'Publisher', 'Hash', 'Path')]
        [string]$Mode = 'Smart',

        [Parameter()]
        [ValidateSet('Allow', 'Deny')]
        [string]$Action = 'Allow',

        [Parameter()]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status = 'Pending',

        [Parameter()]
        [ValidateSet('PublisherOnly', 'PublisherProduct', 'PublisherProductFile', 'Exact')]
        [string]$PublisherLevel = 'PublisherProduct',

        [Parameter()]
        [string]$UserOrGroupSid = 'S-1-1-0',

        [Parameter()]
        [switch]$SkipDlls,

        [Parameter()]
        [switch]$SkipUnsigned,

        [Parameter()]
        [switch]$SkipScripts,

        [Parameter()]
        [switch]$SkipJsOnly,

        [Parameter()]
        [ValidateSet('Smart', 'Publisher', 'Hash', 'None')]
        [string]$DedupeMode = 'Smart',

        [Parameter()]
        [string]$CollectionName,

        [Parameter()]
        [scriptblock]$OnProgress
    )

    begin {
        $allArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        foreach ($art in $Artifacts) {
            if ($art) { $allArtifacts.Add($art) }
        }
    }

    end {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $result = [PSCustomObject]@{
            Success       = $false
            RulesCreated  = 0
            Skipped       = 0
            Duplicates    = 0
            Errors        = [System.Collections.Generic.List[string]]::new()
            Duration      = $null
            Summary       = $null
        }

        if ($allArtifacts.Count -eq 0) {
            $result.Success = $true
            $result.Duration = $stopwatch.Elapsed
            Write-RuleLog -Message "Batch generation: No artifacts to process"
            return $result
        }

        try {
            Write-RuleLog -Message "Batch generation starting: $($allArtifacts.Count) artifacts"
            
            # ========================================
            # PHASE 1: Pre-filter (Exclusions)
            # ========================================
            if ($OnProgress) { & $OnProgress 5 "Filtering artifacts..." }
            
            $filtered = [System.Collections.Generic.List[PSCustomObject]]::new()
            $skipCount = 0
            
            foreach ($art in $allArtifacts) {
                $skip = $false
                
                # Skip DLLs
                if ($SkipDlls -and $art.ArtifactType -eq 'DLL') { $skip = $true }
                
                # Skip unsigned (only if creating publisher rules would fail)
                if ($SkipUnsigned -and -not $art.IsSigned) { $skip = $true }
                
                # Skip scripts
                if ($SkipScripts -and $art.ArtifactType -in @('PS1', 'BAT', 'CMD', 'VBS', 'JS', 'WSF')) { $skip = $true }
                
                # Skip JS only (but allow other scripts)
                if ($SkipJsOnly -and $art.ArtifactType -eq 'JS') { $skip = $true }
                
                if ($skip) {
                    $skipCount++
                } else {
                    $filtered.Add($art)
                }
            }
            
            $result.Skipped = $skipCount
            Write-RuleLog -Message "Filtered: $skipCount excluded, $($filtered.Count) remaining"
            if ($OnProgress) { & $OnProgress 15 "Filtered: $($filtered.Count) artifacts" }

            # ========================================
            # PHASE 2: Deduplicate in Memory
            # ========================================
            if ($OnProgress) { & $OnProgress 20 "Deduplicating artifacts..." }
            
            $unique = if ($DedupeMode -eq 'None') {
                $filtered
            } else {
                Get-UniqueArtifactsForBatch -Artifacts $filtered -Mode $DedupeMode -RuleMode $Mode -PublisherLevel $PublisherLevel
            }
            
            $dedupedCount = $filtered.Count - $unique.Count
            Write-RuleLog -Message "Deduped: $dedupedCount duplicates removed, $($unique.Count) unique"
            if ($OnProgress) { & $OnProgress 30 "Unique: $($unique.Count) artifacts" }

            # ========================================
            # PHASE 3: Check Existing Rules
            # ========================================
            if ($OnProgress) { & $OnProgress 35 "Checking existing rules..." }
            
            # Get existing rule index for O(1) lookups
            $existingIndex = Get-ExistingRuleIndex
            $toCreate = [System.Collections.Generic.List[PSCustomObject]]::new()
            $existingCount = 0
            
            foreach ($art in $unique) {
                $ruleType = Get-RuleTypeForArtifact -Artifact $art -Mode $Mode
                $exists = Test-RuleExistsInIndex -Artifact $art -Index $existingIndex -RuleType $ruleType -PublisherLevel $PublisherLevel
                
                if ($exists) {
                    $existingCount++
                } else {
                    $toCreate.Add($art)
                }
            }
            
            $result.Duplicates = $existingCount
            Write-RuleLog -Message "Existing check: $existingCount already exist, $($toCreate.Count) new"
            if ($OnProgress) { & $OnProgress 40 "New rules: $($toCreate.Count)" }

            if ($toCreate.Count -eq 0) {
                $result.Success = $true
                $result.Duration = $stopwatch.Elapsed
                $result.Summary = New-BatchSummary -Total $allArtifacts.Count -Filtered $skipCount -Deduped $dedupedCount -Existing $existingCount -Created 0
                Write-RuleLog -Message "Batch complete: No new rules to create"
                return $result
            }

            # ========================================
            # PHASE 4: Generate Rule Objects in Memory
            # ========================================
            if ($OnProgress) { & $OnProgress 45 "Generating rules..." }
            
            $rules = [System.Collections.Generic.List[PSCustomObject]]::new()
            $total = $toCreate.Count
            $processed = 0
            $lastProgressPct = 45
            
            foreach ($art in $toCreate) {
                $processed++
                
                try {
                    $rule = New-RuleObjectFromArtifact `
                        -Artifact $art `
                        -Mode $Mode `
                        -Action $Action `
                        -Status $Status `
                        -PublisherLevel $PublisherLevel `
                        -UserOrGroupSid $UserOrGroupSid `
                        -CollectionName $CollectionName
                    
                    if ($rule) {
                        $rules.Add($rule)
                    }
                }
                catch {
                    $result.Errors.Add("Failed to create rule for $($art.FileName): $($_.Exception.Message)")
                }
                
                # Progress updates every 100 items
                if ($OnProgress -and ($processed % 100 -eq 0)) {
                    $pct = 45 + [int](35 * $processed / $total)
                    if ($pct -gt $lastProgressPct) {
                        & $OnProgress $pct "Creating: $processed / $total"
                        $lastProgressPct = $pct
                    }
                }
            }
            
            Write-RuleLog -Message "Generated $($rules.Count) rule objects in memory"
            if ($OnProgress) { & $OnProgress 85 "Saving $($rules.Count) rules..." }

            # ========================================
            # PHASE 5: Bulk Save All Rules
            # ========================================
            $saveResult = Save-RulesBulk -Rules $rules -UpdateIndex
            
            if ($saveResult.Success) {
                $result.RulesCreated = $saveResult.SavedCount
                $result.Success = $true
                Write-RuleLog -Message "Batch save complete: $($saveResult.SavedCount) rules saved"
            } else {
                $result.Errors.Add($saveResult.Error)
                Write-RuleLog -Level Error -Message "Batch save failed: $($saveResult.Error)"
            }

            if ($OnProgress) { & $OnProgress 100 "Complete: $($result.RulesCreated) rules created" }
            
            $stopwatch.Stop()
            $result.Duration = $stopwatch.Elapsed
            $result.Summary = New-BatchSummary `
                -Total $allArtifacts.Count `
                -Filtered $skipCount `
                -Deduped $dedupedCount `
                -Existing $existingCount `
                -Created $result.RulesCreated `
                -Rules $rules
            
            Write-RuleLog -Message "Batch generation complete in $($stopwatch.Elapsed.TotalSeconds.ToString('F1'))s"
        }
        catch {
            $result.Errors.Add("Batch generation failed: $($_.Exception.Message)")
            Write-RuleLog -Level Error -Message "Batch generation error: $($_.Exception.Message)"
        }

        return $result
    }
}

#region ===== HELPER FUNCTIONS =====

function script:Get-RuleTypeForArtifact {
    <#
    .SYNOPSIS
        Determines the rule type for an artifact based on mode.
    #>
    param(
        [PSCustomObject]$Artifact,
        [string]$Mode
    )
    
    switch ($Mode) {
        'Smart' {
            if ($Artifact.IsSigned -and -not [string]::IsNullOrWhiteSpace($Artifact.SignerCertificate)) {
                return 'Publisher'
            }
            return 'Hash'
        }
        'Publisher' { return 'Publisher' }
        'Hash' { return 'Hash' }
        'Path' { return 'Path' }
        default { return 'Hash' }
    }
}

function script:Get-UniqueArtifactsForBatch {
    <#
    .SYNOPSIS
        Deduplicates artifacts based on what will become unique rules.
    #>
    param(
        [System.Collections.Generic.List[PSCustomObject]]$Artifacts,
        [string]$Mode,
        [string]$RuleMode,
        [string]$PublisherLevel = 'PublisherProduct'
    )
    
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $unique = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    foreach ($art in $Artifacts) {
        $key = switch ($Mode) {
            'Smart' {
                # Key based on what rule will be created
                $ruleType = Get-RuleTypeForArtifact -Artifact $art -Mode $RuleMode
                if ($ruleType -eq 'Publisher') {
                    if ($PublisherLevel -eq 'PublisherOnly') {
                        $art.SignerCertificate
                    } else {
                        "$($art.SignerCertificate)|$($art.ProductName)"
                    }
                } else {
                    $art.SHA256Hash
                }
            }
            'Publisher' {
                # Respect PublisherLevel for deduplication
                if ($PublisherLevel -eq 'PublisherOnly') {
                    $art.SignerCertificate
                } else {
                    "$($art.SignerCertificate)|$($art.ProductName)"
                }
            }
            'Hash' {
                $art.SHA256Hash
            }
            default {
                $art.SHA256Hash
            }
        }
        
        if ($key -and -not $seen.Contains($key)) {
            $seen.Add($key) | Out-Null
            $unique.Add($art)
        }
    }
    
    return $unique
}

function script:Test-RuleExistsInIndex {
    <#
    .SYNOPSIS
        Checks if a rule already exists for this artifact using O(1) index lookup.
    #>
    param(
        [PSCustomObject]$Artifact,
        [PSCustomObject]$Index,
        [string]$RuleType,
        [string]$PublisherLevel = 'PublisherProduct'
    )
    
    if (-not $Index) { return $false }
    
    switch ($RuleType) {
        'Publisher' {
            # Respect PublisherLevel for existing rule check
            $key = if ($PublisherLevel -eq 'PublisherOnly') {
                $Artifact.SignerCertificate.ToLower()
            } else {
                "$($Artifact.SignerCertificate)|$($Artifact.ProductName)".ToLower()
            }
            # Use correct index based on PublisherLevel
            if ($PublisherLevel -eq 'PublisherOnly') {
                if ($Index.PublishersOnly) {
                    return $Index.PublishersOnly.Contains($key)
                }
            } else {
                if ($Index.Publishers) {
                    return $Index.Publishers.Contains($key)
                }
            }
            return $false
        }
        'Hash' {
            $hash = $Artifact.SHA256Hash
            if ($hash -and $Index.Hashes) {
                return $Index.Hashes.Contains($hash.ToUpper())
            }
            return $false
        }
        'Path' {
            # Path rules not indexed yet
            return $false
        }
    }
    
    return $false
}

function script:New-RuleObjectFromArtifact {
    <#
    .SYNOPSIS
        Creates a rule object in memory without saving to disk.
    #>
    param(
        [PSCustomObject]$Artifact,
        [string]$Mode,
        [string]$Action,
        [string]$Status,
        [string]$PublisherLevel,
        [string]$UserOrGroupSid,
        [string]$CollectionName
    )
    
    $ruleType = Get-RuleTypeForArtifact -Artifact $Artifact -Mode $Mode
    
    # Get collection type from extension
    $extension = $Artifact.Extension
    if (-not $extension) {
        $extension = [System.IO.Path]::GetExtension($Artifact.FileName)
    }
    $collectionType = Get-CollectionType -Extension $extension
    
    # Get group suggestion
    $groupSuggestion = Get-SuggestedGroup `
        -PublisherName $Artifact.SignerCertificate `
        -ProductName $Artifact.ProductName `
        -FilePath $Artifact.FilePath `
        -IsSigned $Artifact.IsSigned
    $suggestedGroup = if ($groupSuggestion.Success) { $groupSuggestion.Data } else { $null }
    
    $ruleId = [guid]::NewGuid().ToString()
    $now = Get-Date -Format 'o'
    
    switch ($ruleType) {
        'Publisher' {
            # Apply publisher level granularity
            $productName = switch ($PublisherLevel) {
                'PublisherOnly' { '*' }
                default { if ($Artifact.ProductName) { $Artifact.ProductName } else { '*' } }
            }
            
            $binaryName = switch ($PublisherLevel) {
                'PublisherOnly' { '*' }
                'PublisherProduct' { '*' }
                default { $Artifact.FileName }
            }
            
            $minVer = switch ($PublisherLevel) {
                'Exact' { if ($Artifact.ProductVersion) { $Artifact.ProductVersion } else { '*' } }
                default { '*' }
            }
            
            $pubName = Format-PublisherString -CertSubject $Artifact.SignerCertificate
            
            return [PSCustomObject]@{
                Id              = $ruleId
                RuleType        = 'Publisher'
                CollectionType  = $collectionType
                Status          = $Status
                Action          = $Action
                Name            = "Publisher: $pubName - $productName"
                Description     = "Auto-generated publisher rule"
                PublisherName   = $Artifact.SignerCertificate
                ProductName     = $productName
                BinaryName      = $binaryName
                MinVersion      = $minVer
                MaxVersion      = '*'
                UserOrGroupSid  = $UserOrGroupSid
                SourceArtifactId = $Artifact.SHA256Hash
                SourceFile      = $Artifact.FileName
                SourceMachine   = $Artifact.MachineName
                GroupName       = if ($suggestedGroup) { $suggestedGroup.GroupName } else { $null }
                GroupVendor     = if ($suggestedGroup) { $suggestedGroup.Vendor } else { $null }
                CollectionName  = $CollectionName
                CreatedDate     = $now
                ModifiedDate    = $now
            }
        }
        'Hash' {
            if (-not $Artifact.SHA256Hash) { return $null }
            
            return [PSCustomObject]@{
                Id              = $ruleId
                RuleType        = 'Hash'
                CollectionType  = $collectionType
                Status          = $Status
                Action          = $Action
                Name            = "Hash: $($Artifact.FileName)"
                Description     = "Auto-generated hash rule"
                Hash            = $Artifact.SHA256Hash
                HashType        = 'SHA256'
                SourceFileName  = $Artifact.FileName
                SourceFileLength = $Artifact.SizeBytes
                UserOrGroupSid  = $UserOrGroupSid
                SourceArtifactId = $Artifact.SHA256Hash
                SourceFile      = $Artifact.FileName
                SourceMachine   = $Artifact.MachineName
                GroupName       = if ($suggestedGroup) { $suggestedGroup.GroupName } else { $null }
                GroupVendor     = if ($suggestedGroup) { $suggestedGroup.Vendor } else { $null }
                CollectionName  = $CollectionName
                CreatedDate     = $now
                ModifiedDate    = $now
            }
        }
        'Path' {
            return [PSCustomObject]@{
                Id              = $ruleId
                RuleType        = 'Path'
                CollectionType  = $collectionType
                Status          = $Status
                Action          = $Action
                Name            = "Path: $($Artifact.FilePath)"
                Description     = "Auto-generated path rule"
                Path            = $Artifact.FilePath
                UserOrGroupSid  = $UserOrGroupSid
                SourceArtifactId = $Artifact.SHA256Hash
                SourceFile      = $Artifact.FileName
                SourceMachine   = $Artifact.MachineName
                GroupName       = if ($suggestedGroup) { $suggestedGroup.GroupName } else { $null }
                GroupVendor     = if ($suggestedGroup) { $suggestedGroup.Vendor } else { $null }
                CollectionName  = $CollectionName
                CreatedDate     = $now
                ModifiedDate    = $now
            }
        }
    }
    
    return $null
}

function script:New-BatchSummary {
    <#
    .SYNOPSIS
        Creates a summary object for batch generation results.
    #>
    param(
        [int]$Total,
        [int]$Filtered,
        [int]$Deduped,
        [int]$Existing,
        [int]$Created,
        [array]$Rules
    )
    
    $summary = [PSCustomObject]@{
        TotalArtifacts   = $Total
        FilteredOut      = $Filtered
        Deduplicated     = $Deduped
        AlreadyExisted   = $Existing
        RulesCreated     = $Created
        ByRuleType       = @{}
        ByCollection     = @{}
        ByStatus         = @{}
    }
    
    if ($Rules -and $Rules.Count -gt 0) {
        $Rules | Group-Object RuleType | ForEach-Object {
            $summary.ByRuleType[$_.Name] = $_.Count
        }
        $Rules | Group-Object CollectionType | ForEach-Object {
            $summary.ByCollection[$_.Name] = $_.Count
        }
        $Rules | Group-Object Status | ForEach-Object {
            $summary.ByStatus[$_.Name] = $_.Count
        }
    }
    
    return $summary
}

#endregion
