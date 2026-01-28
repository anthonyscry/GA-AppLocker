<#
.SYNOPSIS
    Imports rules from an AppLocker XML policy file.

.DESCRIPTION
    Parses an AppLocker XML policy file and imports rules into the GA-AppLocker database.
    Supports Publisher, Hash, and Path rules from Exe, Msi, Script, and Dll collections.

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
        
        $importedRules = @()
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
                        
                        $action = $rule.Action
                        $userOrGroupSid = $rule.UserOrGroupSid
                        
                        # Get version info
                        $binaryVersionRange = $conditions.SelectSingleNode('BinaryVersionRange')
                        $minVersion = if ($binaryVersionRange) { $binaryVersionRange.LowSection } else { '*' }
                        $maxVersion = if ($binaryVersionRange) { $binaryVersionRange.HighSection } else { '*' }
                        
                        $newRule = New-PublisherRule -PublisherName $publisherName `
                            -ProductName $productName `
                            -BinaryName ($conditions.BinaryName) `
                            -MinimumVersion $minVersion `
                            -MaximumVersion $maxVersion `
                            -Action $action `
                            -UserOrGroupSid $userOrGroupSid `
                            -CollectionType $collectionType `
                            -Description "Imported from $([System.IO.Path]::GetFileName($Path))" `
                            -Save
                        
                        if ($newRule.Success) {
                            # Set initial status if not Pending
                            if ($Status -ne 'Pending' -and $newRule.Data.Id) {
                                Set-RuleStatus -Id $newRule.Data.Id -Status $Status | Out-Null
                            }
                            $importedRules += $newRule.Data
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
                        $hashType = $fileHash.Type
                        $sourceFileName = $fileHash.SourceFileName
                        $sourceFileLength = $fileHash.SourceFileLength
                        
                        # Check for duplicate
                        if ($SkipDuplicates -and $hash) {
                            if ($existingHashes.ContainsKey($hash.ToUpper())) {
                                $skippedCount++
                                continue
                            }
                        }
                        
                        $action = $rule.Action
                        $userOrGroupSid = $rule.UserOrGroupSid
                        
                        $newRule = New-HashRule -Hash $hash `
                            -HashType $hashType `
                            -SourceFileName $sourceFileName `
                            -SourceFileLength $sourceFileLength `
                            -Action $action `
                            -UserOrGroupSid $userOrGroupSid `
                            -CollectionType $collectionType `
                            -Description "Imported from $([System.IO.Path]::GetFileName($Path))" `
                            -Save
                        
                        if ($newRule.Success) {
                            if ($Status -ne 'Pending' -and $newRule.Data.Id) {
                                Set-RuleStatus -Id $newRule.Data.Id -Status $Status | Out-Null
                            }
                            $importedRules += $newRule.Data
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
                        $path = $conditions.Path
                        $action = $rule.Action
                        $userOrGroupSid = $rule.UserOrGroupSid
                        
                        $newRule = New-PathRule -Path $path `
                            -Action $action `
                            -UserOrGroupSid $userOrGroupSid `
                            -CollectionType $collectionType `
                            -Description "Imported from $([System.IO.Path]::GetFileName($Path))" `
                            -Save
                        
                        if ($newRule.Success) {
                            if ($Status -ne 'Pending' -and $newRule.Data.Id) {
                                Set-RuleStatus -Id $newRule.Data.Id -Status $Status | Out-Null
                            }
                            $importedRules += $newRule.Data
                        }
                    }
                }
                catch {
                    $errors += "Path rule: $($_.Exception.Message)"
                }
            }
        }
        
        $message = "Imported $($importedRules.Count) rules from $([System.IO.Path]::GetFileName($Path))"
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
