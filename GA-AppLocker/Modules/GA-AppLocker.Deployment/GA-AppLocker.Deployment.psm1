#Requires -Version 5.1
<#
.SYNOPSIS
    GA-AppLocker Deployment Module

.DESCRIPTION
    Provides deployment functions for applying AppLocker policies
    to Group Policy Objects (GPOs).

.NOTES
    Deployment workflow:
    1. Create deployment job (links policy to GPO)
    2. Validate GPO exists or create new
    3. Export policy XML
    4. Import to GPO using PowerShell GPO cmdlets
    5. Track deployment history
#>

# Get module path for loading functions
$ModulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$FunctionsPath = Join-Path $ModulePath 'Functions'

# Dot-source all function files
if (Test-Path $FunctionsPath) {
    Get-ChildItem -Path $FunctionsPath -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}

# Export all public functions
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
