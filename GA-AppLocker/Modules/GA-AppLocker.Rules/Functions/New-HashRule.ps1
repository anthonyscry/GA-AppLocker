<#
.SYNOPSIS
    Creates a new AppLocker Hash rule.

.DESCRIPTION
    Creates a hash-based AppLocker rule using SHA256 file hash.
    Hash rules are the most secure as they identify a specific file,
    but require updates whenever the file changes.

.PARAMETER Hash
    The SHA256 hash of the file.

.PARAMETER SourceFileName
    Original file name.

.PARAMETER SourceFileLength
    File size in bytes.

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
    New-HashRule -Hash 'ABC123...' -SourceFileName 'app.exe' -SourceFileLength 1234567

.OUTPUTS
    [PSCustomObject] The created rule object.
#>
function New-HashRule {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Hash,

        [Parameter(Mandatory)]
        [string]$SourceFileName,

        [Parameter()]
        [int64]$SourceFileLength = 0,

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
        # Validate hash format (should be 64 hex characters for SHA256)
        $cleanHash = $Hash -replace '^0x', ''
        if ($cleanHash.Length -ne 64 -or $cleanHash -notmatch '^[A-Fa-f0-9]+$') {
            throw "Invalid SHA256 hash format. Expected 64 hex characters."
        }

        # Generate rule name if not provided
        if ([string]::IsNullOrWhiteSpace($Name)) {
            $Name = "$SourceFileName (Hash)"
        }

        # Generate description if not provided
        if ([string]::IsNullOrWhiteSpace($Description)) {
            $Description = "Hash rule for $SourceFileName (SHA256: $($cleanHash.Substring(0,8))...)"
        }

        $rule = [PSCustomObject]@{
            Id               = New-RuleId
            RuleType         = 'Hash'
            Name             = $Name
            Description      = $Description
            Action           = $Action
            CollectionType   = $CollectionType
            UserOrGroupSid   = $UserOrGroupSid
            Status           = $Status
            CreatedDate      = Get-Date
            ModifiedDate     = Get-Date
            # Hash-specific
            Hash             = $cleanHash.ToUpper()
            SourceFileName   = $SourceFileName
            SourceFileLength = $SourceFileLength
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
        Write-RuleLog -Message "Created hash rule: $Name"
    }
    catch {
        $result.Error = "Failed to create hash rule: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}
