function New-Policy {
    <#
    .SYNOPSIS
        Creates a new AppLocker policy.

    .DESCRIPTION
        Creates a policy that can contain multiple rules and be
        targeted to specific OUs or GPOs. Supports phase-based
        deployment with automatic rule type filtering.

    .PARAMETER Name
        The name of the policy.

    .PARAMETER Description
        Optional description of the policy.

    .PARAMETER EnforcementMode
        The enforcement mode: NotConfigured, AuditOnly, or Enabled.
        Note: When using Phase parameter, enforcement is auto-set:
        - Phase 1-3: AuditOnly
        - Phase 4: Enabled

    .PARAMETER Phase
        The deployment phase (1-4). Controls which rule types are exported:
        - Phase 1: EXE rules only (AuditOnly) - Initial testing
        - Phase 2: EXE + Script rules (AuditOnly)
        - Phase 3: EXE + Script + MSI rules (AuditOnly)
        - Phase 4: All rules including DLL (Enabled) - Full enforcement

    .PARAMETER RuleIds
        Optional array of rule IDs to include in the policy.

    .EXAMPLE
        New-Policy -Name "Baseline Policy" -Phase 1
        Creates a Phase 1 policy (EXE only, AuditOnly mode)

    .EXAMPLE
        New-Policy -Name "Production Policy" -Phase 4
        Creates a Phase 4 policy (all rules, Enabled mode)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Description = '',

        [Parameter(Mandatory = $false)]
        [ValidateSet('NotConfigured', 'AuditOnly', 'Enabled')]
        [string]$EnforcementMode = 'AuditOnly',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 4)]
        [int]$Phase = 1,

        [Parameter(Mandatory = $false)]
        [string[]]$RuleIds = @()
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $policiesPath = Join-Path $dataPath 'Policies'

        if (-not (Test-Path $policiesPath)) {
            New-Item -Path $policiesPath -ItemType Directory -Force | Out-Null
        }

        # Determine effective enforcement mode based on Phase
        # SAFETY RULE: Phase 1-3 ALWAYS use AuditOnly (no exceptions)
        # Phase 4 respects user's EnforcementMode setting
        $effectiveEnforcement = if ($Phase -lt 4) {
            # Phase 1-3: Force AuditOnly regardless of user request
            'AuditOnly'
        } elseif ($PSBoundParameters.ContainsKey('EnforcementMode')) {
            # Phase 4 with explicit EnforcementMode: respect user's choice
            $EnforcementMode
        } else {
            # Phase 4 without explicit mode: default to Enabled
            'Enabled'
        }

        $policyId = [guid]::NewGuid().ToString()

        $policy = [PSCustomObject]@{
            PolicyId        = $policyId
            Name            = $Name
            Description     = $Description
            EnforcementMode = $effectiveEnforcement
            Phase           = $Phase
            Status          = 'Draft'
            RuleIds         = @($RuleIds)
            TargetOUs       = @()
            TargetGPO       = $null
            CreatedAt       = (Get-Date).ToString('o')
            ModifiedAt      = (Get-Date).ToString('o')
            CreatedBy       = $env:USERNAME
            Version         = 1
        }

        $policyFile = Join-Path $policiesPath "$policyId.json"
        $policy | ConvertTo-Json -Depth 5 | Set-Content -Path $policyFile -Encoding UTF8
        
        # Invalidate GlobalSearch cache
        if (Get-Command -Name 'Clear-AppLockerCache' -ErrorAction SilentlyContinue) {
            Clear-AppLockerCache -Pattern "GlobalSearch_*" | Out-Null
        }

        return @{
            Success = $true
            Data    = $policy
            Message = "Policy '$Name' created successfully"
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
