function Get-Policy {
    <#
    .SYNOPSIS
        Retrieves a policy by ID or name.


.DESCRIPTION
    Retrieves a policy by ID or name. Returns the requested data wrapped in a standard result object with Success, Data, and Error properties.

    .PARAMETER PolicyId
        The unique identifier of the policy.

    .PARAMETER Name
        The name of the policy to find.

    .EXAMPLE
        Get-Policy -PolicyId "abc123"
        Get-Policy -Name "Baseline Policy"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$PolicyId,

        [Parameter(Mandatory = $false)]
        [string]$Name
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'

        if (-not (Test-Path $policiesPath)) {
            return @{
                Success = $true
                Data    = $null
                Message = 'No policies found'
            }
        }

        if ($PolicyId) {
            $policyFile = Join-Path $policiesPath "$PolicyId.json"
            if (Test-Path $policyFile) {
                $policy = Get-Content -Path $policyFile -Raw | ConvertFrom-Json
                return @{
                    Success = $true
                    Data    = $policy
                }
            }
            return @{
                Success = $false
                Error   = "Policy not found: $PolicyId"
            }
        }

        if ($Name) {
            $policyFiles = Get-ChildItem -Path $policiesPath -Filter '*.json' -File
            foreach ($file in $policyFiles) {
                $policy = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($policy.Name -eq $Name) {
                    return @{
                        Success = $true
                        Data    = $policy
                    }
                }
            }
            return @{
                Success = $false
                Error   = "Policy not found: $Name"
            }
        }

        return @{
            Success = $false
            Error   = 'Please specify PolicyId or Name'
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Get-PolicyCount {
    <#
    .SYNOPSIS
        Gets total policy count without reading/parsing JSON files.

    .DESCRIPTION
        Fast O(1) policy count by counting .json files in the Policies directory.
        Use this instead of Get-AllPolicies when you only need a count (e.g., breadcrumb, dashboard).

    .EXAMPLE
        Get-PolicyCount
        # Returns: 42
    #>
    [CmdletBinding()]
    param()

    try {
        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'

        if (-not (Test-Path $policiesPath)) { return 0 }

        $files = @(Get-ChildItem -Path $policiesPath -Filter '*.json' -File)
        return $files.Count
    }
    catch {
        Write-AppLockerLog -Message "Get-PolicyCount error: $($_.Exception.Message)" -Level 'DEBUG'
        return 0
    }
}

function Get-AllPolicies {
    <#
    .SYNOPSIS
        Retrieves all policies.


.DESCRIPTION
    Retrieves all policies.

    .PARAMETER Status
        Optional filter by status (Draft, Active, Deployed, Archived).

    .EXAMPLE
        Get-AllPolicies
        Get-AllPolicies -Status "Active"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Draft', 'Active', 'Deployed', 'Archived', '')]
        [string]$Status = ''
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'

        if (-not (Test-Path $policiesPath)) {
            return @{
                Success = $true
                Data    = @()
            }
        }

        $policyFiles = Get-ChildItem -Path $policiesPath -Filter '*.json' -File
        $policies = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($file in $policyFiles) {
            try {
                $policy = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                
                if ([string]::IsNullOrEmpty($Status) -or $policy.Status -eq $Status) {
                    [void]$policies.Add($policy)
                }
            }
            catch {
                Write-AppLockerLog -Message "Failed to read policy file $($file.Name): $($_.Exception.Message)" -Level 'DEBUG'
            }
        }

        # Sort by modified date descending (with fallback if ModifiedAt is invalid)
        try {
            $sorted = $policies | Sort-Object -Property { 
                if ($_.ModifiedAt) { [datetime]$_.ModifiedAt } else { [datetime]::MinValue }
            } -Descending
            $policies = @($sorted)
        }
        catch {
            # If sorting fails, return unsorted
            $policies = @($policies)
        }

        return @{
            Success = $true
            Data    = $policies
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
