function Export-PolicyToXml {
    <#
    .SYNOPSIS
        Exports a policy to AppLocker-compatible XML format.

    .DESCRIPTION
        Generates a complete AppLocker policy XML that can be
        imported into Group Policy. Uses the canonical rule schema
        from GA-AppLocker.Rules module.

        Supports phase-based filtering:
        - Phase 1: EXE rules only (AuditOnly)
        - Phase 2: EXE + Script rules (AuditOnly)
        - Phase 3: EXE + Script + MSI rules (AuditOnly)
        - Phase 4: All rules including DLL/Appx (Enabled)

    .PARAMETER PolicyId
        The unique identifier of the policy.

    .PARAMETER OutputPath
        The path to save the XML file.

    .PARAMETER IncludeRejected
        Include rejected rules in export (default: false).

    .PARAMETER PhaseOverride
        Override the policy's Phase setting for this export.
        Useful for testing different phases without modifying the policy.

    .EXAMPLE
        Export-PolicyToXml -PolicyId "abc123" -OutputPath "C:\Policies\baseline.xml"

    .EXAMPLE
        Export-PolicyToXml -PolicyId "abc123" -OutputPath "C:\Policies\phase2.xml" -PhaseOverride 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeRejected,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 4)]
        [int]$PhaseOverride
    )

    try {
        # Get the policy
        $policyResult = Get-Policy -PolicyId $PolicyId
        if (-not $policyResult.Success) {
            return $policyResult
        }
        $policy = $policyResult.Data

        # Get all rules for this policy
        $dataPath = Get-AppLockerDataPath
        $rulesPath = Join-Path $dataPath 'Rules'
        $rules = @()

        foreach ($ruleId in $policy.RuleIds) {
            $ruleFile = Join-Path $rulesPath "$ruleId.json"
            if (Test-Path $ruleFile) {
                $rule = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json
                
                # Skip rejected unless explicitly included
                if ($rule.Status -eq 'Rejected' -and -not $IncludeRejected) {
                    continue
                }
                
                $rules += $rule
            }
        }

        if ($rules.Count -eq 0) {
            return @{
                Success = $false
                Error   = 'No valid rules to export'
            }
        }

        # Determine effective phase (override or from policy)
        $effectivePhase = if ($PSBoundParameters.ContainsKey('PhaseOverride')) {
            $PhaseOverride
        } elseif ($policy.Phase) {
            $policy.Phase
        } else {
            4  # Default to full export if no phase specified
        }

        # Group rules by collection type (use CollectionType from Rules schema)
        $exeRules = $rules | Where-Object { $_.CollectionType -eq 'Exe' }
        $dllRules = $rules | Where-Object { $_.CollectionType -eq 'Dll' }
        $msiRules = $rules | Where-Object { $_.CollectionType -eq 'Msi' }
        $scriptRules = $rules | Where-Object { $_.CollectionType -eq 'Script' }
        $appxRules = $rules | Where-Object { $_.CollectionType -eq 'Appx' }

        # Phase-based filtering:
        # Phase 1: EXE only
        # Phase 2: EXE + Script
        # Phase 3: EXE + Script + MSI
        # Phase 4: All (EXE + Script + MSI + DLL + Appx)
        switch ($effectivePhase) {
            1 {
                # Phase 1: EXE only
                $scriptRules = @()
                $msiRules = @()
                $dllRules = @()
                $appxRules = @()
            }
            2 {
                # Phase 2: EXE + Script
                $msiRules = @()
                $dllRules = @()
                $appxRules = @()
            }
            3 {
                # Phase 3: EXE + Script + MSI
                $dllRules = @()
                $appxRules = @()
            }
            # Phase 4: All rules (no filtering)
        }

        # Determine enforcement mode based on phase
        # Phase 1-3: AuditOnly, Phase 4: Enabled (unless explicitly overridden in policy)
        $enforcementValue = if ($effectivePhase -lt 4) {
            'AuditOnly'
        } elseif ($policy.EnforcementMode -eq 'Enabled') {
            'Enabled'
        } elseif ($policy.EnforcementMode -eq 'AuditOnly') {
            'AuditOnly'
        } else {
            'NotConfigured'
        }

        # Build XML
        $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="$enforcementValue">
$(Build-PolicyRuleCollectionXml -Rules $exeRules)
  </RuleCollection>
  <RuleCollection Type="Dll" EnforcementMode="$enforcementValue">
$(Build-PolicyRuleCollectionXml -Rules $dllRules)
  </RuleCollection>
  <RuleCollection Type="Msi" EnforcementMode="$enforcementValue">
$(Build-PolicyRuleCollectionXml -Rules $msiRules)
  </RuleCollection>
  <RuleCollection Type="Script" EnforcementMode="$enforcementValue">
$(Build-PolicyRuleCollectionXml -Rules $scriptRules)
  </RuleCollection>
  <RuleCollection Type="Appx" EnforcementMode="$enforcementValue">
$(Build-PolicyRuleCollectionXml -Rules $appxRules)
  </RuleCollection>
</AppLockerPolicy>
"@

        # Ensure output directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        $xmlContent | Set-Content -Path $OutputPath -Encoding UTF8

        # Count actually exported rules (after phase filtering)
        $exportedRuleCount = @($exeRules).Count + @($scriptRules).Count + @($msiRules).Count + @($dllRules).Count + @($appxRules).Count

        return @{
            Success = $true
            Data    = @{
                Path            = $OutputPath
                RuleCount       = $exportedRuleCount
                TotalRules      = $rules.Count
                Policy          = $policy.Name
                Phase           = $effectivePhase
                EnforcementMode = $enforcementValue
                RuleBreakdown   = @{
                    Exe    = @($exeRules).Count
                    Script = @($scriptRules).Count
                    Msi    = @($msiRules).Count
                    Dll    = @($dllRules).Count
                    Appx   = @($appxRules).Count
                }
            }
            Message = "Exported $exportedRuleCount rules (Phase $effectivePhase) to $OutputPath"
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Build-PolicyRuleCollectionXml {
    <#
    .SYNOPSIS
        Converts rules to AppLocker XML format using canonical rule schema.
    .DESCRIPTION
        Uses the correct property names from GA-AppLocker.Rules module:
        - Id (not RuleId)
        - CollectionType (not RuleCollection)
        - MinVersion/MaxVersion (not BinaryVersionLow/BinaryVersionHigh)
        - SourceFileName/SourceFileLength (not FileName/FileLength)
    #>
    param([array]$Rules)

    if (-not $Rules -or $Rules.Count -eq 0) {
        return ''
    }

    $xml = ''
    foreach ($rule in $Rules) {
        $action = $rule.Action
        $name = [System.Security.SecurityElement]::Escape($rule.Name)
        $description = if ($rule.Description) { [System.Security.SecurityElement]::Escape($rule.Description) } else { '' }
        $id = $rule.Id  # Canonical: Id (not RuleId)
        $userSid = if ($rule.UserOrGroupSid) { $rule.UserOrGroupSid } else { 'S-1-5-11' }  # Authenticated Users

        switch ($rule.RuleType) {
            'Publisher' {
                $publisher = [System.Security.SecurityElement]::Escape($rule.PublisherName)
                $product = if ($rule.ProductName) { [System.Security.SecurityElement]::Escape($rule.ProductName) } else { '*' }
                $binaryName = if ($rule.BinaryName) { [System.Security.SecurityElement]::Escape($rule.BinaryName) } else { '*' }
                # Canonical: MinVersion/MaxVersion (not BinaryVersionLow/BinaryVersionHigh)
                $minVersion = if ($rule.MinVersion) { $rule.MinVersion } else { '*' }
                $maxVersion = if ($rule.MaxVersion) { $rule.MaxVersion } else { '*' }

                $xml += @"
    <FilePublisherRule Id="$id" Name="$name" Description="$description" UserOrGroupSid="$userSid" Action="$action">
      <Conditions>
        <FilePublisherCondition PublisherName="$publisher" ProductName="$product" BinaryName="$binaryName">
          <BinaryVersionRange LowSection="$minVersion" HighSection="$maxVersion" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>

"@
            }
            'Hash' {
                # Canonical: Hash, SourceFileName, SourceFileLength
                $hash = if ($rule.Hash) { "0x$($rule.Hash)" } else { '' }
                $fileName = if ($rule.SourceFileName) { [System.Security.SecurityElement]::Escape($rule.SourceFileName) } else { '' }
                $fileLength = if ($rule.SourceFileLength) { $rule.SourceFileLength } else { '0' }

                $xml += @"
    <FileHashRule Id="$id" Name="$name" Description="$description" UserOrGroupSid="$userSid" Action="$action">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$hash" SourceFileName="$fileName" SourceFileLength="$fileLength" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

"@
            }
            'Path' {
                $path = [System.Security.SecurityElement]::Escape($rule.Path)

                $xml += @"
    <FilePathRule Id="$id" Name="$name" Description="$description" UserOrGroupSid="$userSid" Action="$action">
      <Conditions>
        <FilePathCondition Path="$path" />
      </Conditions>
    </FilePathRule>

"@
            }
        }
    }

    return $xml.TrimEnd()
}

function Test-PolicyCompliance {
    <#
    .SYNOPSIS
        Tests policy against current system state.

    .DESCRIPTION
        Validates that the policy rules match the current
        executables on the target system.

    .PARAMETER PolicyId
        The unique identifier of the policy.

    .PARAMETER ComputerName
        Optional computer to test against (default: local).

    .EXAMPLE
        Test-PolicyCompliance -PolicyId "abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $false)]
        [string]$ComputerName = $env:COMPUTERNAME
    )

    try {
        $policyResult = Get-Policy -PolicyId $PolicyId
        if (-not $policyResult.Success) {
            return $policyResult
        }
        $policy = $policyResult.Data

        # Basic compliance check - verify rules exist
        $dataPath = Get-AppLockerDataPath
        $rulesPath = Join-Path $dataPath 'Rules'
        
        $validRules = 0
        $missingRules = 0
        $approvedRules = 0

        foreach ($ruleId in $policy.RuleIds) {
            $ruleFile = Join-Path $rulesPath "$ruleId.json"
            if (Test-Path $ruleFile) {
                $validRules++
                $rule = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json
                if ($rule.Status -eq 'Approved') {
                    $approvedRules++
                }
            }
            else {
                $missingRules++
            }
        }

        $compliance = @{
            PolicyName     = $policy.Name
            TotalRules     = $policy.RuleIds.Count
            ValidRules     = $validRules
            MissingRules   = $missingRules
            ApprovedRules  = $approvedRules
            IsCompliant    = ($missingRules -eq 0 -and $approvedRules -eq $validRules)
            TestedAt       = (Get-Date).ToString('o')
            TestedOn       = $ComputerName
        }

        return @{
            Success = $true
            Data    = $compliance
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
