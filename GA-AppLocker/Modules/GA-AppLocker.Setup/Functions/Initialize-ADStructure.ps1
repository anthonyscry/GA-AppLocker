<#
.SYNOPSIS
    Creates the AppLocker OU and security groups in Active Directory.

.DESCRIPTION
    Creates:
    - OU=AppLocker at domain root
    - Security groups inside the AppLocker OU:
      - AppLocker-Admins
      - AppLocker-Exempt
      - AppLocker-Audit
      - AppLocker-Users
      - AppLocker-Installers
      - AppLocker-Developers

.PARAMETER OUName
    Name of the OU to create. Default is 'AppLocker'.

.EXAMPLE
    Initialize-ADStructure
    
    Creates the AppLocker OU and all security groups.

.OUTPUTS
    [PSCustomObject] Result with Success, Data, and Error properties.
#>
function Initialize-ADStructure {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$OUName = 'AppLocker'
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        Write-SetupLog -Message "Initializing AD structure for AppLocker"

        # Check for ActiveDirectory module
        if (-not (Test-ModuleAvailable -ModuleName 'ActiveDirectory')) {
            throw "ActiveDirectory module not available. Install RSAT features."
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        $domainDN = Get-DomainDN
        if (-not $domainDN) {
            throw "Could not determine domain DN"
        }

        $ouPath = "OU=$OUName,$domainDN"
        $ouCreated = $false
        $groupsCreated = @()

        # Create OU if it doesn't exist
        $existingOU = Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -SearchBase $domainDN -ErrorAction SilentlyContinue
        
        if ($existingOU) {
            Write-SetupLog -Message "OU '$OUName' already exists"
            $ouPath = $existingOU.DistinguishedName
        }
        else {
            New-ADOrganizationalUnit -Name $OUName -Path $domainDN -Description "AppLocker management objects" -ErrorAction Stop
            Write-SetupLog -Message "Created OU: $OUName"
            $ouCreated = $true
        }

        # Create security groups
        foreach ($groupDef in $script:DefaultGroups) {
            try {
                $existingGroup = Get-ADGroup -Filter "Name -eq '$($groupDef.Name)'" -ErrorAction SilentlyContinue
                
                if ($existingGroup) {
                    Write-SetupLog -Message "Group '$($groupDef.Name)' already exists"
                    $groupsCreated += [PSCustomObject]@{
                        Name        = $groupDef.Name
                        Status      = 'Existing'
                        Description = $groupDef.Description
                    }
                }
                else {
                    New-ADGroup -Name $groupDef.Name `
                                -GroupScope Global `
                                -GroupCategory Security `
                                -Path $ouPath `
                                -Description $groupDef.Description `
                                -ErrorAction Stop
                    
                    Write-SetupLog -Message "Created group: $($groupDef.Name)"
                    $groupsCreated += [PSCustomObject]@{
                        Name        = $groupDef.Name
                        Status      = 'Created'
                        Description = $groupDef.Description
                    }
                }
            }
            catch {
                Write-SetupLog -Message "Failed to create group '$($groupDef.Name)': $($_.Exception.Message)" -Level Error
                $groupsCreated += [PSCustomObject]@{
                    Name        = $groupDef.Name
                    Status      = 'Failed'
                    Description = $_.Exception.Message
                }
            }
        }

        $result.Success = $true
        $result.Data = [PSCustomObject]@{
            OUName      = $OUName
            OUPath      = $ouPath
            OUCreated   = $ouCreated
            Groups      = $groupsCreated
            TotalGroups = $groupsCreated.Count
            CreatedDate = Get-Date
        }

        Write-SetupLog -Message "AD structure initialization complete"
    }
    catch {
        $result.Error = "Failed to initialize AD structure: $($_.Exception.Message)"
        Write-SetupLog -Message $result.Error -Level Error
    }

    return $result
}
