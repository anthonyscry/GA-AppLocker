<#
.SYNOPSIS
    Creates the default AppLocker GPOs for DC, Servers, and Workstations.

.DESCRIPTION
    Creates three GPOs:
    - AppLocker-DC: Linked to Domain Controllers OU
    - AppLocker-Servers: Linked to Servers OU
    - AppLocker-Workstations: Linked to Computers OU

.PARAMETER CreateOnly
    Only create GPOs without linking them.

.EXAMPLE
    Initialize-AppLockerGPOs
    
    Creates and links all three AppLocker GPOs.

.OUTPUTS
    [PSCustomObject] Result with Success, Data, and Error properties.
#>
function Initialize-AppLockerGPOs {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$CreateOnly,

        [Parameter()]
        [string]$ServersOU,

        [Parameter()]
        [string]$WorkstationsOU
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
    }

    try {
        Write-SetupLog -Message "Initializing AppLocker GPOs"

        # Check for GroupPolicy module
        if (-not (Test-ModuleAvailable -ModuleName 'GroupPolicy')) {
            throw "GroupPolicy module not available. Install RSAT features."
        }

        Import-Module GroupPolicy -ErrorAction Stop

        $domainDN = Get-DomainDN
        if (-not $domainDN) {
            throw "Could not determine domain DN"
        }

        # Define GPOs to create
        $gposToCreate = @(
            @{
                Name        = $script:DefaultGPONames.DC
                Description = 'AppLocker policies for Domain Controllers'
                TargetOU    = "OU=Domain Controllers,$domainDN"
            }
            @{
                Name        = $script:DefaultGPONames.Servers
                Description = 'AppLocker policies for Member Servers'
                TargetOU    = if ($ServersOU) { $ServersOU } else { "CN=Computers,$domainDN" }
            }
            @{
                Name        = $script:DefaultGPONames.Workstations
                Description = 'AppLocker policies for Workstations'
                TargetOU    = if ($WorkstationsOU) { $WorkstationsOU } else { "CN=Computers,$domainDN" }
            }
        )

        $createdGPOs = @()

        foreach ($gpoConfig in $gposToCreate) {
            try {
                # Check if GPO already exists
                $existingGPO = Get-GPO -Name $gpoConfig.Name -ErrorAction SilentlyContinue
                
                if ($existingGPO) {
                    Write-SetupLog -Message "GPO '$($gpoConfig.Name)' already exists"
                    $gpo = $existingGPO
                    $status = 'Existing'
                }
                else {
                    # Create new GPO
                    $gpo = New-GPO -Name $gpoConfig.Name -Comment $gpoConfig.Description -ErrorAction Stop
                    Write-SetupLog -Message "Created GPO: $($gpoConfig.Name)"
                    $status = 'Created'
                }

                # Link to target OU if not CreateOnly
                $linkedTo = $null
                if (-not $CreateOnly) {
                    try {
                        # Check if target exists
                        if (Test-ModuleAvailable -ModuleName 'ActiveDirectory') {
                            Import-Module ActiveDirectory -ErrorAction SilentlyContinue
                            $targetExists = Get-ADObject -Identity $gpoConfig.TargetOU -ErrorAction SilentlyContinue
                        }
                        else {
                            $targetExists = $true  # Assume exists if we can't check
                        }

                        if ($targetExists) {
                            New-GPLink -Name $gpoConfig.Name -Target $gpoConfig.TargetOU -ErrorAction SilentlyContinue
                            $linkedTo = $gpoConfig.TargetOU
                            Write-SetupLog -Message "Linked '$($gpoConfig.Name)' to $($gpoConfig.TargetOU)"
                        }
                    }
                    catch {
                        if ($_.Exception.Message -notmatch 'already linked') {
                            Write-SetupLog -Message "Warning linking GPO: $($_.Exception.Message)" -Level Warning
                        }
                        else {
                            $linkedTo = $gpoConfig.TargetOU
                        }
                    }
                }

                $createdGPOs += [PSCustomObject]@{
                    Name        = $gpoConfig.Name
                    GPOId       = $gpo.Id
                    Description = $gpoConfig.Description
                    LinkedTo    = $linkedTo
                    Status      = $status
                }
            }
            catch {
                Write-SetupLog -Message "Failed to create GPO '$($gpoConfig.Name)': $($_.Exception.Message)" -Level Error
            }
        }

        $result.Success = $createdGPOs.Count -gt 0
        $result.Data = $createdGPOs

        Write-SetupLog -Message "AppLocker GPO initialization complete. Created/Found: $($createdGPOs.Count) GPOs"
    }
    catch {
        $result.Error = "Failed to initialize AppLocker GPOs: $($_.Exception.Message)"
        Write-SetupLog -Message $result.Error -Level Error
    }

    return $result
}
