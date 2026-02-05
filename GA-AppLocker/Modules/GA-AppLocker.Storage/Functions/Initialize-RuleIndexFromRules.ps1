<#
.SYNOPSIS
    Initializes rule index from individual rule files.

.DESCRIPTION
    Builds rules-index.json by scanning all rule JSON files in Rules directory.
    Creates in-memory hashtables for O(1) lookups by Hash and Publisher.
    Called during module initialization to ensure O(1) performance.

.OUTPUTS
    Result object with Success, Data, and Error properties.

.NOTES
    This function replaces the policy-based index rebuild with rule-file based rebuild.
    Policy index is maintained separately by the Policy module.
#>
function Initialize-RuleIndexFromRules {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    Write-AppLockerLog -Message "Initializing rule index from rule files..." -Level Info

    try {
        $rulesPath = Get-RuleStoragePath
        $indexPath = Join-Path $rulesPath 'rules-index.json'

        $ruleFiles = Get-ChildItem -Path $rulesPath -Filter '*.json' -ErrorAction SilentlyContinue

        if ($ruleFiles.Count -eq 0) {
            Write-AppLockerLog -Message "No rule files found, creating empty index" -Level Info
            $emptyIndex = @{
                Rules = @()
                Hash = @{}
                Publisher = @{}
                PublisherOnly = @{}
            }
            $emptyIndex | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $indexPath -Force

            return @{
                Success = $true
                Data = "Empty index created (0 rules)"
            }
        }

        $rulesList = [System.Collections.Generic.List``1]::new()
        $hashIndex = @{}
        $publisherIndex = @{}
        $publisherOnlyIndex = @{}

        foreach ($ruleFile in $ruleFiles) {
            try {
                $content = Get-Content -Path $ruleFile.FullName -Raw -ErrorAction Stop
                $rule = $content | ConvertFrom-Json -ErrorAction Stop

                if ($rule) {
                    $rulesList.Add($rule)

                    if ($rule.Hash) {
                        $hashKey = $rule.Hash.ToUpper()
                        $null = $hashIndex[$hashKey]
                    }

                    if ($rule.PublisherName) {
                        $pubKey = "$($rule.PublisherName.ToLower())|$($rule.ProductName.ToLower())"
                        $null = $publisherIndex[$pubKey]
                    }

                    if ($rule.PublisherName -and -not $rule.ProductName) {
                        $pubOnlyKey = $rule.PublisherName.ToLower()
                        $null = $publisherOnlyIndex[$pubOnlyKey]
                    }
                }
            }
            catch {
                Write-AppLockerLog -Level Warning -Message "Failed to load rule file: $($ruleFile.Name)"
            }
        }

        $jsonIndex = [PSCustomObject]@{
            Rules = @($rulesList)
            Hash = $hashIndex
            Publisher = $publisherIndex
            PublisherOnly = $publisherOnlyIndex
        }

        [System.IO.File]::WriteAllText($indexPath, ($jsonIndex | ConvertTo-Json -Depth 5 -Compress))

        Write-AppLockerLog -Level Info -Message "Rule index built from $($rulesList.Count) rule files"
        Write-AppLockerLog -Level Info -Message "Hash index: $($hashIndex.Count) entries"
        Write-AppLockerLog -Level Info -Message "Publisher index: $($publisherIndex.Count) entries"
        Write-AppLockerLog -Level Info -Message "Publisher-only index: $($publisherOnlyIndex.Count) entries"

        return @{
            Success = $true
            Data = "Index rebuilt from $($rulesList.Count) rules"
        }
    }
    catch {
        Write-AppLockerLog -Level Error -Message "Failed to initialize rule index: $($_.Exception.Message)"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
