<#
.SYNOPSIS
    Functions for rule history and versioning.

.DESCRIPTION
    Provides version tracking for rule changes including:
    - Automatic version history on rule updates
    - View previous versions
    - Restore from previous version
    - Compare versions


    .EXAMPLE
    Get-RuleHistory
    # Get RuleHistory
    #>

function Get-RuleHistory {
    <#
    .SYNOPSIS
        Gets the version history for a rule.

    .DESCRIPTION
        Gets the version history for a rule. Returns the requested data in a standard result object.

    .PARAMETER RuleId
        The rule ID to get history for.

    .PARAMETER IncludeContent
        Include full rule content in each version.

    .EXAMPLE
        Get-RuleHistory -RuleId '12345678-...'

    .OUTPUTS
        [PSCustomObject] Result with Success and Data (array of versions).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId,

        [Parameter()]
        [switch]$IncludeContent
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
    }

    try {
        $historyPath = Get-RuleHistoryPath
        $ruleHistoryDir = Join-Path $historyPath $RuleId

        if (-not (Test-Path $ruleHistoryDir)) {
            $result.Success = $true
            $result.Data = @()
            return $result
        }

        $versions = [System.Collections.Generic.List[PSCustomObject]]::new()
        $versionFiles = Get-ChildItem -Path $ruleHistoryDir -Filter '*.json' | 
            Sort-Object { [int]($_.BaseName -replace 'v', '') } -Descending

        foreach ($file in $versionFiles) {
            $versionData = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            
            $versionInfo = [PSCustomObject]@{
                Version     = $versionData.Version
                ModifiedAt  = $versionData.ModifiedAt
                ModifiedBy  = $versionData.ModifiedBy
                ChangeType  = $versionData.ChangeType
                ChangeSummary = $versionData.ChangeSummary
            }

            if ($IncludeContent) {
                $versionInfo | Add-Member -NotePropertyName 'RuleContent' -NotePropertyValue $versionData.RuleContent
            }

            [void]$versions.Add($versionInfo)
        }

        $result.Success = $true
        $result.Data = $versions.ToArray()
    }
    catch {
        $result.Error = "Failed to get rule history: $($_.Exception.Message)"
        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message $result.Error -Level 'ERROR'
        }
    }

    return $result
}

function Save-RuleVersion {
    <#
    .SYNOPSIS
        Saves a new version of a rule to history.

    .DESCRIPTION
        Saves a new version of a rule to history. Writes data to persistent storage.

    .PARAMETER Rule
        The rule object to save.

    .PARAMETER ChangeType
        Type of change: Created, Updated, StatusChanged, Restored.

    .PARAMETER ChangeSummary
        Brief description of the change.

    .EXAMPLE
        Save-RuleVersion -Rule $rule -ChangeType 'Updated' -ChangeSummary 'Changed version range'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Rule,

        [Parameter(Mandatory)]
        [ValidateSet('Created', 'Updated', 'StatusChanged', 'Restored', 'Imported')]
        [string]$ChangeType,

        [Parameter()]
        [string]$ChangeSummary
    )

    $result = [PSCustomObject]@{
        Success = $false
        Version = 0
        Error   = $null
    }

    try {
        $historyPath = Get-RuleHistoryPath
        $ruleHistoryDir = Join-Path $historyPath $Rule.Id

        # Create history directory for this rule if needed
        if (-not (Test-Path $ruleHistoryDir)) {
            New-Item -Path $ruleHistoryDir -ItemType Directory -Force | Out-Null
        }

        # Determine next version number
        $existingVersions = Get-ChildItem -Path $ruleHistoryDir -Filter '*.json' -ErrorAction SilentlyContinue
        $nextVersion = 1
        if ($existingVersions) {
            $maxVersion = $existingVersions | 
                ForEach-Object { [int]($_.BaseName -replace 'v', '') } | 
                Measure-Object -Maximum | 
                Select-Object -ExpandProperty Maximum
            $nextVersion = $maxVersion + 1
        }

        # Create version record
        $versionRecord = [PSCustomObject]@{
            Version       = $nextVersion
            RuleId        = $Rule.Id
            ModifiedAt    = (Get-Date).ToString('o')
            ModifiedBy    = "$env:USERDOMAIN\$env:USERNAME"
            ChangeType    = $ChangeType
            ChangeSummary = if ($ChangeSummary) { $ChangeSummary } else { "$ChangeType rule" }
            RuleContent   = $Rule
        }

        # Save version file
        $versionFile = Join-Path $ruleHistoryDir "v$nextVersion.json"
        $versionRecord | ConvertTo-Json -Depth 15 | Set-Content -Path $versionFile -Encoding UTF8

        $result.Success = $true
        $result.Version = $nextVersion

        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message "Saved rule version v$nextVersion for $($Rule.Name) ($($Rule.Id))" -Level 'INFO'
        }
    }
    catch {
        $result.Error = "Failed to save rule version: $($_.Exception.Message)"
        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message $result.Error -Level 'ERROR'
        }
    }

    return $result
}

function Restore-RuleVersion {
    <#
    .SYNOPSIS
        Restores a rule to a previous version.

    .DESCRIPTION
        Restores a rule to a previous version. Restores from a previously saved version.

    .PARAMETER RuleId
        The rule ID to restore.

    .PARAMETER Version
        The version number to restore to.

    .EXAMPLE
        Restore-RuleVersion -RuleId '12345678-...' -Version 2
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId,

        [Parameter(Mandatory)]
        [int]$Version
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $historyPath = Get-RuleHistoryPath
        $versionFile = Join-Path $historyPath "$RuleId\v$Version.json"

        if (-not (Test-Path $versionFile)) {
            $result.Error = "Version $Version not found for rule $RuleId"
            return $result
        }

        # Load the version
        $versionData = Get-Content -Path $versionFile -Raw | ConvertFrom-Json
        $restoredRule = $versionData.RuleContent

        # Update modification date
        $restoredRule.ModifiedDate = Get-Date -Format 'o'

        # Save as current rule
        $rulePath = Get-RuleStoragePath
        $ruleFile = Join-Path $rulePath "$RuleId.json"
        $restoredRule | ConvertTo-Json -Depth 15 | Set-Content -Path $ruleFile -Encoding UTF8

        # Update the index with restored rule's status
        if (Get-Command -Name 'Update-RuleStatusInIndex' -ErrorAction SilentlyContinue) {
            Update-RuleStatusInIndex -RuleIds @($RuleId) -Status $restoredRule.Status | Out-Null
        }

        # Save this restore as a new version
        Save-RuleVersion -Rule $restoredRule -ChangeType 'Restored' -ChangeSummary "Restored from version $Version" | Out-Null

        $result.Success = $true
        $result.Data = $restoredRule

        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message "Restored rule $($restoredRule.Name) to version $Version" -Level 'INFO'
        }
    }
    catch {
        $result.Error = "Failed to restore rule version: $($_.Exception.Message)"
        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message $result.Error -Level 'ERROR'
        }
    }

    return $result
}

function Compare-RuleVersions {
    <#
    .SYNOPSIS
        Compares two versions of a rule.

    .DESCRIPTION
        Compares two versions of a rule. Returns the differences found between items.

    .PARAMETER RuleId
        The rule ID to compare versions for.

    .PARAMETER Version1
        First version number.

    .PARAMETER Version2
        Second version number (default: current).

    .EXAMPLE
        Compare-RuleVersions -RuleId '12345678-...' -Version1 1 -Version2 3
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId,

        [Parameter(Mandatory)]
        [int]$Version1,

        [Parameter()]
        [int]$Version2 = 0
    )

    $result = [PSCustomObject]@{
        Success     = $false
        Differences = @()
        Error       = $null
    }

    try {
        $historyPath = Get-RuleHistoryPath
        
        # Load version 1
        $v1File = Join-Path $historyPath "$RuleId\v$Version1.json"
        if (-not (Test-Path $v1File)) {
            $result.Error = "Version $Version1 not found"
            return $result
        }
        $v1Data = (Get-Content -Path $v1File -Raw | ConvertFrom-Json).RuleContent

        # Load version 2 (or current)
        $v2Data = $null
        if ($Version2 -gt 0) {
            $v2File = Join-Path $historyPath "$RuleId\v$Version2.json"
            if (-not (Test-Path $v2File)) {
                $result.Error = "Version $Version2 not found"
                return $result
            }
            $v2Data = (Get-Content -Path $v2File -Raw | ConvertFrom-Json).RuleContent
        }
        else {
            # Load current rule
            $rulePath = Get-RuleStoragePath
            $ruleFile = Join-Path $rulePath "$RuleId.json"
            if (Test-Path $ruleFile) {
                $v2Data = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json
                $Version2 = 'Current'
            }
            else {
                $result.Error = "Current rule not found"
                return $result
            }
        }

        # Compare properties
        $differences = [System.Collections.Generic.List[PSCustomObject]]::new()
        $propsToCompare = @('Name', 'Status', 'Action', 'RuleType', 'CollectionType', 
                           'PublisherName', 'ProductName', 'BinaryName', 'MinVersion', 'MaxVersion',
                           'Hash', 'Path', 'Description')

        foreach ($prop in $propsToCompare) {
            $val1 = $v1Data.$prop
            $val2 = $v2Data.$prop

            if ($val1 -ne $val2) {
                [void]$differences.Add([PSCustomObject]@{
                    Property = $prop
                    Version1Value = $val1
                    Version2Value = $val2
                })
            }
        }

        $result.Success = $true
        $result.Differences = $differences.ToArray()
        $result | Add-Member -NotePropertyName 'Version1' -NotePropertyValue $Version1
        $result | Add-Member -NotePropertyName 'Version2' -NotePropertyValue $Version2
    }
    catch {
        $result.Error = "Failed to compare versions: $($_.Exception.Message)"
    }

    return $result
}

function Get-RuleVersionContent {
    <#
    .SYNOPSIS
        Gets the full content of a specific rule version.

    .DESCRIPTION
        Gets the full content of a specific rule version. Returns the requested data in a standard result object.

    .PARAMETER RuleId
        The rule ID.

    .PARAMETER Version
        The version number.

    .EXAMPLE
        Get-RuleVersionContent -RuleId '12345678-...' -Version 2
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId,

        [Parameter(Mandatory)]
        [int]$Version
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $historyPath = Get-RuleHistoryPath
        $versionFile = Join-Path $historyPath "$RuleId\v$Version.json"

        if (-not (Test-Path $versionFile)) {
            $result.Error = "Version $Version not found for rule $RuleId"
            return $result
        }

        $versionData = Get-Content -Path $versionFile -Raw | ConvertFrom-Json
        $result.Success = $true
        $result.Data = $versionData
    }
    catch {
        $result.Error = "Failed to get version content: $($_.Exception.Message)"
    }

    return $result
}

function Remove-RuleHistory {
    <#
    .SYNOPSIS
        Removes all history for a rule.

    .DESCRIPTION
        Removes all history for a rule. Permanently removes the item from storage.

    .PARAMETER RuleId
        The rule ID to remove history for.

    .EXAMPLE
        Remove-RuleHistory -RuleId '12345678-...'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleId
    )

    $result = [PSCustomObject]@{
        Success = $false
        Error   = $null
    }

    try {
        $historyPath = Get-RuleHistoryPath
        $ruleHistoryDir = Join-Path $historyPath $RuleId

        if (Test-Path $ruleHistoryDir) {
            Remove-Item -Path $ruleHistoryDir -Recurse -Force
        }

        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to remove rule history: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-RuleHistoryCleanup {
    <#
    .SYNOPSIS
        Cleans up old rule history, keeping only recent versions.

    .DESCRIPTION
        Cleans up old rule history, keeping only recent versions. Executes the operation and returns a result object.

    .PARAMETER KeepVersions
        Number of versions to keep per rule. Default: 10.

    .PARAMETER OlderThanDays
        Delete versions older than this many days. Default: 90.

    .EXAMPLE
        Invoke-RuleHistoryCleanup -KeepVersions 5 -OlderThanDays 30
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [int]$KeepVersions = 10,

        [Parameter()]
        [int]$OlderThanDays = 90
    )

    $result = [PSCustomObject]@{
        Success        = $false
        VersionsRemoved = 0
        Error          = $null
    }

    try {
        $historyPath = Get-RuleHistoryPath
        $cutoffDate = (Get-Date).AddDays(-$OlderThanDays)
        $removed = 0

        $ruleDirs = Get-ChildItem -Path $historyPath -Directory -ErrorAction SilentlyContinue

        foreach ($ruleDir in $ruleDirs) {
            $versionFiles = Get-ChildItem -Path $ruleDir.FullName -Filter '*.json' |
                Sort-Object { [int]($_.BaseName -replace 'v', '') } -Descending

            $keepCount = 0
            foreach ($file in $versionFiles) {
                $keepCount++
                
                # Keep minimum versions
                if ($keepCount -le $KeepVersions) {
                    continue
                }

                # Check age
                if ($file.LastWriteTime -lt $cutoffDate) {
                    Remove-Item -Path $file.FullName -Force
                    $removed++
                }
            }
        }

        $result.Success = $true
        $result.VersionsRemoved = $removed

        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message "Rule history cleanup: removed $removed old versions" -Level 'INFO'
        }
    }
    catch {
        $result.Error = "Failed to cleanup rule history: $($_.Exception.Message)"
    }

    return $result
}

#region Helper Functions

function script:Get-RuleHistoryPath {
    <#
    .SYNOPSIS
        Gets the path to rule history storage directory.

    .DESCRIPTION
        Gets the path to rule history storage directory.
    #>
    $dataPath = Get-AppLockerDataPath
    $historyPath = Join-Path $dataPath 'RuleHistory'
    
    if (-not (Test-Path $historyPath)) {
        New-Item -Path $historyPath -ItemType Directory -Force | Out-Null
    }
    
    return $historyPath
}

#endregion
