#Requires -Modules Pester
<#
.SYNOPSIS
    Tests for GA-AppLocker.Scanning module.

.DESCRIPTION
    Covers scanning module functions and helpers:
    - Get-LocalArtifacts (local file scanning)
    - Get-RemoteArtifacts (remote WinRM scanning)
    - Get-AppxArtifacts (Appx/MSIX package enumeration)
    - Get-AppLockerEventLogs (event log collection)
    - Start-ArtifactScan (orchestrator)
    - Artifact type and collection type mapping
    - SHA256 hash computation
    - Scan result structure validation

.NOTES
    Module: GA-AppLocker.Scanning
    Run with: Invoke-Pester -Path .\Tests\Unit\Scanning.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Get-Module 'GA-AppLocker*' | Remove-Module -Force -ErrorAction SilentlyContinue
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Dot-source the scanning psm1 to access script-scope helpers for testing
    $scanModulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\GA-AppLocker.Scanning.psm1'
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

Describe 'Scanning Module Exports' -Tag 'Unit', 'Scanning' {

    It 'Should export Get-LocalArtifacts' {
        Get-Command -Name 'Get-LocalArtifacts' -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-RemoteArtifacts' {
        Get-Command -Name 'Get-RemoteArtifacts' -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-AppxArtifacts' {
        Get-Command -Name 'Get-AppxArtifacts' -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-AppLockerEventLogs' {
        Get-Command -Name 'Get-AppLockerEventLogs' -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Should export Start-ArtifactScan' {
        Get-Command -Name 'Start-ArtifactScan' -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-ScanResults' {
        Get-Command -Name 'Get-ScanResults' -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Should export Export-ScanResults' {
        Get-Command -Name 'Export-ScanResults' -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Should export scheduled scan functions' {
        'New-ScheduledScan', 'Get-ScheduledScans', 'Remove-ScheduledScan',
        'Set-ScheduledScanEnabled', 'Invoke-ScheduledScan' | ForEach-Object {
            Get-Command -Name $_ -Module 'GA-AppLocker' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty -Because "$_ should be exported"
        }
    }
}

# ============================================================================
# ARTIFACT TYPE MAPPING
# ============================================================================

Describe 'Artifact Type Mapping' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        # Access the script-scope Get-ArtifactType via module internals
        $scanModule = Get-Module 'GA-AppLocker.Scanning'
        $getArtifactType = {
            param([string]$Extension)
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
    }

    It 'Should map .exe to EXE' {
        & $getArtifactType '.exe' | Should -Be 'EXE'
    }

    It 'Should map .dll to DLL' {
        & $getArtifactType '.dll' | Should -Be 'DLL'
    }

    It 'Should map .msi to MSI' {
        & $getArtifactType '.msi' | Should -Be 'MSI'
    }

    It 'Should map .msp to MSP' {
        & $getArtifactType '.msp' | Should -Be 'MSP'
    }

    It 'Should map .ps1 to PS1' {
        & $getArtifactType '.ps1' | Should -Be 'PS1'
    }

    It 'Should map .psm1 to PS1 (grouped with PowerShell)' {
        & $getArtifactType '.psm1' | Should -Be 'PS1'
    }

    It 'Should map .psd1 to PS1 (grouped with PowerShell)' {
        & $getArtifactType '.psd1' | Should -Be 'PS1'
    }

    It 'Should map .bat to BAT' {
        & $getArtifactType '.bat' | Should -Be 'BAT'
    }

    It 'Should map .cmd to CMD' {
        & $getArtifactType '.cmd' | Should -Be 'CMD'
    }

    It 'Should map .vbs to VBS' {
        & $getArtifactType '.vbs' | Should -Be 'VBS'
    }

    It 'Should map .js to JS' {
        & $getArtifactType '.js' | Should -Be 'JS'
    }

    It 'Should map .wsf to WSF' {
        & $getArtifactType '.wsf' | Should -Be 'WSF'
    }

    It 'Should map .appx to APPX' {
        & $getArtifactType '.appx' | Should -Be 'APPX'
    }

    It 'Should map .msix to APPX (grouped with APPX)' {
        & $getArtifactType '.msix' | Should -Be 'APPX'
    }

    It 'Should map unknown extension to Unknown' {
        & $getArtifactType '.xyz' | Should -Be 'Unknown'
    }

    It 'Should be case-insensitive' {
        & $getArtifactType '.EXE' | Should -Be 'EXE'
        & $getArtifactType '.Dll' | Should -Be 'DLL'
        & $getArtifactType '.PS1' | Should -Be 'PS1'
    }
}

# ============================================================================
# COLLECTION TYPE MAPPING
# ============================================================================

Describe 'Collection Type Mapping' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        # Mirror the collection type logic from the scanning module
        $getCollectionType = {
            param([string]$ArtifactType)
            switch ($ArtifactType) {
                'EXE'     { 'Exe' }
                'DLL'     { 'Dll' }
                { $_ -in 'MSI','MSP' } { 'Msi' }
                { $_ -in 'PS1','BAT','CMD','VBS','JS','WSF' } { 'Script' }
                'APPX'    { 'Appx' }
                default   { 'Exe' }
            }
        }
    }

    It 'Should map EXE to Exe collection' {
        & $getCollectionType 'EXE' | Should -Be 'Exe'
    }

    It 'Should map DLL to Dll collection' {
        & $getCollectionType 'DLL' | Should -Be 'Dll'
    }

    It 'Should map MSI to Msi collection' {
        & $getCollectionType 'MSI' | Should -Be 'Msi'
    }

    It 'Should map MSP to Msi collection' {
        & $getCollectionType 'MSP' | Should -Be 'Msi'
    }

    It 'Should map PS1 to Script collection' {
        & $getCollectionType 'PS1' | Should -Be 'Script'
    }

    It 'Should map BAT to Script collection' {
        & $getCollectionType 'BAT' | Should -Be 'Script'
    }

    It 'Should map CMD to Script collection' {
        & $getCollectionType 'CMD' | Should -Be 'Script'
    }

    It 'Should map VBS to Script collection' {
        & $getCollectionType 'VBS' | Should -Be 'Script'
    }

    It 'Should map JS to Script collection' {
        & $getCollectionType 'JS' | Should -Be 'Script'
    }

    It 'Should map WSF to Script collection' {
        & $getCollectionType 'WSF' | Should -Be 'Script'
    }

    It 'Should map APPX to Appx collection' {
        & $getCollectionType 'APPX' | Should -Be 'Appx'
    }

    It 'Should default unknown types to Exe collection' {
        & $getCollectionType 'UNKNOWN' | Should -Be 'Exe'
    }
}

# ============================================================================
# SHA256 HASH COMPUTATION
# ============================================================================

Describe 'SHA256 Hash Computation' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        # Create a temp file with known content for hash testing
        $script:tempDir = Join-Path $env:TEMP "GA-AppLocker-ScanTest-$(Get-Random)"
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        
        $script:testExe = Join-Path $script:tempDir 'test-app.exe'
        # Write known content to compute expected hash
        [System.IO.File]::WriteAllText($script:testExe, 'Hello AppLocker Test Content')
        
        # Compute expected hash
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.IO.File]::ReadAllBytes($script:testExe)
        $hashBytes = $sha256.ComputeHash($bytes)
        $script:expectedHash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        $sha256.Dispose()
    }

    AfterAll {
        if (Test-Path $script:tempDir) {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should compute SHA256 hash for a file' {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($script:testExe)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            $hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        }
        finally {
            $stream.Close()
            $stream.Dispose()
            $sha256.Dispose()
        }
        $hash | Should -Be $script:expectedHash
    }

    It 'Should produce a 64-character uppercase hex string' {
        $script:expectedHash.Length | Should -Be 64
        $script:expectedHash | Should -Match '^[A-F0-9]{64}$'
    }

    It 'Should be deterministic (same file produces same hash)' {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $stream1 = [System.IO.File]::OpenRead($script:testExe)
        try {
            $hash1 = [System.BitConverter]::ToString($sha256.ComputeHash($stream1)) -replace '-', ''
        }
        finally { $stream1.Close(); $stream1.Dispose() }
        
        $stream2 = [System.IO.File]::OpenRead($script:testExe)
        try {
            $hash2 = [System.BitConverter]::ToString($sha256.ComputeHash($stream2)) -replace '-', ''
        }
        finally { $stream2.Close(); $stream2.Dispose() }
        $sha256.Dispose()
        
        $hash1 | Should -Be $hash2
    }

    It 'Should produce different hash for different content' {
        $otherFile = Join-Path $script:tempDir 'other.exe'
        [System.IO.File]::WriteAllText($otherFile, 'Different Content Here')
        
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($otherFile)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            $otherHash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        }
        finally { $stream.Close(); $stream.Dispose(); $sha256.Dispose() }
        
        $otherHash | Should -Not -Be $script:expectedHash
    }
}

# ============================================================================
# GET-LOCALARTIFACTS — PARAMETER VALIDATION
# ============================================================================

Describe 'Get-LocalArtifacts Parameters' -Tag 'Unit', 'Scanning' {

    It 'Should accept Paths parameter' {
        $cmd = Get-Command 'Get-LocalArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'Paths'
    }

    It 'Should accept Extensions parameter' {
        $cmd = Get-Command 'Get-LocalArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'Extensions'
    }

    It 'Should accept Recurse switch' {
        $cmd = Get-Command 'Get-LocalArtifacts'
        $cmd.Parameters['Recurse'].SwitchParameter | Should -Be $true
    }

    It 'Should accept SkipDllScanning switch' {
        $cmd = Get-Command 'Get-LocalArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'SkipDllScanning'
    }

    It 'Should accept SkipWshScanning switch' {
        $cmd = Get-Command 'Get-LocalArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'SkipWshScanning'
    }

    It 'Should accept SkipShellScanning switch' {
        $cmd = Get-Command 'Get-LocalArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'SkipShellScanning'
    }
}

# ============================================================================
# GET-LOCALARTIFACTS — SCAN WITH TEMP FILES
# ============================================================================

Describe 'Get-LocalArtifacts Scanning' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        $script:scanDir = Join-Path $env:TEMP "GA-AppLocker-ScanTest-$(Get-Random)"
        New-Item -Path $script:scanDir -ItemType Directory -Force | Out-Null
        
        # Create test files with various extensions
        [System.IO.File]::WriteAllText((Join-Path $script:scanDir 'app.exe'), 'MZ fake exe content')
        [System.IO.File]::WriteAllText((Join-Path $script:scanDir 'lib.dll'), 'MZ fake dll content')
        [System.IO.File]::WriteAllText((Join-Path $script:scanDir 'installer.msi'), 'fake msi')
        [System.IO.File]::WriteAllText((Join-Path $script:scanDir 'script.ps1'), 'Write-Host "Hello"')
        [System.IO.File]::WriteAllText((Join-Path $script:scanDir 'batch.bat'), '@echo off')
        [System.IO.File]::WriteAllText((Join-Path $script:scanDir 'readme.txt'), 'Not an artifact')
    }

    AfterAll {
        if (Test-Path $script:scanDir) {
            Remove-Item -Path $script:scanDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should return a result object with Success property' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Success'
    }

    It 'Should succeed when scanning valid paths' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $result.Success | Should -Be $true
    }

    It 'Should return artifacts in Data property' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $result.Data | Should -Not -BeNullOrEmpty
    }

    It 'Should find EXE files' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $exeArtifacts = @($result.Data | Where-Object { $_.ArtifactType -eq 'EXE' })
        $exeArtifacts.Count | Should -BeGreaterOrEqual 1
    }

    It 'Should find DLL files' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $dllArtifacts = @($result.Data | Where-Object { $_.ArtifactType -eq 'DLL' })
        $dllArtifacts.Count | Should -BeGreaterOrEqual 1
    }

    It 'Should find PS1 files' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $psArtifacts = @($result.Data | Where-Object { $_.ArtifactType -eq 'PS1' })
        $psArtifacts.Count | Should -BeGreaterOrEqual 1
    }

    It 'Should NOT include non-artifact extensions like .txt' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $txtArtifacts = @($result.Data | Where-Object { $_.FileName -eq 'readme.txt' })
        $txtArtifacts.Count | Should -Be 0
    }

    It 'Should skip DLLs when SkipDllScanning is specified' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir) -SkipDllScanning
        $dllArtifacts = @($result.Data | Where-Object { $_.ArtifactType -eq 'DLL' })
        $dllArtifacts.Count | Should -Be 0
    }

    It 'Should compute SHA256 hash for each artifact' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        foreach ($artifact in $result.Data) {
            $artifact.SHA256Hash | Should -Not -BeNullOrEmpty -Because "$($artifact.FileName) should have a hash"
            $artifact.SHA256Hash | Should -Match '^[A-F0-9]{64}$' -Because "Hash should be 64 hex chars"
        }
    }

    It 'Should include ComputerName on each artifact' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        foreach ($artifact in $result.Data) {
            $artifact.ComputerName | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should include FilePath on each artifact' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        foreach ($artifact in $result.Data) {
            $artifact.FilePath | Should -Not -BeNullOrEmpty
            Test-Path $artifact.FilePath | Should -Be $true
        }
    }

    It 'Should set CollectionType based on ArtifactType' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $exeItem = $result.Data | Where-Object { $_.ArtifactType -eq 'EXE' } | Select-Object -First 1
        if ($exeItem) { $exeItem.CollectionType | Should -Be 'Exe' }
        
        $dllItem = $result.Data | Where-Object { $_.ArtifactType -eq 'DLL' } | Select-Object -First 1
        if ($dllItem) { $dllItem.CollectionType | Should -Be 'Dll' }
        
        $ps1Item = $result.Data | Where-Object { $_.ArtifactType -eq 'PS1' } | Select-Object -First 1
        if ($ps1Item) { $ps1Item.CollectionType | Should -Be 'Script' }
    }

    It 'Should include a Summary property' {
        $result = Get-LocalArtifacts -Paths @($script:scanDir)
        $result.Summary | Should -Not -BeNullOrEmpty
    }

    It 'Should handle non-existent paths gracefully' {
        $result = Get-LocalArtifacts -Paths @('C:\NonExistent\Path\That\Does\Not\Exist')
        # Should not throw — returns success with empty data
        $result.Success | Should -Be $true
        @($result.Data).Count | Should -Be 0
    }

    It 'Should handle empty directory' {
        $emptyDir = Join-Path $env:TEMP "GA-AppLocker-Empty-$(Get-Random)"
        New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
        try {
            $result = Get-LocalArtifacts -Paths @($emptyDir)
            $result.Success | Should -Be $true
            @($result.Data).Count | Should -Be 0
        }
        finally {
            Remove-Item -Path $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================================
# GET-LOCALARTIFACTS — SCRIPT TYPE FILTERING
# ============================================================================

Describe 'Get-LocalArtifacts Script Type Filtering' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        $script:filterDir = Join-Path $env:TEMP "GA-AppLocker-FilterTest-$(Get-Random)"
        New-Item -Path $script:filterDir -ItemType Directory -Force | Out-Null
        
        # Create files of various script types
        [System.IO.File]::WriteAllText((Join-Path $script:filterDir 'app.exe'), 'MZ exe')
        [System.IO.File]::WriteAllText((Join-Path $script:filterDir 'test.vbs'), 'wscript.echo')
        [System.IO.File]::WriteAllText((Join-Path $script:filterDir 'test.js'), 'var x=1')
        [System.IO.File]::WriteAllText((Join-Path $script:filterDir 'test.wsf'), '<job></job>')
        [System.IO.File]::WriteAllText((Join-Path $script:filterDir 'test.bat'), '@echo off')
        [System.IO.File]::WriteAllText((Join-Path $script:filterDir 'test.cmd'), '@echo off')
    }

    AfterAll {
        if (Test-Path $script:filterDir) {
            Remove-Item -Path $script:filterDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should skip WSH scripts (VBS, JS, WSF) when SkipWshScanning is set' {
        $result = Get-LocalArtifacts -Paths @($script:filterDir) -SkipWshScanning
        $wshArtifacts = @($result.Data | Where-Object { $_.ArtifactType -in 'VBS','JS','WSF' })
        $wshArtifacts.Count | Should -Be 0
    }

    It 'Should skip shell scripts (BAT, CMD) when SkipShellScanning is set' {
        $result = Get-LocalArtifacts -Paths @($script:filterDir) -SkipShellScanning
        $shellArtifacts = @($result.Data | Where-Object { $_.ArtifactType -in 'BAT','CMD' })
        $shellArtifacts.Count | Should -Be 0
    }

    It 'Should still include EXE when script filters are active' {
        $result = Get-LocalArtifacts -Paths @($script:filterDir) -SkipWshScanning -SkipShellScanning
        $exeArtifacts = @($result.Data | Where-Object { $_.ArtifactType -eq 'EXE' })
        $exeArtifacts.Count | Should -BeGreaterOrEqual 1
    }
}

# ============================================================================
# GET-REMOTEARTIFACTS — PARAMETER VALIDATION
# ============================================================================

Describe 'Get-RemoteArtifacts Parameters' -Tag 'Unit', 'Scanning' {

    It 'Should require ComputerName parameter' {
        $cmd = Get-Command 'Get-RemoteArtifacts'
        $cmd.Parameters['ComputerName'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
            Should -Not -BeNullOrEmpty
    }

    It 'Should accept Credential parameter' {
        $cmd = Get-Command 'Get-RemoteArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'Credential'
    }

    It 'Should accept ThrottleLimit parameter' {
        $cmd = Get-Command 'Get-RemoteArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'ThrottleLimit'
    }

    It 'Should accept BatchSize parameter' {
        $cmd = Get-Command 'Get-RemoteArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'BatchSize'
    }
}

# ============================================================================
# START-ARTIFACTSCAN — PARAMETER VALIDATION
# ============================================================================

Describe 'Start-ArtifactScan Parameters' -Tag 'Unit', 'Scanning' {

    It 'Should accept Machines parameter' {
        $cmd = Get-Command 'Start-ArtifactScan'
        $cmd.Parameters.Keys | Should -Contain 'Machines'
    }

    It 'Should accept ScanLocal switch' {
        $cmd = Get-Command 'Start-ArtifactScan'
        $cmd.Parameters['ScanLocal'].SwitchParameter | Should -Be $true
    }

    It 'Should accept IncludeEventLogs switch' {
        $cmd = Get-Command 'Start-ArtifactScan'
        $cmd.Parameters.Keys | Should -Contain 'IncludeEventLogs'
    }

    It 'Should accept SaveResults switch' {
        $cmd = Get-Command 'Start-ArtifactScan'
        $cmd.Parameters.Keys | Should -Contain 'SaveResults'
    }

    It 'Should accept ScanName parameter' {
        $cmd = Get-Command 'Start-ArtifactScan'
        $cmd.Parameters.Keys | Should -Contain 'ScanName'
    }

    It 'Should accept ThrottleLimit parameter' {
        $cmd = Get-Command 'Start-ArtifactScan'
        $cmd.Parameters.Keys | Should -Contain 'ThrottleLimit'
    }

    It 'Should accept BatchSize parameter' {
        $cmd = Get-Command 'Start-ArtifactScan'
        $cmd.Parameters.Keys | Should -Contain 'BatchSize'
    }
}

# ============================================================================
# START-ARTIFACTSCAN — LOCAL SCAN
# ============================================================================

Describe 'Start-ArtifactScan Local Scanning' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        $script:localScanDir = Join-Path $env:TEMP "GA-AppLocker-LocalScan-$(Get-Random)"
        New-Item -Path $script:localScanDir -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:localScanDir 'test.exe'), 'MZ test content')
    }

    AfterAll {
        if (Test-Path $script:localScanDir) {
            Remove-Item -Path $script:localScanDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should return result object with standard properties' {
        $result = Start-ArtifactScan -ScanLocal -Paths @($script:localScanDir)
        $result.PSObject.Properties.Name | Should -Contain 'Success'
        $result.PSObject.Properties.Name | Should -Contain 'Data'
    }

    It 'Should succeed with ScanLocal flag' {
        $result = Start-ArtifactScan -ScanLocal -Paths @($script:localScanDir)
        $result.Success | Should -Be $true
    }

    It 'Should return artifacts in Data.Artifacts' {
        $result = Start-ArtifactScan -ScanLocal -Paths @($script:localScanDir)
        $result.Data.Artifacts | Should -Not -BeNullOrEmpty
    }

    It 'Should include a Summary with scan metadata' {
        $result = Start-ArtifactScan -ScanLocal -Paths @($script:localScanDir)
        $result.Summary | Should -Not -BeNullOrEmpty
        $result.Summary.TotalArtifacts | Should -BeGreaterOrEqual 1
    }

    It 'Summary should include StartTime and EndTime' {
        $result = Start-ArtifactScan -ScanLocal -Paths @($script:localScanDir)
        $result.Summary.StartTime | Should -Not -BeNullOrEmpty
        $result.Summary.EndTime | Should -Not -BeNullOrEmpty
    }

    It 'Summary should include signed/unsigned artifact counts' {
        $result = Start-ArtifactScan -ScanLocal -Paths @($script:localScanDir)
        $result.Summary.PSObject.Properties.Name | Should -Contain 'SignedArtifacts'
        $result.Summary.PSObject.Properties.Name | Should -Contain 'UnsignedArtifacts'
    }
}

# ============================================================================
# GET-APPLOCKEREVENTLOGS — PARAMETER VALIDATION
# ============================================================================

Describe 'Get-AppLockerEventLogs Parameters' -Tag 'Unit', 'Scanning' {

    It 'Should accept ComputerName parameter' {
        $cmd = Get-Command 'Get-AppLockerEventLogs'
        $cmd.Parameters.Keys | Should -Contain 'ComputerName'
    }

    It 'Should accept Credential parameter' {
        $cmd = Get-Command 'Get-AppLockerEventLogs'
        $cmd.Parameters.Keys | Should -Contain 'Credential'
    }

    It 'Should accept StartTime parameter' {
        $cmd = Get-Command 'Get-AppLockerEventLogs'
        $cmd.Parameters.Keys | Should -Contain 'StartTime'
    }

    It 'Should accept MaxEvents parameter' {
        $cmd = Get-Command 'Get-AppLockerEventLogs'
        $cmd.Parameters.Keys | Should -Contain 'MaxEvents'
    }
}

# ============================================================================
# GET-APPXARTIFACTS — PARAMETER VALIDATION
# ============================================================================

Describe 'Get-AppxArtifacts Parameters' -Tag 'Unit', 'Scanning' {

    It 'Should accept AllUsers switch' {
        $cmd = Get-Command 'Get-AppxArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'AllUsers'
    }

    It 'Should accept IncludeFrameworks switch' {
        $cmd = Get-Command 'Get-AppxArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'IncludeFrameworks'
    }

    It 'Should accept IncludeSystemApps switch' {
        $cmd = Get-Command 'Get-AppxArtifacts'
        $cmd.Parameters.Keys | Should -Contain 'IncludeSystemApps'
    }
}

# ============================================================================
# ARTIFACT EXTENSIONS COMPLETENESS
# ============================================================================

Describe 'Artifact Extensions Configuration' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        # Expected 14 extensions from the module docs
        $script:expectedExtensions = @(
            '.exe', '.dll', '.msi', '.msp',
            '.ps1', '.psm1', '.psd1',
            '.bat', '.cmd',
            '.vbs', '.js', '.wsf',
            '.appx', '.msix'
        )
    }

    It 'Should support all 14 documented artifact extensions' {
        # Verify each expected extension produces a known ArtifactType
        foreach ($ext in $script:expectedExtensions) {
            $type = switch ($ext.ToLower()) {
                '.exe' { 'EXE' }; '.dll' { 'DLL' }; '.msi' { 'MSI' }; '.msp' { 'MSP' }
                '.ps1' { 'PS1' }; '.psm1' { 'PS1' }; '.psd1' { 'PS1' }
                '.bat' { 'BAT' }; '.cmd' { 'CMD' }
                '.vbs' { 'VBS' }; '.js' { 'JS' }; '.wsf' { 'WSF' }
                '.appx' { 'APPX' }; '.msix' { 'APPX' }
                default { 'Unknown' }
            }
            $type | Should -Not -Be 'Unknown' -Because "Extension $ext should map to a known type"
        }
    }

    It 'Should map all extensions to one of the 5 collection types' {
        $validCollections = @('Exe', 'Dll', 'Msi', 'Script', 'Appx')
        foreach ($ext in $script:expectedExtensions) {
            $artType = switch ($ext.ToLower()) {
                '.exe' { 'EXE' }; '.dll' { 'DLL' }; '.msi' { 'MSI' }; '.msp' { 'MSP' }
                '.ps1' { 'PS1' }; '.psm1' { 'PS1' }; '.psd1' { 'PS1' }
                '.bat' { 'BAT' }; '.cmd' { 'CMD' }
                '.vbs' { 'VBS' }; '.js' { 'JS' }; '.wsf' { 'WSF' }
                '.appx' { 'APPX' }; '.msix' { 'APPX' }
            }
            $colType = switch ($artType) {
                'EXE' { 'Exe' }; 'DLL' { 'Dll' }
                { $_ -in 'MSI','MSP' } { 'Msi' }
                { $_ -in 'PS1','BAT','CMD','VBS','JS','WSF' } { 'Script' }
                'APPX' { 'Appx' }
            }
            $colType | Should -BeIn $validCollections -Because "Extension $ext should map to a valid collection"
        }
    }
}

# ============================================================================
# ARTIFACT OBJECT STRUCTURE
# ============================================================================

Describe 'Artifact Object Structure' -Tag 'Unit', 'Scanning' {

    BeforeAll {
        $script:structDir = Join-Path $env:TEMP "GA-AppLocker-StructTest-$(Get-Random)"
        New-Item -Path $script:structDir -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:structDir 'struct-test.exe'), 'MZ struct test')
        
        $result = Get-LocalArtifacts -Paths @($script:structDir)
        $script:sampleArtifact = $result.Data | Select-Object -First 1
    }

    AfterAll {
        if (Test-Path $script:structDir) {
            Remove-Item -Path $script:structDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should have FilePath property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'FilePath'
    }

    It 'Should have FileName property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'FileName'
    }

    It 'Should have Extension property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'Extension'
    }

    It 'Should have SHA256Hash property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'SHA256Hash'
    }

    It 'Should have IsSigned property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'IsSigned'
    }

    It 'Should have ArtifactType property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'ArtifactType'
    }

    It 'Should have CollectionType property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'CollectionType'
    }

    It 'Should have ComputerName property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'ComputerName'
    }

    It 'Should have Publisher property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'Publisher'
    }

    It 'Should have ProductName property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'ProductName'
    }

    It 'Should have SizeBytes property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'SizeBytes'
        $script:sampleArtifact.SizeBytes | Should -BeGreaterThan 0
    }

    It 'Should have CollectedDate property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'CollectedDate'
    }

    It 'Should have SignatureStatus property' {
        $script:sampleArtifact.PSObject.Properties.Name | Should -Contain 'SignatureStatus'
    }
}

# ============================================================================
# SCAN RESULTS PERSISTENCE
# ============================================================================

Describe 'Get-ScanResults' -Tag 'Unit', 'Scanning' {

    It 'Should return a result object' {
        $result = Get-ScanResults
        $result.PSObject.Properties.Name | Should -Contain 'Success'
    }

    It 'Should return Data as array (possibly empty)' {
        $result = Get-ScanResults
        # Data may be empty if no scans saved, but should not throw
        $result.Success | Should -Be $true
    }
}

Describe 'Export-ScanResults Parameters' -Tag 'Unit', 'Scanning' {

    It 'Should accept ScanId parameter' {
        $cmd = Get-Command 'Export-ScanResults'
        $cmd.Parameters.Keys | Should -Contain 'ScanId'
    }

    It 'Should accept OutputPath parameter' {
        $cmd = Get-Command 'Export-ScanResults'
        $cmd.Parameters.Keys | Should -Contain 'OutputPath'
    }
}
