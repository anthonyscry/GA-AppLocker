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

<#
.SYNOPSIS
    Reads a computer list from either TXT or CSV format.

.DESCRIPTION
    Supports two formats:
    - TXT: One computer name per line (lines starting with # are comments)
    - CSV: Must have a 'ComputerName' column header

.PARAMETER Path
    Path to the computer list file (.txt or .csv)

.OUTPUTS
    Array of computer names
#>
function Get-ComputerList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLower()

    if ($extension -eq ".csv") {
        # CSV format - expect ComputerName column
        $csv = Import-Csv -Path $Path
        if (-not ($csv | Get-Member -Name "ComputerName" -MemberType NoteProperty)) {
            throw "CSV file must have a 'ComputerName' column header"
        }
        $computers = @($csv |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.ComputerName) } |
            ForEach-Object { $_.ComputerName.Trim() })
    }
    else {
        # TXT format - one computer per line, # for comments
        $computers = @(Get-Content -Path $Path |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#") } |
            ForEach-Object { $_.Trim() })
    }

    return $computers
}

#endregion

#region Validation Functions

<#
.SYNOPSIS
    Validates an AppLocker policy XML file.

.PARAMETER PolicyPath
    Path to the policy XML file.

.OUTPUTS
    PSCustomObject with validation results.
#>
function Test-AppLockerPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyPath
    )

    $result = [PSCustomObject]@{
        Path          = $PolicyPath
        IsValid       = $false
        XmlValid      = $false
        HasRules      = $false
        RuleCount     = 0
        Collections   = @()
        Warnings      = [System.Collections.Generic.List[string]]::new()
        Errors        = [System.Collections.Generic.List[string]]::new()
    }

    # Check file exists
    if (-not (Test-Path $PolicyPath)) {
        $result.Errors.Add("File not found: $PolicyPath")
        return $result
    }

    # Validate XML structure
    try {
        [xml]$policy = Get-Content -Path $PolicyPath -Raw -ErrorAction Stop
        $result.XmlValid = $true
    }
    catch {
        $result.Errors.Add("Invalid XML: $($_.Exception.Message)")
        return $result
    }

    # Check for AppLockerPolicy root element
    if ($null -eq $policy.AppLockerPolicy) {
        $result.Errors.Add("Missing <AppLockerPolicy> root element")
        return $result
    }

    # Analyze rule collections
    $totalRules = 0
    foreach ($collection in $policy.AppLockerPolicy.RuleCollection) {
        $collectionType = $collection.Type
        $enforcementMode = $collection.EnforcementMode

        $ruleCount = 0
        $ruleCount += ($collection.FilePublisherRule | Measure-Object).Count
        $ruleCount += ($collection.FilePathRule | Measure-Object).Count
        $ruleCount += ($collection.FileHashRule | Measure-Object).Count

        $result.Collections += [PSCustomObject]@{
            Type            = $collectionType
            EnforcementMode = $enforcementMode
            RuleCount       = $ruleCount
        }

        $totalRules += $ruleCount

        # Check for empty enforced collections (warning)
        if ($enforcementMode -eq "Enabled" -and $ruleCount -eq 0) {
            $result.Warnings.Add("$collectionType collection is enforced but has no rules - will block everything!")
        }

        # Check for DLL rules in enforce mode (warning)
        if ($collectionType -eq "Dll" -and $enforcementMode -eq "Enabled") {
            $result.Warnings.Add("DLL rules are in Enforce mode - ensure thorough testing was done")
        }
    }

    $result.RuleCount = $totalRules
    $result.HasRules = $totalRules -gt 0

    # Additional security checks
    $securityIssues = Test-PolicySecurity -Policy $policy
    foreach ($issue in $securityIssues) {
        $result.Warnings.Add($issue)
    }

    # Determine overall validity
    $result.IsValid = $result.XmlValid -and $result.HasRules -and ($result.Errors.Count -eq 0)

    return $result
}

<#
.SYNOPSIS
    Checks a policy for common security issues.

.PARAMETER Policy
    The XML policy object.

.OUTPUTS
    Array of warning messages.
#>
function Test-PolicySecurity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Policy
    )

    $warnings = @()

    foreach ($collection in $Policy.AppLockerPolicy.RuleCollection) {
        # Check for overly permissive path rules
        foreach ($rule in $collection.FilePathRule) {
            $path = $rule.Conditions.FilePathCondition.Path
            $action = $rule.Action
            $sid = $rule.UserOrGroupSid

            # Warning: Allow * for Everyone
            if ($path -eq "*" -and $action -eq "Allow" -and $sid -eq "S-1-1-0") {
                $warnings += "[$($collection.Type)] Rule '$($rule.Name)' allows EVERYTHING for Everyone"
            }

            # Warning: Allow from user-writable paths
            $userWritablePaths = @("%TEMP%", "%TMP%", "%APPDATA%", "%LOCALAPPDATA%", "Downloads")
            foreach ($uwp in $userWritablePaths) {
                if ($path -like "*$uwp*" -and $action -eq "Allow") {
                    $warnings += "[$($collection.Type)] Rule '$($rule.Name)' allows execution from user-writable path: $path"
                }
            }
        }

        # Check for wildcard publisher rules to Everyone
        foreach ($rule in $collection.FilePublisherRule) {
            $publisher = $rule.Conditions.FilePublisherCondition.PublisherName
            $sid = $rule.UserOrGroupSid

            # Warning: Overly broad publisher to Everyone
            if ($publisher -eq "*" -and $sid -eq "S-1-1-0") {
                $warnings += "[$($collection.Type)] Rule '$($rule.Name)' allows ANY publisher for Everyone"
            }
        }
    }

    return $warnings
}

<#
.SYNOPSIS
    Compares two AppLocker policies and reports differences.

.PARAMETER ReferencePath
    Path to the reference (baseline) policy.

.PARAMETER DifferencePath
    Path to the policy to compare.

.OUTPUTS
    PSCustomObject with comparison results.
#>
function Compare-AppLockerPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReferencePath,

        [Parameter(Mandatory = $true)]
        [string]$DifferencePath
    )

    $result = [PSCustomObject]@{
        ReferencePath  = $ReferencePath
        DifferencePath = $DifferencePath
        AreIdentical   = $false
        RulesOnlyInRef = @()
        RulesOnlyInDiff = @()
        ModeDifferences = @()
    }

    # Load both policies
    try {
        [xml]$refPolicy = Get-Content -Path $ReferencePath -Raw
        [xml]$diffPolicy = Get-Content -Path $DifferencePath -Raw
    }
    catch {
        Write-Error "Failed to load policies: $_"
        return $result
    }

    # Compare enforcement modes
    foreach ($refColl in $refPolicy.AppLockerPolicy.RuleCollection) {
        $diffColl = $diffPolicy.AppLockerPolicy.RuleCollection | Where-Object { $_.Type -eq $refColl.Type }

        if ($refColl.EnforcementMode -ne $diffColl.EnforcementMode) {
            $result.ModeDifferences += [PSCustomObject]@{
                Collection    = $refColl.Type
                ReferenceMode = $refColl.EnforcementMode
                DifferenceMode = $diffColl.EnforcementMode
            }
        }
    }

    # Extract rule identifiers for comparison
    $refRules = Get-PolicyRuleIdentifiers -Policy $refPolicy
    $diffRules = Get-PolicyRuleIdentifiers -Policy $diffPolicy

    $result.RulesOnlyInRef = $refRules | Where-Object { $_ -notin $diffRules }
    $result.RulesOnlyInDiff = $diffRules | Where-Object { $_ -notin $refRules }

    $result.AreIdentical = ($result.RulesOnlyInRef.Count -eq 0) -and
                           ($result.RulesOnlyInDiff.Count -eq 0) -and
                           ($result.ModeDifferences.Count -eq 0)

    return $result
}

<#
.SYNOPSIS
    Extracts unique rule identifiers from a policy for comparison.
#>
function Get-PolicyRuleIdentifiers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Policy
    )

    $identifiers = @()

    foreach ($collection in $Policy.AppLockerPolicy.RuleCollection) {
        $type = $collection.Type

        foreach ($rule in $collection.FilePublisherRule) {
            $pub = $rule.Conditions.FilePublisherCondition
            $identifiers += "$type|Publisher|$($pub.PublisherName)|$($pub.ProductName)|$($pub.BinaryName)"
        }

        foreach ($rule in $collection.FilePathRule) {
            $path = $rule.Conditions.FilePathCondition.Path
            $identifiers += "$type|Path|$($rule.Action)|$path"
        }

        foreach ($rule in $collection.FileHashRule) {
            $hash = $rule.Conditions.FileHashCondition.FileHash.Data
            $identifiers += "$type|Hash|$hash"
        }
    }

    return $identifiers
}

<#
.SYNOPSIS
    Validates scan data directory structure and content.

.PARAMETER ScanPath
    Path to the scan results directory.

.OUTPUTS
    PSCustomObject with validation results.
#>
function Test-ScanData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanPath
    )

    $result = [PSCustomObject]@{
        Path           = $ScanPath
        IsValid        = $false
        ComputerCount  = 0
        HasExecutables = $false
        HasPublishers  = $false
        HasWritable    = $false
        Computers      = @()
        Warnings       = [System.Collections.Generic.List[string]]::new()
        Errors         = [System.Collections.Generic.List[string]]::new()
    }

    # Check path exists
    if (-not (Test-Path $ScanPath)) {
        $result.Errors.Add("Scan path not found: $ScanPath")
        return $result
    }

    # Find computer folders (folders containing CSV files)
    $computerFolders = Get-ChildItem -Path $ScanPath -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "*.csv") }

    if ($computerFolders.Count -eq 0) {
        $result.Errors.Add("No computer scan data found in $ScanPath")
        return $result
    }

    $result.ComputerCount = $computerFolders.Count

    foreach ($folder in $computerFolders) {
        $computerData = [PSCustomObject]@{
            Name           = $folder.Name
            ExecutableCount = 0
            SignedCount    = 0
            PublisherCount = 0
            WritableCount  = 0
        }

        # Check for Executables.csv
        $exePath = Join-Path $folder.FullName "Executables.csv"
        if (Test-Path $exePath) {
            $exes = Import-Csv -Path $exePath
            $computerData.ExecutableCount = $exes.Count
            $computerData.SignedCount = ($exes | Where-Object { $_.IsSigned -eq "True" }).Count
            $result.HasExecutables = $true
        }

        # Check for Publishers.csv
        $pubPath = Join-Path $folder.FullName "Publishers.csv"
        if (Test-Path $pubPath) {
            $pubs = Import-Csv -Path $pubPath
            $computerData.PublisherCount = $pubs.Count
            $result.HasPublishers = $true
        }

        # Check for WritableDirectories.csv
        $writablePath = Join-Path $folder.FullName "WritableDirectories.csv"
        if (Test-Path $writablePath) {
            $writable = Import-Csv -Path $writablePath
            $computerData.WritableCount = $writable.Count
            $result.HasWritable = $true
        }

        $result.Computers += $computerData
    }

    # Add warnings for missing data
    if (-not $result.HasExecutables) {
        $result.Warnings.Add("No executable data found - publisher rules cannot be generated")
    }

    if (-not $result.HasWritable) {
        $result.Warnings.Add("No writable directory data - security analysis incomplete")
    }

    $result.IsValid = $result.HasExecutables -and ($result.Errors.Count -eq 0)

    return $result
}

<#
.SYNOPSIS
    Displays validation results in a formatted manner.

.PARAMETER ValidationResult
    The result object from Test-AppLockerPolicy or Test-ScanData.
#>
function Show-ValidationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ValidationResult
    )

    $statusColor = if ($ValidationResult.IsValid) { "Green" } else { "Red" }
    $statusText = if ($ValidationResult.IsValid) { "VALID" } else { "INVALID" }

    Write-Host "`n=== Validation Result: $statusText ===" -ForegroundColor $statusColor
    Write-Host "Path: $($ValidationResult.Path)" -ForegroundColor Cyan

    if ($ValidationResult.RuleCount) {
        Write-Host "Total Rules: $($ValidationResult.RuleCount)" -ForegroundColor Gray
    }

    if ($ValidationResult.Collections) {
        Write-Host "`nRule Collections:" -ForegroundColor Yellow
        foreach ($coll in $ValidationResult.Collections) {
            Write-Host "  $($coll.Type): $($coll.RuleCount) rules ($($coll.EnforcementMode))" -ForegroundColor Gray
        }
    }

    if ($ValidationResult.ComputerCount) {
        Write-Host "Computers: $($ValidationResult.ComputerCount)" -ForegroundColor Gray
    }

    if ($ValidationResult.Warnings.Count -gt 0) {
        Write-Host "`nWarnings:" -ForegroundColor Yellow
        foreach ($warning in $ValidationResult.Warnings) {
            Write-Host "  [!] $warning" -ForegroundColor Yellow
        }
    }

    if ($ValidationResult.Errors.Count -gt 0) {
        Write-Host "`nErrors:" -ForegroundColor Red
        foreach ($err in $ValidationResult.Errors) {
            Write-Host "  [-] $err" -ForegroundColor Red
        }
    }

    Write-Host ""
}

#endregion

#region Parameter and Input Helpers

<#
.SYNOPSIS
    Prompts for and validates a path with proper error handling.

.PARAMETER Prompt
    The prompt message to display.

.PARAMETER DefaultValue
    Optional default value if user provides no input.

.PARAMETER MustExist
    If true, validates that the path exists.

.PARAMETER MustBeFile
    If true, validates that the path is a file (not directory).

.PARAMETER MustBeDirectory
    If true, validates that the path is a directory (not file).

.OUTPUTS
    String path, or $null if validation fails.
#>
function Get-ValidatedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$DefaultValue = "",
        [string]$Example = "",
        [switch]$MustExist,
        [switch]$MustBeFile,
        [switch]$MustBeDirectory
    )

    # Show example if provided
    if ($Example) {
        Write-Host "  Example: $Example" -ForegroundColor DarkGray
    }

    # Prompt with default
    if ($DefaultValue) {
        $input = Read-Host "$Prompt (default: $DefaultValue)"
        if ([string]::IsNullOrWhiteSpace($input)) {
            $input = $DefaultValue
        }
    }
    else {
        $input = Read-Host $Prompt
    }

    # Check if empty
    if ([string]::IsNullOrWhiteSpace($input)) {
        Write-Host "  [-] Path is required" -ForegroundColor Red
        return $null
    }

    # Check existence if required
    if ($MustExist -and -not (Test-Path $input)) {
        Write-Host "  [-] Path not found: $input" -ForegroundColor Red
        return $null
    }

    # Validate file type
    if ($MustExist) {
        $item = Get-Item $input -ErrorAction SilentlyContinue
        if ($item) {
            if ($MustBeFile -and $item.PSIsContainer) {
                Write-Host "  [-] Path is a directory, not a file: $input" -ForegroundColor Red
                Write-Host "      Please provide a file path" -ForegroundColor Yellow
                return $null
            }
            if ($MustBeDirectory -and -not $item.PSIsContainer) {
                Write-Host "  [-] Path is a file, not a directory: $input" -ForegroundColor Red
                Write-Host "      Please provide a directory path" -ForegroundColor Yellow
                return $null
            }
        }
    }

    return $input
}

<#
.SYNOPSIS
    Adds parameters to a hashtable only if they have non-empty values.

.PARAMETER Hashtable
    The hashtable to add parameters to.

.PARAMETER Parameters
    Hashtable of parameter names and values to conditionally add.

.EXAMPLE
    $params = @{}
    Add-NonEmptyParameters -Hashtable $params -Parameters @{
        Path = $Path
        Name = $Name
        Force = $Force
    }
#>
function Add-NonEmptyParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hashtable,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]

        # Add if: not null, not empty string, or is a switch/bool
        if ($null -ne $value) {
            if ($value -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $Hashtable[$key] = $value
                }
            }
            elseif ($value -is [bool] -or $value -is [switch]) {
                if ($value) {
                    $Hashtable[$key] = $value
                }
            }
            else {
                $Hashtable[$key] = $value
            }
        }
    }
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
    'Get-TimestampedFileName',

    # Validation
    'Test-AppLockerPolicy',
    'Test-PolicySecurity',
    'Compare-AppLockerPolicies',
    'Get-PolicyRuleIdentifiers',
    'Test-ScanData',
    'Show-ValidationResult',

    # Parameter and Input Helpers
    'Get-ValidatedPath',
    'Add-NonEmptyParameters'
)
