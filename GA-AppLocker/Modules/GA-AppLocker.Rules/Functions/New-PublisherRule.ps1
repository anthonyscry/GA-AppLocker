<#
.SYNOPSIS
    Creates a new AppLocker Publisher rule.

.DESCRIPTION
    Creates a publisher-based AppLocker rule using digital signature information.
    Publisher rules are the most flexible as they allow updates to pass through
    as long as they're signed by the same publisher.

.PARAMETER PublisherName
    The publisher/signer certificate subject or O= field.

.PARAMETER ProductName
    The product name. Use '*' for any product.

.PARAMETER BinaryName
    The binary file name. Use '*' for any binary.

.PARAMETER MinVersion
    Minimum version (inclusive). Default is '*' (any).

.PARAMETER MaxVersion
    Maximum version (inclusive). Default is '*' (any).

.PARAMETER Action
    Rule action: Allow or Deny. Default is Allow.

.PARAMETER CollectionType
    AppLocker collection: Exe, Dll, Msi, Script, Appx.

.PARAMETER Name
    Display name for the rule.

.PARAMETER Description
    Description of the rule.

.PARAMETER UserOrGroupSid
    SID of user or group this rule applies to. Default is Everyone (S-1-1-0).

.PARAMETER Status
    Rule status for traffic light workflow: Pending, Approved, Rejected, Review.

.PARAMETER SourceArtifactId
    ID of the artifact this rule was generated from (for tracking).

.EXAMPLE
    New-PublisherRule -PublisherName 'O=MICROSOFT CORPORATION' -ProductName '*' -Action Allow

.EXAMPLE
    New-PublisherRule -PublisherName 'O=ADOBE INC.' -ProductName 'ADOBE READER' -MinVersion '11.0.0.0'

.OUTPUTS
    [PSCustomObject] The created rule object.
#>
function New-PublisherRule {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PublisherName,

        [Parameter()]
        [string]$ProductName = '*',

        [Parameter()]
        [string]$BinaryName = '*',

        [Parameter()]
        [string]$MinVersion = '*',

        [Parameter()]
        [string]$MaxVersion = '*',

        [Parameter()]
        [ValidateSet('Allow', 'Deny')]
        [string]$Action = 'Allow',

        [Parameter()]
        [ValidateSet('Exe', 'Dll', 'Msi', 'Script', 'Appx')]
        [string]$CollectionType = 'Exe',

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$UserOrGroupSid = 'S-1-1-0',

        [Parameter()]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status = 'Pending',

        [Parameter()]
        [string]$SourceArtifactId,

        [Parameter()]
        [string]$GroupName,

        [Parameter()]
        [PSCustomObject]$GroupSuggestion,

        [Parameter()]
        [switch]$Save
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # Clean PublisherName: truncate after country code (C=XX)
        # Raw cert subjects have OID/serial junk after the country code
        # e.g., "CN=Microsoft Corp, O=Microsoft Corp, L=Redmond, S=Washington, C=US, SERIALNUMBER=232927, OID.2.5.4.15=..."
        # becomes "CN=Microsoft Corp, O=Microsoft Corp, L=Redmond, S=Washington, C=US"
        if ($PublisherName -match '(.*,\s*C=[A-Z]{2})') {
            $PublisherName = $Matches[1]
        }

        # Check for existing rule with same publisher/product (prevent duplicates)
        if ($Save) {
            $existingRule = Find-ExistingPublisherRule -PublisherName $PublisherName -ProductName $ProductName -CollectionType $CollectionType
            if ($existingRule) {
                Write-RuleLog -Level Warning -Message "Publisher rule already exists: $($existingRule.Name) (ID: $($existingRule.Id))"
                $result.Success = $true
                $result.Data = $existingRule
                $result | Add-Member -NotePropertyName 'Warning' -NotePropertyValue 'Existing rule returned instead of creating duplicate' -Force
                return $result
            }
        }

        # Generate rule name if not provided
        if ([string]::IsNullOrWhiteSpace($Name)) {
            $pubDisplay = Format-PublisherString -CertSubject $PublisherName
            $Name = if ($ProductName -eq '*') {
                "$pubDisplay - All Products"
            } else {
                "$pubDisplay - $ProductName"
            }
        }

        # Generate description if not provided
        if ([string]::IsNullOrWhiteSpace($Description)) {
            $Description = "Publisher rule for $PublisherName"
            if ($ProductName -ne '*') { $Description += ", Product: $ProductName" }
            if ($BinaryName -ne '*') { $Description += ", Binary: $BinaryName" }
        }

        $rule = [PSCustomObject]@{
            Id               = New-RuleId
            RuleType         = 'Publisher'
            Name             = $Name
            Description      = $Description
            Action           = $Action
            CollectionType   = $CollectionType
            UserOrGroupSid   = $UserOrGroupSid
            Status           = $Status
            CreatedDate      = Get-Date -Format 'o'
            ModifiedDate     = Get-Date -Format 'o'
            # Publisher-specific
            PublisherName    = $PublisherName
            ProductName      = $ProductName
            BinaryName       = $BinaryName
            MinVersion       = $MinVersion
            MaxVersion       = $MaxVersion
            # Tracking
            SourceArtifactId = $SourceArtifactId
            GeneratedBy      = $env:USERNAME
            MachineName      = $env:COMPUTERNAME
            # Smart Group Assignment
            GroupName        = if ($GroupName) { $GroupName } elseif ($GroupSuggestion) { $GroupSuggestion.SuggestedGroup } else { $null }
            GroupVendor      = if ($GroupSuggestion) { $GroupSuggestion.Vendor } else { $null }
            GroupCategory    = if ($GroupSuggestion) { $GroupSuggestion.Category } else { $null }
            GroupRiskLevel   = if ($GroupSuggestion) { $GroupSuggestion.RiskLevel } else { $null }
        }

        if ($Save) {
            Save-Rule -Rule $rule
        }

        $result.Success = $true
        $result.Data = $rule
        Write-RuleLog -Message "Created publisher rule: $Name"
    }
    catch {
        $result.Error = "Failed to create publisher rule: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}
