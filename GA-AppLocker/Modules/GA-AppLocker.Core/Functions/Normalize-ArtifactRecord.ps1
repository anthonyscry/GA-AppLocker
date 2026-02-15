function Normalize-ArtifactRecord {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Artifact
    )

    $normalized = [ordered]@{}
    foreach ($property in $Artifact.PSObject.Properties) {
        $normalized[$property.Name] = $property.Value
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
    if ($normalized.Contains('SizeBytes')) {
        $rawSizeBytes = $normalized['SizeBytes']
    }

    if ($null -eq $rawSizeBytes -or ([string]$rawSizeBytes).Trim() -eq '') {
        if ($normalized.Contains('FileSize')) {
            $rawSizeBytes = $normalized['FileSize']
        }
    }

    if ($null -ne $rawSizeBytes -and ([string]$rawSizeBytes).Trim() -ne '') {
        try {
            $normalized['SizeBytes'] = [int64]$rawSizeBytes
        }
        catch {
            $normalized['SizeBytes'] = $rawSizeBytes
        }
    }

    return [PSCustomObject]$normalized
}
