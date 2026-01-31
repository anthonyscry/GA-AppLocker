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

.PARAMETER SkipWshScripts
    Exclude WSH script artifacts (JS, VBS, WSF) — legacy malware vectors.

.PARAMETER SkipShellScripts
    Exclude shell script artifacts (PS1, BAT, CMD) — admin/management scripts.

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
        [switch]$SkipWshScripts,

        [Parameter()]
        [switch]$SkipShellScripts,

        [Parameter()]
        [ValidateSet('Smart', 'Publisher', 'Hash', 'None')]
        [string]$DedupeMode = 'Smart',

        [Parameter()]
        [ValidateSet('Hash', 'Path', 'Skip')]
        [string]$UnsignedMode = 'Hash',

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
                
                # Skip WSH scripts (.js, .vbs, .wsf)
                if ($SkipWshScripts -and $art.ArtifactType -in @('JS', 'VBS', 'WSF')) { $skip = $true }
                
                # Skip shell scripts (.ps1, .bat, .cmd)
                if ($SkipShellScripts -and $art.ArtifactType -in @('PS1', 'BAT', 'CMD')) { $skip = $true }
                
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
                Get-UniqueArtifactsForBatch -Artifacts $filtered -Mode $DedupeMode -RuleMode $Mode -PublisherLevel $PublisherLevel -UnsignedMode $UnsignedMode
            }
            
            $dedupedCount = $filtered.Count - $unique.Count
            Write-RuleLog -Message "DEBUG Invoke-BatchRuleGeneration received PublisherLevel=$PublisherLevel, UnsignedMode=$UnsignedMode"
            Write-RuleLog -Message "Deduped: $dedupedCount duplicates removed, $($unique.Count) unique (Mode=$Mode, DedupeMode=$DedupeMode, PublisherLevel=$PublisherLevel, UnsignedMode=$UnsignedMode)"
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
                $ruleType = Get-RuleTypeForArtifact -Artifact $art -Mode $Mode -UnsignedMode $UnsignedMode
                if ($ruleType -eq 'Skip') { continue }  # Skip unsigned files if UnsignedMode is 'Skip'
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
                        -CollectionName $CollectionName `
                        -UnsignedMode $UnsignedMode
                    
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

#region ===== PREVIEW FUNCTION =====

function Get-BatchPreview {
    <#
    .SYNOPSIS
        Calculates a preview of what rules would be created from artifacts.
    .DESCRIPTION
        Used by the Rule Generation Wizard to show estimated counts before
        actually generating rules. Performs the same filtering/deduplication
        logic as Invoke-BatchRuleGeneration but doesn't create any rules.
    .PARAMETER Artifacts
        Array of artifact objects from scanning module.
    .PARAMETER Mode
        Rule type preference: Smart, Publisher, Hash, Path.
    .PARAMETER SkipDlls
        Exclude DLL artifacts.
    .PARAMETER SkipUnsigned
        Exclude unsigned artifacts.
    .PARAMETER SkipScripts
        Exclude script artifacts.
    .PARAMETER DedupeMode
        Deduplication strategy: Smart, Publisher, Hash, None.
    .PARAMETER PublisherLevel
        Granularity for publisher rules.
    .OUTPUTS
        PSCustomObject with preview statistics.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Artifacts,

        [ValidateSet('Smart', 'Publisher', 'Hash', 'Path')]
        [string]$Mode = 'Smart',

        [switch]$SkipDlls,
        [switch]$SkipUnsigned,
        [switch]$SkipScripts,

        [ValidateSet('Smart', 'Publisher', 'Hash', 'None')]
        [string]$DedupeMode = 'Smart',

        [ValidateSet('PublisherOnly', 'PublisherProduct', 'PublisherProductFile', 'Exact')]
        [string]$PublisherLevel = 'PublisherProduct',

        [ValidateSet('Hash', 'Path', 'Skip')]
        [string]$UnsignedMode = 'Hash'
    )

    $preview = [PSCustomObject]@{
        TotalArtifacts = $Artifacts.Count
        AfterExclusions = 0
        AfterDedup = 0
        NewRulesToCreate = 0
        ExistingRules = 0
        EstimatedPublisher = 0
        EstimatedHash = 0
        EstimatedPath = 0
        SampleRules = @()
    }

    if ($Artifacts.Count -eq 0) {
        return $preview
    }

    # Phase 1: Apply exclusions
    $filtered = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($art in $Artifacts) {
        $skip = $false
        if ($SkipDlls -and $art.ArtifactType -eq 'DLL') { $skip = $true }
        if ($SkipUnsigned -and -not $art.IsSigned) { $skip = $true }
        if ($SkipScripts -and $art.ArtifactType -in @('PS1', 'BAT', 'CMD', 'VBS', 'JS', 'WSF')) { $skip = $true }
        
        if (-not $skip) {
            $filtered.Add($art)
        }
    }
    $preview.AfterExclusions = $filtered.Count

    if ($filtered.Count -eq 0) {
        return $preview
    }

    # Phase 2: Deduplicate
    $unique = if ($DedupeMode -eq 'None') {
        $filtered
    } else {
        Get-UniqueArtifactsForBatch -Artifacts $filtered -Mode $DedupeMode -RuleMode $Mode -PublisherLevel $PublisherLevel -UnsignedMode $UnsignedMode
    }
    $preview.AfterDedup = $unique.Count

    # Phase 3: Check existing rules
    $existingIndex = Get-ExistingRuleIndex
    $toCreate = [System.Collections.Generic.List[PSCustomObject]]::new()
    $existingCount = 0
    $pubCount = 0
    $hashCount = 0
    $pathCount = 0

    foreach ($art in $unique) {
        $ruleType = Get-RuleTypeForArtifact -Artifact $art -Mode $Mode -UnsignedMode $UnsignedMode
        if ($ruleType -eq 'Skip') { continue }
        
        $exists = Test-RuleExistsInIndex -Artifact $art -Index $existingIndex -RuleType $ruleType -PublisherLevel $PublisherLevel
        
        if ($exists) {
            $existingCount++
        } else {
            $toCreate.Add($art)
            switch ($ruleType) {
                'Publisher' { $pubCount++ }
                'Hash' { $hashCount++ }
                'Path' { $pathCount++ }
            }
        }
    }

    $preview.ExistingRules = $existingCount
    $preview.NewRulesToCreate = $toCreate.Count
    $preview.EstimatedPublisher = $pubCount
    $preview.EstimatedHash = $hashCount
    $preview.EstimatedPath = $pathCount

    # Generate sample rules (first 10)
    $sampleRules = [System.Collections.Generic.List[PSCustomObject]]::new()
    $sampleCount = [Math]::Min(10, $toCreate.Count)
    
    for ($i = 0; $i -lt $sampleCount; $i++) {
        $art = $toCreate[$i]
        $ruleType = Get-RuleTypeForArtifact -Artifact $art -Mode $Mode -UnsignedMode $UnsignedMode
        
        $sampleRules.Add([PSCustomObject]@{
            FileName = $art.FileName
            RuleType = $ruleType
            Publisher = if ($art.SignerCertificate) { 
                (Format-PublisherString -CertSubject $art.SignerCertificate -FileName $art.FileName)
            } elseif ($art.PublisherName) {
                $art.PublisherName
            } else { 'N/A' }
            Product = if ($art.ProductName) { $art.ProductName } else { 'N/A' }
            IsSigned = $art.IsSigned
        })
    }
    $preview.SampleRules = $sampleRules.ToArray()

    return $preview
}

#endregion

#region ===== HELPER FUNCTIONS =====

function script:Test-GuidOnlyCertificate {
    <#
    .SYNOPSIS
        Checks if a certificate subject contains only a GUID as the CN with no other useful info.
        GUID-only certificates don't provide meaningful publisher identification.

    .DESCRIPTION
        Checks if a certificate subject contains only a GUID as the CN with no other useful info. GUID-only certificates don't provide meaningful publisher identification.
    #>
    param([string]$CertSubject)
    
    if ([string]::IsNullOrWhiteSpace($CertSubject)) { return $false }
    
    # Pattern for GUID-only certificate (CN=GUID with nothing else)
    $guidPattern = '^CN=[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
    
    return $CertSubject -match $guidPattern
}

function script:Get-AppNameFromFileName {
    <#
    .SYNOPSIS
        Extracts a friendly app name from an Appx package filename.
        e.g., "AcerIncorporated.AcerCareCenterS.appx" -> "Acer Care Center S"

    .DESCRIPTION
        Extracts a friendly app name from an Appx package filename. e.g., "AcerIncorporated.AcerCareCenterS.appx" -> "Acer Care Center S".
    #>
    param([string]$FileName)
    
    if ([string]::IsNullOrWhiteSpace($FileName)) { return $null }
    
    # Remove extension
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    
    # Common patterns: Publisher.AppName or Publisher.App.Name
    # Try to extract the app name part (after first dot)
    if ($name -match '^[^.]+\.(.+)$') {
        $appPart = $Matches[1]
        
        # Convert PascalCase to spaces: "AcerCareCenterS" -> "Acer Care Center S"
        $friendly = $appPart -creplace '([a-z])([A-Z])', '$1 $2'
        # Also handle "PowerBI" style -> "Power BI"
        $friendly = $friendly -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
        # Remove dots
        $friendly = $friendly -replace '\.', ' '
        
        return $friendly.Trim()
    }
    
    return $name
}

function script:Get-RuleTypeForArtifact {
    <#
    .SYNOPSIS
        Determines the rule type for an artifact based on mode and unsigned handling.

    .DESCRIPTION
        Determines the rule type for an artifact based on mode and unsigned handling.
    #>
    param(
        [PSCustomObject]$Artifact,
        [string]$Mode,
        [string]$UnsignedMode = 'Hash'
    )
    
    # For Appx packages, use PublisherName instead of SignerCertificate
    $publisherString = if ($Artifact.CollectionType -eq 'Appx' -and $Artifact.PublisherName) {
        $Artifact.PublisherName
    } else {
        $Artifact.SignerCertificate
    }
    
    switch ($Mode) {
        'Smart' {
            if ($Artifact.IsSigned -and -not [string]::IsNullOrWhiteSpace($publisherString)) {
                # Check for GUID-only certificates - use Hash instead since they don't provide
                # meaningful publisher identification and typically cover only one file
                if (Test-GuidOnlyCertificate -CertSubject $publisherString) {
                    Write-RuleLog -Message "GUID-only certificate detected for $($Artifact.FileName), using Hash rule"
                    return 'Hash'
                }
                return 'Publisher'
            }
            # Unsigned file - check UnsignedMode
            switch ($UnsignedMode) {
                'Path' { return 'Path' }
                'Skip' { return 'Skip' }
                default { return 'Hash' }
            }
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

    .DESCRIPTION
        Deduplicates artifacts based on what will become unique rules.
    #>
    param(
        [System.Collections.Generic.List[PSCustomObject]]$Artifacts,
        [string]$Mode,
        [string]$RuleMode,
        [string]$PublisherLevel = 'PublisherProduct',
        [string]$UnsignedMode = 'Hash'
    )
    
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $unique = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    foreach ($art in $Artifacts) {
        # Determine what rule type this artifact will create
        $ruleType = Get-RuleTypeForArtifact -Artifact $art -Mode $RuleMode -UnsignedMode $UnsignedMode
        
        # Skip artifacts marked for skipping
        if ($ruleType -eq 'Skip') { continue }
        
        # Get publisher string (Appx uses PublisherName, others use SignerCertificate)
        $pubStr = if ($art.CollectionType -eq 'Appx' -and $art.PublisherName) {
            $art.PublisherName
        } else {
            $art.SignerCertificate
        }
        
        $key = switch ($Mode) {
            'Smart' {
                # Key based on what rule will be created
                switch ($ruleType) {
                    'Publisher' {
                        if ($PublisherLevel -eq 'PublisherOnly') {
                            $pubStr
                        } else {
                            "$pubStr|$($art.ProductName)"
                        }
                    }
                    'Path' {
                        # Dedupe by folder + collection type for path rules
                        $folder = Split-Path $art.FilePath -Parent
                        $ext = if ($art.Extension) { $art.Extension } else { [System.IO.Path]::GetExtension($art.FileName) }
                        $collection = Get-CollectionType -Extension $ext
                        "$collection|$folder"
                    }
                    default {
                        $art.SHA256Hash
                    }
                }
            }
            'Publisher' {
                # Respect PublisherLevel for deduplication
                if ($PublisherLevel -eq 'PublisherOnly') {
                    $pubStr
                } else {
                    "$pubStr|$($art.ProductName)"
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

    .DESCRIPTION
        Checks if a rule already exists for this artifact using O(1) index lookup.
    #>
    param(
        [PSCustomObject]$Artifact,
        [PSCustomObject]$Index,
        [string]$RuleType,
        [string]$PublisherLevel = 'PublisherProduct'
    )
    
    if (-not $Index) { return $false }
    
    # Get publisher string (Appx uses PublisherName, others use SignerCertificate)
    $pubStr = if ($Artifact.CollectionType -eq 'Appx' -and $Artifact.PublisherName) {
        $Artifact.PublisherName
    } else {
        $Artifact.SignerCertificate
    }
    
    switch ($RuleType) {
        'Publisher' {
            # Respect PublisherLevel for existing rule check
            $key = if ($PublisherLevel -eq 'PublisherOnly') {
                $pubStr.ToLower()
            } else {
                "$pubStr|$($Artifact.ProductName)".ToLower()
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

    .DESCRIPTION
        Creates a rule object in memory without saving to disk.
    #>
    param(
        [PSCustomObject]$Artifact,
        [string]$Mode,
        [string]$Action,
        [string]$Status,
        [string]$PublisherLevel,
        [string]$UserOrGroupSid,
        [string]$CollectionName,
        [string]$UnsignedMode = 'Hash'
    )
    
    $ruleType = Get-RuleTypeForArtifact -Artifact $Artifact -Mode $Mode -UnsignedMode $UnsignedMode
    if ($ruleType -eq 'Skip') { return $null }
    
    # Get collection type from extension
    $extension = $Artifact.Extension
    if (-not $extension) {
        $extension = [System.IO.Path]::GetExtension($Artifact.FileName)
    }
    $collectionType = Get-CollectionType -Extension $extension
    
    # Get publisher string (Appx uses PublisherName, others use SignerCertificate)
    $pubStr = if ($Artifact.CollectionType -eq 'Appx' -and $Artifact.PublisherName) {
        $Artifact.PublisherName
    } else {
        $Artifact.SignerCertificate
    }
    
    # Get group suggestion
    $groupSuggestion = Get-SuggestedGroup `
        -PublisherName $pubStr `
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
            
            $pubName = Format-PublisherString -CertSubject $pubStr -FileName $Artifact.FileName
            
            return [PSCustomObject]@{
                Id              = $ruleId
                RuleType        = 'Publisher'
                CollectionType  = $collectionType
                Status          = $Status
                Action          = $Action
                Name            = "Publisher: $pubName - $productName"
                Description     = "Auto-generated publisher rule"
                PublisherName   = $pubStr
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
            # For path rules from unsigned files, use folder path with wildcard
            $folderPath = Split-Path $Artifact.FilePath -Parent
            $pathRule = "$folderPath\*"
            $folderName = Split-Path $folderPath -Leaf
            
            return [PSCustomObject]@{
                Id              = $ruleId
                RuleType        = 'Path'
                CollectionType  = $collectionType
                Status          = $Status
                Action          = $Action
                Name            = "Path: $folderName\*"
                Description     = "Auto-generated path rule for folder: $folderPath"
                Path            = $pathRule
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

    .DESCRIPTION
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
