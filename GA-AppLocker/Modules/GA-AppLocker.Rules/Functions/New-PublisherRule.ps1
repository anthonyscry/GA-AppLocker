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
        [switch]$Save
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
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
            CreatedDate      = Get-Date
            ModifiedDate     = Get-Date
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
