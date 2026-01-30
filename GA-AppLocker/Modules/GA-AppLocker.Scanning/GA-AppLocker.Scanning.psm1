#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Scanning

.DESCRIPTION
    Artifact scanning and collection for GA-AppLocker Dashboard.
    Collects executable artifacts from local and remote machines:
    - EXE, DLL, MSI, MSP, PS1, BAT, CMD, VBS, JS files
    - AppLocker event logs (8001-8025)
    - Publisher information and file hashes

.DEPENDENCIES
    - GA-AppLocker.Core (logging, config)
    - GA-AppLocker.Credentials (tiered authentication)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release - Phase 4

.NOTES
    Supports local and remote scanning via WinRM.
    Air-gapped environment compatible.
#>
#endregion

#region ===== MODULE CONFIGURATION =====
$script:ArtifactExtensions = @(
    '.exe', '.dll', '.msi', '.msp',      # Executables and installers
    '.ps1', '.psm1', '.psd1',            # PowerShell
    '.bat', '.cmd',                       # Batch files
    '.vbs', '.js', '.wsf',               # Scripts
    '.appx', '.msix'                     # Packaged apps (UWP/MSIX)
)

# Default paths loaded from config; fallback if config unavailable
$script:DefaultScanPaths = $null

function script:Get-DefaultScanPaths {
    if ($null -eq $script:DefaultScanPaths) {
        try {
            $config = Get-AppLockerConfig
            if ($config.DefaultScanPaths) {
                $script:DefaultScanPaths = @($config.DefaultScanPaths)
            }
        }
        catch { }
        
        # Fallback if config unavailable
        if ($null -eq $script:DefaultScanPaths -or $script:DefaultScanPaths.Count -eq 0) {
            $script:DefaultScanPaths = @(
                'C:\Program Files',
                'C:\Program Files (x86)',
                'C:\Windows\System32',
                'C:\Windows\SysWOW64',
                'C:\ProgramData',
                'C:\Windows\Microsoft.NET',
                "$env:LOCALAPPDATA\Programs",
                "$env:LOCALAPPDATA\Microsoft\WindowsApps"
            )
        }
    }
    return $script:DefaultScanPaths
}

$script:AppLockerEventIds = @(8001, 8002, 8003, 8004, 8005, 8006, 8007, 8020, 8021, 8022, 8023, 8024, 8025)
#endregion

#region ===== SAFE LOGGING WRAPPER =====
function script:Write-ScanLog {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== HELPER FUNCTIONS =====
function script:Get-FileArtifact {
    <#
    .SYNOPSIS
        Extracts artifact information from a file.

    .DESCRIPTION
        Extracts artifact information from a file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter()]
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    try {
        $file = Get-Item -Path $FilePath -ErrorAction Stop
        
        # Get file hash
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
        
        # Get version info (publisher, product, etc.)
        $versionInfo = $null
        try {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
        }
        catch { }
        
        # Get digital signature — use .NET cert extraction (no CRL/OCSP network calls)
        # Get-AuthenticodeSignature triggers revocation checks that timeout on air-gapped networks
        $isSigned = $false
        $signerSubject = $null
        $sigStatus = 'NotSigned'
        try {
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($FilePath)
            if ($cert) {
                $isSigned = $true
                $signerSubject = $cert.Subject
                $sigStatus = 'Valid'
            }
        } catch {
            # File has no embedded Authenticode signature (or is catalog-signed)
        }
        
        [PSCustomObject]@{
            FilePath         = $FilePath
            FileName         = $file.Name
            Extension        = $file.Extension.ToLower()
            Directory        = $file.DirectoryName
            ComputerName     = $ComputerName
            SizeBytes        = $file.Length
            CreatedDate      = $file.CreationTime
            ModifiedDate     = $file.LastWriteTime
            SHA256Hash       = $hash.Hash
            # Publisher info
            Publisher        = $versionInfo.CompanyName
            ProductName      = $versionInfo.ProductName
            ProductVersion   = $versionInfo.ProductVersion
            FileVersion      = $versionInfo.FileVersion
            FileDescription  = $versionInfo.FileDescription
            OriginalFilename = $versionInfo.OriginalFilename
            # Signature info
            IsSigned         = $isSigned
            SignerCertificate = $signerSubject
            SignatureStatus  = $sigStatus
            # Metadata
            CollectedDate    = Get-Date
            ArtifactType     = Get-ArtifactType -Extension $file.Extension
        }
    }
    catch {
        Write-ScanLog -Level Warning -Message "Failed to get artifact info for: $FilePath - $($_.Exception.Message)"
        return $null
    }
}

function script:Get-ArtifactType {
    param([string]$Extension)
    
    # Return UI-compatible artifact type values
    # UI filters expect: EXE, DLL, MSI, PS1, BAT, CMD, VBS, JS
    switch ($Extension.ToLower()) {
        '.exe' { 'EXE' }
        '.dll' { 'DLL' }
        '.msi' { 'MSI' }
        '.msp' { 'MSP' }
        '.ps1' { 'PS1' }
        '.psm1' { 'PS1' }
        '.psd1' { 'PS1' }
        '.bat' { 'BAT' }
        '.cmd' { 'CMD' }
        '.vbs' { 'VBS' }
        '.js' { 'JS' }
        '.wsf' { 'WSF' }
        '.appx' { 'APPX' }
        '.msix' { 'APPX' }
        default { 'Unknown' }
    }
}

function script:Get-ScanStoragePath {
    $dataPath = Get-AppLockerDataPath
    $scanPath = Join-Path $dataPath 'Scans'
    
    if (-not (Test-Path $scanPath)) {
        New-Item -Path $scanPath -ItemType Directory -Force | Out-Null
    }
    
    return $scanPath
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
    'Get-LocalArtifacts',
    'Get-RemoteArtifacts',
    'Get-AppxArtifacts',
    'Get-AppLockerEventLogs',
    'Start-ArtifactScan',
    'Get-ScanResults',
    'Export-ScanResults',
    # Scheduled Scans
    'New-ScheduledScan',
    'Get-ScheduledScans',
    'Remove-ScheduledScan',
    'Set-ScheduledScanEnabled',
    'Invoke-ScheduledScan'
)
#endregion
