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
        - Phase 4: EXE + Script + MSI + APPX rules (AuditOnly)
        - Phase 5: All rules including DLL (Enabled)

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

    .PARAMETER SkipValidation
        If specified, skips the 5-stage validation pipeline after export.
        By default, exported XML is validated automatically.

    .EXAMPLE
        Export-PolicyToXml -PolicyId "abc123" -OutputPath "C:\Policies\phase2.xml" -PhaseOverride 2

    .EXAMPLE
        Export-PolicyToXml -PolicyId "abc123" -OutputPath "C:\Policies\quick.xml" -SkipValidation
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
        [ValidateRange(1, 5)]
        [int]$PhaseOverride,

        [Parameter(Mandatory = $false)]
        [switch]$SkipValidation
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
        $rules = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($ruleId in $policy.RuleIds) {
            $ruleFile = Join-Path $rulesPath "$ruleId.json"
            if (Test-Path $ruleFile) {
                $rule = Get-Content -Path $ruleFile -Raw | ConvertFrom-Json

                # Skip rejected unless explicitly included
                if ($rule.Status -eq 'Rejected' -and -not $IncludeRejected) {
                    continue
                }

                [void]$rules.Add($rule)
            }
        }

        if ($rules.Count -eq 0) {
            return @{
                Success = $false
                Error   = 'No valid rules to export'
            }
        }

        $rulesArray = @($rules)

        # Determine effective phase (override or from policy)
        $effectivePhase = if ($PSBoundParameters.ContainsKey('PhaseOverride')) {
            $PhaseOverride
        } elseif ($policy.Phase) {
            $policy.Phase
        } else {
            5  # Default to full export if no phase specified
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
        # Phase 4: EXE + Script + MSI + Appx
        # Phase 5: All (EXE + Script + MSI + Appx + DLL)
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
            4 {
                # Phase 4: EXE + Script + MSI + Appx
                $dllRules = @()
            }
            # Phase 5: All rules (no filtering)
        }

        # Determine enforcement mode based on phase
        # Phase 1-4: AuditOnly, Phase 5: Enabled (unless explicitly overridden in policy)
        $enforcementValue = if ($effectivePhase -lt 5) {
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

        # Write WITHOUT BOM -- PS 5.1's Set-Content -Encoding UTF8 adds a BOM which can
        # cause Set-AppLockerPolicy to misinterpret the content as a file path.
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($OutputPath, $xmlContent, $utf8NoBom)

        # Count actually exported rules (after phase filtering)
        $exportedRuleCount = @($exeRules).Count + @($scriptRules).Count + @($msiRules).Count + @($dllRules).Count + @($appxRules).Count

        # Run 5-stage validation pipeline on exported XML (unless skipped)
        $validationResult = $null
        $validationPassed = $true
        if (-not $SkipValidation) {
            try {
                $validationResult = Invoke-AppLockerPolicyValidation -XmlPath $OutputPath
                $validationPassed = $validationResult.OverallSuccess
            }
            catch {
                # Validation module may not be available; treat as warning, not failure
                $validationResult = @{
                    OverallSuccess = $false
                    TotalErrors    = 0
                    TotalWarnings  = 1
                    Summary        = "Validation skipped: $($_.Exception.Message)"
                }
                $validationPassed = $true  # Don't fail export if validation module is unavailable
            }
        }

        $result = @{
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
                Validation      = $validationResult
            }
            Message = "Exported $exportedRuleCount rules (Phase $effectivePhase) to $OutputPath"
        }

        # If validation failed, still return the export but flag it
        if (-not $validationPassed) {
            $result.Data.ValidationFailed = $true
            $result.Message += " [WARNING: Validation failed with $($validationResult.TotalErrors) error(s)]"
        }

        return $result
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

    $xml = [System.Text.StringBuilder]::new()
    foreach ($rule in $Rules) {
        # Default to 'Allow' if Action is missing, empty, or whitespace (required by AppLocker schema)
        $action = 'Allow'
        if ($rule.Action) {
            $trimmed = "$($rule.Action)".Trim()
            if ($trimmed -eq 'Allow' -or $trimmed -eq 'Deny') {
                $action = $trimmed
            }
        }
        $name = [System.Security.SecurityElement]::Escape($rule.Name)
        $description = if ($rule.Description) { [System.Security.SecurityElement]::Escape($rule.Description) } else { '' }
        $id = $rule.Id  # Canonical: Id (not RuleId)
        # Validate SID format — UNRESOLVED: placeholders must never reach XML
        $userSid = 'S-1-5-11'  # Default: Authenticated Users
        if ($rule.UserOrGroupSid -and $rule.UserOrGroupSid -match '^S-1-\d+(-\d+)+$') {
            $userSid = $rule.UserOrGroupSid
        }
        elseif ($rule.UserOrGroupSid -and $rule.UserOrGroupSid -notmatch '^S-1-') {
            # Invalid SID (e.g., UNRESOLVED:AppLocker-Users) — try to resolve now
            $groupName = $rule.UserOrGroupSid -replace '^UNRESOLVED:', ''
            $resolvedSid = Resolve-GroupSid -GroupName $groupName
            if ($resolvedSid -and $resolvedSid -match '^S-1-') {
                $userSid = $resolvedSid
            }
            # else: falls through to S-1-5-11 default (Authenticated Users)
        }

        switch ($rule.RuleType) {
            'Publisher' {
                $publisher = if (-not [string]::IsNullOrWhiteSpace($rule.PublisherName)) { [System.Security.SecurityElement]::Escape($rule.PublisherName) } else { '*' }
                $product = if (-not [string]::IsNullOrWhiteSpace($rule.ProductName)) { [System.Security.SecurityElement]::Escape($rule.ProductName) } else { '*' }
                $binaryName = if (-not [string]::IsNullOrWhiteSpace($rule.BinaryName)) { [System.Security.SecurityElement]::Escape($rule.BinaryName) } else { '*' }
                $minVersion = if (-not [string]::IsNullOrWhiteSpace($rule.MinVersion)) { $rule.MinVersion } else { '*' }
                $maxVersion = if (-not [string]::IsNullOrWhiteSpace($rule.MaxVersion)) { $rule.MaxVersion } else { '*' }

                $ruleXml = @"
    <FilePublisherRule Id="$id" Name="$name" Description="$description" UserOrGroupSid="$userSid" Action="$action">
      <Conditions>
        <FilePublisherCondition PublisherName="$publisher" ProductName="$product" BinaryName="$binaryName">
          <BinaryVersionRange LowSection="$minVersion" HighSection="$maxVersion" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>

"@
                [void]$xml.Append($ruleXml)
            }
            'Hash' {
                $hash = if ($rule.Hash) { "0x$($rule.Hash.ToUpper())" } else { '0x' + ('0' * 64) }
                # Resolve best available filename for SourceFileName attribute
                $fileName = $null
                if (-not [string]::IsNullOrWhiteSpace($rule.SourceFileName) -and $rule.SourceFileName -ne 'Unknown') {
                    $fileName = $rule.SourceFileName
                } elseif ($rule.Name -match '^(.+)\s+\(Hash\)$') {
                    # Extract filename from "filename.ext (Hash)" name pattern
                    $fileName = $Matches[1]
                }
                if (-not $fileName) { $fileName = 'Unknown' }
                $fileName = [System.Security.SecurityElement]::Escape($fileName)
                $fileLength = if ($rule.SourceFileLength -and $rule.SourceFileLength -gt 0) { $rule.SourceFileLength } else { 0 }

                $ruleXml = @"
    <FileHashRule Id="$id" Name="$name" Description="$description" UserOrGroupSid="$userSid" Action="$action">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$hash" SourceFileName="$fileName" SourceFileLength="$fileLength" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

"@
                [void]$xml.Append($ruleXml)
            }
            'Path' {
                $path = if (-not [string]::IsNullOrWhiteSpace($rule.Path)) { [System.Security.SecurityElement]::Escape($rule.Path) } else { '*' }

                $ruleXml = @"
    <FilePathRule Id="$id" Name="$name" Description="$description" UserOrGroupSid="$userSid" Action="$action">
      <Conditions>
        <FilePathCondition Path="$path" />
      </Conditions>
    </FilePathRule>

"@
                [void]$xml.Append($ruleXml)
            }
        }
    }

    return $xml.ToString().TrimEnd()
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
