<#
.SYNOPSIS
    Pure business logic functions for Rules panel.
.DESCRIPTION
    Contains data validation, transformation, and filtering logic
    extracted from the Rules panel UI code. These functions have
    NO dependencies on $Window or WPF types.
#>

function Get-RuleGenerationOptions {
    <#
    .SYNOPSIS
        Parses rule generation options from UI values.
    .DESCRIPTION
        Converts UI combo box/radio button indices to option strings.
    #>
    param(
        [int]$ModeIndex = 0,
        [bool]$IsAllow = $true,
        [string]$TargetGroupSid = 'S-1-1-0',
        [string]$PublisherLevel = 'PublisherProduct',
        [string]$CollectionName = 'Default'
    )
    
    $mode = switch ($ModeIndex) {
        0 { 'Smart' }
        1 { 'Publisher' }
        2 { 'Hash' }
        3 { 'Path' }
        default { 'Smart' }
    }
    
    return @{
        Mode = $mode
        Action = if ($IsAllow) { 'Allow' } else { 'Deny' }
        TargetGroupSid = $TargetGroupSid
        PublisherLevel = $PublisherLevel
        CollectionName = $CollectionName
    }
}

function Test-ArtifactsAvailable {
    <#
    .SYNOPSIS
        Validates that artifacts are available for processing.
    #>
    param([array]$Artifacts)
    
    return ($null -ne $Artifacts -and $Artifacts.Count -gt 0)
}

function Get-FilteredRules {
    <#
    .SYNOPSIS
        Filters rules by type and status.
    .DESCRIPTION
        Pure filtering logic without UI dependencies.
    #>
    param(
        [array]$Rules,
        [string]$TypeFilter = 'All',
        [string]$StatusFilter = 'All'
    )
    
    if (-not $Rules -or $Rules.Count -eq 0) { return @() }
    
    $filtered = $Rules
    
    # Apply type filter
    if ($TypeFilter -ne 'All') {
        $filtered = $filtered.Where({ $_.RuleType -eq $TypeFilter })
    }
    
    # Apply status filter
    if ($StatusFilter -ne 'All') {
        $filtered = $filtered.Where({ $_.Status -eq $StatusFilter })
    }
    
    return @($filtered)
}

function Get-RuleCountsByStatus {
    <#
    .SYNOPSIS
        Counts rules by status category.
    #>
    param([array]$Rules)
    
    if (-not $Rules -or $Rules.Count -eq 0) {
        return @{
            Total = 0
            Approved = 0
            Pending = 0
            Rejected = 0
            Review = 0
        }
    }
    
    return @{
        Total = $Rules.Count
        Approved = @($Rules.Where({ $_.Status -eq 'Approved' })).Count
        Pending = @($Rules.Where({ $_.Status -eq 'Pending' })).Count
        Rejected = @($Rules.Where({ $_.Status -eq 'Rejected' })).Count
        Review = @($Rules.Where({ $_.Status -eq 'Review' })).Count
    }
}

function Get-RuleCountsByType {
    <#
    .SYNOPSIS
        Counts rules by type category.
    #>
    param([array]$Rules)
    
    if (-not $Rules -or $Rules.Count -eq 0) {
        return @{
            Publisher = 0
            Hash = 0
            Path = 0
        }
    }
    
    return @{
        Publisher = @($Rules.Where({ $_.RuleType -eq 'Publisher' })).Count
        Hash = @($Rules.Where({ $_.RuleType -eq 'Hash' })).Count
        Path = @($Rules.Where({ $_.RuleType -eq 'Path' })).Count
    }
}

function Format-RuleForExport {
    <#
    .SYNOPSIS
        Formats a rule object for CSV/export.
    #>
    param([PSCustomObject]$Rule)
    
    return [PSCustomObject]@{
        Id = $Rule.Id
        Name = $Rule.Name
        RuleType = $Rule.RuleType
        Status = $Rule.Status
        Action = $Rule.Action
        Publisher = $Rule.Publisher
        ProductName = $Rule.ProductName
        FileName = $Rule.FileName
        FileVersion = $Rule.FileVersion
        Hash = $Rule.SHA256Hash
        Path = $Rule.Path
        Description = $Rule.Description
        CreatedAt = $Rule.CreatedAt
        ModifiedAt = $Rule.ModifiedAt
    }
}

function Get-RuleDisplayText {
    <#
    .SYNOPSIS
        Gets display text for a rule based on its type.
    #>
    param([PSCustomObject]$Rule)
    
    switch ($Rule.RuleType) {
        'Publisher' {
            $parts = @()
            if ($Rule.Publisher) { $parts += $Rule.Publisher }
            if ($Rule.ProductName) { $parts += $Rule.ProductName }
            if ($Rule.FileName) { $parts += $Rule.FileName }
            return $parts -join ' > '
        }
        'Hash' {
            if ($Rule.FileName) { return $Rule.FileName }
            if ($Rule.SHA256Hash) { return $Rule.SHA256Hash.Substring(0, 16) + '...' }
            return 'Hash Rule'
        }
        'Path' {
            return $Rule.Path
        }
        default {
            return $Rule.Name
        }
    }
}

function Test-RuleSelectionValid {
    <#
    .SYNOPSIS
        Validates a rule selection for bulk operations.
    #>
    param(
        [array]$SelectedRules,
        [int]$MinCount = 1
    )
    
    return ($null -ne $SelectedRules -and $SelectedRules.Count -ge $MinCount)
}

function Group-RulesByPublisher {
    <#
    .SYNOPSIS
        Groups rules by publisher for tree view display.
    #>
    param([array]$Rules)
    
    if (-not $Rules -or $Rules.Count -eq 0) { return @{} }
    
    $grouped = @{}
    
    foreach ($rule in $Rules) {
        $publisher = if ($rule.Publisher) { $rule.Publisher } else { '(Unknown Publisher)' }
        
        if (-not $grouped.ContainsKey($publisher)) {
            $grouped[$publisher] = @{
                Publisher = $publisher
                Rules = [System.Collections.Generic.List[PSCustomObject]]::new()
                Products = @{}
            }
        }
        
        $grouped[$publisher].Rules.Add($rule)
        
        # Group by product within publisher
        $product = if ($rule.ProductName) { $rule.ProductName } else { '(Unknown Product)' }
        if (-not $grouped[$publisher].Products.ContainsKey($product)) {
            $grouped[$publisher].Products[$product] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $grouped[$publisher].Products[$product].Add($rule)
    }
    
    return $grouped
}
