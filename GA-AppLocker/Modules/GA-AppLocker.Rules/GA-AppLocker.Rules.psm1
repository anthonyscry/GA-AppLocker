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
        Saves a rule to storage.
    #>
    param([PSCustomObject]$Rule)
    
    $rulePath = Get-RuleStoragePath
    $ruleFile = Join-Path $rulePath "$($Rule.Id).json"
    
    $Rule | ConvertTo-Json -Depth 10 | Set-Content -Path $ruleFile -Encoding UTF8
    Write-RuleLog -Message "Saved rule: $($Rule.Name) ($($Rule.Id))"
}

function script:Format-PublisherString {
    <#
    .SYNOPSIS
        Formats a publisher certificate subject into a display name.
    #>
    param([string]$CertSubject)
    
    if ([string]::IsNullOrWhiteSpace($CertSubject)) { return 'Unknown' }
    
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

function script:ConvertTo-AppLockerXmlRule {
    <#
    .SYNOPSIS
        Converts a rule object to AppLocker XML format.
    #>
    param([PSCustomObject]$Rule)
    
    $action = $Rule.Action
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
          <FileHash Type="SHA256" Data="0x$($Rule.Hash)" SourceFileName="$([System.Security.SecurityElement]::Escape($Rule.SourceFileName))" SourceFileLength="$($Rule.SourceFileLength)" />
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
    'Get-AllRules',
    'Remove-Rule',
    'Export-RulesToXml',
    'Set-RuleStatus'
)
#endregion
