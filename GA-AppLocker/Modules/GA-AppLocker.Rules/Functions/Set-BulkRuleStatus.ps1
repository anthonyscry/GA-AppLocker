<#
.SYNOPSIS
    Bulk update rule status for multiple rules.

.DESCRIPTION
    Efficiently updates the status of multiple AppLocker rules based on filters.
    Supports filtering by vendor, publisher pattern, group, rule type, and collection.
    Essential for processing large numbers of pending rules.

.PARAMETER Status
    New status to apply: Pending, Approved, Rejected, Review.

.PARAMETER Vendor
    Match rules where GroupVendor equals this value (exact match).

.PARAMETER VendorPattern
    Match rules where GroupVendor matches this wildcard pattern.

.PARAMETER PublisherPattern
    Match rules where PublisherName matches this wildcard pattern (Publisher rules only).

.PARAMETER GroupName
    Match rules where GroupName equals this value.

.PARAMETER RuleType
    Filter by rule type: Publisher, Hash, Path.

.PARAMETER CollectionType
    Filter by collection: Exe, Dll, Msi, Script, Appx.

.PARAMETER CurrentStatus
    Only update rules that currently have this status.

.PARAMETER WhatIf
    Preview changes without applying them.

.PARAMETER PassThru
    Return the updated rules.

.EXAMPLE
    Set-BulkRuleStatus -VendorPattern '*MICROSOFT*' -Status Approved -CurrentStatus Pending
    
    Approves all pending Microsoft rules.

.EXAMPLE
    Set-BulkRuleStatus -PublisherPattern '*ADOBE*' -Status Approved -WhatIf
    
    Shows what Adobe rules would be approved without making changes.

.OUTPUTS
    [PSCustomObject] Result with Success, UpdatedCount, and optionally Data.
#>
function Set-BulkRuleStatus {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status,

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string]$VendorPattern,

        [Parameter()]
        [string]$PublisherPattern,

        [Parameter()]
        [string]$GroupName,

        [Parameter()]
        [ValidateSet('Publisher', 'Hash', 'Path')]
        [string]$RuleType,

        [Parameter()]
        [ValidateSet('Exe', 'Dll', 'Msi', 'Script', 'Appx')]
        [string]$CollectionType,

        [Parameter()]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$CurrentStatus,

        [Parameter()]
        [switch]$PassThru
    )

    $result = [PSCustomObject]@{
        Success      = $false
        UpdatedCount = 0
        SkippedCount = 0
        ErrorCount   = 0
        Data         = @()
        Error        = $null
        Summary      = $null
    }

    try {
        $rulePath = Get-RuleStoragePath
        $ruleFiles = Get-ChildItem -Path $rulePath -Filter '*.json' -ErrorAction SilentlyContinue
        $totalFiles = $ruleFiles.Count

        if ($totalFiles -eq 0) {
            $result.Error = "No rules found in storage"
            return $result
        }

        Write-RuleLog -Message "Scanning $totalFiles rules for bulk status update..."

        $matchedRules = @()
        $processedCount = 0

        foreach ($file in $ruleFiles) {
            $processedCount++
            
            # Progress reporting every 1000 files
            if ($processedCount % 1000 -eq 0) {
                $pct = [math]::Round(($processedCount / $totalFiles) * 100)
                Write-Progress -Activity "Scanning rules" -Status "$processedCount of $totalFiles ($pct%)" -PercentComplete $pct
            }

            try {
                $rule = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json

                # Apply filters
                $matches = $true

                # Current status filter
                if ($CurrentStatus -and $rule.Status -ne $CurrentStatus) {
                    $matches = $false
                }

                # Already at target status - skip
                if ($rule.Status -eq $Status) {
                    $matches = $false
                }

                # Vendor exact match
                if ($matches -and $Vendor) {
                    if ($rule.GroupVendor -ne $Vendor) {
                        $matches = $false
                    }
                }

                # Vendor pattern match
                if ($matches -and $VendorPattern) {
                    if (-not ($rule.GroupVendor -like $VendorPattern)) {
                        $matches = $false
                    }
                }

                # Publisher pattern match (for publisher rules, match PublisherName)
                if ($matches -and $PublisherPattern) {
                    if ($rule.RuleType -eq 'Publisher') {
                        if (-not ($rule.PublisherName -like $PublisherPattern)) {
                            $matches = $false
                        }
                    }
                    else {
                        # For non-publisher rules, try matching Name field
                        if (-not ($rule.Name -like $PublisherPattern)) {
                            $matches = $false
                        }
                    }
                }

                # Group name match
                if ($matches -and $GroupName) {
                    if ($rule.GroupName -ne $GroupName) {
                        $matches = $false
                    }
                }

                # Rule type filter
                if ($matches -and $RuleType) {
                    if ($rule.RuleType -ne $RuleType) {
                        $matches = $false
                    }
                }

                # Collection type filter
                if ($matches -and $CollectionType) {
                    if ($rule.CollectionType -ne $CollectionType) {
                        $matches = $false
                    }
                }

                if ($matches) {
                    $matchedRules += @{
                        File = $file
                        Rule = $rule
                    }
                }
            }
            catch {
                $result.ErrorCount++
            }
        }

        Write-Progress -Activity "Scanning rules" -Completed

        if ($matchedRules.Count -eq 0) {
            $result.Success = $true
            $result.Summary = "No rules matched the specified filters"
            Write-RuleLog -Message $result.Summary
            return $result
        }

        # Build summary by type
        $byType = $matchedRules | Group-Object { $_.Rule.RuleType }
        $byCollection = $matchedRules | Group-Object { $_.Rule.CollectionType }

        $summaryText = "Found $($matchedRules.Count) rules to update:`n"
        $summaryText += "  By Type: " + (($byType | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ", ") + "`n"
        $summaryText += "  By Collection: " + (($byCollection | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ", ")

        # WhatIf mode - just report
        if ($WhatIfPreference) {
            $result.Success = $true
            $result.Summary = "WhatIf: Would update $($matchedRules.Count) rules to status '$Status'`n$summaryText"
            Write-Host $result.Summary -ForegroundColor Cyan
            return $result
        }

        # Apply updates
        Write-RuleLog -Message "Updating $($matchedRules.Count) rules to status '$Status'..."
        $updateCount = 0

        foreach ($item in $matchedRules) {
            $updateCount++
            
            if ($updateCount % 500 -eq 0) {
                $pct = [math]::Round(($updateCount / $matchedRules.Count) * 100)
                Write-Progress -Activity "Updating rules" -Status "$updateCount of $($matchedRules.Count) ($pct%)" -PercentComplete $pct
            }

            try {
                $oldStatus = $item.Rule.Status
                $item.Rule.Status = $Status
                $item.Rule.ModifiedDate = Get-Date

                $item.Rule | ConvertTo-Json -Depth 10 | Set-Content -Path $item.File.FullName -Encoding UTF8

                $result.UpdatedCount++

                if ($PassThru) {
                    $result.Data += $item.Rule
                }
            }
            catch {
                $result.ErrorCount++
                Write-RuleLog -Level Warning -Message "Failed to update rule $($item.Rule.Id): $($_.Exception.Message)"
            }
        }

        Write-Progress -Activity "Updating rules" -Completed

        $result.Success = $true
        $result.Summary = "Updated $($result.UpdatedCount) rules to status '$Status'`n$summaryText"
        
        if ($result.ErrorCount -gt 0) {
            $result.Summary += "`nErrors: $($result.ErrorCount)"
        }

        Write-RuleLog -Message $result.Summary
    }
    catch {
        $result.Error = "Bulk status update failed: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}

<#
.SYNOPSIS
    Approves all rules from trusted vendors.

.DESCRIPTION
    Convenience function to bulk-approve rules from well-known trusted vendors
    like Microsoft, Adobe, Oracle, Google, etc. Only approves rules currently
    in Pending status.

.PARAMETER WhatIf
    Preview changes without applying them.

.PARAMETER IncludeMediumRisk
    Also approve medium-risk vendors (NodeJS, Python runtimes).

.EXAMPLE
    Approve-TrustedVendorRules -WhatIf
    
    Shows how many rules would be approved without making changes.

.EXAMPLE
    Approve-TrustedVendorRules
    
    Approves all pending rules from trusted vendors.

.OUTPUTS
    [PSCustomObject] Combined result from all vendor approvals.
#>
function Approve-TrustedVendorRules {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$IncludeMediumRisk
    )

    $result = [PSCustomObject]@{
        Success      = $false
        TotalUpdated = 0
        ByVendor     = @{}
        Error        = $null
    }

    # Low-risk trusted vendors (from KnownVendors.json)
    $trustedPatterns = @(
        @{ Name = 'Microsoft'; Pattern = '*MICROSOFT*' },
        @{ Name = 'Adobe'; Pattern = '*ADOBE*' },
        @{ Name = 'Oracle'; Pattern = '*ORACLE*' },
        @{ Name = 'Google'; Pattern = '*GOOGLE*' },
        @{ Name = 'Mozilla'; Pattern = '*MOZILLA*' },
        @{ Name = 'Apple'; Pattern = '*APPLE*' },
        @{ Name = 'Cisco'; Pattern = '*CISCO*' },
        @{ Name = 'VMware'; Pattern = '*VMWARE*' },
        @{ Name = 'Citrix'; Pattern = '*CITRIX*' },
        @{ Name = 'Zoom'; Pattern = '*ZOOM*' },
        @{ Name = 'Slack'; Pattern = '*SLACK*' },
        @{ Name = '7-Zip'; Pattern = '*IGOR PAVLOV*' },
        @{ Name = 'Notepad++'; Pattern = '*NOTEPAD++*' },
        @{ Name = 'Git'; Pattern = '*GIT*' },
        @{ Name = 'JetBrains'; Pattern = '*JETBRAINS*' },
        @{ Name = 'Docker'; Pattern = '*DOCKER*' },
        @{ Name = 'NVIDIA'; Pattern = '*NVIDIA*' },
        @{ Name = 'Intel'; Pattern = '*INTEL*' },
        @{ Name = 'AMD'; Pattern = '*AMD*' },
        @{ Name = 'Dell'; Pattern = '*DELL*' },
        @{ Name = 'HP'; Pattern = '*HEWLETT*' },
        @{ Name = 'Lenovo'; Pattern = '*LENOVO*' }
    )

    # Medium-risk vendors (optional)
    if ($IncludeMediumRisk) {
        $trustedPatterns += @(
            @{ Name = 'NodeJS'; Pattern = '*NODEJS*' },
            @{ Name = 'Python'; Pattern = '*PYTHON*' }
        )
    }

    try {
        Write-RuleLog -Message "Approving rules from $($trustedPatterns.Count) trusted vendors..."

        foreach ($vendor in $trustedPatterns) {
            $vendorResult = Set-BulkRuleStatus `
                -Status 'Approved' `
                -PublisherPattern $vendor.Pattern `
                -CurrentStatus 'Pending' `
                -WhatIf:$WhatIfPreference

            $result.ByVendor[$vendor.Name] = $vendorResult.UpdatedCount
            $result.TotalUpdated += $vendorResult.UpdatedCount

            if ($vendorResult.UpdatedCount -gt 0) {
                Write-Host "  $($vendor.Name): $($vendorResult.UpdatedCount) rules" -ForegroundColor Green
            }
        }

        $result.Success = $true
        
        if ($WhatIfPreference) {
            Write-Host "`nWhatIf: Would approve $($result.TotalUpdated) total rules from trusted vendors" -ForegroundColor Cyan
        }
        else {
            Write-RuleLog -Message "Approved $($result.TotalUpdated) rules from trusted vendors"
        }
    }
    catch {
        $result.Error = "Failed to approve trusted vendor rules: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}
