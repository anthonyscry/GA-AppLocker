<#
.SYNOPSIS
    Imports rules from an AppLocker XML policy file.

.DESCRIPTION
    Parses an AppLocker XML policy file and imports rules into the GA-AppLocker database.
    Supports Publisher, Hash, and Path rules from Exe, Msi, Script, and Dll collections.
    Uses batch save for high performance (single disk write + single index rebuild).

.PARAMETER Path
    Path to the AppLocker XML file to import.

.PARAMETER Status
    Initial status for imported rules. Defaults to 'Pending'.

.PARAMETER SkipDuplicates
    If specified, skips rules that already exist (by hash or publisher+product match).

.EXAMPLE
    Import-RulesFromXml -Path 'C:\Policies\AppLocker.xml'
    Imports all rules from the XML file with 'Pending' status.

.EXAMPLE
    Import-RulesFromXml -Path 'C:\Policies\AppLocker.xml' -Status 'Approved' -SkipDuplicates
    Imports rules as 'Approved' and skips any duplicates.
#>
function Import-RulesFromXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path,
        
        [Parameter()]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status = 'Pending',
        
        [Parameter()]
        [switch]$SkipDuplicates
    )
    
    try {
        # Load XML
        [xml]$xml = Get-Content -Path $Path -Raw -ErrorAction Stop
        
        $importedRules = [System.Collections.Generic.List[PSCustomObject]]::new()
        $skippedCount = 0
        $errors = @()
        
        # Build duplicate index if needed
        $existingHashes = @{}
        $existingPublishers = @{}
        
        if ($SkipDuplicates) {
            $allRules = Get-AllRules -Take 100000
            if ($allRules.Success -and $allRules.Data) {
                foreach ($rule in $allRules.Data) {
                    if ($rule.SHA256Hash -or $rule.HashValue) {
                        $hash = if ($rule.SHA256Hash) { $rule.SHA256Hash } else { $rule.HashValue }
                        $existingHashes[$hash.ToUpper()] = $true
                    }
                    if ($rule.PublisherName -and $rule.ProductName) {
                        $key = "$($rule.PublisherName)|$($rule.ProductName)".ToLower()
                        $existingPublishers[$key] = $true
                    }
                }
            }
        }
        
        # Find AppLocker policy element
        $appLockerPolicy = $xml.SelectSingleNode('//AppLockerPolicy')
        if (-not $appLockerPolicy) {
            return @{
                Success = $false
                Error = "Not a valid AppLocker XML file - missing AppLockerPolicy element"
                Data = @()
            }
        }
        
        $fileName = [System.IO.Path]::GetFileName($Path)
        
        # Process each rule collection (Exe, Msi, Script, Dll, Appx)
        $ruleCollections = $appLockerPolicy.SelectNodes('RuleCollection')
        
        foreach ($collection in $ruleCollections) {
            $collectionType = $collection.Type
            
            # Process FilePublisherRule (Publisher rules)
            $publisherRules = $collection.SelectNodes('FilePublisherRule')
            foreach ($rule in $publisherRules) {
                try {
                    $conditions = $rule.SelectSingleNode('Conditions/FilePublisherCondition')
                    if ($conditions) {
                        $publisherName = $conditions.PublisherName
                        $productName = $conditions.ProductName

                        # Check for duplicate
                        if ($SkipDuplicates -and $publisherName -and $productName) {
                            $key = "$publisherName|$productName".ToLower()
                            if ($existingPublishers.ContainsKey($key)) {
                                $skippedCount++
                                continue
                            }
                        }

                        # Default empty values to prevent parameter binding errors
                        $action = if (-not [string]::IsNullOrWhiteSpace($rule.Action)) { $rule.Action } else { 'Allow' }
                        $userOrGroupSid = if (-not [string]::IsNullOrWhiteSpace($rule.UserOrGroupSid)) { $rule.UserOrGroupSid } else { 'S-1-1-0' }
                        $binaryName = if (-not [string]::IsNullOrWhiteSpace($conditions.BinaryName)) { $conditions.BinaryName } else { '*' }
                        if ([string]::IsNullOrWhiteSpace($productName)) { $productName = '*' }

                        # Get version info - default empty to '*'
                        $binaryVersionRange = $conditions.SelectSingleNode('BinaryVersionRange')
                        $minVersion = '*'
                        $maxVersion = '*'
                        if ($binaryVersionRange) {
                            if (-not [string]::IsNullOrWhiteSpace($binaryVersionRange.LowSection))  { $minVersion = $binaryVersionRange.LowSection }
                            if (-not [string]::IsNullOrWhiteSpace($binaryVersionRange.HighSection)) { $maxVersion = $binaryVersionRange.HighSection }
                        }

                        # Create rule in memory only (no -Save)
                        $newRule = New-PublisherRule -PublisherName $publisherName `
                            -ProductName $productName `
                            -BinaryName $binaryName `
                            -MinVersion $minVersion `
                            -MaxVersion $maxVersion `
                            -Action $action `
                            -UserOrGroupSid $userOrGroupSid `
                            -CollectionType $collectionType `
                            -Status $Status `
                            -Description "Imported from $fileName"

                        if ($newRule.Success) {
                            $importedRules.Add($newRule.Data)
                        }
                    }
                }
                catch {
                    $errors += "Publisher rule: $($_.Exception.Message)"
                }
            }
            
            # Process FileHashRule (Hash rules)
            $hashRules = $collection.SelectNodes('FileHashRule')
            foreach ($rule in $hashRules) {
                try {
                    $conditions = $rule.SelectNodes('Conditions/FileHashCondition/FileHash')
                    foreach ($fileHash in $conditions) {
                        $hash = $fileHash.Data
                        $sourceFileName = $fileHash.SourceFileName
                        $sourceFileLength = $fileHash.SourceFileLength

                        # Strip 0x prefix if present (New-HashRule expects raw hex)
                        if ($hash) { $hash = $hash -replace '^0x', '' }

                        # Check for duplicate
                        if ($SkipDuplicates -and $hash) {
                            if ($existingHashes.ContainsKey($hash.ToUpper())) {
                                $skippedCount++
                                continue
                            }
                        }

                        # Default empty values to prevent parameter binding errors
                        $action = if (-not [string]::IsNullOrWhiteSpace($rule.Action)) { $rule.Action } else { 'Allow' }
                        $userOrGroupSid = if (-not [string]::IsNullOrWhiteSpace($rule.UserOrGroupSid)) { $rule.UserOrGroupSid } else { 'S-1-1-0' }
                        if ([string]::IsNullOrWhiteSpace($sourceFileName)) { $sourceFileName = $rule.Name; if ([string]::IsNullOrWhiteSpace($sourceFileName)) { $sourceFileName = 'Unknown' } }
                        $fileLengthInt = 0
                        if ($sourceFileLength -and $sourceFileLength -match '^\d+$') { $fileLengthInt = [int64]$sourceFileLength }

                        # Create rule in memory only (no -Save)
                        $newRule = New-HashRule -Hash $hash `
                            -SourceFileName $sourceFileName `
                            -SourceFileLength $fileLengthInt `
                            -Action $action `
                            -UserOrGroupSid $userOrGroupSid `
                            -CollectionType $collectionType `
                            -Status $Status `
                            -Description "Imported from $fileName"

                        if ($newRule.Success) {
                            $importedRules.Add($newRule.Data)
                        }
                    }
                }
                catch {
                    $errors += "Hash rule: $($_.Exception.Message)"
                }
            }
            
            # Process FilePathRule (Path rules)
            $pathRules = $collection.SelectNodes('FilePathRule')
            foreach ($rule in $pathRules) {
                try {
                    $conditions = $rule.SelectSingleNode('Conditions/FilePathCondition')
                    if ($conditions) {
                        $rulePath = $conditions.Path
                        $action = if (-not [string]::IsNullOrWhiteSpace($rule.Action)) { $rule.Action } else { 'Allow' }
                        $userOrGroupSid = if (-not [string]::IsNullOrWhiteSpace($rule.UserOrGroupSid)) { $rule.UserOrGroupSid } else { 'S-1-1-0' }

                        # Create rule in memory only (no -Save)
                        $newRule = New-PathRule -Path $rulePath `
                            -Action $action `
                            -UserOrGroupSid $userOrGroupSid `
                            -CollectionType $collectionType `
                            -Status $Status `
                            -Description "Imported from $fileName"
                        
                        if ($newRule.Success) {
                            $importedRules.Add($newRule.Data)
                        }
                    }
                }
                catch {
                    $errors += "Path rule: $($_.Exception.Message)"
                }
            }
        }
        
        # Batch save all rules at once (single disk write + single index rebuild)
        if ($importedRules.Count -gt 0) {
            $saveResult = Save-RulesBulk -Rules $importedRules.ToArray() -UpdateIndex
            if (-not $saveResult.Success) {
                return @{
                    Success = $false
                    Error = "Batch save failed: $($saveResult.Error)"
                    Data = @()
                }
            }
        }
        
        $message = "Imported $($importedRules.Count) rules from $fileName"
        if ($skippedCount -gt 0) {
            $message += " ($skippedCount duplicates skipped)"
        }
        
        try { Write-AppLockerLog -Message $message -Level 'INFO' } catch { }
        
        return @{
            Success = $true
            Data = $importedRules
            Message = $message
            SkippedCount = $skippedCount
            Errors = $errors
        }
    }
    catch {
        try { Write-AppLockerLog -Message "Failed to import rules from XML: $($_.Exception.Message)" -Level 'ERROR' } catch { }
        return @{
            Success = $false
            Error = $_.Exception.Message
            Data = @()
        }
    }
}

Export-ModuleMember -Function Import-RulesFromXml
