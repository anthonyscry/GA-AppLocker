<#
.SYNOPSIS
    Pure business logic functions for Scanner panel.
.DESCRIPTION
    Contains data validation, transformation, and filtering logic
    extracted from the Scanner panel UI code. These functions have
    NO dependencies on $Window or WPF types.
#>

function Test-ScanPathValid {
    <#
    .SYNOPSIS
        Validates a scan path.
    .DESCRIPTION
        Checks if a path is valid for scanning (exists, accessible, etc.).
    #>
    param(
        [string]$Path,
        [switch]$AllowUNC
    )
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{ Valid = $false; Error = 'Path is empty' }
    }
    
    # Check for UNC paths
    if ($Path.StartsWith('\\')) {
        if (-not $AllowUNC) {
            return @{ Valid = $false; Error = 'UNC paths not allowed' }
        }
    }
    
    # Check if path exists
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) {
        return @{ Valid = $false; Error = 'Path does not exist' }
    }
    
    return @{ Valid = $true; Error = $null }
}

function Get-ScanPathsFromText {
    <#
    .SYNOPSIS
        Parses scan paths from multi-line text input.
    #>
    param([string]$Text)
    
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    
    $paths = $Text -split "`r?`n" | 
        ForEach-Object { $_.Trim() } | 
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    
    return @($paths)
}

function Get-FilteredArtifacts {
    <#
    .SYNOPSIS
        Filters artifacts by type criteria.
    #>
    param(
        [array]$Artifacts,
        [string]$TypeFilter = 'All',
        [switch]$ExcludeDlls,
        [switch]$ExcludeScripts,
        [switch]$ExcludeUnsigned
    )
    
    if (-not $Artifacts -or $Artifacts.Count -eq 0) { return @() }
    
    $filtered = $Artifacts
    
    # Type filter
    if ($TypeFilter -ne 'All') {
        $filtered = $filtered.Where({ $_.FileType -eq $TypeFilter })
    }
    
    # Exclusions
    if ($ExcludeDlls) {
        $filtered = $filtered.Where({ $_.Extension -ne '.dll' })
    }
    
    if ($ExcludeScripts) {
        $scriptExts = @('.ps1', '.bat', '.cmd', '.vbs', '.js')
        $filtered = $filtered.Where({ $_.Extension -notin $scriptExts })
    }
    
    if ($ExcludeUnsigned) {
        $filtered = $filtered.Where({ $_.IsSigned -eq $true })
    }
    
    return @($filtered)
}

function Get-ArtifactCountsByType {
    <#
    .SYNOPSIS
        Counts artifacts by file type.
    #>
    param([array]$Artifacts)
    
    if (-not $Artifacts -or $Artifacts.Count -eq 0) {
        return @{
            Total = 0
            Executables = 0
            DLLs = 0
            Scripts = 0
            Installers = 0
            Signed = 0
            Unsigned = 0
        }
    }
    
    return @{
        Total = $Artifacts.Count
        Executables = @($Artifacts.Where({ $_.Extension -eq '.exe' })).Count
        DLLs = @($Artifacts.Where({ $_.Extension -eq '.dll' })).Count
        Scripts = @($Artifacts.Where({ $_.Extension -in @('.ps1', '.bat', '.cmd', '.vbs', '.js') })).Count
        Installers = @($Artifacts.Where({ $_.Extension -in @('.msi', '.msp') })).Count
        Signed = @($Artifacts.Where({ $_.IsSigned -eq $true })).Count
        Unsigned = @($Artifacts.Where({ $_.IsSigned -ne $true })).Count
    }
}

function Format-ArtifactForDisplay {
    <#
    .SYNOPSIS
        Formats an artifact for display in the data grid.
    #>
    param([PSCustomObject]$Artifact)
    
    return [PSCustomObject]@{
        FileName = $Artifact.FileName
        Extension = $Artifact.Extension
        Publisher = if ($Artifact.Publisher) { $Artifact.Publisher } else { '(Unsigned)' }
        ProductName = $Artifact.ProductName
        FileVersion = $Artifact.FileVersion
        FilePath = $Artifact.FilePath
        FileSize = Format-FileSize -Bytes $Artifact.FileSize
        IsSigned = $Artifact.IsSigned
        SHA256Hash = if ($Artifact.SHA256Hash) { $Artifact.SHA256Hash.Substring(0, 16) + '...' } else { '' }
    }
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Formats file size in human-readable format.
    #>
    param([long]$Bytes)
    
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N2} GB" -f ($Bytes / 1GB)
}

function Get-ScanProgressMessage {
    <#
    .SYNOPSIS
        Gets a progress message for scan status display.
    #>
    param(
        [int]$Scanned,
        [int]$Total,
        [string]$CurrentPath = ''
    )
    
    $percent = if ($Total -gt 0) { [math]::Round(($Scanned / $Total) * 100) } else { 0 }
    
    $msg = "Scanned $Scanned of $Total files ($percent%)"
    if ($CurrentPath) {
        $shortPath = if ($CurrentPath.Length -gt 50) { 
            '...' + $CurrentPath.Substring($CurrentPath.Length - 47) 
        } else { 
            $CurrentPath 
        }
        $msg += " - $shortPath"
    }
    
    return $msg
}

function Get-ScanSummary {
    <#
    .SYNOPSIS
        Generates a summary of scan results.
    #>
    param(
        [array]$Artifacts,
        [TimeSpan]$Duration,
        [int]$PathsScanned = 1
    )
    
    $counts = Get-ArtifactCountsByType -Artifacts $Artifacts
    
    return [PSCustomObject]@{
        TotalArtifacts = $counts.Total
        Executables = $counts.Executables
        DLLs = $counts.DLLs
        Scripts = $counts.Scripts
        Installers = $counts.Installers
        SignedCount = $counts.Signed
        UnsignedCount = $counts.Unsigned
        Duration = $Duration
        DurationText = "{0:mm\:ss}" -f $Duration
        PathsScanned = $PathsScanned
    }
}

function Test-ArtifactSelectionValid {
    <#
    .SYNOPSIS
        Validates artifact selection for bulk operations.
    #>
    param(
        [array]$SelectedArtifacts,
        [int]$MinCount = 1
    )
    
    return ($null -ne $SelectedArtifacts -and $SelectedArtifacts.Count -ge $MinCount)
}

function Group-ArtifactsByPublisher {
    <#
    .SYNOPSIS
        Groups artifacts by publisher for summary display.
    #>
    param([array]$Artifacts)
    
    if (-not $Artifacts -or $Artifacts.Count -eq 0) { return @{} }
    
    $grouped = @{}
    
    foreach ($artifact in $Artifacts) {
        $publisher = if ($artifact.Publisher) { $artifact.Publisher } else { '(Unsigned)' }
        
        if (-not $grouped.ContainsKey($publisher)) {
            $grouped[$publisher] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        
        $grouped[$publisher].Add($artifact)
    }
    
    return $grouped
}
