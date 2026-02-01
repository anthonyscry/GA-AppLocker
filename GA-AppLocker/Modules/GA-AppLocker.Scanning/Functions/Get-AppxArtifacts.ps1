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
        }

        # Get Appx packages — try AllUsers first (needs admin), fall back to current user
        $packages = $null
        if ($AllUsers) {
            try {
                $packages = Get-AppxPackage -AllUsers -ErrorAction Stop
                Write-ScanLog -Message "Enumerated Appx packages for all users"
            }
            catch {
                Write-ScanLog -Level Warning -Message "AllUsers enumeration failed (needs admin): $($_.Exception.Message). Falling back to current user."
                $packages = Get-AppxPackage -ErrorAction SilentlyContinue
            }
        }
        else {
            $packages = Get-AppxPackage -ErrorAction SilentlyContinue
        }

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
                $SyncHash.StatusText = "Appx packages: $processed of $totalPackages"
                # Use 89-95 range so we don't overwrite file scan progress (26-88)
                # and leave room for remote scan completion
                $SyncHash.Progress = [math]::Min(95, 89 + [math]::Round($pct * 0.06))
            }

            # Extract publisher info from the package
            $publisherName = $pkg.Publisher
            $publisherDisplayName = $pkg.PublisherDisplayName
            
            # Create artifact object compatible with rule generation and DataGrid display
            $artifact = [PSCustomObject]@{
                # Core identification (property names match Get-FileArtifact for DataGrid binding)
                FilePath        = $pkg.InstallLocation
                FileName        = "$($pkg.Name).appx"
                Extension       = '.appx'
                FileExtension   = '.appx'
                Directory       = $pkg.InstallLocation
                
                # Package-specific info
                PackageName     = $pkg.Name
                PackageFullName = $pkg.PackageFullName
                Version         = $pkg.Version.ToString()
                Architecture    = $pkg.Architecture.ToString()
                
                # Publisher info (used for Appx rules)
                Publisher       = if ($publisherDisplayName) { $publisherDisplayName } else { $publisherName }
                PublisherName   = $publisherName
                PublisherDisplayName = $publisherDisplayName
                ProductName     = if ($pkg.DisplayName) { $pkg.DisplayName } else { $pkg.Name }
                FileVersion     = $pkg.Version.ToString()
                FileDescription = if ($pkg.DisplayName) { $pkg.DisplayName } else { $pkg.Name }
                
                # Signature info
                SignerCertificate = $publisherName
                SignatureKind   = $pkg.SignatureKind.ToString()
                SignatureStatus = 'Valid'
                IsSigned        = $true  # All Appx packages must be signed
                IsFramework     = $pkg.IsFramework
                
                # Metadata (property names match Get-FileArtifact for DataGrid binding)
                SHA256Hash      = $null  # Appx rules use publisher, not hash
                SizeBytes       = 0
                Hash            = $null
                FileSize        = 0
                ArtifactType    = 'APPX'
                CollectionType  = 'Appx'
                ComputerName    = $env:COMPUTERNAME
                CollectedDate   = Get-Date
                ScanDate        = Get-Date
                
                # For rule generation
                RuleType        = 'Publisher'  # Appx rules are always publisher-based
            }

            [void]$artifacts.Add($artifact)
        }

        if ($SyncHash) {
            $SyncHash.StatusText = "Appx enumeration complete: $($artifacts.Count) packages"
            # Don't set progress to 100 — let the parent scan orchestrator own final progress
            $SyncHash.Progress = 95
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
