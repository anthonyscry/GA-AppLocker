#region ===== BACKUP & RESTORE =====
<#
.SYNOPSIS
    Backup and restore functionality for GA-AppLocker configuration and data.

.DESCRIPTION
    Creates full backups of all GA-AppLocker data including rules, policies,
    settings, credentials (encrypted), and audit logs. Supports restore with
    validation.


    .EXAMPLE
    Backup-AppLockerData
    # Backup AppLockerData
    #>

function Backup-AppLockerData {
    <#
    .SYNOPSIS
        Creates a full backup of GA-AppLocker data.

    .DESCRIPTION
        Creates a full backup of GA-AppLocker data. Creates a backup copy for disaster recovery.

    .PARAMETER OutputPath
        Path for the backup file (.zip).

    .PARAMETER IncludeCredentials
        Include encrypted credential files (default: $true).

    .PARAMETER IncludeAuditLog
        Include audit log history (default: $true).

    .PARAMETER Description
        Optional description for the backup.

    .EXAMPLE
        Backup-AppLockerData -OutputPath 'C:\Backups\applocker-backup.zip'

    .EXAMPLE
        Backup-AppLockerData -OutputPath 'C:\Backups\backup.zip' -Description 'Pre-upgrade backup'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [switch]$IncludeCredentials = $true,
        [switch]$IncludeAuditLog = $true,

        [string]$Description = ''
    )

    try {
        # Ensure .zip extension
        if (-not $OutputPath.EndsWith('.zip')) {
            $OutputPath = "$OutputPath.zip"
        }

        # Create temp directory for staging
        $tempDir = Join-Path $env:TEMP "GAAppLocker_Backup_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        $backupManifest = @{
            BackupVersion = '1.0'
            CreatedAt = Get-Date -Format 'o'
            CreatedBy = "$env:USERDOMAIN\$env:USERNAME"
            Computer = $env:COMPUTERNAME
            Description = $Description
            Contents = @()
        }

        # Get data path
        $dataPath = if (Get-Command 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
            Get-AppLockerDataPath
        } else {
            Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
        }

        # Backup Rules (JSON index and rule files)
        $indexPath = Join-Path $dataPath 'rules-index.json'
        if (Test-Path $indexPath) {
            Copy-Item $indexPath (Join-Path $tempDir 'rules-index.json') -Force
            [void]$backupManifest.Contents.Add(@{ Type = 'RulesIndex'; File = 'rules-index.json'; Size = (Get-Item $indexPath).Length })
        }

        $rulesPath = Join-Path $dataPath 'Rules'
        if (Test-Path $rulesPath) {
            $rulesDir = Join-Path $tempDir 'Rules'
            Copy-Item $rulesPath $rulesDir -Recurse -Force
            $ruleFiles = Get-ChildItem $rulesPath -Filter '*.json' -File -ErrorAction SilentlyContinue
            [void]$backupManifest.Contents.Add(@{ Type = 'Rules'; Folder = 'Rules'; FileCount = $ruleFiles.Count })
        }

        # Backup Policies
        $policiesPath = Join-Path $dataPath 'Policies'
        if (Test-Path $policiesPath) {
            $policiesDir = Join-Path $tempDir 'Policies'
            Copy-Item $policiesPath $policiesDir -Recurse -Force
            $policyFiles = Get-ChildItem $policiesPath -Recurse -File
            $backupManifest.Contents += @{ Type = 'Policies'; Folder = 'Policies'; FileCount = $policyFiles.Count }
        }

        # Backup Configuration (check both legacy config.json and current Settings\settings.json)
        $configPath = Join-Path $dataPath 'config.json'
        if (Test-Path $configPath) {
            Copy-Item $configPath (Join-Path $tempDir 'config.json') -Force
            $backupManifest.Contents += @{ Type = 'Config'; File = 'config.json' }
        }
        $settingsPath = Join-Path $dataPath 'Settings\settings.json'
        if (Test-Path $settingsPath) {
            $settingsDir = Join-Path $tempDir 'Settings'
            if (-not (Test-Path $settingsDir)) {
                New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item $settingsPath (Join-Path $settingsDir 'settings.json') -Force
            $backupManifest.Contents += @{ Type = 'Settings'; File = 'Settings\settings.json' }
        }

        # Backup Credentials (encrypted)
        if ($IncludeCredentials) {
            $credsPath = Join-Path $dataPath 'Credentials'
            if (Test-Path $credsPath) {
                $credsDir = Join-Path $tempDir 'Credentials'
                Copy-Item $credsPath $credsDir -Recurse -Force
                $credFiles = Get-ChildItem $credsPath -Recurse -File
                $backupManifest.Contents += @{ Type = 'Credentials'; Folder = 'Credentials'; FileCount = $credFiles.Count }
            }
        }

        # Backup Audit Logs
        if ($IncludeAuditLog) {
            $logsPath = Join-Path $dataPath 'Logs'
            if (Test-Path $logsPath) {
                $logsDir = Join-Path $tempDir 'Logs'
                New-Item $logsDir -ItemType Directory -Force | Out-Null
                
                # Only copy audit log files (not general logs)
                Get-ChildItem $logsPath -Filter 'audit*.json' | ForEach-Object {
                    Copy-Item $_.FullName $logsDir -Force
                }
                $auditFiles = Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue
                $backupManifest.Contents += @{ Type = 'AuditLogs'; Folder = 'Logs'; FileCount = ($auditFiles | Measure-Object).Count }
            }
        }

        # Backup Policy Snapshots
        $snapshotsPath = Join-Path $dataPath 'Snapshots'
        if (Test-Path $snapshotsPath) {
            $snapshotsDir = Join-Path $tempDir 'Snapshots'
            Copy-Item $snapshotsPath $snapshotsDir -Recurse -Force
            $snapshotFiles = Get-ChildItem $snapshotsPath -Recurse -File
            $backupManifest.Contents += @{ Type = 'Snapshots'; Folder = 'Snapshots'; FileCount = $snapshotFiles.Count }
        }

        # Backup Rule History
        $historyPath = Join-Path $dataPath 'RuleHistory'
        if (Test-Path $historyPath) {
            $historyDir = Join-Path $tempDir 'RuleHistory'
            Copy-Item $historyPath $historyDir -Recurse -Force
            $historyFiles = Get-ChildItem $historyPath -Recurse -File
            $backupManifest.Contents += @{ Type = 'RuleHistory'; Folder = 'RuleHistory'; FileCount = $historyFiles.Count }
        }

        # Write manifest
        $backupManifest | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $tempDir 'manifest.json') -Force

        # Create zip
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # Remove existing backup if present
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force
        }

        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $OutputPath -Force

        # Cleanup temp
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        # Get final size
        $backupSize = (Get-Item $OutputPath).Length

        # Audit log
        if (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue) {
            Write-AuditLog -Action 'BackupCreated' -Category 'System' -Target $OutputPath `
                -Details "Size: $([math]::Round($backupSize / 1MB, 2)) MB, Items: $($backupManifest.Contents.Count)" | Out-Null
        }

        return @{
            Success = $true
            Data = @{
                Path = $OutputPath
                Size = $backupSize
                SizeMB = [math]::Round($backupSize / 1MB, 2)
                CreatedAt = $backupManifest.CreatedAt
                Contents = $backupManifest.Contents
            }
            Error = $null
        }
    }
    catch {
        # Cleanup on error
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Restore-AppLockerData {
    <#
    .SYNOPSIS
        Restores GA-AppLocker data from a backup.

    .DESCRIPTION
        Restores GA-AppLocker data from a backup. Restores from a previously saved version.

    .PARAMETER BackupPath
        Path to the backup .zip file.

    .PARAMETER RestoreCredentials
        Restore credential files (default: $true). Note: DPAPI-encrypted credentials
        may only work on the original machine/user.

    .PARAMETER RestoreAuditLog
        Restore audit log history (default: $true).

    .PARAMETER Force
        Overwrite existing data without prompting.

    .EXAMPLE
        Restore-AppLockerData -BackupPath 'C:\Backups\applocker-backup.zip'

    .EXAMPLE
        Restore-AppLockerData -BackupPath 'C:\Backups\backup.zip' -Force
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$BackupPath,

        [switch]$RestoreCredentials = $true,
        [switch]$RestoreAuditLog = $true,
        [switch]$Force
    )

    try {
        # Create temp directory for extraction
        $tempDir = Join-Path $env:TEMP "GAAppLocker_Restore_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        # Extract backup
        Expand-Archive -Path $BackupPath -DestinationPath $tempDir -Force

        # Read manifest
        $manifestPath = Join-Path $tempDir 'manifest.json'
        if (-not (Test-Path $manifestPath)) {
            throw "Invalid backup: manifest.json not found"
        }

        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

        # Validate backup version
        if ($manifest.BackupVersion -ne '1.0') {
            Write-Warning "Backup version mismatch: expected 1.0, got $($manifest.BackupVersion)"
        }

        # Get data path
        $dataPath = if (Get-Command 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue) {
            Get-AppLockerDataPath
        } else {
            Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
        }

        # Ensure data path exists
        if (-not (Test-Path $dataPath)) {
            New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
        }

        $restoredItems = @()

        # Restore rules index
        $indexBackup = Join-Path $tempDir 'rules-index.json'
        if (Test-Path $indexBackup) {
            $indexTarget = Join-Path $dataPath 'rules-index.json'
            if ((Test-Path $indexTarget) -and -not $Force) {
                Write-Warning "Rules index exists. Use -Force to overwrite."
            } else {
                Copy-Item $indexBackup $indexTarget -Force
                $restoredItems += 'Rules Index (rules-index.json)'
            }
        }
        
        # Restore Rules folder
        $rulesBackup = Join-Path $tempDir 'Rules'
        if (Test-Path $rulesBackup) {
            $rulesTarget = Join-Path $dataPath 'Rules'
            if (-not (Test-Path $rulesTarget)) {
                New-Item -Path $rulesTarget -ItemType Directory -Force | Out-Null
            }
            Copy-Item "$rulesBackup\*" $rulesTarget -Recurse -Force
            $ruleCount = (Get-ChildItem $rulesBackup -Filter '*.json' -File).Count
            $restoredItems += "Rules ($ruleCount files)"
            
            # Reset cache to pick up restored rules
            if (Get-Command -Name 'Reset-RulesIndexCache' -ErrorAction SilentlyContinue) {
                Reset-RulesIndexCache
            }
        }

        # Restore Policies
        $policiesBackup = Join-Path $tempDir 'Policies'
        if (Test-Path $policiesBackup) {
            $policiesTarget = Join-Path $dataPath 'Policies'
            if (-not (Test-Path $policiesTarget)) {
                New-Item -Path $policiesTarget -ItemType Directory -Force | Out-Null
            }
            Copy-Item (Join-Path $policiesBackup '*') $policiesTarget -Recurse -Force
            $restoredItems += 'Policies'
        }

        # Restore Config
        $configBackup = Join-Path $tempDir 'config.json'
        if (Test-Path $configBackup) {
            Copy-Item $configBackup (Join-Path $dataPath 'config.json') -Force
            $restoredItems += 'Configuration'
        }
        # Restore Settings (Settings\settings.json)
        $settingsBackup = Join-Path $tempDir 'Settings\settings.json'
        if (Test-Path $settingsBackup) {
            $settingsTarget = Join-Path $dataPath 'Settings'
            if (-not (Test-Path $settingsTarget)) {
                New-Item -Path $settingsTarget -ItemType Directory -Force | Out-Null
            }
            Copy-Item $settingsBackup (Join-Path $settingsTarget 'settings.json') -Force
            $restoredItems += 'Settings'
        }

        # Restore Credentials
        if ($RestoreCredentials) {
            $credsBackup = Join-Path $tempDir 'Credentials'
            if (Test-Path $credsBackup) {
                $credsTarget = Join-Path $dataPath 'Credentials'
                if (-not (Test-Path $credsTarget)) {
                    New-Item -Path $credsTarget -ItemType Directory -Force | Out-Null
                }
                Copy-Item (Join-Path $credsBackup '*') $credsTarget -Recurse -Force
                $restoredItems += 'Credentials'
                Write-Warning "Credentials restored. DPAPI-encrypted credentials may only work on the original machine/user."
            }
        }

        # Restore Audit Logs
        if ($RestoreAuditLog) {
            $logsBackup = Join-Path $tempDir 'Logs'
            if (Test-Path $logsBackup) {
                $logsTarget = Join-Path $dataPath 'Logs'
                if (-not (Test-Path $logsTarget)) {
                    New-Item -Path $logsTarget -ItemType Directory -Force | Out-Null
                }
                Copy-Item (Join-Path $logsBackup '*') $logsTarget -Recurse -Force
                $restoredItems += 'Audit Logs'
            }
        }

        # Restore Snapshots
        $snapshotsBackup = Join-Path $tempDir 'Snapshots'
        if (Test-Path $snapshotsBackup) {
            $snapshotsTarget = Join-Path $dataPath 'Snapshots'
            if (-not (Test-Path $snapshotsTarget)) {
                New-Item -Path $snapshotsTarget -ItemType Directory -Force | Out-Null
            }
            Copy-Item (Join-Path $snapshotsBackup '*') $snapshotsTarget -Recurse -Force
            $restoredItems += 'Policy Snapshots'
        }

        # Restore Rule History
        $historyBackup = Join-Path $tempDir 'RuleHistory'
        if (Test-Path $historyBackup) {
            $historyTarget = Join-Path $dataPath 'RuleHistory'
            if (-not (Test-Path $historyTarget)) {
                New-Item -Path $historyTarget -ItemType Directory -Force | Out-Null
            }
            Copy-Item (Join-Path $historyBackup '*') $historyTarget -Recurse -Force
            $restoredItems += 'Rule History'
        }

        # Cleanup temp
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        # Audit log
        if (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue) {
            Write-AuditLog -Action 'BackupRestored' -Category 'System' -Target $BackupPath `
                -Details "Restored: $($restoredItems -join ', ')" | Out-Null
        }

        return @{
            Success = $true
            Data = @{
                BackupPath = $BackupPath
                BackupCreatedAt = $manifest.CreatedAt
                BackupCreatedBy = $manifest.CreatedBy
                RestoredItems = $restoredItems
            }
            Error = $null
        }
    }
    catch {
        # Cleanup on error
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

function Get-BackupHistory {
    <#
    .SYNOPSIS
        Lists available backups in a directory.

    .DESCRIPTION
        Lists available backups in a directory. Returns the requested data in a standard result object.

    .PARAMETER BackupDirectory
        Directory containing backup files.

    .PARAMETER Last
        Return only the last N backups.

    .EXAMPLE
        Get-BackupHistory -BackupDirectory 'C:\Backups'

    .EXAMPLE
        Get-BackupHistory -BackupDirectory 'C:\Backups' -Last 5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$BackupDirectory,

        [int]$Last = 0
    )

    try {
        $backups = @()
        
        $zipFiles = Get-ChildItem -Path $BackupDirectory -Filter '*.zip' -File | 
            Sort-Object LastWriteTime -Descending

        if ($Last -gt 0) {
            $zipFiles = $zipFiles | Select-Object -First $Last
        }

        foreach ($zip in $zipFiles) {
            $backupInfo = @{
                Path = $zip.FullName
                FileName = $zip.Name
                Size = $zip.Length
                SizeMB = [math]::Round($zip.Length / 1MB, 2)
                ModifiedDate = $zip.LastWriteTime
                IsValid = $false
                Manifest = $null
            }

            # Try to read manifest from zip using Expand-Archive (Shell.Application extracts
            # with original filename, not the random temp name, causing Test-Path to always fail)
            try {
                $tempExtractDir = Join-Path $env:TEMP "GABackup_Check_$(Get-Random)"
                New-Item $tempExtractDir -ItemType Directory -Force | Out-Null
                try {
                    Expand-Archive -Path $zip.FullName -DestinationPath $tempExtractDir -Force
                    $tempManifest = Join-Path $tempExtractDir 'manifest.json'
                    if (Test-Path $tempManifest) {
                        $manifest = Get-Content $tempManifest -Raw | ConvertFrom-Json
                        $backupInfo.IsValid = $true
                        $backupInfo.Manifest = @{
                            CreatedAt = $manifest.CreatedAt
                            CreatedBy = $manifest.CreatedBy
                            Computer = $manifest.Computer
                            Description = $manifest.Description
                            Contents = $manifest.Contents
                        }
                    }
                }
                finally {
                    Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Couldn't read manifest - might still be valid backup
                Write-AppLockerLog -Level Debug -NoConsole -Message "Empty catch in Get-BackupHistory (manifest read): $($_.Exception.Message)"
                $backupInfo.IsValid = $false
            }

            $backups += [PSCustomObject]$backupInfo
        }

        return @{
            Success = $true
            Data = $backups
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion
