function Test-AppLockerRuleConditions {
    <#
    .SYNOPSIS
        Validates rule conditions for all rule types.

    .DESCRIPTION
        Validates:
        - Publisher rules: PublisherName non-empty, BinaryVersionRange format
        - Hash rules: SHA256 format (0x prefix + 64 hex chars), Type=SHA256, SourceFileName/Length
        - Path rules: Valid path format, warns about user-writable locations

    .PARAMETER XmlPath
        Path to the AppLocker policy XML file.

    .OUTPUTS
        [PSCustomObject] with Success, Errors, Warnings, RuleStats properties

    .EXAMPLE
        Test-AppLockerRuleConditions -XmlPath "C:\Policies\baseline.xml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$XmlPath
    )

    $result = [PSCustomObject]@{
        Success  = $false
        Errors   = [System.Collections.ArrayList]::new()
        Warnings = [System.Collections.ArrayList]::new()
        RuleStats = [PSCustomObject]@{
            Publisher = 0
            Hash      = 0
            Path      = 0
        }
    }

    $sha256Pattern = '^0x[0-9A-Fa-f]{64}$|^[0-9A-Fa-f]{64}$'

    try {
        [xml]$policy = Get-Content $XmlPath -Raw

        foreach ($collection in $policy.AppLockerPolicy.RuleCollection) {
            $collectionType = $collection.Type

            # Validate Publisher Rules
            foreach ($rule in $collection.FilePublisherRule) {
                if (-not $rule) { continue }
                $result.RuleStats.Publisher++

                $name = $rule.Name
                $conditions = $rule.Conditions.FilePublisherCondition

                if (-not $conditions) {
                    [void]$result.Errors.Add("[$collectionType] Publisher rule '$name' missing FilePublisherCondition")
                    continue
                }

                foreach ($condition in $conditions) {
                    # Validate PublisherName
                    if ([string]::IsNullOrWhiteSpace($condition.PublisherName)) {
                        [void]$result.Errors.Add("[$collectionType] Publisher rule '$name' has empty PublisherName")
                    }
                    elseif ($condition.PublisherName -match '\b[OLS]=\w+') {
                        [void]$result.Errors.Add("[$collectionType] Publisher rule '$name' contains OID attributes (O=, L=, S=, C=) which cause import failures: $($condition.PublisherName)")
                    }

                    # Validate BinaryVersionRange
                    $versionRange = $condition.BinaryVersionRange
                    if ($versionRange) {
                        $lowVersion = $versionRange.LowSection
                        $highVersion = $versionRange.HighSection

                        if ($lowVersion -and $lowVersion -notmatch '^\d+(\.\d+)*$' -and $lowVersion -ne '*') {
                            [void]$result.Errors.Add("[$collectionType] Rule '$name' has invalid LowSection version: $lowVersion")
                        }
                        if ($highVersion -and $highVersion -notmatch '^\d+(\.\d+)*$' -and $highVersion -ne '*') {
                            [void]$result.Errors.Add("[$collectionType] Rule '$name' has invalid HighSection version: $highVersion")
                        }
                    }
                }
            }

            # Validate Hash Rules
            foreach ($rule in $collection.FileHashRule) {
                if (-not $rule) { continue }
                $result.RuleStats.Hash++

                $name = $rule.Name
                $conditions = $rule.Conditions.FileHashCondition

                if (-not $conditions) {
                    [void]$result.Errors.Add("[$collectionType] Hash rule '$name' missing FileHashCondition")
                    continue
                }

                foreach ($condition in $conditions) {
                    $fileHash = $condition.FileHash

                    if (-not $fileHash) {
                        [void]$result.Errors.Add("[$collectionType] Hash rule '$name' missing FileHash element")
                        continue
                    }

                    # Validate hash format
                    $hash = $fileHash.Data
                    if ($hash -notmatch $sha256Pattern) {
                        [void]$result.Errors.Add("[$collectionType] Hash rule '$name' has invalid SHA256 hash: $hash")
                    }

                    # Validate Type attribute
                    $hashType = $fileHash.Type
                    if ($hashType -ne 'SHA256') {
                        [void]$result.Errors.Add("[$collectionType] Hash rule '$name' must have Type='SHA256', found: $hashType")
                    }

                    # Validate SourceFileName
                    if ([string]::IsNullOrWhiteSpace($fileHash.SourceFileName)) {
                        [void]$result.Warnings.Add("[$collectionType] Hash rule '$name' missing SourceFileName")
                    }

                    # Validate SourceFileLength
                    $length = $fileHash.SourceFileLength
                    if ($length -and $length -notmatch '^\d+$') {
                        [void]$result.Errors.Add("[$collectionType] Hash rule '$name' has invalid SourceFileLength: $length")
                    }
                }
            }

            # Validate Path Rules
            foreach ($rule in $collection.FilePathRule) {
                if (-not $rule) { continue }
                $result.RuleStats.Path++

                $name = $rule.Name
                $conditions = $rule.Conditions.FilePathCondition

                if (-not $conditions) {
                    [void]$result.Errors.Add("[$collectionType] Path rule '$name' missing FilePathCondition")
                    continue
                }

                foreach ($condition in $conditions) {
                    $path = $condition.Path

                    if ([string]::IsNullOrWhiteSpace($path)) {
                        [void]$result.Errors.Add("[$collectionType] Path rule '$name' has empty Path")
                        continue
                    }

                    # Check for invalid characters
                    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
                    foreach ($char in $invalidChars) {
                        if ($path.Contains($char)) {
                            [void]$result.Errors.Add("[$collectionType] Path rule '$name' contains invalid character in path")
                            break
                        }
                    }

                    # Warn about user-writable paths (check both env var and literal patterns)
                    $userWritablePaths = @(
                        '*\Users\*\Downloads\*', '*\Users\*\Desktop\*',
                        '*\Users\*\AppData\Local\Temp\*', '*\Windows\Temp\*',
                        '*\Users\Public\*', '*\Users\*\Documents\*',
                        '*\PerfLogs\*'
                    )
                    foreach ($uwp in $userWritablePaths) {
                        if ($path -like $uwp) {
                            [void]$result.Warnings.Add("[$collectionType] Path rule '$name' includes user-writable location: $path")
                        }
                    }
                }
            }
        }

        $result.Success = ($result.Errors.Count -eq 0)
    }
    catch {
        [void]$result.Errors.Add("Rule condition validation failed: $($_.Exception.Message)")
    }

    return $result
}
