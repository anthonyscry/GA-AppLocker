<#
.SYNOPSIS
    Converts artifacts to AppLocker rules.

.DESCRIPTION
    Automatically generates AppLocker rules from scanned artifacts.
    Uses a smart strategy to select the best rule type:
    - Publisher rule if artifact is signed (preferred)
    - Hash rule if artifact is unsigned
    - Path rule if explicitly requested

.PARAMETER Artifact
    Artifact object from scanning module (or array of artifacts).

.PARAMETER PreferredRuleType
    Force a specific rule type: Auto, Publisher, Hash, Path.
    Default is Auto (publisher for signed, hash for unsigned).

.PARAMETER GroupByPublisher
    Group artifacts by publisher into single rules (default: true).
    Only applies to publisher rules.

.PARAMETER IncludeProductVersion
    Include product version constraints in publisher rules.

.PARAMETER Action
    Rule action: Allow or Deny. Default is Allow.

.PARAMETER Status
    Initial rule status: Pending, Approved, Rejected, Review.
    Default is Pending for review workflow.

.PARAMETER Save
    Save rules to storage immediately.

.EXAMPLE
    $artifacts | ConvertFrom-Artifact -Save
    
    Converts all artifacts to rules and saves them.

.EXAMPLE
    ConvertFrom-Artifact -Artifact $myArtifact -PreferredRuleType Hash -Save
    
    Forces hash rule generation regardless of signature status.

.EXAMPLE
    $scanResult.Data.Artifacts | ConvertFrom-Artifact -GroupByPublisher -Status Approved -Save
    
    Groups signed artifacts by publisher and auto-approves them.

.OUTPUTS
    [PSCustomObject] Result with Success, Data (array of rules), and Summary.
#>
function ConvertFrom-Artifact {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$Artifact,

        [Parameter()]
        [ValidateSet('Auto', 'Publisher', 'Hash', 'Path')]
        [string]$PreferredRuleType = 'Auto',

        [Parameter()]
        [switch]$GroupByPublisher,

        [Parameter()]
        [switch]$IncludeProductVersion,

        [Parameter()]
        [ValidateSet('Allow', 'Deny')]
        [string]$Action = 'Allow',

        [Parameter()]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status = 'Pending',

        [Parameter()]
        [string]$UserOrGroupSid = 'S-1-1-0',

        [Parameter()]
        [switch]$Save
    )

    begin {
        $allArtifacts = @()
        $result = [PSCustomObject]@{
            Success = $false
            Data    = @()
            Error   = $null
            Summary = $null
        }
    }

    process {
        foreach ($art in $Artifact) {
            $allArtifacts += $art
        }
    }

    end {
        try {
            Write-RuleLog -Message "Converting $($allArtifacts.Count) artifacts to rules..."

            $rules = @()
            $publisherGroups = @{}
            $hashRules = @()
            $pathRules = @()

            foreach ($art in $allArtifacts) {
                $ruleType = $PreferredRuleType

                # Auto-detect rule type
                if ($ruleType -eq 'Auto') {
                    if ($art.IsSigned -and -not [string]::IsNullOrWhiteSpace($art.SignerCertificate)) {
                        $ruleType = 'Publisher'
                    }
                    else {
                        $ruleType = 'Hash'
                    }
                }

                # Get collection type from extension
                $extension = $art.Extension
                if (-not $extension) {
                    $extension = [System.IO.Path]::GetExtension($art.FileName)
                }
                $collectionType = Get-CollectionType -Extension $extension

                switch ($ruleType) {
                    'Publisher' {
                        if ($GroupByPublisher) {
                            # Group by publisher certificate
                            $pubKey = $art.SignerCertificate
                            if (-not $publisherGroups.ContainsKey($pubKey)) {
                                $publisherGroups[$pubKey] = @{
                                    Publisher  = $art.SignerCertificate
                                    Company    = $art.Publisher
                                    Products   = @{}
                                    Artifacts  = @()
                                    Collection = $collectionType
                                }
                            }
                            
                            # Track products
                            $prodKey = if ($art.ProductName) { $art.ProductName } else { '*' }
                            if (-not $publisherGroups[$pubKey].Products.ContainsKey($prodKey)) {
                                $publisherGroups[$pubKey].Products[$prodKey] = @{
                                    MinVersion = $null
                                    MaxVersion = $null
                                }
                            }
                            
                            if ($IncludeProductVersion -and $art.ProductVersion) {
                                $current = $publisherGroups[$pubKey].Products[$prodKey]
                                if (-not $current.MinVersion -or $art.ProductVersion -lt $current.MinVersion) {
                                    $current.MinVersion = $art.ProductVersion
                                }
                                if (-not $current.MaxVersion -or $art.ProductVersion -gt $current.MaxVersion) {
                                    $current.MaxVersion = $art.ProductVersion
                                }
                            }
                            
                            $publisherGroups[$pubKey].Artifacts += $art
                        }
                        else {
                            # Individual publisher rule per artifact
                            $productName = if ($art.ProductName) { $art.ProductName } else { '*' }
                            $minVer = if ($IncludeProductVersion -and $art.ProductVersion) { $art.ProductVersion } else { '*' }
                            
                            $pubResult = New-PublisherRule `
                                -PublisherName $art.SignerCertificate `
                                -ProductName $productName `
                                -BinaryName $art.FileName `
                                -MinVersion $minVer `
                                -MaxVersion '*' `
                                -Action $Action `
                                -CollectionType $collectionType `
                                -Status $Status `
                                -UserOrGroupSid $UserOrGroupSid `
                                -SourceArtifactId $art.SHA256Hash `
                                -Save:$Save

                            if ($pubResult.Success) {
                                $rules += $pubResult.Data
                            }
                        }
                    }
                    'Hash' {
                        if (-not $art.SHA256Hash) {
                            Write-RuleLog -Level Warning -Message "Skipping artifact without hash: $($art.FileName)"
                            continue
                        }

                        $hashResult = New-HashRule `
                            -Hash $art.SHA256Hash `
                            -SourceFileName $art.FileName `
                            -SourceFileLength $art.SizeBytes `
                            -Action $Action `
                            -CollectionType $collectionType `
                            -Status $Status `
                            -UserOrGroupSid $UserOrGroupSid `
                            -SourceArtifactId $art.SHA256Hash `
                            -Save:$Save

                        if ($hashResult.Success) {
                            $rules += $hashResult.Data
                        }
                    }
                    'Path' {
                        $pathResult = New-PathRule `
                            -Path $art.FilePath `
                            -Action $Action `
                            -CollectionType $collectionType `
                            -Status $Status `
                            -UserOrGroupSid $UserOrGroupSid `
                            -SourceArtifactId $art.SHA256Hash `
                            -Save:$Save

                        if ($pathResult.Success) {
                            $rules += $pathResult.Data
                        }
                    }
                }
            }

            # Process grouped publisher rules
            if ($GroupByPublisher -and $publisherGroups.Count -gt 0) {
                foreach ($pubKey in $publisherGroups.Keys) {
                    $group = $publisherGroups[$pubKey]
                    
                    foreach ($prodKey in $group.Products.Keys) {
                        $prod = $group.Products[$prodKey]
                        
                        $minVer = if ($prod.MinVersion) { $prod.MinVersion } else { '*' }
                        $maxVer = if ($prod.MaxVersion) { $prod.MaxVersion } else { '*' }
                        
                        $pubResult = New-PublisherRule `
                            -PublisherName $group.Publisher `
                            -ProductName $prodKey `
                            -BinaryName '*' `
                            -MinVersion $minVer `
                            -MaxVersion $maxVer `
                            -Action $Action `
                            -CollectionType $group.Collection `
                            -Status $Status `
                            -UserOrGroupSid $UserOrGroupSid `
                            -Description "Auto-generated from $($group.Artifacts.Count) artifacts" `
                            -Save:$Save

                        if ($pubResult.Success) {
                            $rules += $pubResult.Data
                        }
                    }
                }
            }

            # Build summary
            $result.Success = $true
            $result.Data = $rules
            $result.Summary = [PSCustomObject]@{
                TotalArtifacts   = $allArtifacts.Count
                TotalRules       = $rules.Count
                PublisherRules   = ($rules | Where-Object { $_.RuleType -eq 'Publisher' }).Count
                HashRules        = ($rules | Where-Object { $_.RuleType -eq 'Hash' }).Count
                PathRules        = ($rules | Where-Object { $_.RuleType -eq 'Path' }).Count
                ByCollection     = $rules | Group-Object CollectionType | Select-Object Name, Count
                ByStatus         = $rules | Group-Object Status | Select-Object Name, Count
            }

            Write-RuleLog -Message "Created $($rules.Count) rules from $($allArtifacts.Count) artifacts"
        }
        catch {
            $result.Error = "Failed to convert artifacts: $($_.Exception.Message)"
            Write-RuleLog -Level Error -Message $result.Error
        }

        return $result
    }
}
