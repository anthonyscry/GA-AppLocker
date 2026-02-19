<#
.SYNOPSIS
    Drag-and-Drop support for GA-AppLocker Dashboard.

.DESCRIPTION
    Implements drag-and-drop functionality for:
    - Dropping files onto Scanner panel to scan them
    - Dropping files onto Rules panel to create rules from artifacts
    - Dragging rules between policies
    - Dropping exported XML files to import

.NOTES
    Load this file in MainWindow.xaml.ps1 and call Register-DragDropHandlers
    after the window is created.
#>

#region ===== DRAG-DROP REGISTRATION =====

function Register-DragDropHandlers {
    <#
    .SYNOPSIS
        Registers drag-and-drop handlers on relevant UI elements.

    .PARAMETER Window
        The WPF Window to register handlers on.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Window
    )

    # Enable drop on the main window
    $Window.AllowDrop = $true

    # Register window-level drop handler for file drops
    $Window.add_Drop({
        param($sender, $e)
        Invoke-WindowDrop -Window $sender -DragEventArgs $e
    })

    $Window.add_DragOver({
        param($sender, $e)
        Invoke-DragOver -Window $sender -DragEventArgs $e
    })

    # Register panel-specific handlers
    Register-ScannerPanelDrop -Window $Window
    Register-RulesPanelDrop -Window $Window
    Register-PolicyPanelDrop -Window $Window

    Write-Log -Message "Drag-and-drop handlers registered"
}

function Register-ScannerPanelDrop {
    <#
    .SYNOPSIS
        Registers drop handler for the Scanner panel.
    #>
    param($Window)

    $scannerPanel = $Window.FindName('PanelScanner')
    if ($scannerPanel) {
        $scannerPanel.AllowDrop = $true
        
        $scannerPanel.add_Drop({
            param($sender, $e)
            Invoke-ScannerPanelDrop -Window $global:GA_MainWindow -DragEventArgs $e
        })

        $scannerPanel.add_DragOver({
            param($sender, $e)
            if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
                $e.Effects = [System.Windows.DragDropEffects]::Copy
            }
            else {
                $e.Effects = [System.Windows.DragDropEffects]::None
            }
            $e.Handled = $true
        })
    }

    # Also register on the artifacts data grid area
    $artifactsDropZone = $Window.FindName('ArtifactsDropZone')
    if ($artifactsDropZone) {
        $artifactsDropZone.AllowDrop = $true
        
        $artifactsDropZone.add_Drop({
            param($sender, $e)
            Invoke-ScannerPanelDrop -Window $global:GA_MainWindow -DragEventArgs $e
        })
    }
}

function Register-RulesPanelDrop {
    <#
    .SYNOPSIS
        Registers drop handler for the Rules panel.
    #>
    param($Window)

    $rulesPanel = $Window.FindName('PanelRules')
    if ($rulesPanel) {
        $rulesPanel.AllowDrop = $true
        
        $rulesPanel.add_Drop({
            param($sender, $e)
            Invoke-RulesPanelDrop -Window $global:GA_MainWindow -DragEventArgs $e
        })

        $rulesPanel.add_DragOver({
            param($sender, $e)
            if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
                $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
                # Accept exe, dll, msi, ps1, or xml files
                $validExtensions = @('.exe', '.dll', '.msi', '.ps1', '.xml', '.json')
                $hasValidFile = $files | Where-Object { 
                    $ext = [System.IO.Path]::GetExtension($_).ToLower()
                    $validExtensions -contains $ext
                }
                if ($hasValidFile) {
                    $e.Effects = [System.Windows.DragDropEffects]::Copy
                }
                else {
                    $e.Effects = [System.Windows.DragDropEffects]::None
                }
            }
            else {
                $e.Effects = [System.Windows.DragDropEffects]::None
            }
            $e.Handled = $true
        })
    }
}

function Register-PolicyPanelDrop {
    <#
    .SYNOPSIS
        Registers drop handler for the Policy panel.
    #>
    param($Window)

    $policyPanel = $Window.FindName('PanelPolicy')
    if ($policyPanel) {
        $policyPanel.AllowDrop = $true
        
        $policyPanel.add_Drop({
            param($sender, $e)
            Invoke-PolicyPanelDrop -Window $global:GA_MainWindow -DragEventArgs $e
        })

        $policyPanel.add_DragOver({
            param($sender, $e)
            if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
                $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
                # Accept XML files for policy import
                $hasXml = $files | Where-Object { 
                    [System.IO.Path]::GetExtension($_).ToLower() -eq '.xml'
                }
                if ($hasXml) {
                    $e.Effects = [System.Windows.DragDropEffects]::Copy
                }
                else {
                    $e.Effects = [System.Windows.DragDropEffects]::None
                }
            }
            else {
                $e.Effects = [System.Windows.DragDropEffects]::None
            }
            $e.Handled = $true
        })
    }

    # Policy rules data grid for rule drops
    $policyRulesGrid = $Window.FindName('PolicyRulesDataGrid')
    if ($policyRulesGrid) {
        $policyRulesGrid.AllowDrop = $true
        
        $policyRulesGrid.add_Drop({
            param($sender, $e)
            Invoke-PolicyRulesGridDrop -Window $global:GA_MainWindow -DragEventArgs $e
        })
    }
}

#endregion

#region ===== DROP HANDLERS =====

function Invoke-WindowDrop {
    <#
    .SYNOPSIS
        Handles file drops on the main window.
    #>
    param(
        $Window,
        $DragEventArgs
    )

    if (-not $DragEventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        return
    }

    $files = $DragEventArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
    $currentPanel = $script:CurrentActivePanel

    # Route to appropriate handler based on current panel
    switch ($currentPanel) {
        'PanelScanner' {
            Invoke-ScannerPanelDrop -Window $Window -DragEventArgs $DragEventArgs
        }
        'PanelRules' {
            Invoke-RulesPanelDrop -Window $Window -DragEventArgs $DragEventArgs
        }
        'PanelPolicy' {
            Invoke-PolicyPanelDrop -Window $Window -DragEventArgs $DragEventArgs
        }
        default {
            # Check file types and suggest appropriate panel
            $hasExecutables = $files | Where-Object {
                $ext = [System.IO.Path]::GetExtension($_).ToLower()
                $ext -in @('.exe', '.dll', '.msi', '.ps1')
            }
            $hasXml = $files | Where-Object {
                [System.IO.Path]::GetExtension($_).ToLower() -eq '.xml'
            }

            if ($hasExecutables) {
                $result = Show-DropActionDialog -FileCount $files.Count -FileType 'executable'
                if ($result -eq 'Scan') {
                    Set-ActivePanel -PanelName 'PanelScanner'
                    $capturedWindow = $Window
                    $capturedFiles = $files
                    $timer = New-Object System.Windows.Threading.DispatcherTimer
                    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
                    $timer.Add_Tick({
                        $timer.Stop()
                        Invoke-ScannerPanelDrop -Window $capturedWindow -Files $capturedFiles
                    }.GetNewClosure())
                    $timer.Start()
                }
                elseif ($result -eq 'CreateRules') {
                    Set-ActivePanel -PanelName 'PanelRules'
                    $capturedWindow = $Window
                    $capturedFiles = $files
                    $timer = New-Object System.Windows.Threading.DispatcherTimer
                    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
                    $timer.Add_Tick({
                        $timer.Stop()
                        Invoke-RulesPanelDrop -Window $capturedWindow -Files $capturedFiles
                    }.GetNewClosure())
                    $timer.Start()
                }
            }
            elseif ($hasXml) {
                Set-ActivePanel -PanelName 'PanelPolicy'
                $capturedWindow = $Window
                $capturedFiles = $files
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(100)
                $timer.Add_Tick({
                    $timer.Stop()
                    Invoke-PolicyPanelDrop -Window $capturedWindow -Files $capturedFiles
                }.GetNewClosure())
                $timer.Start()
            }
            else {
                Show-Toast -Message "Unsupported file type" -Type 'Warning'
            }
        }
    }

    $DragEventArgs.Handled = $true
}

function Invoke-DragOver {
    <#
    .SYNOPSIS
        Handles drag-over events to show appropriate cursor.
    #>
    param(
        $Window,
        $DragEventArgs
    )

    if ($DragEventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $DragEventArgs.Effects = [System.Windows.DragDropEffects]::Copy
    }
    else {
        $DragEventArgs.Effects = [System.Windows.DragDropEffects]::None
    }
    $DragEventArgs.Handled = $true
}

function Invoke-ScannerPanelDrop {
    <#
    .SYNOPSIS
        Handles file drops on the Scanner panel - scans dropped files.
    #>
    param(
        $Window,
        $DragEventArgs = $null,
        [string[]]$Files = $null
    )

    if ($DragEventArgs -and -not $Files) {
        if (-not $DragEventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            return
        }
        $Files = $DragEventArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
    }

    if (-not $Files -or $Files.Count -eq 0) {
        return
    }

    Write-Log -Message "Scanner: Received $($Files.Count) files via drag-drop"

    # Filter for scannable files
    $scannableExtensions = @('.exe', '.dll', '.msi', '.msp', '.ps1', '.bat', '.cmd', '.vbs', '.js')
    $scannableFiles = [System.Collections.Generic.List[string]]::new()
    $folders = [System.Collections.Generic.List[string]]::new()

    foreach ($path in $Files) {
        if (Test-Path -Path $path -PathType Container) {
            [void]$folders.Add($path)
        }
        elseif (Test-Path -Path $path -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($path).ToLower()
            if ($scannableExtensions -contains $ext) {
                [void]$scannableFiles.Add($path)
            }
        }
    }

    # If folders dropped, scan recursively
    foreach ($folder in $folders) {
        $foundFiles = Get-ChildItem -Path $folder -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $scannableExtensions -contains $_.Extension.ToLower() } |
            Select-Object -ExpandProperty FullName
        foreach ($f in @($foundFiles)) { [void]$scannableFiles.Add($f) }
    }

    if ($scannableFiles.Count -eq 0) {
        Show-Toast -Message "No scannable files found" -Type 'Warning'
        return
    }

    Show-Toast -Message "Scanning $($scannableFiles.Count) files..." -Type 'Info'

    # Start scan with these files
    Invoke-DroppedFileScan -Window $Window -FilePaths $scannableFiles
}

function Invoke-RulesPanelDrop {
    <#
    .SYNOPSIS
        Handles file drops on the Rules panel - creates rules from artifacts.
    #>
    param(
        $Window,
        $DragEventArgs = $null,
        [string[]]$Files = $null
    )

    if ($DragEventArgs -and -not $Files) {
        if (-not $DragEventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            return
        }
        $Files = $DragEventArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
    }

    if (-not $Files -or $Files.Count -eq 0) {
        return
    }

    Write-Log -Message "Rules: Received $($Files.Count) files via drag-drop"

    # Check for XML (rule import)
    $xmlFiles = $Files | Where-Object { [System.IO.Path]::GetExtension($_).ToLower() -eq '.xml' }
    if ($xmlFiles) {
        Invoke-ImportRulesFromXml -Window $Window -XmlPaths $xmlFiles
        return
    }

    # Check for JSON (artifact import)
    $jsonFiles = $Files | Where-Object { [System.IO.Path]::GetExtension($_).ToLower() -eq '.json' }
    if ($jsonFiles) {
        Invoke-ImportArtifactsFromJson -Window $Window -JsonPaths $jsonFiles
        return
    }

    # Otherwise scan and create rules
    $executableExtensions = @('.exe', '.dll', '.msi', '.ps1')
    $executableFiles = $Files | Where-Object {
        $ext = [System.IO.Path]::GetExtension($_).ToLower()
        $executableExtensions -contains $ext
    }

    if ($executableFiles.Count -gt 0) {
        Show-Toast -Message "Creating rules from $($executableFiles.Count) files..." -Type 'Info'
        Invoke-CreateRulesFromDroppedFiles -Window $Window -FilePaths $executableFiles
    }
    else {
        Show-Toast -Message "No executable files to create rules from" -Type 'Warning'
    }
}

function Invoke-PolicyPanelDrop {
    <#
    .SYNOPSIS
        Handles file drops on the Policy panel - imports policy XML.
    #>
    param(
        $Window,
        $DragEventArgs = $null,
        [string[]]$Files = $null
    )

    if ($DragEventArgs -and -not $Files) {
        if (-not $DragEventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            return
        }
        $Files = $DragEventArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
    }

    if (-not $Files -or $Files.Count -eq 0) {
        return
    }

    # Filter for XML files
    $xmlFiles = $Files | Where-Object { [System.IO.Path]::GetExtension($_).ToLower() -eq '.xml' }

    if ($xmlFiles.Count -eq 0) {
        Show-Toast -Message "Drop AppLocker XML files to import" -Type 'Warning'
        return
    }

    Write-Log -Message "Policy: Received $($xmlFiles.Count) XML files via drag-drop"
    Show-Toast -Message "Importing $($xmlFiles.Count) policy files..." -Type 'Info'

    Invoke-ImportPoliciesFromXml -Window $Window -XmlPaths $xmlFiles
}

function Invoke-PolicyRulesGridDrop {
    <#
    .SYNOPSIS
        Handles rule drops onto the policy rules grid - adds rules to policy.
    #>
    param(
        $Window,
        $DragEventArgs
    )

    # Check if dropping rule IDs (internal drag from rules panel)
    if ($DragEventArgs.Data.GetDataPresent([System.Windows.DataFormats]::StringFormat)) {
        $data = $DragEventArgs.Data.GetData([System.Windows.DataFormats]::StringFormat)
        
        # Check if it's a rule ID or JSON
        if ($data -match '^[a-f0-9-]{36}$') {
            # Single rule ID
            if ($script:SelectedPolicyId) {
                Invoke-AddRulesToPolicyById -PolicyId $script:SelectedPolicyId -RuleIds @($data)
                Show-Toast -Message "Rule added to policy" -Type 'Success'
            }
        }
        elseif ($data.StartsWith('[') -or $data.StartsWith('{')) {
            # JSON array of rule IDs
            try {
                $ruleIds = $data | ConvertFrom-Json
                if ($script:SelectedPolicyId -and $ruleIds.Count -gt 0) {
                    Invoke-AddRulesToPolicyById -PolicyId $script:SelectedPolicyId -RuleIds $ruleIds
                    Show-Toast -Message "$($ruleIds.Count) rules added to policy" -Type 'Success'
                }
            }
            catch {
                Write-Log -Level Warning -Message "Failed to parse dropped rule data: $($_.Exception.Message)"
            }
        }
    }
}

#endregion

#region ===== HELPER FUNCTIONS =====

function Invoke-DroppedFileScan {
    <#
    .SYNOPSIS
        Scans dropped files and adds to current artifacts list.
    #>
    param(
        $Window,
        [string[]]$FilePaths
    )

    # Use existing scan infrastructure if available
    if (Get-Command -Name 'Start-LocalFileScan' -ErrorAction SilentlyContinue) {
        $result = Start-LocalFileScan -FilePaths $FilePaths
        if ($result.Success) {
            $script:CurrentScanArtifacts += $result.Data
            Update-ArtifactsDataGrid -Window $Window
            Show-Toast -Message "Scanned $($result.Data.Count) files" -Type 'Success'
        }
    }
    else {
        # Fallback: basic file info extraction
        $artifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($path in $FilePaths) {
            if (Test-Path $path) {
                $file = Get-Item $path
                $hash = (Get-FileHash -Path $path -Algorithm SHA256).Hash

                [void]$artifacts.Add([PSCustomObject]@{
                    FileName      = $file.Name
                    FilePath      = $file.FullName
                    Hash          = $hash
                    FileSize      = $file.Length
                    Extension     = $file.Extension
                    LastModified  = $file.LastWriteTime
                    IsSigned      = $false
                    Publisher     = ''
                    ProductName   = ''
                    Version       = ''
                })
            }
        }

        $script:CurrentScanArtifacts += $artifacts
        Update-ArtifactsDataGrid -Window $Window
        Show-Toast -Message "Added $($artifacts.Count) artifacts" -Type 'Success'
    }
}

function Invoke-CreateRulesFromDroppedFiles {
    <#
    .SYNOPSIS
        Creates rules from dropped executable files.
    #>
    param(
        $Window,
        [string[]]$FilePaths
    )

    $createdCount = 0

    foreach ($path in $FilePaths) {
        if (-not (Test-Path $path)) { continue }

        # Get file info
        $file = Get-Item $path
        $hash = (Get-FileHash -Path $path -Algorithm SHA256).Hash

        # Create hash rule
        if (Get-Command -Name 'New-HashRule' -ErrorAction SilentlyContinue) {
            $result = New-HashRule -Hash $hash `
                -FileName $file.Name `
                -FileSize $file.Length `
                -Name "Allow $($file.Name)" `
                -Action 'Allow' `
                -CollectionType (Get-CollectionTypeForExtension -Extension $file.Extension) `
                -Status 'Pending' `
                -Save

            if ($result.Success) {
                $createdCount++
            }
        }
    }

    if ($createdCount -gt 0) {
        Update-RulesDataGrid -Window $Window -Async
        Show-Toast -Message "Created $createdCount rules" -Type 'Success'
    }
    else {
        Show-Toast -Message "No rules created" -Type 'Warning'
    }
}

function Invoke-ImportRulesFromXml {
    <#
    .SYNOPSIS
        Imports rules from AppLocker XML files.
    #>
    param(
        $Window,
        [string[]]$XmlPaths
    )

    $importedCount = 0

    foreach ($path in $XmlPaths) {
        if (Get-Command -Name 'Import-RulesFromXml' -ErrorAction SilentlyContinue) {
            $result = Import-RulesFromXml -Path $path
            if ($result.Success) {
                $importedCount += $result.Data.Count
            }
        }
    }

    Update-RulesDataGrid -Window $Window -Async

    if ($importedCount -gt 0) {
        Show-Toast -Message "Imported $importedCount rules" -Type 'Success'
    }
    else {
        Show-Toast -Message "No rules imported" -Type 'Warning'
    }
}

function Invoke-ImportArtifactsFromJson {
    <#
    .SYNOPSIS
        Imports artifacts from JSON export files.
    #>
    param(
        $Window,
        [string[]]$JsonPaths
    )

    $importedCount = 0

    foreach ($path in $JsonPaths) {
        try {
            $content = Get-Content -Path $path -Raw | ConvertFrom-Json
            if ($content) {
                if ($content -is [array]) {
                    $script:CurrentScanArtifacts += $content
                    $importedCount += $content.Count
                }
                else {
                    $script:CurrentScanArtifacts += $content
                    $importedCount++
                }
            }
        }
        catch {
            Write-Log -Level Warning -Message "Failed to import $path : $($_.Exception.Message)"
        }
    }

    Update-ArtifactsDataGrid -Window $Window

    if ($importedCount -gt 0) {
        Show-Toast -Message "Imported $importedCount artifacts" -Type 'Success'
    }
}

function Invoke-ImportPoliciesFromXml {
    <#
    .SYNOPSIS
        Imports policies from AppLocker XML files.
    #>
    param(
        $Window,
        [string[]]$XmlPaths
    )

    $importedCount = 0

    foreach ($path in $XmlPaths) {
        if (Get-Command -Name 'Import-PolicyFromXml' -ErrorAction SilentlyContinue) {
            $result = Import-PolicyFromXml -Path $path
            if ($result.Success) {
                $importedCount++
            }
        }
    }

    Update-PoliciesDataGrid -Window $Window -Async

    if ($importedCount -gt 0) {
        Show-Toast -Message "Imported $importedCount policies" -Type 'Success'
    }
    else {
        Show-Toast -Message "No policies imported" -Type 'Warning'
    }
}

function Show-DropActionDialog {
    <#
    .SYNOPSIS
        Shows a dialog asking what to do with dropped files.
    #>
    param(
        [int]$FileCount,
        [string]$FileType
    )

    $result = Show-AppLockerMessageBox "You dropped $FileCount $FileType file(s).`n`nWhat would you like to do?`n`n[Yes] = Scan files for artifacts`n[No] = Create rules directly`n[Cancel] = Do nothing" 'Drop Action' 'YesNoCancel' 'Question'

    switch ($result) {
        'Yes' { return 'Scan' }
        'No' { return 'CreateRules' }
        default { return 'Cancel' }
    }
}

function Get-CollectionTypeForExtension {
    <#
    .SYNOPSIS
        Maps file extension to AppLocker collection type.
    #>
    param([string]$Extension)

    $ext = $Extension.ToLower()
    switch ($ext) {
        { $_ -in @('.exe', '.com') } { return 'Exe' }
        { $_ -in @('.dll', '.ocx') } { return 'Dll' }
        { $_ -in @('.msi', '.msp', '.mst') } { return 'Msi' }
        { $_ -in @('.ps1', '.psm1', '.psd1', '.bat', '.cmd', '.vbs', '.js', '.wsf') } { return 'Script' }
        { $_ -in @('.appx', '.msix') } { return 'Appx' }
        default { return 'Exe' }
    }
}

function Invoke-AddRulesToPolicyById {
    <#
    .SYNOPSIS
        Adds rules to a policy by IDs.
    #>
    param(
        [string]$PolicyId,
        [string[]]$RuleIds
    )

    if (Get-Command -Name 'Add-RuleToPolicy' -ErrorAction SilentlyContinue) {
        foreach ($ruleId in $RuleIds) {
            Add-RuleToPolicy -PolicyId $PolicyId -RuleId $ruleId | Out-Null
        }
    }
}

#endregion

#region ===== DRAG SOURCE HELPERS =====

function Enable-RuleDragSource {
    <#
    .SYNOPSIS
        Enables drag-from-source on the rules data grid.
    #>
    param($Window)

    $rulesGrid = $Window.FindName('RulesDataGrid')
    if ($rulesGrid) {
        $rulesGrid.add_MouseMove({
            param($sender, $e)
            
            if ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
                $selectedItems = $sender.SelectedItems
                if ($selectedItems.Count -gt 0) {
                    $ruleIds = @($selectedItems | ForEach-Object { $_.Id })
                    $data = $ruleIds | ConvertTo-Json -Compress
                    
                    [System.Windows.DragDrop]::DoDragDrop(
                        $sender,
                        $data,
                        [System.Windows.DragDropEffects]::Copy
                    )
                }
            }
        })
    }
}

#endregion
