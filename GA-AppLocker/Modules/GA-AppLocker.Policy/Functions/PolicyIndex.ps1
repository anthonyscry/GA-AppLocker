#region ===== MODULE STATE =====
$script:PolicyIndexPath = $null
$script:PolicyIndex = $null
$script:PolicyIndexLoaded = $false
$script:PolicyById = @{}
#endregion

#region ===== PATH HELPERS =====
function script:Get-PolicyIndexPath {
    if (-not $script:PolicyIndexPath) {
        $dataPath = try { Get-AppLockerDataPath } catch { Join-Path $env:LOCALAPPDATA 'GA-AppLocker' }
        $script:PolicyIndexPath = Join-Path $dataPath 'policy-index.json'
    }
    return $script:PolicyIndexPath
}
#endregion

#region ===== INTERNAL HELPERS =====
function script:Escape-PolicyIndexValue {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function script:Append-PolicyIndexStringArray {
    param(
        [Parameter(Mandatory)]
        [System.Text.StringBuilder]$Builder,
        [object[]]$Values,
        [switch]$Escape
    )

    [void]$Builder.Append('[')
    $firstItem = $true

    foreach ($item in @($Values)) {
        if (-not $firstItem) { [void]$Builder.Append(',') }
        $firstItem = $false

        if ($null -eq $item) {
            [void]$Builder.Append('null')
        }
        else {
            $stringValue = [string]$item
            if ($Escape) { $stringValue = (Escape-PolicyIndexValue -Value $stringValue) }
            [void]$Builder.Append('"')
            [void]$Builder.Append($stringValue)
            [void]$Builder.Append('"')
        }
    }

    [void]$Builder.Append(']')
}
#endregion

#region ===== INDEX MANAGEMENT =====
function Reset-PolicyIndexCache {
    <#
    .SYNOPSIS
        Forces the policy index to be reloaded from disk on next access.
    #>
    [CmdletBinding()]
    param()

    $script:PolicyIndexLoaded = $false
    $script:PolicyIndex = $null
    $script:PolicyById = @{}
    Write-PolicyLog -Message 'Policy index cache reset - will reload from disk on next access'
}

function Initialize-PolicyIndex {
    [CmdletBinding()]
    param([switch]$Force)

    if ($script:PolicyIndexLoaded -and -not $Force) { return }

    $indexPath = Get-PolicyIndexPath
    $indexLoaded = $false

    if (Test-Path $indexPath) {
        try {
            $content = [System.IO.File]::ReadAllText($indexPath)
            $script:PolicyIndex = $content | ConvertFrom-Json

            if (-not $script:PolicyIndex -or -not $script:PolicyIndex.Policies) {
                throw 'Invalid policy index format'
            }

            $script:PolicyById = @{}
            foreach ($policy in $script:PolicyIndex.Policies) {
                if ($policy.PolicyId) {
                    $null = $script:PolicyById[$policy.PolicyId] = $policy
                }
            }

            $script:PolicyIndexLoaded = $true
            $indexLoaded = $true
            Write-PolicyLog -Message "Loaded policy index with $($script:PolicyIndex.Policies.Count) policies"
        }
        catch {
            Write-PolicyLog -Message "Failed to load policy index: $($_.Exception.Message)" -Level 'ERROR'
            $script:PolicyIndexLoaded = $false
            $script:PolicyIndex = $null
            $script:PolicyById = @{}
        }
    }

    if (-not $indexLoaded) {
        Write-PolicyLog -Message 'Policy index missing or invalid - rebuilding from policy files'
        $buildResult = Rebuild-PolicyIndex
        if ($buildResult.Success) {
            $script:PolicyIndexLoaded = $true
            return
        }

        $script:PolicyIndex = [PSCustomObject]@{ Policies = @(); LastUpdated = (Get-Date -Format 'o') }
        $script:PolicyById = @{}
        $script:PolicyIndexLoaded = $true
    }
}

function script:Save-PolicyIndex {
    [CmdletBinding()]
    param()

    $indexPath = Get-PolicyIndexPath
    $dir = Split-Path -Parent $indexPath

    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $now = Get-Date -Format 'o'
    $script:PolicyIndex.LastUpdated = $now

    $policies = $script:PolicyIndex.Policies
    $count = if ($policies) { @($policies).Count } else { 0 }

    if ($count -eq 0) {
        [System.IO.File]::WriteAllText($indexPath, "{`"LastUpdated`":`"$now`",`"Policies`":[]}", [System.Text.Encoding]::UTF8)
        return
    }

    $sb = [System.Text.StringBuilder]::new($count * 420 + 200)
    [void]$sb.Append("{`"LastUpdated`":`"$now`",`"Policies`":[")

    $first = $true
    foreach ($p in $policies) {
        if (-not $first) { [void]$sb.Append(',') }
        $first = $false

        [void]$sb.Append('{"PolicyId":"')
        [void]$sb.Append($p.PolicyId)
        [void]$sb.Append('"')

        [void]$sb.Append(',"Name":')
        if ($null -ne $p.Name) { [void]$sb.Append('"'); [void]$sb.Append((Escape-PolicyIndexValue -Value $p.Name)); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"Description":')
        if ($null -ne $p.Description) { [void]$sb.Append('"'); [void]$sb.Append((Escape-PolicyIndexValue -Value $p.Description)); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"EnforcementMode":')
        if ($p.EnforcementMode) { [void]$sb.Append('"'); [void]$sb.Append($p.EnforcementMode); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"Phase":')
        if ($null -ne $p.Phase) { [void]$sb.Append($p.Phase) } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"Status":')
        if ($p.Status) { [void]$sb.Append('"'); [void]$sb.Append($p.Status); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"RuleIds":')
        Append-PolicyIndexStringArray -Builder $sb -Values $p.RuleIds

        [void]$sb.Append(',"TargetOUs":')
        Append-PolicyIndexStringArray -Builder $sb -Values $p.TargetOUs -Escape

        [void]$sb.Append(',"TargetGPO":')
        if ($null -ne $p.TargetGPO) { [void]$sb.Append('"'); [void]$sb.Append((Escape-PolicyIndexValue -Value $p.TargetGPO)); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"CreatedAt":')
        if ($p.CreatedAt) { [void]$sb.Append('"'); [void]$sb.Append($p.CreatedAt); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"ModifiedAt":')
        if ($p.ModifiedAt) { [void]$sb.Append('"'); [void]$sb.Append($p.ModifiedAt); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"Version":')
        if ($null -ne $p.Version) { [void]$sb.Append($p.Version) } else { [void]$sb.Append('null') }

        [void]$sb.Append(',"FilePath":')
        if ($null -ne $p.FilePath) { [void]$sb.Append('"'); [void]$sb.Append((Escape-PolicyIndexValue -Value $p.FilePath)); [void]$sb.Append('"') } else { [void]$sb.Append('null') }

        [void]$sb.Append('}')
    }

    [void]$sb.Append(']}')
    [System.IO.File]::WriteAllText($indexPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
}

function Rebuild-PolicyIndex {
    <#
    .SYNOPSIS
        Rebuilds the policy index from policy files on disk.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$PoliciesPath,
        [scriptblock]$ProgressCallback
    )

    $result = [PSCustomObject]@{
        Success = $false
        PolicyCount = 0
        Duration = $null
        Error = $null
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not $PoliciesPath) {
        $PoliciesPath = script:Get-PolicyStoragePath
    }

    if (-not (Test-Path $PoliciesPath)) {
        $script:PolicyIndex = [PSCustomObject]@{ Policies = @(); LastUpdated = (Get-Date -Format 'o') }
        $script:PolicyById = @{}
        Save-PolicyIndex

        $result.Success = $true
        $result.Error = "No policies directory at: $PoliciesPath"
        return $result
    }

    try {
        $policies = [System.Collections.Generic.List[PSCustomObject]]::new()
        $files = [System.IO.Directory]::EnumerateFiles($PoliciesPath, '*.json', [System.IO.SearchOption]::TopDirectoryOnly)
        $fileList = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $files) { [void]$fileList.Add($file) }

        $totalFiles = $fileList.Count
        $processed = 0

        Write-PolicyLog -Message "Building policy index from $totalFiles JSON files..."

        foreach ($filePath in $fileList) {
            $processed++

            try {
                $content = [System.IO.File]::ReadAllText($filePath)
                $policy = $content | ConvertFrom-Json

                $policyId = if ($policy.PolicyId) { $policy.PolicyId } elseif ($policy.Id) { $policy.Id } else { $null }
                if ($policyId) {
                    $indexEntry = [PSCustomObject]@{
                        PolicyId        = $policyId
                        Name            = $policy.Name
                        Description     = $policy.Description
                        EnforcementMode = if ($policy.EnforcementMode) { $policy.EnforcementMode } else { 'AuditOnly' }
                        Phase           = if ($policy.Phase) { $policy.Phase } else { 1 }
                        Status          = if ($policy.Status) { $policy.Status } else { 'Draft' }
                        RuleIds         = @($policy.RuleIds)
                        TargetOUs       = @($policy.TargetOUs)
                        TargetGPO       = $policy.TargetGPO
                        CreatedAt       = $policy.CreatedAt
                        ModifiedAt      = $policy.ModifiedAt
                        Version         = if ($policy.Version) { $policy.Version } else { 1 }
                        FilePath        = $filePath
                    }
                    [void]$policies.Add($indexEntry)
                }
            }
            catch {
                Write-PolicyLog -Message "Failed to parse policy file '$filePath': $($_.Exception.Message)" -Level 'DEBUG'
            }

            if ($ProgressCallback -and ($processed % 500 -eq 0)) {
                $pct = [math]::Round(($processed / $totalFiles) * 100)
                & $ProgressCallback $processed $totalFiles $pct
            }
        }

        $script:PolicyIndex = [PSCustomObject]@{
            Policies = $policies.ToArray()
            LastUpdated = Get-Date -Format 'o'
            SourcePath = $PoliciesPath
        }

        $script:PolicyById = @{}
        foreach ($policy in $policies) {
            $null = $script:PolicyById[$policy.PolicyId] = $policy
        }

        Save-PolicyIndex
        $script:PolicyIndexLoaded = $true

        $stopwatch.Stop()
        $result.Success = $true
        $result.PolicyCount = $policies.Count
        $result.Duration = $stopwatch.Elapsed

        Write-PolicyLog -Message "Built policy index: $($policies.Count) policies in $($stopwatch.Elapsed.TotalSeconds.ToString('F1'))s"
    }
    catch {
        $result.Error = "Failed to build policy index: $($_.Exception.Message)"
        Write-PolicyLog -Message $result.Error -Level 'ERROR'
    }

    return $result
}
#endregion

#region ===== ENTRY HELPERS =====
function Add-PolicyIndexEntry {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Entry,
        [switch]$SkipSave
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data = $null
        Error = $null
    }

    try {
        Initialize-PolicyIndex

        if (-not $Entry.PolicyId) {
            $result.Error = 'PolicyId is required for index entry'
            return $result
        }

        if ($script:PolicyIndex.Policies -isnot [System.Collections.Generic.List[PSCustomObject]]) {
            $list = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($item in @($script:PolicyIndex.Policies)) { [void]$list.Add($item) }
            $script:PolicyIndex.Policies = $list
        }

        if ($script:PolicyById.ContainsKey($Entry.PolicyId)) {
            $null = Update-PolicyIndexEntry -PolicyId $Entry.PolicyId -UpdatedEntry $Entry -SkipSave:$SkipSave
        }
        else {
            [void]$script:PolicyIndex.Policies.Add($Entry)
            $script:PolicyById[$Entry.PolicyId] = $Entry
            if (-not $SkipSave) { Save-PolicyIndex }
        }

        $result.Success = $true
        $result.Data = $Entry
    }
    catch {
        $result.Error = "Failed to add policy index entry: $($_.Exception.Message)"
    }

    return $result
}

function Update-PolicyIndexEntry {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId,
        [Parameter(Mandatory)]
        [PSCustomObject]$UpdatedEntry,
        [switch]$SkipSave
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data = $null
        Error = $null
    }

    try {
        Initialize-PolicyIndex

        if (-not $script:PolicyById.ContainsKey($PolicyId)) {
            $result.Error = "Policy not found in index: $PolicyId"
            return $result
        }

        $entry = $script:PolicyById[$PolicyId]
        $fields = @(
            'Name','Description','EnforcementMode','Phase','Status','RuleIds',
            'TargetOUs','TargetGPO','CreatedAt','ModifiedAt','Version','FilePath'
        )

        foreach ($field in $fields) {
            if ($UpdatedEntry.PSObject.Properties.Name -contains $field) {
                $entry.$field = $UpdatedEntry.$field
            }
        }

        if (-not $SkipSave) { Save-PolicyIndex }

        $result.Success = $true
        $result.Data = $entry
    }
    catch {
        $result.Error = "Failed to update policy index entry: $($_.Exception.Message)"
    }

    return $result
}

function Remove-PolicyIndexEntry {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$PolicyIds,
        [switch]$SkipSave
    )

    $result = [PSCustomObject]@{
        Success = $false
        RemovedCount = 0
        Error = $null
    }

    try {
        Initialize-PolicyIndex

        $idsToRemove = [System.Collections.Generic.HashSet[string]]::new($PolicyIds, [System.StringComparer]::OrdinalIgnoreCase)
        $originalCount = $script:PolicyIndex.Policies.Count

        foreach ($id in $PolicyIds) {
            if ($script:PolicyById.ContainsKey($id)) {
                $null = $script:PolicyById.Remove($id)
            }
        }

        $filtered = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($policy in @($script:PolicyIndex.Policies)) {
            if (-not $idsToRemove.Contains($policy.PolicyId)) {
                [void]$filtered.Add($policy)
            }
        }

        $script:PolicyIndex.Policies = $filtered
        $removedCount = $originalCount - $filtered.Count

        if ($removedCount -gt 0 -and -not $SkipSave) { Save-PolicyIndex }

        $result.Success = $true
        $result.RemovedCount = $removedCount
    }
    catch {
        $result.Error = "Failed to remove policy index entries: $($_.Exception.Message)"
    }

    return $result
}

function Find-PolicyIndexEntryById {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId
    )

    Initialize-PolicyIndex

    if ($script:PolicyById.ContainsKey($PolicyId)) {
        return $script:PolicyById[$PolicyId]
    }

    return $null
}
#endregion
