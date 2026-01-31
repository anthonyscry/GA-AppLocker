<#
.SYNOPSIS
    Functions for working with pre-built AppLocker rule templates.

.DESCRIPTION
    Provides functions to import rule templates and create rules from them.
    Templates are stored in Data/RuleTemplates.json and cover common
    enterprise applications like Microsoft Office, browsers, etc.
#>

<#
.SYNOPSIS
    Gets all available rule templates.

.DESCRIPTION
    Loads and returns all rule templates from the RuleTemplates.json file.
    Each template contains pre-configured rules for common applications.

.PARAMETER TemplateName
    Optional. Filter to return only a specific template by name.

.EXAMPLE
    Get-RuleTemplates
    Returns all available rule templates.

.EXAMPLE
    Get-RuleTemplates -TemplateName 'Microsoft Office'
    Returns only the Microsoft Office template.

.OUTPUTS
    [PSCustomObject] Template data with Success, Data, and Error properties.
#>
function Get-RuleTemplates {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$TemplateName
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # $PSScriptRoot is the Functions folder, go up one level to module root
        $modulePath = Split-Path -Parent $PSScriptRoot
        $dataPath = Join-Path $modulePath 'Data'
        $templatePath = Join-Path $dataPath 'RuleTemplates.json'

        # Validate path stays within expected module boundaries
        $normalizedPath = [System.IO.Path]::GetFullPath($templatePath)
        $normalizedDataPath = [System.IO.Path]::GetFullPath($dataPath)
        if (-not $normalizedPath.StartsWith($normalizedDataPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Invalid template path: path traversal detected"
        }

        if (-not (Test-Path $templatePath)) {
            throw "Rule templates file not found: $templatePath"
        }

        $templateContent = Get-Content -Path $templatePath -Raw -ErrorAction Stop
        $templates = $templateContent | ConvertFrom-Json

        # Remove metadata fields
        $templateNames = $templates.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' }

        if ($TemplateName) {
            if ($templateNames -contains $TemplateName) {
                $selectedTemplate = $templates.$TemplateName
                $result.Data = [PSCustomObject]@{
                    Name        = $TemplateName
                    Description = $selectedTemplate.Description
                    Rules       = $selectedTemplate.Rules
                    RuleCount   = $selectedTemplate.Rules.Count
                }
            }
            else {
                throw "Template '$TemplateName' not found. Available templates: $($templateNames -join ', ')"
            }
        }
        else {
            # Return all template names with descriptions
            $templateList = @()
            foreach ($name in $templateNames) {
                $template = $templates.$name
                $templateList += [PSCustomObject]@{
                    Name        = $name
                    Description = $template.Description
                    RuleCount   = $template.Rules.Count
                }
            }
            $result.Data = $templateList
        }

        $result.Success = $true
        Write-RuleLog -Message "Retrieved $(if ($TemplateName) { 'template: ' + $TemplateName } else { $templateNames.Count.ToString() + ' templates' })"
    }
    catch {
        $result.Error = "Failed to get rule templates: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}

<#
.SYNOPSIS
    Creates AppLocker rules from a template.

.DESCRIPTION
    Creates rules from a named template. Templates provide pre-configured
    rules for common enterprise applications.

.PARAMETER TemplateName
    Name of the template to use (e.g., 'Microsoft Office', 'Google Chrome').

.PARAMETER UserOrGroupSid
    Optional. Override the default user/group SID for all rules.
    Default is Everyone (S-1-1-0).

.PARAMETER Status
    Status for created rules: Pending, Approved, Rejected, Review.
    Default is Pending.

.PARAMETER Save
    If specified, saves the rules to disk.

.EXAMPLE
    New-RulesFromTemplate -TemplateName 'Microsoft Office'
    Creates Office rules with default settings.

.EXAMPLE
    New-RulesFromTemplate -TemplateName 'Block High Risk Locations' -Status Approved -Save
    Creates and saves pre-approved deny rules for risky paths.

.OUTPUTS
    [PSCustomObject] Created rules with Success, Data, and Error properties.
#>
function New-RulesFromTemplate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,

        [Parameter()]
        [string]$UserOrGroupSid,

        [Parameter()]
        [ValidateSet('Pending', 'Approved', 'Rejected', 'Review')]
        [string]$Status = 'Pending',

        [Parameter()]
        [switch]$Save
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        # Get the template
        $templateResult = Get-RuleTemplates -TemplateName $TemplateName
        if (-not $templateResult.Success) {
            throw $templateResult.Error
        }

        $template = $templateResult.Data
        $createdRules = @()

        foreach ($ruleConfig in $template.Rules) {
            # Determine the SID to use
            $sid = if ($UserOrGroupSid) { 
                $UserOrGroupSid 
            } 
            elseif ($ruleConfig.UserOrGroup -and $ruleConfig.UserOrGroup.StartsWith('RESOLVE:')) {
                Resolve-GroupSid -GroupName $ruleConfig.UserOrGroup
            }
            elseif ($ruleConfig.UserOrGroup -eq 'Everyone') { 
                'S-1-1-0' 
            }
            else {
                'S-1-1-0'  # Default to Everyone
            }

            # Create rule based on type
            $ruleParams = @{
                Name           = $ruleConfig.Name
                Action         = $ruleConfig.Action
                CollectionType = $ruleConfig.CollectionType
                UserOrGroupSid = $sid
                Status         = $Status
                Save           = $Save
            }

            $ruleResult = $null

            switch ($ruleConfig.Type) {
                'Publisher' {
                    $ruleParams['PublisherName'] = $ruleConfig.Publisher
                    $ruleParams['ProductName'] = $ruleConfig.ProductName
                    $ruleParams['BinaryName'] = '*'
                    $ruleParams['MinVersion'] = '*'
                    $ruleParams['MaxVersion'] = '*'
                    $ruleResult = New-PublisherRule @ruleParams
                }
                'Path' {
                    $ruleParams['Path'] = $ruleConfig.Path
                    $ruleResult = New-PathRule @ruleParams
                }
                'Hash' {
                    # Hash rules require actual file hash - skip for templates
                    Write-RuleLog -Level Warning -Message "Skipping hash rule '$($ruleConfig.Name)' - requires actual file hash"
                    continue
                }
                default {
                    Write-RuleLog -Level Warning -Message "Unknown rule type: $($ruleConfig.Type)"
                    continue
                }
            }

            if ($ruleResult -and $ruleResult.Success) {
                $createdRules += $ruleResult.Data
            }
            elseif ($ruleResult) {
                Write-RuleLog -Level Warning -Message "Failed to create rule '$($ruleConfig.Name)': $($ruleResult.Error)"
            }
        }

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            TemplateName = $TemplateName
            Description  = $template.Description
            RulesCreated = $createdRules.Count
            Rules        = $createdRules
        }

        Write-RuleLog -Message "Created $($createdRules.Count) rules from template '$TemplateName'"
    }
    catch {
        $result.Error = "Failed to create rules from template: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}

<#
.SYNOPSIS
    Gets template names grouped by category.

.DESCRIPTION
    Returns templates organized by their purpose: Allow (applications),
    Block (deny rules), and Windows (system defaults).

.EXAMPLE
    Get-RuleTemplateCategories

.OUTPUTS
    [PSCustomObject] Categories with template names.
#>
function Get-RuleTemplateCategories {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        $templatesResult = Get-RuleTemplates
        if (-not $templatesResult.Success) {
            throw $templatesResult.Error
        }

        $allow = @()
        $block = @()
        $windows = @()

        foreach ($template in $templatesResult.Data) {
            if ($template.Name -like 'Block*') {
                $block += $template.Name
            }
            elseif ($template.Name -like 'Windows*') {
                $windows += $template.Name
            }
            else {
                $allow += $template.Name
            }
        }

        $result.Data = [PSCustomObject]@{
            Applications = $allow
            BlockRules   = $block
            WindowsRules = $windows
        }
        $result.Success = $true
    }
    catch {
        $result.Error = "Failed to categorize templates: $($_.Exception.Message)"
        Write-RuleLog -Level Error -Message $result.Error
    }

    return $result
}
