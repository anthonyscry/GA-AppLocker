function Test-GPOExists {
    <#
    .SYNOPSIS
        Tests if a GPO exists.

    .PARAMETER GPOName
        The name of the GPO to check.

    .EXAMPLE
        Test-GPOExists -GPOName "AppLocker-Workstations"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GPOName
    )

    try {
        # Check if GroupPolicy module is available
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            return @{
                Success        = $false
                Data           = $null
                Error          = 'GroupPolicy module not available. Install RSAT-GPMC feature.'
                ManualRequired = $true
            }
        }

        Import-Module GroupPolicy -ErrorAction Stop

        $gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue

        return @{
            Success = $true
            Data    = ($null -ne $gpo)
            Message = if ($gpo) { "GPO '$GPOName' exists" } else { "GPO '$GPOName' does not exist" }
        }
    }
    catch {
        return @{
            Success = $false
            Data    = $null
            Error   = "Could not verify GPO: $($_.Exception.Message)"
        }
    }
}

function New-AppLockerGPO {
    <#
    .SYNOPSIS
        Creates a new GPO for AppLocker policies.

    .PARAMETER GPOName
        The name for the new GPO.

    .PARAMETER Comment
        Optional comment/description for the GPO.

    .EXAMPLE
        New-AppLockerGPO -GPOName "AppLocker-Workstations"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $false)]
        [string]$Comment = 'Created by GA-AppLocker Dashboard'
    )

    try {
        # Check if GroupPolicy module is available
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            return @{
                Success = $false
                Error   = 'GroupPolicy module not available. Install RSAT-GPMC feature.'
            }
        }

        Import-Module GroupPolicy -ErrorAction Stop

        # Check if GPO already exists
        $existing = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
        if ($existing) {
            return @{
                Success = $true
                Data    = $existing
                Message = "GPO '$GPOName' already exists"
            }
        }

        # Create new GPO
        $gpo = New-GPO -Name $GPOName -Comment $Comment -ErrorAction Stop

        Write-AppLockerLog -Message "Created GPO: $GPOName"

        return @{
            Success = $true
            Data    = $gpo
            Message = "GPO '$GPOName' created successfully"
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Import-PolicyToGPO {
    <#
    .SYNOPSIS
        Imports an AppLocker policy XML to a GPO.

    .DESCRIPTION
        Uses Set-AppLockerPolicy to import the XML policy
        to the specified GPO.

    .PARAMETER GPOName
        The name of the target GPO.

    .PARAMETER XmlPath
        Path to the AppLocker policy XML file.

    .PARAMETER Merge
        If true, merge with existing policy. If false, replace.

    .EXAMPLE
        Import-PolicyToGPO -GPOName "AppLocker-Workstations" -XmlPath "C:\policy.xml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $true)]
        [string]$XmlPath,

        [Parameter(Mandatory = $false)]
        [switch]$Merge
    )

    try {
        if (-not (Test-Path $XmlPath)) {
            return @{
                Success = $false
                Error   = "XML file not found: $XmlPath"
            }
        }

        # Check if required modules are available
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            return @{
                Success = $false
                Error   = 'GroupPolicy module not available. Install RSAT-GPMC feature.'
            }
        }

        Import-Module GroupPolicy -ErrorAction Stop

        # Get GPO
        $gpo = Get-GPO -Name $GPOName -ErrorAction Stop

        # Read XML content
        $xmlContent = Get-Content -Path $XmlPath -Raw

        # Set AppLocker policy using PowerShell
        # Note: Set-AppLockerPolicy requires AppLocker module
        if (Get-Command -Name 'Set-AppLockerPolicy' -ErrorAction SilentlyContinue) {
            if ($Merge) {
                Set-AppLockerPolicy -XmlPolicy $xmlContent -Ldap "LDAP://CN={$($gpo.Id)},CN=Policies,CN=System,$((Get-ADDomain).DistinguishedName)" -Merge
            }
            else {
                Set-AppLockerPolicy -XmlPolicy $xmlContent -Ldap "LDAP://CN={$($gpo.Id)},CN=Policies,CN=System,$((Get-ADDomain).DistinguishedName)"
            }
        }
        else {
            # Set-AppLockerPolicy not available - cannot auto-import
            Write-AppLockerLog -Level Warning -Message "Set-AppLockerPolicy not available. Policy exported to: $XmlPath"
            Write-AppLockerLog -Message "Manual import required: Use GPMC to import the policy XML"

            return @{
                Success        = $false
                Data           = @{
                    GPOName = $GPOName
                    XmlPath = $XmlPath
                }
                Error          = 'Set-AppLockerPolicy cmdlet not available. Manual import required via GPMC.'
                ManualRequired = $true
            }
        }

        Write-AppLockerLog -Message "Policy imported to GPO: $GPOName"

        return @{
            Success = $true
            Data    = @{
                GPOName = $GPOName
                GPOId   = $gpo.Id
            }
            Message = "Policy imported to GPO '$GPOName'"
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Get-DeploymentHistory {
    <#
    .SYNOPSIS
        Gets deployment history entries.

    .PARAMETER JobId
        Optional filter by job ID.

    .PARAMETER Limit
        Maximum number of entries to return.

    .EXAMPLE
        Get-DeploymentHistory
        Get-DeploymentHistory -JobId "abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$JobId,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $historyPath = Join-Path $dataPath 'DeploymentHistory'

        if (-not (Test-Path $historyPath)) {
            return @{
                Success = $true
                Data    = @()
            }
        }

        $historyFiles = Get-ChildItem -Path $historyPath -Filter '*.json' -File
        $entries = @()

        foreach ($file in $historyFiles) {
            $entry = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            
            if ([string]::IsNullOrEmpty($JobId) -or $entry.JobId -eq $JobId) {
                $entries += $entry
            }
        }

        # Sort by timestamp descending and limit
        $entries = $entries | Sort-Object -Property Timestamp -Descending | Select-Object -First $Limit

        return @{
            Success = $true
            Data    = $entries
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
