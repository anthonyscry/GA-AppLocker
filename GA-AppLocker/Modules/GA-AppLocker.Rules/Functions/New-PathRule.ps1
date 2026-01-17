<#
.SYNOPSIS
    Creates a new AppLocker Path rule.

.DESCRIPTION
    Creates a path-based AppLocker rule using file or folder paths.
    Path rules are the least secure but most convenient for allowing
    entire directories like Program Files.

.PARAMETER Path
    The file or folder path. Supports wildcards and variables:
    - * matches any characters
    - %OSDRIVE% = C:
    - %WINDIR% = C:\Windows
    - %SYSTEM32% = C:\Windows\System32
    - %PROGRAMFILES% = C:\Program Files
    - %REMOVABLE% = Removable drives
    - %HOT% = Hot-plugged drives

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
    New-PathRule -Path '%PROGRAMFILES%\*' -Action Allow

.EXAMPLE
    New-PathRule -Path 'C:\CustomApp\*.exe' -Action Allow -CollectionType Exe

.OUTPUTS
    [PSCustomObject] The created rule object.
#>
function New-PathRule {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

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
            # Create a friendly name from the path
            $shortPath = $Path
            if ($Path.Length -gt 50) {
                $shortPath = "..." + $Path.Substring($Path.Length - 47)
            }
            $Name = "Path: $shortPath"
        }

        # Generate description if not provided
        if ([string]::IsNullOrWhiteSpace($Description)) {
            $Description = "Path rule allowing execution from: $Path"
        }

        $rule = [PSCustomObject]@{
            Id               = New-RuleId
            RuleType         = 'Path'
            Name             = $Name
            Description      = $Description
            Action           = $Action
            CollectionType   = $CollectionType
            UserOrGroupSid   = $UserOrGroupSid
            Status           = $Status
            CreatedDate      = Get-Date
            ModifiedDate     = Get-Date
            # Path-specific
            Path             = $Path
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
        Write-RuleLog -Message "Created path rule: $Name"
    }
    catch {
        $result.Error = "Failed to create path rule: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}
