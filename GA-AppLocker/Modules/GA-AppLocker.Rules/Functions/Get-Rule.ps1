<#
.SYNOPSIS
    Retrieves rules from storage.

.DESCRIPTION
    Gets one or more AppLocker rules from local storage.
    Can filter by ID, name, type, collection, or status.

.PARAMETER Id
    Specific rule GUID to retrieve.

.PARAMETER Name
    Filter by rule name (supports wildcards).

.PARAMETER RuleType
    Filter by rule type: Publisher, Hash, Path.

.PARAMETER CollectionType
    Filter by collection: Exe, Dll, Msi, Script, Appx.

.PARAMETER Status
    Filter by status: Pending, Approved, Rejected, Review.

.EXAMPLE
    Get-Rule -Id '12345678-...'

.EXAMPLE
    Get-Rule -RuleType Publisher -Status Approved

.EXAMPLE
    Get-Rule -Name '*Microsoft*'

.OUTPUTS
    [PSCustomObject] Result with Success and Data (rule or array of rules).
#>
function Get-Rule {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$Name,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Publisher', 'Hash', 'Path')]
        [string]$RuleType,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Exe', 'Dll', 'Msi', 'Script', 'Appx')]
        [string]$CollectionType,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # Try using Storage layer (fast indexed queries)
        $useStorage = Get-Command -Name 'Get-RulesFromDatabase' -ErrorAction SilentlyContinue
        
        if ($useStorage) {
            if ($Id) {
                # Get specific rule by ID from Storage
                $rule = Get-RuleFromDatabase -Id $Id
                if ($rule) {
                    $result.Data = $rule
                    $result.Success = $true
                } else {
                    # Fallback to JSON file
                    $rulePath = Get-RuleStoragePath
                    $ruleFile = Join-Path $rulePath "$Id.json"
                    if (Test-Path $ruleFile) {
                        $result.Data = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json
                        $result.Success = $true
                    } else {
                        $result.Error = "Rule not found: $Id"
                    }
                }
            }
            else {
                # Query from Storage with filters
                $queryResult = Get-RulesFromDatabase -Status $Status -RuleType $RuleType -CollectionType $CollectionType -SearchText $Name -FullPayload
                
                if ($queryResult.Success) {
                    $result.Data = $queryResult.Data
                    $result.Success = $true
                } else {
                    $result.Error = $queryResult.Error
                }
            }
        }
        else {
            # Fallback: Load from JSON files (slow path)
            $rulePath = Get-RuleStoragePath
            $ruleFiles = Get-ChildItem -Path $rulePath -Filter '*.json' -ErrorAction SilentlyContinue

            if ($Id) {
                $ruleFile = Join-Path $rulePath "$Id.json"
                if (Test-Path $ruleFile) {
                    $result.Data = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json
                    $result.Success = $true
                } else {
                    $result.Error = "Rule not found: $Id"
                }
            }
            else {
                # Load all rules using List for performance
                $rules = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($file in $ruleFiles) {
                    try {
                        $rule = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                        $rules.Add($rule)
                    }
                    catch {
                        Write-RuleLog -Level Warning -Message "Failed to load rule file: $($file.Name)"
                    }
                }

                # Apply filters
                $filtered = $rules.ToArray()
                if ($Name) {
                    $filtered = @($filtered | Where-Object { $_.Name -like $Name })
                }
                if ($RuleType) {
                    $filtered = @($filtered | Where-Object { $_.RuleType -eq $RuleType })
                }
                if ($CollectionType) {
                    $filtered = @($filtered | Where-Object { $_.CollectionType -eq $CollectionType })
                }
                if ($Status) {
                    $filtered = @($filtered | Where-Object { $_.Status -eq $Status })
                }

                $result.Data = $filtered
                $result.Success = $true
            }
        }
    }
    catch {
        $result.Error = "Failed to retrieve rules: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}

<#
.SYNOPSIS
    Retrieves all rules from storage.

.DESCRIPTION
    Gets all AppLocker rules from local storage with optional grouping.

.PARAMETER GroupBy
    Group results by: RuleType, CollectionType, Status, Publisher.

.EXAMPLE
    Get-AllRules

.EXAMPLE
    Get-AllRules -GroupBy CollectionType

.OUTPUTS
    [PSCustomObject] Result with Success and Data.
#>
function Get-AllRules {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('RuleType', 'CollectionType', 'Status', 'Publisher')]
        [string]$GroupBy,
        
        [Parameter()]
        [int]$Take = 0,
        
        [Parameter()]
        [int]$Skip = 0
    )

    # Try using Storage layer for fast queries
    $useStorage = Get-Command -Name 'Get-RulesFromDatabase' -ErrorAction SilentlyContinue
    
    if ($useStorage) {
        # Use indexed storage for fast retrieval
        $takeParam = if ($Take -gt 0) { $Take } else { 100000 }  # Large default to get all
        $queryResult = Get-RulesFromDatabase -Take $takeParam -Skip $Skip -FullPayload
        
        $result = [PSCustomObject]@{
            Success = $queryResult.Success
            Data    = $queryResult.Data
            Total   = $queryResult.Total
            Error   = $queryResult.Error
        }
    }
    else {
        # Fallback to Get-Rule (slow path)
        $result = Get-Rule
    }

    if ($result.Success -and $GroupBy -and $result.Data) {
        $grouped = switch ($GroupBy) {
            'RuleType' { $result.Data | Group-Object RuleType }
            'CollectionType' { $result.Data | Group-Object CollectionType }
            'Status' { $result.Data | Group-Object Status }
            'Publisher' { $result.Data | Where-Object { $_.RuleType -eq 'Publisher' } | Group-Object PublisherName }
        }
        $result.Data = $grouped
    }

    return $result
}

<#
.SYNOPSIS
    Removes a rule from storage.

.DESCRIPTION
    Deletes an AppLocker rule from local storage.

.PARAMETER Id
    Rule GUID to delete.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    Remove-Rule -Id '12345678-...'

.OUTPUTS
    [PSCustomObject] Result with Success.
#>
function Remove-Rule {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [switch]$Force
    )

    $result = [PSCustomObject]@{
        Success = $false
        Error   = $null
    }

    try {
        # Get rule name for logging before deletion
        $rule = Get-RuleById -Id $Id
        $ruleName = if ($rule) { $rule.Name } else { $Id }
        
        # Use storage layer to remove
        $deleteResult = Remove-Rule -RuleIds @($Id)
        
        if ($deleteResult.Success -and $deleteResult.RemovedCount -gt 0) {
            $result.Success = $true
            Write-RuleLog -Message "Deleted rule: $ruleName ($Id)"
            
            # Invalidate caches
            if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
                Clear-AppLockerCache -Pattern "GlobalSearch_*" | Out-Null
                Clear-AppLockerCache -Pattern 'RuleCounts*' | Out-Null
                Clear-AppLockerCache -Pattern 'RuleQuery*' | Out-Null
            }
        }
        elseif ($deleteResult.Success -and $deleteResult.RemovedCount -eq 0) {
            $result.Error = "Rule not found: $Id"
        }
        else {
            $result.Error = $deleteResult.Error
            
            if (Get-Command -Name 'Remove-RulesFromIndex' -ErrorAction SilentlyContinue) {
                Remove-RulesFromIndex -RuleIds @($Id) | Out-Null
            }
            
            $result.Success = $true
            Write-RuleLog -Message "Deleted rule: $ruleName ($Id)"
            
            if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
                Clear-AppLockerCache -Pattern "GlobalSearch_*" | Out-Null
            }
        }
    }
    catch {
        $result.Error = "Failed to delete rule: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}

# NOTE: Remove-RulesBulk is now defined in GA-AppLocker.Storage/Functions/BulkOperations.ps1
# Use that version for proper index synchronization.

<#
.SYNOPSIS
    Updates a rule's status.

.DESCRIPTION
    Changes the approval status of a rule (traffic light workflow).

.PARAMETER Id
    Rule GUID to update.

.PARAMETER Status
    New status: Pending, Approved, Rejected, Review.

.EXAMPLE
    Set-RuleStatus -Id '12345678-...' -Status Approved

.OUTPUTS
    [PSCustomObject] Result with Success and updated rule.
#>
function Set-RuleStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $rulePath = Get-RuleStoragePath
        $ruleFile = Join-Path $rulePath "$Id.json"

        if (-not (Test-Path $ruleFile)) {
            $result.Error = "Rule not found: $Id"
            return $result
        }

        $rule = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json
        $oldStatus = $rule.Status
        $rule.Status = $Status
        $rule.ModifiedDate = Get-Date

        $rule | ConvertTo-Json -Depth 10 | Set-Content -Path $ruleFile -Encoding UTF8

        # Update the index with new status
        if (Get-Command -Name 'Update-RuleStatusInIndex' -ErrorAction SilentlyContinue) {
            Update-RuleStatusInIndex -RuleIds @($Id) -Status $Status | Out-Null
        }

        # Save version history
        if (Get-Command -Name 'Save-RuleVersion' -ErrorAction SilentlyContinue) {
            Save-RuleVersion -Rule $rule -ChangeType 'StatusChanged' -ChangeSummary "Status changed from $oldStatus to $Status"
        }
        
        # Write audit log
        if (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue) {
            Write-AuditLog -Action "Rule$Status" -Category 'Rule' -Target $rule.Name -TargetId $Id `
                -Details "Status changed from $oldStatus to $Status" -OldValue $oldStatus -NewValue $Status
        }

        $result.Success = $true
        $result.Data = $rule
        Write-RuleLog -Message "Rule status changed: $($rule.Name) [$oldStatus -> $Status]"
    }
    catch {
        $result.Error = "Failed to update rule status: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}
