#Requires -Version 5.1
#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Deployment

.DESCRIPTION
    Deployment functions for applying AppLocker policies to Group Policy Objects (GPOs).
    
    Deployment workflow:
    1. Create deployment job (links policy to GPO)
    2. Validate GPO exists or create new
    3. Export policy XML
    4. Import to GPO using PowerShell GPO cmdlets
    5. Track deployment history

.DEPENDENCIES
    - GA-AppLocker.Core (logging, config)
    - GA-AppLocker.Policy (policy retrieval, XML export)
    - GroupPolicy module (optional, for GPO operations)
    - ActiveDirectory module (optional, for OU linking)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release

.NOTES
    Deployment tracking is stored locally.
    Air-gapped environment compatible.
#>
#endregion

#region ===== SAFE LOGGING WRAPPER =====
function script:Write-DeployLog {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== HELPER FUNCTIONS =====
function script:Get-DeploymentStoragePath {
    $dataPath = Get-AppLockerDataPath
    $deployPath = Join-Path $dataPath 'Deployments'
    
    if (-not (Test-Path $deployPath)) {
        New-Item -Path $deployPath -ItemType Directory -Force | Out-Null
    }
    
    return $deployPath
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
    'New-DeploymentJob',
    'Get-DeploymentJob',
    'Get-AllDeploymentJobs',
    'Start-Deployment',
    'Stop-Deployment',
    'Get-DeploymentStatus',
    'Test-GPOExists',
    'New-AppLockerGPO',
    'Import-PolicyToGPO',
    'Get-DeploymentHistory'
)
#endregion
