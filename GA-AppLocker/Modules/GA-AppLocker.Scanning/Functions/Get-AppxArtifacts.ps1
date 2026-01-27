<#
.SYNOPSIS
    Collects installed Appx/MSIX packages for AppLocker rule generation.

.DESCRIPTION
    Enumerates installed Windows App packages (UWP/MSIX) using Get-AppxPackage.
    These packaged apps require special handling in AppLocker as they use
    Publisher rules based on package publisher certificates.

.PARAMETER AllUsers
    Include packages installed for all users (requires admin).

.PARAMETER IncludeFrameworks
    Include framework packages (Microsoft.NET, VCLibs, etc.).

.PARAMETER IncludeSystemApps
    Include Windows system apps (Calculator, Photos, etc.).

.EXAMPLE
    Get-AppxArtifacts
    Returns user-installed Appx packages.

.EXAMPLE
    Get-AppxArtifacts -AllUsers -IncludeSystemApps
    Returns all Appx packages including system apps.

.OUTPUTS
    [PSCustomObject] Result with Success, Data (artifacts array), and Summary.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Get-AppxArtifacts {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$AllUsers,

        [Parameter()]
        [switch]$IncludeFrameworks,

        [Parameter()]
        [switch]$IncludeSystemApps,

        [Parameter()]
        [hashtable]$SyncHash = $null
    )

    $result = [PSCustomObject]@{
        Success  = $false
        Data     = @()
        Error    = $null
        Summary  = $null
    }

    try {
        Write-ScanLog -Message "Starting Appx package enumeration"
        
        if ($SyncHash) {
            $SyncHash.StatusText = "Enumerating installed app packages..."
            $SyncHash.Progress = 10
        }

        # Get Appx packages
        $getAppxParams = @{
            ErrorAction = 'SilentlyContinue'
        }
        
        if ($AllUsers) {
            # Requires admin privileges
            $getAppxParams.AllUsers = $true
        }

        $packages = Get-AppxPackage @getAppxParams

        if (-not $packages) {
            $result.Success = $true
            $result.Data = @()
            $result.Summary = @{ TotalPackages = 0 }
            return $result
        }

        # Filter packages
        if (-not $IncludeFrameworks) {
            $packages = $packages | Where-Object { -not $_.IsFramework }
        }

        if (-not $IncludeSystemApps) {
            # Filter out Windows system apps (typically have Microsoft.Windows prefix)
            $packages = $packages | Where-Object { 
                $_.Name -notmatch '^Microsoft\.Windows\.' -and
                $_.Name -notmatch '^windows\.' -and
                $_.SignatureKind -ne 'System'
            }
        }

        $artifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
        $totalPackages = @($packages).Count
        $processed = 0

        foreach ($pkg in $packages) {
            $processed++
            
            if ($SyncHash -and $processed % 10 -eq 0) {
                $pct = [math]::Round(($processed / $totalPackages) * 100)
                $SyncHash.StatusText = "Processing packages: $processed of $totalPackages"
                $SyncHash.Progress = 10 + [math]::Round($pct * 0.8)
            }

            # Extract publisher info from the package
            $publisherName = $pkg.Publisher
            $publisherDisplayName = $pkg.PublisherDisplayName
            
            # Create artifact object compatible with rule generation
            $artifact = [PSCustomObject]@{
                # Core identification
                FilePath        = $pkg.InstallLocation
                FileName        = "$($pkg.Name).appx"
                FileExtension   = '.appx'
                
                # Package-specific info
                PackageName     = $pkg.Name
                PackageFullName = $pkg.PackageFullName
                Version         = $pkg.Version.ToString()
                Architecture    = $pkg.Architecture.ToString()
                
                # Publisher info (used for Appx rules)
                PublisherName   = $publisherName
                PublisherDisplayName = $publisherDisplayName
                ProductName     = if ($pkg.DisplayName) { $pkg.DisplayName } else { $pkg.Name }
                
                # Signature info
                SignatureKind   = $pkg.SignatureKind.ToString()
                IsSigned        = $true  # All Appx packages must be signed
                IsFramework     = $pkg.IsFramework
                
                # Metadata
                Hash            = $null  # Appx rules typically use publisher, not hash
                FileSize        = 0
                CollectionType  = 'Appx'
                ComputerName    = $env:COMPUTERNAME
                ScanDate        = Get-Date
                
                # For rule generation
                RuleType        = 'Publisher'  # Appx rules are always publisher-based
            }

            $artifacts.Add($artifact)
        }

        if ($SyncHash) {
            $SyncHash.StatusText = "Appx enumeration complete"
            $SyncHash.Progress = 100
        }

        $result.Success = $true
        $result.Data = $artifacts.ToArray()
        $result.Summary = @{
            TotalPackages    = $artifacts.Count
            FrameworkCount   = @($artifacts | Where-Object { $_.IsFramework }).Count
            UserAppCount     = @($artifacts | Where-Object { -not $_.IsFramework }).Count
            Publishers       = @($artifacts | Select-Object -ExpandProperty PublisherDisplayName -Unique).Count
        }

        Write-ScanLog -Message "Appx enumeration complete: $($artifacts.Count) packages found"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-ScanLog -Level Error -Message "Appx enumeration failed: $($_.Exception.Message)"
    }

    return $result
}
