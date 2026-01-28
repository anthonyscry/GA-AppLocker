<#
.SYNOPSIS
    Async rule generation helpers for the Rules panel.
.DESCRIPTION
    Contains the async runspace management code for rule generation,
    extracted from Rules.ps1 to reduce file size and improve maintainability.
#>

function global:Start-RuleGenerationAsync {
    <#
    .SYNOPSIS
        Starts async rule generation from artifacts.
    .DESCRIPTION
        Sets up a background runspace to generate rules from artifacts
        and monitors progress via a DispatcherTimer.
    #>
    param(
        [System.Windows.Window]$Window,
        [array]$Artifacts,
        [string]$Mode = 'Smart',
        [string]$Action = 'Allow',
        [string]$TargetGroupSid = 'S-1-5-11',
        [string]$PublisherLevel = 'PublisherProduct',
        [scriptblock]$OnComplete
    )
    
    # Create sync hashtable for async communication
    Write-RuleLog -Message "DEBUG Creating SyncHash with PublisherLevel=$PublisherLevel"
    $script:RuleGenSyncHash = [hashtable]::Synchronized(@{
        Window = $Window
        Artifacts = @($Artifacts)
        Mode = $Mode
        Action = $Action
        TargetGroupSid = $TargetGroupSid
        PublisherLevel = $PublisherLevel
        Generated = 0
        Failed = 0
        Progress = 0
        ProgressMessage = ''
        Summary = $null
        IsComplete = $false
        Error = $null
    })

    # Create runspace for background processing
    $script:RuleGenRunspace = [runspacefactory]::CreateRunspace()
    $script:RuleGenRunspace.ApartmentState = 'STA'
    $script:RuleGenRunspace.ThreadOptions = 'ReuseThread'
    $script:RuleGenRunspace.Open()
    $script:RuleGenRunspace.SessionStateProxy.SetVariable('SyncHash', $script:RuleGenSyncHash)

    # Get module path - try multiple methods
    $modulePath = $null
    $gaModule = Get-Module GA-AppLocker -ErrorAction SilentlyContinue
    if ($gaModule) {
        $modulePath = $gaModule.ModuleBase
    }
    if (-not $modulePath) {
        # Fallback: look relative to GUI folder
        $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        if (-not (Test-Path (Join-Path $modulePath "GA-AppLocker.psd1"))) {
            $modulePath = Join-Path $PSScriptRoot "..\..\"
        }
    }
    $script:RuleGenRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:RuleGenPowerShell = [powershell]::Create()
    $script:RuleGenPowerShell.Runspace = $script:RuleGenRunspace

    [void]$script:RuleGenPowerShell.AddScript({
        param($SyncHash, $ModulePath)
        
        try {
            # Import module in runspace
            $manifestPath = Join-Path $ModulePath "GA-AppLocker.psd1"
            if (-not (Test-Path $manifestPath)) {
                throw "Module not found at: $manifestPath"
            }
            Import-Module $manifestPath -Force -ErrorAction Stop

            # DEBUG: Log what we received in the runspace
            Write-RuleLog -Message "DEBUG Runspace: SyncHash.PublisherLevel = '$($SyncHash.PublisherLevel)'"

            # Use batch generation for 10x+ performance improvement
            $batchParams = @{
                Artifacts = $SyncHash.Artifacts
                Mode = $SyncHash.Mode
                Action = $SyncHash.Action
                UserOrGroupSid = $SyncHash.TargetGroupSid
                Status = 'Pending'
                DedupeMode = 'Smart'
            }
            
            # Add publisher level if specified
            if ($SyncHash.PublisherLevel) {
                $batchParams['PublisherLevel'] = $SyncHash.PublisherLevel
                Write-RuleLog -Message "DEBUG Runspace: Added PublisherLevel='$($SyncHash.PublisherLevel)' to batchParams"
            } else {
                Write-RuleLog -Message "DEBUG Runspace: PublisherLevel was NULL/EMPTY - using default!"
            }
            
            # Progress callback to update sync hash
            $batchParams['OnProgress'] = {
                param($pct, $msg)
                $SyncHash.Progress = $pct
                $SyncHash.ProgressMessage = $msg
            }.GetNewClosure()
            
            $result = Invoke-BatchRuleGeneration @batchParams
            
            $SyncHash.Generated = $result.RulesCreated
            $SyncHash.Failed = $result.Errors.Count
            $SyncHash.Summary = $result.Summary
        }
        catch {
            $SyncHash.Error = $_.Exception.Message
        }
        finally {
            $SyncHash.IsComplete = $true
        }
    })

    [void]$script:RuleGenPowerShell.AddArgument($script:RuleGenSyncHash)
    [void]$script:RuleGenPowerShell.AddArgument($modulePath)

    # Start async
    $script:RuleGenAsyncResult = $script:RuleGenPowerShell.BeginInvoke()

    # Timer to check completion
    $script:RuleGenTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:RuleGenTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    
    # Store callback reference
    $script:RuleGenOnComplete = $OnComplete
    
    $script:RuleGenTimer.Add_Tick({
        $syncHash = $script:RuleGenSyncHash
        
        # Update progress display from batch operation
        if ($syncHash.Progress -gt 0 -and -not $syncHash.IsComplete) {
            $msg = if ($syncHash.ProgressMessage) { $syncHash.ProgressMessage } else { "$($syncHash.Progress)% complete" }
            Update-LoadingText -Message "Generating Rules..." -SubMessage $msg
        }
        
        if ($syncHash.IsComplete) {
            $script:RuleGenTimer.Stop()
            
            # Hide loading overlay
            Hide-LoadingOverlay
            
            # Cleanup
            try { $script:RuleGenPowerShell.EndInvoke($script:RuleGenAsyncResult) } catch {}
            if ($script:RuleGenPowerShell) { $script:RuleGenPowerShell.Dispose() }
            if ($script:RuleGenRunspace) { 
                $script:RuleGenRunspace.Close()
                $script:RuleGenRunspace.Dispose()
            }

            # Call completion callback if provided
            if ($script:RuleGenOnComplete) {
                & $script:RuleGenOnComplete $syncHash
            }
        }
    })

    $script:RuleGenTimer.Start()
}

function global:Get-FilteredArtifactsForRuleGeneration {
    <#
    .SYNOPSIS
        Filters artifacts to exclude those that already have rules.
    .DESCRIPTION
        Uses the existing rule index to filter out artifacts that are already
        covered by existing rules (by hash or publisher).
    #>
    param(
        [array]$Artifacts,
        [string]$PublisherLevel = 'PublisherProduct'
    )
    
    $originalCount = $Artifacts.Count
    $artifactsToProcess = @($Artifacts)
    
    try {
        $ruleIndex = Get-ExistingRuleIndex
        if ($ruleIndex.HashCount -gt 0 -or $ruleIndex.PublisherCount -gt 0) {
            $artifactsToProcess = @($Artifacts | Where-Object {
                $dominated = $false
                # Check hash rules
                if ($_.SHA256Hash -and $ruleIndex.Hashes.Contains($_.SHA256Hash)) {
                    $dominated = $true
                }
                # Check publisher rules (for signed files)
                if (-not $dominated -and $_.IsSigned -and $_.Publisher) {
                    # Respect PublisherLevel when checking existing rules
                    $pubKey = if ($PublisherLevel -eq 'PublisherOnly') {
                        $_.Publisher.ToLower()
                    } else {
                        "$($_.Publisher)|$($_.ProductName)".ToLower()
                    }
                    # Use correct index based on PublisherLevel
                    $indexToCheck = if ($PublisherLevel -eq 'PublisherOnly') {
                        $ruleIndex.PublishersOnly
                    } else {
                        $ruleIndex.Publishers
                    }
                    if ($indexToCheck -and $indexToCheck.Contains($pubKey)) {
                        $dominated = $true
                    }
                }
                -not $dominated
            })
            
            $skipped = $originalCount - $artifactsToProcess.Count
            if ($skipped -gt 0) {
                Write-Log -Message "Filtered $skipped artifacts that already have rules"
            }
        }
    }
    catch {
        Write-Log -Level Warning -Message "Could not filter existing rules: $($_.Exception.Message)"
    }
    
    return @{
        Artifacts = $artifactsToProcess
        OriginalCount = $originalCount
        SkippedCount = $originalCount - $artifactsToProcess.Count
    }
}

function global:Get-DeduplicatedArtifacts {
    <#
    .SYNOPSIS
        Deduplicates artifacts by hash or publisher.
    .DESCRIPTION
        Removes duplicate artifacts (same file in multiple locations) to avoid
        creating redundant rules.
    #>
    param(
        [array]$Artifacts,
        [string]$Mode = 'Smart',
        [string]$PublisherLevel = 'PublisherProduct'
    )
    
    $beforeDedupeCount = $Artifacts.Count
    $seenHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenPublishers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $dedupedArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    foreach ($artifact in $Artifacts) {
        $dominated = $false
        
        # For Publisher mode or Smart mode with signed files, dedupe by publisher+product
        if ($Mode -in @('Publisher', 'Smart') -and $artifact.IsSigned -and $artifact.Publisher) {
            # Respect PublisherLevel when deduplicating
            $pubKey = if ($PublisherLevel -eq 'PublisherOnly') {
                $artifact.Publisher.ToLower()
            } else {
                "$($artifact.Publisher)|$($artifact.ProductName)".ToLower()
            }
            if ($seenPublishers.Contains($pubKey)) {
                $dominated = $true
            }
            else {
                [void]$seenPublishers.Add($pubKey)
            }
        }
        
        # For Hash mode or unsigned files in Smart mode, dedupe by hash
        if (-not $dominated -and $artifact.SHA256Hash) {
            if ($Mode -eq 'Hash' -or ($Mode -eq 'Smart' -and -not $artifact.IsSigned)) {
                if ($seenHashes.Contains($artifact.SHA256Hash)) {
                    $dominated = $true
                }
                else {
                    [void]$seenHashes.Add($artifact.SHA256Hash)
                }
            }
        }
        
        if (-not $dominated) {
            $dedupedArtifacts.Add($artifact)
        }
    }
    
    $dedupedCount = $beforeDedupeCount - $dedupedArtifacts.Count
    if ($dedupedCount -gt 0) {
        Write-Log -Message "Deduplicated $dedupedCount artifacts (same hash/publisher) - processing $($dedupedArtifacts.Count) unique"
    }
    
    return @{
        Artifacts = $dedupedArtifacts.ToArray()
        OriginalCount = $beforeDedupeCount
        DedupedCount = $dedupedCount
    }
}
