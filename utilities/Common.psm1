<#
.SYNOPSIS
    Common utility functions for GA-AppLocker scripts.

.DESCRIPTION
    This module provides shared functions used across all AppLocker scripts:
    - SID resolution
    - XML generation helpers
    - File and path utilities
    - Logging functions

.NOTES
    Import this module in scripts using:
    Import-Module "$PSScriptRoot\utilities\Common.psm1" -Force
#>

#region SID Resolution Functions

<#
.SYNOPSIS
    Resolves a user/group name to its Security Identifier (SID).

.PARAMETER Name
    The name to resolve (e.g., "Everyone", "BUILTIN\Administrators", "DOMAIN\Group")

.OUTPUTS
    String containing the SID value
#>
function Resolve-AccountToSid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    # If already a SID, return as-is
    if ($Name -match "^S-1-") {
        return $Name
    }

    # Check well-known SIDs first (faster than translation)
    $config = Get-AppLockerConfig
    if ($config.WellKnownSids.ContainsKey($Name)) {
        return $config.WellKnownSids[$Name]
    }

    # Try to translate via .NET
    try {
        $account = New-Object System.Security.Principal.NTAccount($Name)
        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
        return $sid.Value
    }
    catch {
        Write-Warning "Could not resolve '$Name' to SID - using placeholder. Verify group exists in AD."
        return "S-1-5-21-YOURDOMAINSID-YOURGROUP"
    }
}

<#
.SYNOPSIS
    Resolves multiple account names to SIDs.

.PARAMETER Names
    Array of names to resolve

.OUTPUTS
    Hashtable with Name as key and SID as value
#>
function Resolve-AccountsToSids {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    $result = @{}
    foreach ($name in $Names) {
        $result[$name] = Resolve-AccountToSid -Name $name
    }
    return $result
}

<#
.SYNOPSIS
    Gets standard principal SIDs used in AppLocker policies.

.PARAMETER DomainName
    Optional domain name for custom group resolution

.OUTPUTS
    Hashtable of principal names to SIDs
#>
function Get-StandardPrincipalSids {
    [CmdletBinding()]
    param(
        [string]$DomainName,
        [string]$AdminsGroup,
        [string]$StandardUsersGroup,
        [string]$ServiceAccountsGroup,
        [string]$InstallersGroup
    )

    # Set defaults if not provided
    if ($DomainName) {
        if (-not $AdminsGroup) { $AdminsGroup = "$DomainName\AppLocker-Admins" }
        if (-not $StandardUsersGroup) { $StandardUsersGroup = "$DomainName\AppLocker-StandardUsers" }
        if (-not $ServiceAccountsGroup) { $ServiceAccountsGroup = "$DomainName\AppLocker-Service-Accounts" }
        if (-not $InstallersGroup) { $InstallersGroup = "$DomainName\AppLocker-Installers" }
    }

    $sids = @{
        # Mandatory Allow Principals
        SYSTEM         = Resolve-AccountToSid "NT AUTHORITY\SYSTEM"
        LocalService   = Resolve-AccountToSid "NT AUTHORITY\LOCAL SERVICE"
        NetworkService = Resolve-AccountToSid "NT AUTHORITY\NETWORK SERVICE"
        BuiltinAdmins  = Resolve-AccountToSid "BUILTIN\Administrators"
        Everyone       = Resolve-AccountToSid "Everyone"
    }

    # Add custom groups if domain specified
    if ($DomainName) {
        $sids.Admins = Resolve-AccountToSid $AdminsGroup
        $sids.StandardUsers = Resolve-AccountToSid $StandardUsersGroup
        $sids.ServiceAccounts = Resolve-AccountToSid $ServiceAccountsGroup
        $sids.Installers = Resolve-AccountToSid $InstallersGroup
    }

    return $sids
}

#endregion

#region XML Generation Helpers

<#
.SYNOPSIS
    Creates an AppLocker rule XML element.

.PARAMETER Type
    Rule type: FilePathRule, FilePublisherRule, FileHashRule

.PARAMETER Name
    Display name for the rule

.PARAMETER Description
    Rule description

.PARAMETER Sid
    Security identifier for the user/group

.PARAMETER Action
    Allow or Deny

.PARAMETER Condition
    Inner XML for the rule condition
#>
function New-AppLockerRuleXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("FilePathRule", "FilePublisherRule", "FileHashRule")]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Description = "",

        [Parameter(Mandatory = $true)]
        [string]$Sid,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Allow", "Deny")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Condition
    )

    $id = [guid]::NewGuid().ToString()
    $escapedName = [System.Security.SecurityElement]::Escape($Name)
    $escapedDesc = [System.Security.SecurityElement]::Escape($Description)

    return @"
    <$Type Id="$id" Name="$escapedName" Description="$escapedDesc" UserOrGroupSid="$Sid" Action="$Action">
      <Conditions>
        $Condition
      </Conditions>
    </$Type>
"@
}

<#
.SYNOPSIS
    Creates a FilePathCondition XML element.
#>
function New-PathConditionXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return "<FilePathCondition Path=`"$Path`"/>"
}

<#
.SYNOPSIS
    Creates a FilePublisherCondition XML element.
#>
function New-PublisherConditionXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Publisher,

        [string]$Product = "*",
        [string]$Binary = "*",
        [string]$LowVersion = "*",
        [string]$HighVersion = "*"
    )

    $escapedPublisher = [System.Security.SecurityElement]::Escape($Publisher)

    return @"
<FilePublisherCondition PublisherName="$escapedPublisher" ProductName="$Product" BinaryName="$Binary">
          <BinaryVersionRange LowSection="$LowVersion" HighSection="$HighVersion"/>
        </FilePublisherCondition>
"@
}

<#
.SYNOPSIS
    Creates a FileHashCondition XML element.
#>
function New-HashConditionXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hash,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [long]$FileSize,

        [string]$HashType = "SHA256"
    )

    return @"
<FileHashCondition>
          <FileHash Type="$HashType" Data="0x$Hash" SourceFileName="$FileName" SourceFileLength="$FileSize"/>
        </FileHashCondition>
"@
}

<#
.SYNOPSIS
    Creates the XML header for an AppLocker policy.
#>
function New-PolicyHeaderXml {
    [CmdletBinding()]
    param(
        [string]$Comment = "",
        [string]$TargetType = "",
        [string]$Phase = "",
        [string]$Mode = "Generated"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    return @"
<?xml version="1.0" encoding="utf-8"?>
<!--
  AppLocker Policy - $Mode
  Generated: $timestamp
  Target: $TargetType
  Phase: $Phase
  $Comment
-->
<AppLockerPolicy Version="1">
"@
}

<#
.SYNOPSIS
    Creates a RuleCollection XML element.
#>
function New-RuleCollectionXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Exe", "Msi", "Script", "Dll", "Appx")]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [ValidateSet("AuditOnly", "Enabled", "NotConfigured")]
        [string]$EnforcementMode,

        [string]$Rules = ""
    )

    return @"
  <RuleCollection Type="$Type" EnforcementMode="$EnforcementMode">
$Rules  </RuleCollection>
"@
}

#endregion

#region Configuration Functions

<#
.SYNOPSIS
    Loads the AppLocker configuration from Config.psd1
#>
function Get-AppLockerConfig {
    [CmdletBinding()]
    param()

    $configPath = Join-Path $PSScriptRoot "Config.psd1"

    if (Test-Path $configPath) {
        return Import-PowerShellDataFile -Path $configPath
    }
    else {
        Write-Warning "Config file not found at $configPath - using defaults"
        return Get-DefaultConfig
    }
}

<#
.SYNOPSIS
    Returns default configuration if Config.psd1 is missing.
#>
function Get-DefaultConfig {
    return @{
        WellKnownSids = @{
            "NT AUTHORITY\SYSTEM"              = "S-1-5-18"
            "NT AUTHORITY\LOCAL SERVICE"       = "S-1-5-19"
            "NT AUTHORITY\NETWORK SERVICE"     = "S-1-5-20"
            "BUILTIN\Administrators"           = "S-1-5-32-544"
            "BUILTIN\Users"                    = "S-1-5-32-545"
            "Everyone"                         = "S-1-1-0"
            "NT AUTHORITY\Authenticated Users" = "S-1-5-11"
        }
        LOLBins = @(
            @{ Name = "mshta.exe"; Description = "HTML Application Host" }
            @{ Name = "cscript.exe"; Description = "Console Script Host" }
            @{ Name = "wscript.exe"; Description = "Windows Script Host" }
        )
        DefaultDenyPaths = @(
            @{ Path = "%USERPROFILE%\Downloads\*"; Description = "User Downloads folder" }
            @{ Path = "%APPDATA%\*"; Description = "Roaming AppData" }
            @{ Path = "%TEMP%\*"; Description = "System Temp folder" }
        )
    }
}

#endregion

#region Logging Functions

<#
.SYNOPSIS
    Writes a formatted status message.
#>
function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("Info", "Success", "Warning", "Error", "Header")]
        [string]$Type = "Info"
    )

    $colors = @{
        Info    = "Cyan"
        Success = "Green"
        Warning = "Yellow"
        Error   = "Red"
        Header  = "Magenta"
    }

    $prefix = @{
        Info    = "[*]"
        Success = "[+]"
        Warning = "[!]"
        Error   = "[-]"
        Header  = "==="
    }

    Write-Host "$($prefix[$Type]) $Message" -ForegroundColor $colors[$Type]
}

<#
.SYNOPSIS
    Writes a banner/header for script output.
#>
function Write-Banner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [string]$Subtitle = ""
    )

    $width = 78
    $line = "=" * $width

    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  " + $Title.PadRight($width - 4)) -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host ("  " + $Subtitle.PadRight($width - 4)) -ForegroundColor Gray
    }
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

#endregion

#region File Utilities

<#
.SYNOPSIS
    Ensures a directory exists, creating it if necessary.
#>
function Confirm-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Verbose "Created directory: $Path"
    }
    return $Path
}

<#
.SYNOPSIS
    Generates a timestamped filename.
#>
function Get-TimestampedFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [string]$Extension = "xml"
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return "$BaseName-$timestamp.$Extension"
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    # SID Resolution
    'Resolve-AccountToSid',
    'Resolve-AccountsToSids',
    'Get-StandardPrincipalSids',

    # XML Generation
    'New-AppLockerRuleXml',
    'New-PathConditionXml',
    'New-PublisherConditionXml',
    'New-HashConditionXml',
    'New-PolicyHeaderXml',
    'New-RuleCollectionXml',

    # Configuration
    'Get-AppLockerConfig',
    'Get-DefaultConfig',

    # Logging
    'Write-Status',
    'Write-Banner',

    # File Utilities
    'Confirm-Directory',
    'Get-TimestampedFileName'
)
