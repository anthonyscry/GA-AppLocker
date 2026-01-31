<#
.SYNOPSIS
    Exports rules to AppLocker XML format.

.DESCRIPTION
    Exports approved rules to XML format compatible with AppLocker GPO import.
    Only exports rules with Approved status by default.

.PARAMETER OutputPath
    Path for the output XML file.

.PARAMETER IncludeAllStatuses
    Include rules regardless of status (not just Approved).

.PARAMETER CollectionTypes
    Specific collections to export. Default is all.

.PARAMETER EnforcementMode
    Enforcement mode for each collection: NotConfigured, AuditOnly, Enabled.
    Default is AuditOnly for safety.

.EXAMPLE
    Export-RulesToXml -OutputPath 'C:\Policies\applocker.xml'

.EXAMPLE
    Export-RulesToXml -OutputPath 'C:\Policies\exe-rules.xml' -CollectionTypes 'Exe' -EnforcementMode Enabled

.OUTPUTS
    [PSCustomObject] Result with Success and path to exported file.
#>
function Export-RulesToXml {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$IncludeAllStatuses,

        [Parameter()]
        [ValidateSet('Exe', 'Dll', 'Msi', 'Script', 'Appx')]
        [string[]]$CollectionTypes = @('Exe', 'Dll', 'Msi', 'Script', 'Appx'),

        [Parameter()]
        [ValidateSet('NotConfigured', 'AuditOnly', 'Enabled')]
        [string]$EnforcementMode = 'AuditOnly'
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # Get rules
        $ruleResult = Get-AllRules -Take 100000
        if (-not $ruleResult.Success) {
            $result.Error = "Failed to retrieve rules: $($ruleResult.Error)"
            return $result
        }

        $rules = $ruleResult.Data

        # Filter by status
        if (-not $IncludeAllStatuses) {
            $rules = $rules | Where-Object { $_.Status -eq 'Approved' }
        }

        if ($rules.Count -eq 0) {
            $result.Error = "No rules to export. Approve some rules first."
            return $result
        }

        # Filter by collection type
        $rules = $rules | Where-Object { $_.CollectionType -in $CollectionTypes }

        if ($rules.Count -eq 0) {
            $result.Error = "No rules found for specified collection types."
            return $result
        }

        Write-RuleLog -Message "Exporting $($rules.Count) rules to XML..."

        # Build XML structure
        $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
"@

        # Group rules by collection type
        $rulesByCollection = $rules | Group-Object CollectionType

        foreach ($collectionType in $CollectionTypes) {
            $collectionRules = $rulesByCollection | Where-Object { $_.Name -eq $collectionType }
            
            $xmlContent += @"

  <RuleCollection Type="$collectionType" EnforcementMode="$EnforcementMode">
"@

            if ($collectionRules -and $collectionRules.Group) {
                foreach ($rule in $collectionRules.Group) {
                    $ruleXml = ConvertTo-AppLockerXmlRule -Rule $rule
                    $xmlContent += $ruleXml
                }
            }

            $xmlContent += @"

  </RuleCollection>
"@
        }

        $xmlContent += @"

</AppLockerPolicy>
"@

        # Ensure directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # Write file
        $xmlContent | Set-Content -Path $OutputPath -Encoding UTF8

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            OutputPath       = $OutputPath
            RuleCount        = $rules.Count
            CollectionTypes  = $CollectionTypes
            EnforcementMode  = $EnforcementMode
            ExportedDate     = Get-Date
        }

        Write-RuleLog -Message "Exported $($rules.Count) rules to: $OutputPath"
    }
    catch {
        $result.Error = "Failed to export rules: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}
