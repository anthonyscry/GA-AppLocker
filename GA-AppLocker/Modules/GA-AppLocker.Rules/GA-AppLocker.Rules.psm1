#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Rules

.DESCRIPTION
    AppLocker rule generation module for GA-AppLocker Dashboard.
    Creates Publisher, Hash, and Path rules from collected artifacts.
    Supports traffic light approval workflow (Auto/Review/Block).

.RULE TYPES
    - Publisher: Based on digital signature (most flexible)
    - Hash: Based on SHA256 file hash (most secure)
    - Path: Based on file path with wildcards (least secure)

.RULE COLLECTION TYPES
    - Exe: Executable files (.exe, .com)
    - Dll: Dynamic Link Libraries (.dll, .ocx)
    - Msi: Windows Installer files (.msi, .msp, .mst)
    - Script: Script files (.ps1, .bat, .cmd, .vbs, .js)
    - Appx: Packaged apps (UWP)

.DEPENDENCIES
    - GA-AppLocker.Core (logging, config)
    - GA-AppLocker.Scanning (artifact data)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release - Phase 5

.NOTES
    Rules are stored locally and can be exported to AppLocker XML format.
    Air-gapped environment compatible.
#>
#endregion

#region ===== MODULE CONFIGURATION =====

# Rule collection type mapping
$script:CollectionTypeMap = @{
    '.exe' = 'Exe'
    '.com' = 'Exe'
    '.dll' = 'Dll'
    '.ocx' = 'Dll'
    '.msi' = 'Msi'
    '.msp' = 'Msi'
    '.mst' = 'Msi'
    '.ps1' = 'Script'
    '.psm1' = 'Script'
    '.psd1' = 'Script'
    '.bat' = 'Script'
    '.cmd' = 'Script'
    '.vbs' = 'Script'
    '.js'  = 'Script'
    '.wsf' = 'Script'
    '.appx' = 'Appx'
    '.msix' = 'Appx'
}

# Rule status for traffic light system
$script:RuleStatuses = @('Pending', 'Approved', 'Rejected', 'Review')

# Default rule action
$script:DefaultAction = 'Allow'

#endregion

#region ===== SAFE LOGGING WRAPPER =====
function script:Write-RuleLog {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== HELPER FUNCTIONS =====

function script:Get-RuleStoragePath {
    <#
    .SYNOPSIS
        Gets the path to rule storage directory.
    #>
    $dataPath = Get-AppLockerDataPath
    $rulePath = Join-Path $dataPath 'Rules'
    
    if (-not (Test-Path $rulePath)) {
        New-Item -Path $rulePath -ItemType Directory -Force | Out-Null
    }
    
    return $rulePath
}

function script:Get-CollectionType {
    <#
    .SYNOPSIS
        Determines the AppLocker collection type for a file extension.
    #>
    param([string]$Extension)
    
    $ext = $Extension.ToLower()
    if (-not $ext.StartsWith('.')) { $ext = ".$ext" }
    
    if ($script:CollectionTypeMap.ContainsKey($ext)) {
        return $script:CollectionTypeMap[$ext]
    }
    return 'Exe'  # Default to Exe
}

function script:New-RuleId {
    <#
    .SYNOPSIS
        Generates a new unique rule GUID.
    #>
    return [guid]::NewGuid().ToString()
}

function script:Save-Rule {
    <#
    .SYNOPSIS
        Saves a rule to storage and updates the index.
    #>
    param([PSCustomObject]$Rule)
    
    $rulePath = Get-RuleStoragePath
    $ruleFile = Join-Path $rulePath "$($Rule.Id).json"
    
    $Rule | ConvertTo-Json -Depth 10 | Set-Content -Path $ruleFile -Encoding UTF8
    
    # Update the index with the new rule
    if (Get-Command -Name 'Add-RulesToIndex' -ErrorAction SilentlyContinue) {
        Add-RulesToIndex -Rules @($Rule) | Out-Null
    }
    
    Write-RuleLog -Message "Saved rule: $($Rule.Name) ($($Rule.Id))"
}

function script:Format-PublisherString {
    <#
    .SYNOPSIS
        Formats a publisher certificate subject into a display name.
        Handles GUID-only certificates by returning a clearer indicator.
    #>
    param(
        [string]$CertSubject,
        [string]$FileName = $null
    )
    
    if ([string]::IsNullOrWhiteSpace($CertSubject)) { return 'Unknown' }
    
    # Check for GUID-only certificate pattern
    $guidPattern = '^CN=[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
    if ($CertSubject -match $guidPattern) {
        # Try to extract app name from filename for Appx packages
        if ($FileName -and $FileName -match '\.appx$') {
            $appName = Get-AppNameFromFileName -FileName $FileName
            if ($appName) {
                return "$appName (Store App)"
            }
        }
        # Fallback: show shortened GUID with indicator
        if ($CertSubject -match 'CN=([0-9A-Fa-f]{8})') {
            return "Store App ($($Matches[1])...)"
        }
    }
    
    # Extract CN (Common Name) from certificate subject
    if ($CertSubject -match 'CN=([^,]+)') {
        return $Matches[1].Trim('"')
    }
    
    # Extract O (Organization) as fallback
    if ($CertSubject -match 'O=([^,]+)') {
        return $Matches[1].Trim('"')
    }
    
    return $CertSubject
}

function script:Get-AppNameFromFileName {
    <#
    .SYNOPSIS
        Extracts a friendly app name from an Appx package filename.
        e.g., "AcerIncorporated.AcerCareCenterS.appx" -> "Acer Care Center S"
    #>
    param([string]$FileName)
    
    if ([string]::IsNullOrWhiteSpace($FileName)) { return $null }
    
    # Remove extension
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    
    # Common patterns: Publisher.AppName or Publisher.App.Name
    # Try to extract the app name part (after first dot)
    if ($name -match '^[^.]+\.(.+)$') {
        $appPart = $Matches[1]
        
        # Convert PascalCase to spaces: "AcerCareCenterS" -> "Acer Care Center S"
        $friendly = $appPart -creplace '([a-z])([A-Z])', '$1 $2'
        # Also handle "PowerBI" style -> "Power BI"
        $friendly = $friendly -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
        # Remove dots
        $friendly = $friendly -replace '\.', ' '
        
        return $friendly.Trim()
    }
    
    return $name
}

function script:ConvertTo-AppLockerXmlRule {
    <#
    .SYNOPSIS
        Converts a rule object to AppLocker XML format.
    #>
    param([PSCustomObject]$Rule)

    # Default to 'Allow' if Action is missing, empty, or whitespace (required by AppLocker schema)
    $action = 'Allow'
    if ($Rule.Action) {
        $trimmed = "$($Rule.Action)".Trim()
        if ($trimmed -eq 'Allow' -or $trimmed -eq 'Deny') {
            $action = $trimmed
        }
    }

    $userOrGroupSid = $Rule.UserOrGroupSid
    if ([string]::IsNullOrWhiteSpace($userOrGroupSid)) {
        $userOrGroupSid = 'S-1-1-0'  # Everyone
    }
    
    switch ($Rule.RuleType) {
        'Publisher' {
            @"
    <FilePublisherRule Id="$($Rule.Id)" Name="$([System.Security.SecurityElement]::Escape($Rule.Name))" Description="$([System.Security.SecurityElement]::Escape($Rule.Description))" UserOrGroupSid="$userOrGroupSid" Action="$action">
      <Conditions>
        <FilePublisherCondition PublisherName="$([System.Security.SecurityElement]::Escape($Rule.PublisherName))" ProductName="$([System.Security.SecurityElement]::Escape($Rule.ProductName))" BinaryName="$([System.Security.SecurityElement]::Escape($Rule.BinaryName))">
          <BinaryVersionRange LowSection="$($Rule.MinVersion)" HighSection="$($Rule.MaxVersion)" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
"@
        }
        'Hash' {
            @"
    <FileHashRule Id="$($Rule.Id)" Name="$([System.Security.SecurityElement]::Escape($Rule.Name))" Description="$([System.Security.SecurityElement]::Escape($Rule.Description))" UserOrGroupSid="$userOrGroupSid" Action="$action">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x$($Rule.Hash.ToUpper())" SourceFileName="$([System.Security.SecurityElement]::Escape($Rule.SourceFileName))" SourceFileLength="$($Rule.SourceFileLength)" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
"@
        }
        'Path' {
            @"
    <FilePathRule Id="$($Rule.Id)" Name="$([System.Security.SecurityElement]::Escape($Rule.Name))" Description="$([System.Security.SecurityElement]::Escape($Rule.Description))" UserOrGroupSid="$userOrGroupSid" Action="$action">
      <Conditions>
        <FilePathCondition Path="$([System.Security.SecurityElement]::Escape($Rule.Path))" />
      </Conditions>
    </FilePathRule>
"@
        }
    }
}

#endregion

#region ===== FUNCTION LOADING =====
$functionPath = Join-Path $PSScriptRoot 'Functions'

if (Test-Path $functionPath) {
    $functionFiles = Get-ChildItem -Path $functionPath -Filter '*.ps1' -ErrorAction SilentlyContinue

    foreach ($file in $functionFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Warning "Failed to load function file: $($file.Name). Error: $($_.Exception.Message)"
        }
    }
}
#endregion

#region ===== EXPORTS =====
Export-ModuleMember -Function @(
    'New-PublisherRule',
    'New-HashRule',
    'New-PathRule',
    'ConvertFrom-Artifact',
    'Get-Rule',
    # NOTE: Get-AllRules is exported from GA-AppLocker.Storage only (avoids shadowing)
    'Remove-Rule',
    'Export-RulesToXml',
    'Set-RuleStatus',
    'Get-SuggestedGroup',
    'Get-KnownVendors',
    # Rule Templates
    'Get-RuleTemplates',
    'New-RulesFromTemplate',
    'Get-RuleTemplateCategories',
    # Bulk Operations
    'Set-BulkRuleStatus',
    'Approve-TrustedVendorRules',
    # Batch Rule Generation (10x faster)
    'Invoke-BatchRuleGeneration',
    # Deduplication
    'Remove-DuplicateRules',
    'Find-DuplicateRules',
    'Find-ExistingHashRule',
    'Find-ExistingPublisherRule',
    # NOTE: Get-ExistingRuleIndex is exported from GA-AppLocker.Storage, not this module
    # Import
    'Import-RulesFromXml',
    # Rule History/Versioning
    'Get-RuleHistory',
    'Save-RuleVersion',
    'Restore-RuleVersion',
    'Compare-RuleVersions',
    'Get-RuleVersionContent',
    'Remove-RuleHistory',
    'Invoke-RuleHistoryCleanup'
)
#endregion
