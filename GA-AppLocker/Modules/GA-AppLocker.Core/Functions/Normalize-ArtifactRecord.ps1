function Normalize-ArtifactRecord {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSObject]$Artifact
    )

    $normalized = [ordered]@{}
    if ($Artifact -is [System.Collections.IDictionary]) {
        foreach ($entry in $Artifact.GetEnumerator()) {
            $normalized[[string]$entry.Key] = $entry.Value
        }
    }
    else {
        foreach ($property in $Artifact.PSObject.Properties) {
            $normalized[$property.Name] = $property.Value
        }
    }

    $isSigned = $false
    $rawIsSigned = $null
    if ($normalized.Contains('IsSigned')) {
        $rawIsSigned = $normalized['IsSigned']
    }

    if ($rawIsSigned -is [bool]) {
        $isSigned = $rawIsSigned
    }
    elseif ($rawIsSigned -is [string]) {
        $isSigned = $rawIsSigned.Trim() -match '^(?i:true|1)$'
    }
    elseif ($null -ne $rawIsSigned) {
        try {
            $isSigned = [int64]$rawIsSigned -eq 1
        }
        catch {
            $isSigned = $false
        }
    }

    $normalized['IsSigned'] = $isSigned

    $rawSizeBytes = $null
    $rawFileSize = $null
    $hasSizeBytes = $normalized.Contains('SizeBytes')
    $hasFileSize = $normalized.Contains('FileSize')

    if ($hasSizeBytes) {
        $rawSizeBytes = $normalized['SizeBytes']
    }

    if ($hasFileSize) {
        $rawFileSize = $normalized['FileSize']
    }

    $parsedSizeBytes = $null
    $sizeParsed = $false

    if ($null -ne $rawSizeBytes -and ([string]$rawSizeBytes).Trim() -ne '') {
        try {
            $parsedSizeBytes = [int64]$rawSizeBytes
            $sizeParsed = $true
        }
        catch {
            $sizeParsed = $false
        }
    }

    if (-not $sizeParsed -and $null -ne $rawFileSize -and ([string]$rawFileSize).Trim() -ne '') {
        try {
            $parsedSizeBytes = [int64]$rawFileSize
            $sizeParsed = $true
        }
        catch {
            $sizeParsed = $false
        }
    }

    if ($sizeParsed) {
        $normalized['SizeBytes'] = $parsedSizeBytes
    }
    elseif ($hasSizeBytes) {
        $normalized['SizeBytes'] = $rawSizeBytes
    }
    elseif ($hasFileSize) {
        $normalized['SizeBytes'] = $rawFileSize
    }
    else {
        $normalized['SizeBytes'] = $null
    }

    return [PSCustomObject]$normalized
}
