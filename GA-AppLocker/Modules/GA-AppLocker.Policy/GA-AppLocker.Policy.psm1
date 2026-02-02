#Requires -Version 5.1
#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Policy

.DESCRIPTION
    Policy creation, management, and targeting functions for GA-AppLocker Dashboard.
    Policies combine rules into deployable units that can be targeted to specific OUs or GPOs.

.DEPENDENCIES
    - GA-AppLocker.Core (logging, config)
    - GA-AppLocker.Rules (rule retrieval)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release

.NOTES
    Policies are stored locally and can be exported to AppLocker XML format.
    Air-gapped environment compatible.
#>
#endregion

#region ===== SAFE LOGGING WRAPPER =====
function script:Write-PolicyLog {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== HELPER FUNCTIONS =====
function script:Get-PolicyStoragePath {
    $dataPath = Get-AppLockerDataPath
    $policyPath = Join-Path $dataPath 'Policies'
    
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -ItemType Directory -Force | Out-Null
    }
    
    return $policyPath
}
#endregion

#region ===== FUNCTION LOADING =====
$functionPath = Join-Path $PSScriptRoot 'Functions'

if (Test-Path $functionPath) {
    $functionFiles = Get-ChildItem -Path $functionPath -Filter '*.ps1' -ErrorAction SilentlyContinue

    foreach ($file in $functionFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Warning "Failed to load function file: $($file.Name). Error: $($_.Exception.Message)"
        }
    }
}
#endregion

#region ===== EXPORTS =====
Export-ModuleMember -Function @(
    # Core Policy CRUD
    'New-Policy',
    'Get-Policy',
    'Get-AllPolicies',
    'Get-PolicyCount',
    'Update-Policy',
    'Remove-Policy',
    'Set-PolicyStatus',
    # Rule Management
    'Add-RuleToPolicy',
    'Remove-RuleFromPolicy',
    # Targeting
    'Set-PolicyTarget',
    # Export
    'Export-PolicyToXml',
    'Test-PolicyCompliance',
    # Policy Comparison
    'Compare-Policies',
    'Compare-RuleProperties',
    'Get-PolicyDiffReport',
    # Policy Snapshots
    'New-PolicySnapshot',
    'Get-PolicySnapshots',
    'Get-PolicySnapshot',
    'Restore-PolicySnapshot',
    'Remove-PolicySnapshot',
    'Invoke-PolicySnapshotCleanup'
)
#endregion
