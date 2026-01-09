<#
.SYNOPSIS
Manages software lists for AppLocker rule generation.

.DESCRIPTION
Part of GA-AppLocker toolkit. Provides functions to create, manage, and use
software lists (whitelists/allowlists) for generating AppLocker rules.

Software lists contain predefined approved software with:
- Publisher/Signature information (for publisher rules)
- SHA256 hashes (for hash rules)
- Path information (for path rules)
- Metadata (category, notes, approval status)

This enables rule generation from curated lists rather than just scan data.

.EXAMPLE
# Create a new software list
New-SoftwareList -Name "BusinessApps" -Description "Standard business applications"

.EXAMPLE
# Add software to a list
Add-SoftwareListItem -ListPath .\SoftwareLists\BusinessApps.json -Name "Adobe Reader" `
    -Publisher "ADOBE INC." -ProductName "Adobe Acrobat Reader" -Category "PDF"

.EXAMPLE
# Generate rules from a software list
$rules = Get-SoftwareListRules -ListPath .\SoftwareLists\BusinessApps.json -RuleType Publisher

.EXAMPLE
# Import software from scan data into a list
Import-ScanDataToSoftwareList -ScanPath .\Scans -ListPath .\SoftwareLists\Discovered.json
#>

#Requires -Version 5.1

# Import common utilities if available
$scriptRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot "Common.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Software List Schema Definition
# =============================================================================
<#
Software List JSON Schema:
{
    "metadata": {
        "name": "List Name",
        "description": "Description",
        "created": "ISO 8601 timestamp",
        "modified": "ISO 8601 timestamp",
        "version": "1.0"
    },
    "items": [
        {
            "id": "GUID",
            "name": "Software Display Name",
            "publisher": "O=PUBLISHER NAME",
            "productName": "Product Name (for publisher rules)",
            "binaryName": "*.exe or specific.exe",
            "minVersion": "0.0.0.0",
            "maxVersion": "*",
            "hash": "SHA256 hash (for hash rules)",
            "hashSourceFile": "original filename",
            "hashSourceSize": file size in bytes,
            "path": "Path pattern (for path rules)",
            "category": "Category/Tag",
            "notes": "Additional notes",
            "approved": true/false,
            "ruleType": "Publisher|Hash|Path",
            "added": "ISO 8601 timestamp",
            "addedBy": "Username"
        }
    ]
}
#>

# =============================================================================
# Software List Management Functions
# =============================================================================

function New-SoftwareList {
    <#
    .SYNOPSIS
    Creates a new software list file.

    .PARAMETER Name
    Name of the software list.

    .PARAMETER Description
    Description of what this list contains.

    .PARAMETER OutputPath
    Directory to save the list file. Defaults to .\SoftwareLists

    .EXAMPLE
    New-SoftwareList -Name "ApprovedSoftware" -Description "Corporate approved applications"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Description = "",

        [string]$OutputPath = ".\SoftwareLists"
    )

    # Create output directory if needed
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $listFile = Join-Path $OutputPath "$Name.json"

    if (Test-Path $listFile) {
        Write-Warning "Software list '$Name' already exists at: $listFile"
        return $listFile
    }

    $softwareList = @{
        metadata = @{
            name        = $Name
            description = $Description
            created     = (Get-Date).ToString("o")
            modified    = (Get-Date).ToString("o")
            version     = "1.0"
        }
        items    = @()
    }

    $softwareList | ConvertTo-Json -Depth 10 | Out-File -FilePath $listFile -Encoding UTF8

    Write-Host "Created software list: $listFile" -ForegroundColor Green
    return $listFile
}


function Get-SoftwareList {
    <#
    .SYNOPSIS
    Loads a software list from file.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .EXAMPLE
    $list = Get-SoftwareList -ListPath .\SoftwareLists\ApprovedSoftware.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath
    )

    $content = Get-Content -Path $ListPath -Raw | ConvertFrom-Json
    return $content
}


function Save-SoftwareList {
    <#
    .SYNOPSIS
    Saves a software list object to file.

    .PARAMETER List
    The software list object to save.

    .PARAMETER ListPath
    Path to save the JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$List,

        [Parameter(Mandatory = $true)]
        [string]$ListPath
    )

    # Update modified timestamp
    $List.metadata.modified = (Get-Date).ToString("o")

    $List | ConvertTo-Json -Depth 10 | Out-File -FilePath $ListPath -Encoding UTF8
    Write-Verbose "Saved software list to: $ListPath"
}


function Add-SoftwareListItem {
    <#
    .SYNOPSIS
    Adds a software item to a software list.

    .DESCRIPTION
    Adds software with publisher signature, hash, or path information
    for AppLocker rule generation.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER Name
    Display name of the software.

    .PARAMETER Publisher
    Publisher/Organization name from certificate (e.g., "ADOBE INC.")

    .PARAMETER ProductName
    Product name for publisher rules. Use "*" for all products from publisher.

    .PARAMETER BinaryName
    Binary name for publisher rules. Use "*" for all binaries.

    .PARAMETER MinVersion
    Minimum version to allow. Default: "*" (any version)

    .PARAMETER MaxVersion
    Maximum version to allow. Default: "*" (any version)

    .PARAMETER Hash
    SHA256 hash for hash-based rules.

    .PARAMETER HashSourceFile
    Original filename for the hash.

    .PARAMETER HashSourceSize
    File size in bytes for the hash.

    .PARAMETER Path
    Path pattern for path-based rules.

    .PARAMETER Category
    Category/tag for organizing software (e.g., "Productivity", "Security")

    .PARAMETER Notes
    Additional notes about this software.

    .PARAMETER RuleType
    Type of rule to generate: Publisher, Hash, or Path

    .PARAMETER Approved
    Whether this software is approved. Default: $true

    .EXAMPLE
    # Add publisher-based software
    Add-SoftwareListItem -ListPath .\list.json -Name "Adobe Reader" `
        -Publisher "ADOBE INC." -ProductName "Adobe Acrobat Reader" `
        -Category "PDF" -RuleType Publisher

    .EXAMPLE
    # Add hash-based software
    Add-SoftwareListItem -ListPath .\list.json -Name "Custom Tool" `
        -Hash "A1B2C3D4..." -HashSourceFile "tool.exe" -HashSourceSize 12345 `
        -Category "Internal" -RuleType Hash
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Publisher,
        [string]$ProductName = "*",
        [string]$BinaryName = "*",
        [string]$MinVersion = "*",
        [string]$MaxVersion = "*",

        [string]$Hash,
        [string]$HashSourceFile,
        [int64]$HashSourceSize,

        [string]$Path,

        [string]$Category = "Uncategorized",
        [string]$Notes = "",

        [ValidateSet("Publisher", "Hash", "Path")]
        [string]$RuleType = "Publisher",

        [bool]$Approved = $true
    )

    $list = Get-SoftwareList -ListPath $ListPath

    # Validate required fields based on rule type
    switch ($RuleType) {
        "Publisher" {
            if (-not $Publisher) {
                throw "Publisher is required for Publisher rule type"
            }
        }
        "Hash" {
            if (-not $Hash) {
                throw "Hash is required for Hash rule type"
            }
        }
        "Path" {
            if (-not $Path) {
                throw "Path is required for Path rule type"
            }
        }
    }

    # Check for duplicates
    $existingItem = $list.items | Where-Object {
        ($_.publisher -eq $Publisher -and $_.productName -eq $ProductName -and $_.binaryName -eq $BinaryName) -or
        ($_.hash -eq $Hash -and $Hash) -or
        ($_.path -eq $Path -and $Path)
    }

    if ($existingItem) {
        Write-Warning "Similar item already exists in list: $($existingItem.name)"
        return $existingItem
    }

    $newItem = [PSCustomObject]@{
        id             = [guid]::NewGuid().ToString()
        name           = $Name
        publisher      = $Publisher
        productName    = $ProductName
        binaryName     = $BinaryName
        minVersion     = $MinVersion
        maxVersion     = $MaxVersion
        hash           = $Hash
        hashSourceFile = $HashSourceFile
        hashSourceSize = $HashSourceSize
        path           = $Path
        category       = $Category
        notes          = $Notes
        approved       = $Approved
        ruleType       = $RuleType
        added          = (Get-Date).ToString("o")
        addedBy        = $env:USERNAME
    }

    # Convert items to array if needed and add new item
    $items = @($list.items)
    $items += $newItem
    $list.items = $items

    Save-SoftwareList -List $list -ListPath $ListPath

    Write-Host "Added: $Name ($RuleType rule)" -ForegroundColor Green
    return $newItem
}


function Remove-SoftwareListItem {
    <#
    .SYNOPSIS
    Removes an item from a software list.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER Id
    ID of the item to remove.

    .PARAMETER Name
    Name of the item to remove (if ID not specified).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath,

        [string]$Id,
        [string]$Name
    )

    if (-not $Id -and -not $Name) {
        throw "Either -Id or -Name must be specified"
    }

    $list = Get-SoftwareList -ListPath $ListPath

    $itemToRemove = if ($Id) {
        $list.items | Where-Object { $_.id -eq $Id }
    }
    else {
        $list.items | Where-Object { $_.name -eq $Name }
    }

    if (-not $itemToRemove) {
        Write-Warning "Item not found in list"
        return
    }

    $list.items = @($list.items | Where-Object { $_.id -ne $itemToRemove.id })

    Save-SoftwareList -List $list -ListPath $ListPath
    Write-Host "Removed: $($itemToRemove.name)" -ForegroundColor Yellow
}


function Update-SoftwareListItem {
    <#
    .SYNOPSIS
    Updates an existing item in a software list.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER Id
    ID of the item to update.

    .PARAMETER Properties
    Hashtable of properties to update.

    .EXAMPLE
    Update-SoftwareListItem -ListPath .\list.json -Id "guid" -Properties @{approved=$true; notes="Tested OK"}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [hashtable]$Properties
    )

    $list = Get-SoftwareList -ListPath $ListPath

    $item = $list.items | Where-Object { $_.id -eq $Id }
    if (-not $item) {
        throw "Item with ID '$Id' not found"
    }

    foreach ($key in $Properties.Keys) {
        if ($item.PSObject.Properties.Name -contains $key) {
            $item.$key = $Properties[$key]
        }
    }

    Save-SoftwareList -List $list -ListPath $ListPath
    Write-Host "Updated: $($item.name)" -ForegroundColor Cyan
    return $item
}


# =============================================================================
# Import Functions - Convert scan data to software list
# =============================================================================

function Import-ScanDataToSoftwareList {
    <#
    .SYNOPSIS
    Imports software discovered during scans into a software list.

    .DESCRIPTION
    Reads Executables.csv and Publishers.csv from scan data and creates
    software list entries with publisher and hash information.

    .PARAMETER ScanPath
    Path to scan results from Invoke-RemoteScan.ps1

    .PARAMETER ListPath
    Path to the software list to import into. Creates if doesn't exist.

    .PARAMETER Category
    Category to assign to imported items.

    .PARAMETER SignedOnly
    Only import signed executables (with publisher info).

    .PARAMETER UnsignedOnly
    Only import unsigned executables (hash-based rules).

    .PARAMETER AutoApprove
    Automatically mark imported items as approved.

    .PARAMETER Deduplicate
    Deduplicate by publisher (imports unique publishers only).

    .EXAMPLE
    Import-ScanDataToSoftwareList -ScanPath .\Scans -ListPath .\SoftwareLists\Discovered.json -SignedOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ScanPath,

        [Parameter(Mandatory = $true)]
        [string]$ListPath,

        [string]$Category = "Discovered",

        [switch]$SignedOnly,
        [switch]$UnsignedOnly,
        [switch]$AutoApprove,
        [switch]$Deduplicate
    )

    # Create list if doesn't exist
    if (-not (Test-Path $ListPath)) {
        $listDir = Split-Path -Parent $ListPath
        $listName = [System.IO.Path]::GetFileNameWithoutExtension($ListPath)
        New-SoftwareList -Name $listName -Description "Imported from scan data" -OutputPath $listDir | Out-Null
    }

    $list = Get-SoftwareList -ListPath $ListPath

    # Find scan data - check if ScanPath is a folder with CSVs directly or contains subfolders
    $scanSource = [System.IO.Path]::GetFileName($ScanPath)
    $computerFolders = @()

    # Check if CSVs exist directly in ScanPath (single computer folder selected)
    $directCsvs = Get-ChildItem -Path $ScanPath -Filter "*.csv" -ErrorAction SilentlyContinue
    if ($directCsvs.Count -gt 0) {
        # ScanPath itself contains CSV files - treat as single folder
        $computerFolders = @([PSCustomObject]@{ FullName = $ScanPath; Name = $scanSource })
    }
    else {
        # Look for subfolders containing CSVs
        $computerFolders = @(Get-ChildItem -Path $ScanPath -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $csvFiles = Get-ChildItem -Path $_.FullName -Filter "*.csv" -ErrorAction SilentlyContinue
                $csvFiles.Count -gt 0
            })
    }

    if ($computerFolders.Count -eq 0) {
        Write-Warning "No scan data found in $ScanPath"
        return $list
    }

    Write-Host "Loading scan data from $($computerFolders.Count) source(s)..." -ForegroundColor Cyan

    $allExecutables = @()
    $sourceNames = @()
    foreach ($folder in $computerFolders) {
        $exePath = Join-Path $folder.FullName "Executables.csv"
        if (Test-Path $exePath) {
            try {
                $csvData = Import-Csv -Path $exePath -ErrorAction Stop
                $allExecutables += $csvData
                $sourceNames += $folder.Name
            }
            catch {
                Write-Warning "Failed to read $exePath : $_"
            }
        }
    }

    if ($allExecutables.Count -eq 0) {
        Write-Warning "No executables found in scan data"
        return $list
    }

    Write-Host "  Found $($allExecutables.Count) total executables" -ForegroundColor Gray

    # Filter based on switches
    $toImport = @($allExecutables)
    if ($SignedOnly) {
        $toImport = @($toImport | Where-Object { $_.IsSigned -eq "True" -and $_.Publisher })
    }
    if ($UnsignedOnly) {
        $toImport = @($toImport | Where-Object { $_.IsSigned -ne "True" -and $_.Hash })
    }

    if ($toImport.Count -eq 0) {
        Write-Host "  No executables match the filter criteria" -ForegroundColor Yellow
        return $list
    }

    # Track what we've added for deduplication
    $addedPublishers = @{}
    $addedHashes = @{}
    $importCount = 0

    # Build source description for notes
    $sourceDescription = if ($sourceNames.Count -eq 1) { $sourceNames[0] } else { "$($sourceNames.Count) sources" }

    foreach ($exe in $toImport) {
        # Defensive: skip if name is empty
        if ([string]::IsNullOrWhiteSpace($exe.Name)) { continue }

        $ruleType = if ($exe.IsSigned -eq "True" -and $exe.Publisher) { "Publisher" } else { "Hash" }

        # Defensive: For hash rules, ensure we have a hash
        if ($ruleType -eq "Hash" -and [string]::IsNullOrWhiteSpace($exe.Hash)) { continue }

        # Deduplicate if requested
        if ($Deduplicate -and $ruleType -eq "Publisher" -and $exe.Publisher) {
            if ($addedPublishers.ContainsKey($exe.Publisher)) { continue }
            $addedPublishers[$exe.Publisher] = $true
        }
        if ($Deduplicate -and $ruleType -eq "Hash" -and $exe.Hash) {
            if ($addedHashes.ContainsKey($exe.Hash)) { continue }
            $addedHashes[$exe.Hash] = $true
        }

        # Check if already in list (defensive null checks)
        $listItems = @($list.items)
        $exists = $listItems | Where-Object {
            ($_.publisher -and $exe.Publisher -and $_.publisher -eq $exe.Publisher) -or
            ($_.hash -and $exe.Hash -and $_.hash -eq $exe.Hash)
        }
        if ($exists) { continue }

        # Extract product name from path (with null check)
        $productName = "*"
        if ($exe.Path -and $exe.Path -match "\\([^\\]+)\\[^\\]+$") {
            $productName = $matches[1]
        }

        # Parse file size safely
        $fileSize = 0
        if ($exe.Size -and $exe.Size -match "^\d+$") {
            $fileSize = [int64]$exe.Size
        }

        $newItem = [PSCustomObject]@{
            id             = [guid]::NewGuid().ToString()
            name           = $exe.Name
            publisher      = $exe.Publisher
            productName    = $productName
            binaryName     = $exe.Name
            minVersion     = "*"
            maxVersion     = "*"
            hash           = $exe.Hash
            hashSourceFile = $exe.Name
            hashSourceSize = $fileSize
            path           = $exe.Path
            category       = $Category
            notes          = "Imported from scan: $sourceDescription"
            approved       = [bool]$AutoApprove
            ruleType       = $ruleType
            added          = (Get-Date).ToString("o")
            addedBy        = if ($env:USERNAME) { $env:USERNAME } else { "System" }
        }

        $items = @($list.items)
        $items += $newItem
        $list.items = $items
        $importCount++
    }

    Save-SoftwareList -List $list -ListPath $ListPath

    Write-Host "Imported $importCount items to software list" -ForegroundColor Green
    Write-Host "  Publisher-based: $($addedPublishers.Count)" -ForegroundColor Gray
    Write-Host "  Hash-based: $($addedHashes.Count)" -ForegroundColor Gray

    return $list
}


function Import-ExecutableToSoftwareList {
    <#
    .SYNOPSIS
    Imports a specific executable file into a software list.

    .DESCRIPTION
    Reads signature and hash information from an executable and adds it
    to a software list for rule generation.

    .PARAMETER FilePath
    Path to the executable file.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER Category
    Category to assign.

    .PARAMETER Notes
    Notes to add.

    .PARAMETER PreferHash
    Use hash rule even if file is signed.

    .EXAMPLE
    Import-ExecutableToSoftwareList -FilePath "C:\Tools\app.exe" -ListPath .\list.json -Category "Internal Tools"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$ListPath,

        [string]$Category = "Imported",
        [string]$Notes = "",
        [switch]$PreferHash
    )

    $file = Get-Item $FilePath
    $sig = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue
    $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash

    $isSigned = $sig -and $sig.Status -eq "Valid"
    $publisher = $null

    if ($isSigned -and $sig.SignerCertificate) {
        if ($sig.SignerCertificate.Subject -match "O=([^,]+)") {
            $publisher = $matches[1].Trim('"')
        }
    }

    $ruleType = if ($isSigned -and $publisher -and -not $PreferHash) { "Publisher" } else { "Hash" }

    $params = @{
        ListPath = $ListPath
        Name     = $file.Name
        Category = $Category
        Notes    = $Notes
        RuleType = $ruleType
        Approved = $true
    }

    if ($ruleType -eq "Publisher") {
        $params.Publisher = $publisher
        $params.ProductName = "*"
        $params.BinaryName = $file.Name
    }
    else {
        $params.Hash = $hash
        $params.HashSourceFile = $file.Name
        $params.HashSourceSize = $file.Length
    }

    Add-SoftwareListItem @params
}


function Import-AppLockerEventLog {
    <#
    .SYNOPSIS
    Imports blocked/audited executables from AppLocker event logs into a software list.

    .DESCRIPTION
    Parses AppLocker audit events (8003, 8004, 8006, 8007) to find executables that
    were blocked or would be blocked. Creates software list entries for legitimate
    software that needs allow rules.

    Event IDs:
    - 8003: EXE/DLL was allowed (audit)
    - 8004: EXE/DLL was blocked or would be blocked (audit)
    - 8006: Script/MSI was allowed (audit)
    - 8007: Script/MSI was blocked or would be blocked (audit)

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER ComputerName
    Computer to query event logs from. Default: localhost

    .PARAMETER Hours
    Number of hours of logs to analyze. Default: 24

    .PARAMETER EventType
    Type of events to import: Blocked, Allowed, or All. Default: Blocked

    .PARAMETER Category
    Category to assign to imported items.

    .PARAMETER AutoApprove
    Automatically approve imported items.

    .EXAMPLE
    Import-AppLockerEventLog -ListPath .\SoftwareLists\Discovered.json -Hours 168 -EventType Blocked
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ListPath,

        [string]$ComputerName = "localhost",

        [int]$Hours = 24,

        [ValidateSet("Blocked", "Allowed", "All")]
        [string]$EventType = "Blocked",

        [string]$Category = "EventLog-Discovered",

        [switch]$AutoApprove,

        [PSCredential]$Credential
    )

    # Create list if doesn't exist
    if (-not (Test-Path $ListPath)) {
        $listDir = Split-Path -Parent $ListPath
        if (-not $listDir) { $listDir = "." }
        $listName = [System.IO.Path]::GetFileNameWithoutExtension($ListPath)
        New-SoftwareList -Name $listName -Description "Imported from AppLocker event logs" -OutputPath $listDir | Out-Null
    }

    $list = Get-SoftwareList -ListPath $ListPath

    # Determine which event IDs to query
    $eventIds = switch ($EventType) {
        "Blocked" { @(8004, 8007) }
        "Allowed" { @(8003, 8006) }
        "All"     { @(8003, 8004, 8006, 8007) }
    }

    $startTime = (Get-Date).AddHours(-$Hours)

    Write-Host "Querying AppLocker event logs..." -ForegroundColor Cyan
    Write-Host "  Computer: $ComputerName" -ForegroundColor Gray
    Write-Host "  Time range: Last $Hours hours" -ForegroundColor Gray
    Write-Host "  Event types: $EventType (IDs: $($eventIds -join ', '))" -ForegroundColor Gray

    try {
        $getEventParams = @{
            LogName      = "Microsoft-Windows-AppLocker/EXE and DLL"
            Id           = $eventIds
            StartTime    = $startTime
            ErrorAction  = "SilentlyContinue"
        }

        if ($ComputerName -ne "localhost" -and $ComputerName -ne $env:COMPUTERNAME) {
            $getEventParams.ComputerName = $ComputerName
            if ($Credential) {
                $getEventParams.Credential = $Credential
            }
        }

        $events = @(Get-WinEvent @getEventParams)

        # Also check MSI/Script log
        $getEventParams.LogName = "Microsoft-Windows-AppLocker/MSI and Script"
        $events += @(Get-WinEvent @getEventParams)
    }
    catch {
        Write-Warning "Failed to query event logs: $_"
        Write-Host "  Note: Requires administrative privileges and AppLocker in audit mode." -ForegroundColor Yellow
        return $list
    }

    if ($events.Count -eq 0) {
        Write-Host "  No AppLocker events found in the specified time range" -ForegroundColor Yellow
        return $list
    }

    Write-Host "  Found $($events.Count) events" -ForegroundColor Gray

    # Parse events and extract file information
    $discoveredFiles = @{}

    foreach ($event in $events) {
        try {
            $xml = [xml]$event.ToXml()
            $data = @{}

            foreach ($item in $xml.Event.EventData.Data) {
                $data[$item.Name] = $item.'#text'
            }

            $filePath = $data['FilePath']
            $fileHash = $data['FileHash']
            $publisher = $data['PublisherName']
            $userName = $data['UserName']

            if (-not $filePath) { continue }

            $fileName = [System.IO.Path]::GetFileName($filePath)
            $key = if ($fileHash) { $fileHash } else { $filePath.ToLower() }

            if (-not $discoveredFiles.ContainsKey($key)) {
                $discoveredFiles[$key] = @{
                    Name      = $fileName
                    Path      = $filePath
                    Hash      = $fileHash
                    Publisher = $publisher
                    EventId   = $event.Id
                    Count     = 1
                    Users     = @($userName)
                }
            }
            else {
                $discoveredFiles[$key].Count++
                if ($userName -and $userName -notin $discoveredFiles[$key].Users) {
                    $discoveredFiles[$key].Users += $userName
                }
            }
        }
        catch {
            # Skip malformed events
            continue
        }
    }

    Write-Host "  Unique files discovered: $($discoveredFiles.Count)" -ForegroundColor Gray

    # Import to software list
    $importCount = 0
    $listItems = @($list.items)

    foreach ($file in $discoveredFiles.Values) {
        # Skip if already in list
        $exists = $listItems | Where-Object {
            ($_.hash -and $file.Hash -and $_.hash -eq $file.Hash) -or
            ($_.path -and $file.Path -and $_.path -eq $file.Path)
        }
        if ($exists) { continue }

        # Determine rule type
        $ruleType = if ($file.Publisher) { "Publisher" } elseif ($file.Hash) { "Hash" } else { "Path" }

        $eventDesc = if ($file.EventId -in @(8004, 8007)) { "Blocked" } else { "Audited" }
        $notes = "$eventDesc $($file.Count) time(s). Users: $($file.Users -join ', ')"

        $newItem = [PSCustomObject]@{
            id             = [guid]::NewGuid().ToString()
            name           = $file.Name
            publisher      = $file.Publisher
            productName    = "*"
            binaryName     = $file.Name
            minVersion     = "*"
            maxVersion     = "*"
            hash           = $file.Hash
            hashSourceFile = $file.Name
            hashSourceSize = 0
            path           = $file.Path
            category       = $Category
            notes          = $notes
            approved       = [bool]$AutoApprove
            ruleType       = $ruleType
            added          = (Get-Date).ToString("o")
            addedBy        = if ($env:USERNAME) { $env:USERNAME } else { "System" }
        }

        $listItems += $newItem
        $importCount++
    }

    $list.items = $listItems
    Save-SoftwareList -List $list -ListPath $ListPath

    Write-Host "Imported $importCount items from event logs" -ForegroundColor Green

    return $list
}


function Import-InstalledPrograms {
    <#
    .SYNOPSIS
    Imports installed programs from registry into a software list.

    .DESCRIPTION
    Queries the Windows registry for installed programs and creates software
    list entries with publisher information for rule generation.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER ComputerName
    Computer to query. Default: localhost

    .PARAMETER Category
    Category to assign to imported items.

    .PARAMETER AutoApprove
    Automatically approve imported items.

    .PARAMETER IncludeSystemComponents
    Include system components and updates.

    .EXAMPLE
    Import-InstalledPrograms -ListPath .\SoftwareLists\Installed.json -AutoApprove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ListPath,

        [string]$ComputerName = "localhost",

        [string]$Category = "Installed",

        [switch]$AutoApprove,

        [switch]$IncludeSystemComponents,

        [PSCredential]$Credential
    )

    # Create list if doesn't exist
    if (-not (Test-Path $ListPath)) {
        $listDir = Split-Path -Parent $ListPath
        if (-not $listDir) { $listDir = "." }
        $listName = [System.IO.Path]::GetFileNameWithoutExtension($ListPath)
        New-SoftwareList -Name $listName -Description "Imported from installed programs" -OutputPath $listDir | Out-Null
    }

    $list = Get-SoftwareList -ListPath $ListPath

    Write-Host "Querying installed programs..." -ForegroundColor Cyan

    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $installedApps = @()

    $scriptBlock = {
        param($regPaths, $IncludeSystemComponents)

        $apps = @()
        foreach ($path in $regPaths) {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if (-not $item.DisplayName) { continue }

                # Skip system components unless requested
                if (-not $IncludeSystemComponents) {
                    if ($item.SystemComponent -eq 1) { continue }
                    if ($item.DisplayName -match "^(Update for|Security Update|Hotfix)") { continue }
                    if ($item.ReleaseType -in @("Update", "Hotfix", "Security Update")) { continue }
                }

                $apps += [PSCustomObject]@{
                    Name           = $item.DisplayName
                    Publisher      = $item.Publisher
                    Version        = $item.DisplayVersion
                    InstallDate    = $item.InstallDate
                    InstallLocation = $item.InstallLocation
                    UninstallString = $item.UninstallString
                }
            }
        }
        return $apps
    }

    try {
        if ($ComputerName -eq "localhost" -or $ComputerName -eq $env:COMPUTERNAME) {
            $installedApps = & $scriptBlock -regPaths $regPaths -IncludeSystemComponents $IncludeSystemComponents
        }
        else {
            $invokeParams = @{
                ComputerName = $ComputerName
                ScriptBlock  = $scriptBlock
                ArgumentList = @($regPaths, $IncludeSystemComponents)
            }
            if ($Credential) {
                $invokeParams.Credential = $Credential
            }
            $installedApps = Invoke-Command @invokeParams
        }
    }
    catch {
        Write-Warning "Failed to query installed programs: $_"
        return $list
    }

    # Deduplicate by name
    $uniqueApps = $installedApps | Group-Object Name | ForEach-Object { $_.Group | Select-Object -First 1 }

    Write-Host "  Found $($uniqueApps.Count) installed programs" -ForegroundColor Gray

    # Import to software list
    $importCount = 0
    $listItems = @($list.items)
    $addedPublishers = @{}

    foreach ($app in $uniqueApps) {
        if (-not $app.Publisher) { continue }

        # Normalize publisher name
        $publisher = $app.Publisher.ToUpper().Trim()

        # Skip if publisher already added (dedupe by publisher)
        if ($addedPublishers.ContainsKey($publisher)) { continue }

        # Skip if already in list
        $exists = $listItems | Where-Object { $_.publisher -and $_.publisher.ToUpper() -eq $publisher }
        if ($exists) { continue }

        $newItem = [PSCustomObject]@{
            id             = [guid]::NewGuid().ToString()
            name           = $app.Name
            publisher      = $publisher
            productName    = $app.Name
            binaryName     = "*"
            minVersion     = "*"
            maxVersion     = "*"
            hash           = $null
            hashSourceFile = $null
            hashSourceSize = 0
            path           = $app.InstallLocation
            category       = $Category
            notes          = "Installed program. Version: $($app.Version)"
            approved       = [bool]$AutoApprove
            ruleType       = "Publisher"
            added          = (Get-Date).ToString("o")
            addedBy        = if ($env:USERNAME) { $env:USERNAME } else { "System" }
        }

        $listItems += $newItem
        $addedPublishers[$publisher] = $true
        $importCount++
    }

    $list.items = $listItems
    Save-SoftwareList -List $list -ListPath $ListPath

    Write-Host "Imported $importCount publishers from installed programs" -ForegroundColor Green

    return $list
}


function Import-CertificateChainRules {
    <#
    .SYNOPSIS
    Creates publisher rules based on certificate chain (CA) trust.

    .DESCRIPTION
    Generates rules that allow software signed by certificates issued by specific
    Certificate Authorities. Useful for enterprise PKI environments including
    DOD PKI, corporate CAs, and government CAs.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER CertificateAuthority
    Name pattern of the CA to trust (supports wildcards).

    .PARAMETER Preset
    Use a preset CA configuration: DOD, Microsoft, Custom

    .PARAMETER TrustChain
    Trust level: Immediate (direct signer), Intermediate, or Root

    .PARAMETER Category
    Category to assign.

    .PARAMETER ScanPath
    Optional: Scan a folder and import only files signed by matching CAs.

    .EXAMPLE
    # Trust all DOD-signed software
    Import-CertificateChainRules -ListPath .\list.json -Preset DOD -Category "Government"

    .EXAMPLE
    # Trust software signed by specific CA
    Import-CertificateChainRules -ListPath .\list.json -CertificateAuthority "*CONTOSO*" -Category "Enterprise"

    .EXAMPLE
    # Scan folder and import only DOD-signed files
    Import-CertificateChainRules -ListPath .\list.json -Preset DOD -ScanPath "C:\Program Files"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ListPath,

        [string]$CertificateAuthority,

        [ValidateSet("DOD", "Microsoft", "Custom")]
        [string]$Preset,

        [ValidateSet("Immediate", "Intermediate", "Root")]
        [string]$TrustChain = "Immediate",

        [string]$Category = "Certificate-Trust",

        [string]$ScanPath,

        [switch]$AutoApprove
    )

    # Define CA presets
    $caPresets = @{
        DOD = @{
            Name = "DOD PKI"
            Patterns = @(
                "*DOD*CA*",
                "*DEPARTMENT OF DEFENSE*",
                "*DOD ID CA*",
                "*DOD EMAIL CA*",
                "*DOD SW CA*",
                "*DOD ROOT CA*",
                "*US GOVERNMENT*",
                "*DISA*"
            )
            Category = "Government-DOD"
            Notes = "DOD PKI trusted certificate chain"
        }
        Microsoft = @{
            Name = "Microsoft PKI"
            Patterns = @(
                "*MICROSOFT*",
                "*Microsoft Corporation*",
                "*Microsoft Code Signing*",
                "*Microsoft Root*",
                "*Microsoft Authenticode*"
            )
            Category = "Microsoft"
            Notes = "Microsoft certificate chain"
        }
    }

    # Create list if doesn't exist
    if (-not (Test-Path $ListPath)) {
        $listDir = Split-Path -Parent $ListPath
        if (-not $listDir) { $listDir = "." }
        $listName = [System.IO.Path]::GetFileNameWithoutExtension($ListPath)
        New-SoftwareList -Name $listName -Description "Certificate chain trust rules" -OutputPath $listDir | Out-Null
    }

    $list = Get-SoftwareList -ListPath $ListPath

    # Determine CA patterns to match
    $caPatterns = @()
    $presetConfig = $null

    if ($Preset -and $caPresets.ContainsKey($Preset)) {
        $presetConfig = $caPresets[$Preset]
        $caPatterns = $presetConfig.Patterns
        if (-not $Category -or $Category -eq "Certificate-Trust") {
            $Category = $presetConfig.Category
        }
        Write-Host "Using preset: $($presetConfig.Name)" -ForegroundColor Cyan
    }
    elseif ($CertificateAuthority) {
        $caPatterns = @($CertificateAuthority)
    }
    else {
        Write-Warning "Either -Preset or -CertificateAuthority must be specified"
        return $list
    }

    Write-Host "Certificate Authority patterns:" -ForegroundColor Gray
    foreach ($pattern in $caPatterns) {
        Write-Host "  - $pattern" -ForegroundColor Gray
    }

    $listItems = @($list.items)
    $importCount = 0

    if ($ScanPath -and (Test-Path $ScanPath)) {
        # Scan mode: find files matching CA patterns
        Write-Host "Scanning $ScanPath for signed executables..." -ForegroundColor Cyan

        $extensions = @("*.exe", "*.dll", "*.msi")
        $files = @()

        foreach ($ext in $extensions) {
            $files += Get-ChildItem -Path $ScanPath -Filter $ext -Recurse -ErrorAction SilentlyContinue
        }

        Write-Host "  Found $($files.Count) files to check" -ForegroundColor Gray

        $matchedFiles = @()

        foreach ($file in $files) {
            try {
                $sig = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue

                if ($sig.Status -ne "Valid") { continue }

                $cert = $sig.SignerCertificate
                if (-not $cert) { continue }

                # Check certificate chain based on trust level
                $certToCheck = switch ($TrustChain) {
                    "Immediate" { $cert }
                    "Intermediate" {
                        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                        $chain.Build($cert) | Out-Null
                        if ($chain.ChainElements.Count -gt 1) {
                            $chain.ChainElements[1].Certificate
                        } else { $cert }
                    }
                    "Root" {
                        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                        $chain.Build($cert) | Out-Null
                        $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
                    }
                }

                $certSubject = $certToCheck.Subject
                $certIssuer = $certToCheck.Issuer

                # Check if matches any CA pattern
                $matches = $false
                foreach ($pattern in $caPatterns) {
                    if ($certSubject -like $pattern -or $certIssuer -like $pattern) {
                        $matches = $true
                        break
                    }
                }

                if ($matches) {
                    # Extract publisher from signer cert
                    $publisher = $null
                    if ($cert.Subject -match "O=([^,]+)") {
                        $publisher = $Matches[1].Trim('"')
                    }

                    $matchedFiles += @{
                        Name      = $file.Name
                        Path      = $file.FullName
                        Publisher = $publisher
                        Issuer    = $certIssuer
                        Hash      = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                        Size      = $file.Length
                    }
                }
            }
            catch {
                continue
            }
        }

        Write-Host "  Matched $($matchedFiles.Count) files signed by trusted CAs" -ForegroundColor Green

        # Import matched files
        $addedPublishers = @{}

        foreach ($file in $matchedFiles) {
            if (-not $file.Publisher) { continue }

            # Dedupe by publisher
            if ($addedPublishers.ContainsKey($file.Publisher)) { continue }

            # Check if already in list
            $exists = $listItems | Where-Object { $_.publisher -eq $file.Publisher }
            if ($exists) { continue }

            $notes = if ($presetConfig) { $presetConfig.Notes } else { "CA: $($file.Issuer)" }

            $newItem = [PSCustomObject]@{
                id             = [guid]::NewGuid().ToString()
                name           = $file.Name
                publisher      = $file.Publisher
                productName    = "*"
                binaryName     = "*"
                minVersion     = "*"
                maxVersion     = "*"
                hash           = $null
                hashSourceFile = $null
                hashSourceSize = 0
                path           = $null
                category       = $Category
                notes          = $notes
                approved       = [bool]$AutoApprove
                ruleType       = "Publisher"
                added          = (Get-Date).ToString("o")
                addedBy        = if ($env:USERNAME) { $env:USERNAME } else { "System" }
            }

            $listItems += $newItem
            $addedPublishers[$file.Publisher] = $true
            $importCount++
        }
    }
    else {
        # No scan path - create generic CA trust entries
        Write-Host "Creating CA trust entries..." -ForegroundColor Cyan

        foreach ($pattern in $caPatterns) {
            # Create a publisher pattern entry
            $cleanPattern = $pattern.Replace("*", "").Trim()
            if (-not $cleanPattern) { continue }

            # Check if already in list
            $exists = $listItems | Where-Object { $_.publisher -like $pattern }
            if ($exists) { continue }

            $notes = if ($presetConfig) { $presetConfig.Notes } else { "Certificate Authority trust pattern" }

            $newItem = [PSCustomObject]@{
                id             = [guid]::NewGuid().ToString()
                name           = "CA Trust: $cleanPattern"
                publisher      = $pattern
                productName    = "*"
                binaryName     = "*"
                minVersion     = "*"
                maxVersion     = "*"
                hash           = $null
                hashSourceFile = $null
                hashSourceSize = 0
                path           = $null
                category       = $Category
                notes          = $notes
                approved       = [bool]$AutoApprove
                ruleType       = "Publisher"
                added          = (Get-Date).ToString("o")
                addedBy        = if ($env:USERNAME) { $env:USERNAME } else { "System" }
            }

            $listItems += $newItem
            $importCount++
        }
    }

    $list.items = $listItems
    Save-SoftwareList -List $list -ListPath $ListPath

    Write-Host "Added $importCount certificate chain trust entries" -ForegroundColor Green

    return $list
}


function Scan-LocalFolder {
    <#
    .SYNOPSIS
    Scans a local folder for executables and imports them to a software list.

    .DESCRIPTION
    Recursively scans a folder (like C:\Program Files) for executables,
    extracts signature and hash information, and adds them to a software list.

    .PARAMETER FolderPath
    Path to the folder to scan.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER Category
    Category to assign.

    .PARAMETER SignedOnly
    Only import signed executables.

    .PARAMETER Recurse
    Recursively scan subfolders. Default: $true

    .PARAMETER MaxDepth
    Maximum folder depth to scan.

    .EXAMPLE
    Scan-LocalFolder -FolderPath "C:\Program Files" -ListPath .\list.json -SignedOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$FolderPath,

        [Parameter(Mandatory = $true)]
        [string]$ListPath,

        [string]$Category = "Local-Scan",

        [switch]$SignedOnly,

        [switch]$UnsignedOnly,

        [switch]$Recurse = $true,

        [int]$MaxDepth = 5,

        [switch]$AutoApprove
    )

    # Create list if doesn't exist
    if (-not (Test-Path $ListPath)) {
        $listDir = Split-Path -Parent $ListPath
        if (-not $listDir) { $listDir = "." }
        $listName = [System.IO.Path]::GetFileNameWithoutExtension($ListPath)
        New-SoftwareList -Name $listName -Description "Local folder scan" -OutputPath $listDir | Out-Null
    }

    $list = Get-SoftwareList -ListPath $ListPath

    Write-Host "Scanning $FolderPath..." -ForegroundColor Cyan

    $extensions = @("*.exe", "*.dll")
    $files = @()

    foreach ($ext in $extensions) {
        if ($Recurse) {
            $files += Get-ChildItem -Path $FolderPath -Filter $ext -Recurse -Depth $MaxDepth -ErrorAction SilentlyContinue
        }
        else {
            $files += Get-ChildItem -Path $FolderPath -Filter $ext -ErrorAction SilentlyContinue
        }
    }

    Write-Host "  Found $($files.Count) executable files" -ForegroundColor Gray

    $listItems = @($list.items)
    $importCount = 0
    $addedPublishers = @{}
    $addedHashes = @{}
    $processed = 0

    foreach ($file in $files) {
        $processed++
        if ($processed % 100 -eq 0) {
            Write-Host "  Processing: $processed / $($files.Count)" -ForegroundColor DarkGray
        }

        try {
            $sig = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue
            $isSigned = $sig -and $sig.Status -eq "Valid"

            # Apply filters
            if ($SignedOnly -and -not $isSigned) { continue }
            if ($UnsignedOnly -and $isSigned) { continue }

            $publisher = $null
            if ($isSigned -and $sig.SignerCertificate) {
                if ($sig.SignerCertificate.Subject -match "O=([^,]+)") {
                    $publisher = $Matches[1].Trim('"')
                }
            }

            $ruleType = if ($isSigned -and $publisher) { "Publisher" } else { "Hash" }

            # Deduplicate
            if ($ruleType -eq "Publisher" -and $publisher) {
                if ($addedPublishers.ContainsKey($publisher)) { continue }
            }

            $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            if ($ruleType -eq "Hash") {
                if (-not $hash) { continue }
                if ($addedHashes.ContainsKey($hash)) { continue }
            }

            # Check if already in list
            $exists = $listItems | Where-Object {
                ($_.publisher -and $publisher -and $_.publisher -eq $publisher) -or
                ($_.hash -and $hash -and $_.hash -eq $hash)
            }
            if ($exists) { continue }

            $newItem = [PSCustomObject]@{
                id             = [guid]::NewGuid().ToString()
                name           = $file.Name
                publisher      = $publisher
                productName    = "*"
                binaryName     = if ($ruleType -eq "Publisher") { "*" } else { $file.Name }
                minVersion     = "*"
                maxVersion     = "*"
                hash           = if ($ruleType -eq "Hash") { $hash } else { $null }
                hashSourceFile = if ($ruleType -eq "Hash") { $file.Name } else { $null }
                hashSourceSize = if ($ruleType -eq "Hash") { $file.Length } else { 0 }
                path           = $file.FullName
                category       = $Category
                notes          = "Scanned from: $FolderPath"
                approved       = [bool]$AutoApprove
                ruleType       = $ruleType
                added          = (Get-Date).ToString("o")
                addedBy        = if ($env:USERNAME) { $env:USERNAME } else { "System" }
            }

            $listItems += $newItem

            if ($ruleType -eq "Publisher" -and $publisher) {
                $addedPublishers[$publisher] = $true
            }
            elseif ($ruleType -eq "Hash" -and $hash) {
                $addedHashes[$hash] = $true
            }

            $importCount++
        }
        catch {
            continue
        }
    }

    $list.items = $listItems
    Save-SoftwareList -List $list -ListPath $ListPath

    Write-Host "Imported $importCount items" -ForegroundColor Green
    Write-Host "  Publisher rules: $($addedPublishers.Count)" -ForegroundColor Gray
    Write-Host "  Hash rules: $($addedHashes.Count)" -ForegroundColor Gray

    return $list
}


# =============================================================================
# Rule Generation Functions
# =============================================================================

function Get-SoftwareListRules {
    <#
    .SYNOPSIS
    Generates AppLocker rule XML from a software list.

    .DESCRIPTION
    Converts software list items into AppLocker rule XML that can be
    incorporated into a policy.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER RuleType
    Filter by rule type: Publisher, Hash, Path, or All

    .PARAMETER ApprovedOnly
    Only generate rules for approved items.

    .PARAMETER Category
    Filter by category.

    .PARAMETER UserOrGroupSid
    SID to apply rules to. Default: S-1-1-0 (Everyone)

    .PARAMETER Action
    Rule action: Allow or Deny

    .EXAMPLE
    $rules = Get-SoftwareListRules -ListPath .\list.json -RuleType Publisher -ApprovedOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath,

        [ValidateSet("Publisher", "Hash", "Path", "All")]
        [string]$RuleType = "All",

        [switch]$ApprovedOnly,

        [string]$Category,

        [string]$UserOrGroupSid = "S-1-1-0",

        [ValidateSet("Allow", "Deny")]
        [string]$Action = "Allow"
    )

    $list = Get-SoftwareList -ListPath $ListPath

    # Defensive: ensure items is an array
    $items = @($list.items)

    if ($items.Count -eq 0) {
        Write-Verbose "No items in software list"
        return @()
    }

    # Filter by approval status
    if ($ApprovedOnly) {
        $items = @($items | Where-Object { $_.approved -eq $true })
    }

    # Filter by category
    if ($Category) {
        $items = @($items | Where-Object { $_.category -eq $Category })
    }

    # Filter by rule type
    if ($RuleType -ne "All") {
        $items = @($items | Where-Object { $_.ruleType -eq $RuleType })
    }

    if ($items.Count -eq 0) {
        Write-Verbose "No items match the specified filters"
        return @()
    }

    $rules = @()

    foreach ($item in $items) {
        # Skip items with missing required data
        if (-not $item.name) { continue }

        $rule = $null
        switch ($item.ruleType) {
            "Publisher" {
                if ($item.publisher) {
                    $rule = New-PublisherRuleFromListItem -Item $item -Sid $UserOrGroupSid -Action $Action
                }
            }
            "Hash" {
                $rule = New-HashRuleFromListItem -Item $item -Sid $UserOrGroupSid -Action $Action
            }
            "Path" {
                $rule = New-PathRuleFromListItem -Item $item -Sid $UserOrGroupSid -Action $Action
            }
        }

        if ($rule) {
            $rules += $rule
        }
    }

    return $rules
}


function New-PublisherRuleFromListItem {
    <#
    .SYNOPSIS
    Creates a publisher rule XML from a software list item.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Item,

        [string]$Sid = "S-1-1-0",
        [string]$Action = "Allow"
    )

    $pubXml = [System.Security.SecurityElement]::Escape($Item.publisher)
    $prodXml = [System.Security.SecurityElement]::Escape($Item.productName)
    $binXml = [System.Security.SecurityElement]::Escape($Item.binaryName)
    $nameXml = [System.Security.SecurityElement]::Escape($Item.name)

    $lowVersion = if ($Item.minVersion -and $Item.minVersion -ne "*") { $Item.minVersion } else { "*" }
    $highVersion = if ($Item.maxVersion -and $Item.maxVersion -ne "*") { $Item.maxVersion } else { "*" }

    $ruleXml = @"
    <FilePublisherRule Id="$(New-Guid)" Name="$nameXml" Description="From Software List: $($Item.category)" UserOrGroupSid="$Sid" Action="$Action">
      <Conditions>
        <FilePublisherCondition PublisherName="O=$pubXml*" ProductName="$prodXml" BinaryName="$binXml">
          <BinaryVersionRange LowSection="$lowVersion" HighSection="$highVersion"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
"@

    return [PSCustomObject]@{
        Type     = "Publisher"
        Name     = $Item.name
        Category = $Item.category
        Xml      = $ruleXml
        Item     = $Item
    }
}


function New-HashRuleFromListItem {
    <#
    .SYNOPSIS
    Creates a hash rule XML from a software list item.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Item,

        [string]$Sid = "S-1-1-0",
        [string]$Action = "Allow"
    )

    if (-not $Item.hash) {
        Write-Warning "No hash available for: $($Item.name)"
        return $null
    }

    $nameXml = [System.Security.SecurityElement]::Escape($Item.name)
    $sourceFile = [System.Security.SecurityElement]::Escape($Item.hashSourceFile)
    $hashValue = if ($Item.hash -notmatch "^0x") { "0x$($Item.hash)" } else { $Item.hash }

    $ruleXml = @"
    <FileHashRule Id="$(New-Guid)" Name="Hash: $nameXml" Description="From Software List: $($Item.category)" UserOrGroupSid="$Sid" Action="$Action">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$hashValue" SourceFileName="$sourceFile" SourceFileLength="$($Item.hashSourceSize)"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
"@

    return [PSCustomObject]@{
        Type     = "Hash"
        Name     = $Item.name
        Category = $Item.category
        Xml      = $ruleXml
        Item     = $Item
    }
}


function New-PathRuleFromListItem {
    <#
    .SYNOPSIS
    Creates a path rule XML from a software list item.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Item,

        [string]$Sid = "S-1-1-0",
        [string]$Action = "Allow"
    )

    if (-not $Item.path) {
        Write-Warning "No path available for: $($Item.name)"
        return $null
    }

    $nameXml = [System.Security.SecurityElement]::Escape($Item.name)
    $pathXml = [System.Security.SecurityElement]::Escape($Item.path)

    $ruleXml = @"
    <FilePathRule Id="$(New-Guid)" Name="Path: $nameXml" Description="From Software List: $($Item.category)" UserOrGroupSid="$Sid" Action="$Action">
      <Conditions>
        <FilePathCondition Path="$pathXml"/>
      </Conditions>
    </FilePathRule>
"@

    return [PSCustomObject]@{
        Type     = "Path"
        Name     = $Item.name
        Category = $Item.category
        Xml      = $ruleXml
        Item     = $Item
    }
}


# =============================================================================
# Query and Report Functions
# =============================================================================

function Get-SoftwareListSummary {
    <#
    .SYNOPSIS
    Gets a summary of a software list.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .EXAMPLE
    Get-SoftwareListSummary -ListPath .\SoftwareLists\BusinessApps.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath
    )

    $list = Get-SoftwareList -ListPath $ListPath

    # Handle null or empty items array safely
    $items = @($list.items)

    $summary = [PSCustomObject]@{
        Name             = $list.metadata.name
        Description      = $list.metadata.description
        Version          = $list.metadata.version
        Created          = $list.metadata.created
        Modified         = $list.metadata.modified
        TotalItems       = $items.Count
        ApprovedItems    = @($items | Where-Object { $_.approved -eq $true }).Count
        PendingItems     = @($items | Where-Object { $_.approved -ne $true }).Count
        PublisherRules   = @($items | Where-Object { $_.ruleType -eq "Publisher" }).Count
        HashRules        = @($items | Where-Object { $_.ruleType -eq "Hash" }).Count
        PathRules        = @($items | Where-Object { $_.ruleType -eq "Path" }).Count
        Categories       = @($items | Where-Object { $_.category } | Select-Object -ExpandProperty category -Unique)
        UniquePublishers = @($items | Where-Object { $_.publisher } | Select-Object -ExpandProperty publisher -Unique).Count
    }

    return $summary
}


function Find-SoftwareListItem {
    <#
    .SYNOPSIS
    Searches for items in a software list.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER Name
    Search by name (supports wildcards).

    .PARAMETER Publisher
    Search by publisher (supports wildcards).

    .PARAMETER Category
    Filter by category.

    .PARAMETER RuleType
    Filter by rule type.

    .EXAMPLE
    Find-SoftwareListItem -ListPath .\list.json -Publisher "*ADOBE*"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath,

        [string]$Name,
        [string]$Publisher,
        [string]$Category,

        [ValidateSet("Publisher", "Hash", "Path")]
        [string]$RuleType
    )

    $list = Get-SoftwareList -ListPath $ListPath

    # Defensive: ensure items is an array
    $items = @($list.items)

    if ($Name) {
        $items = @($items | Where-Object { $_.name -like $Name })
    }
    if ($Publisher) {
        $items = $items | Where-Object { $_.publisher -like $Publisher }
    }
    if ($Category) {
        $items = $items | Where-Object { $_.category -eq $Category }
    }
    if ($RuleType) {
        $items = $items | Where-Object { $_.ruleType -eq $RuleType }
    }

    return $items
}


function Export-SoftwareListToCsv {
    <#
    .SYNOPSIS
    Exports a software list to CSV format for easy editing.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .PARAMETER OutputPath
    Path for the CSV output file.

    .EXAMPLE
    Export-SoftwareListToCsv -ListPath .\list.json -OutputPath .\list.csv
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ListPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $list = Get-SoftwareList -ListPath $ListPath

    # Defensive: ensure items is an array
    $items = @($list.items)

    if ($items.Count -eq 0) {
        Write-Warning "No items in software list to export"
        return
    }

    $items | Select-Object name, publisher, productName, binaryName, hash, path, category, approved, ruleType, notes |
    Export-Csv -Path $OutputPath -NoTypeInformation

    Write-Host "Exported $($items.Count) items to: $OutputPath" -ForegroundColor Green
}


function Import-SoftwareListFromCsv {
    <#
    .SYNOPSIS
    Imports items from a CSV file into a software list.

    .DESCRIPTION
    CSV should have columns: name, publisher, productName, binaryName, hash, path, category, approved, ruleType, notes

    .PARAMETER CsvPath
    Path to the CSV file.

    .PARAMETER ListPath
    Path to the software list JSON file.

    .EXAMPLE
    Import-SoftwareListFromCsv -CsvPath .\items.csv -ListPath .\SoftwareLists\MyList.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$CsvPath,

        [Parameter(Mandatory = $true)]
        [string]$ListPath
    )

    # Create list if doesn't exist
    if (-not (Test-Path $ListPath)) {
        $listDir = Split-Path -Parent $ListPath
        $listName = [System.IO.Path]::GetFileNameWithoutExtension($ListPath)
        New-SoftwareList -Name $listName -Description "Imported from CSV" -OutputPath $listDir | Out-Null
    }

    $csvItems = Import-Csv -Path $CsvPath
    $importCount = 0

    foreach ($csvItem in $csvItems) {
        # Determine rule type from CSV or infer from available data
        $ruleType = if ($csvItem.ruleType) {
            $csvItem.ruleType
        }
        elseif ($csvItem.hash) {
            "Hash"
        }
        elseif ($csvItem.publisher) {
            "Publisher"
        }
        else {
            "Path"
        }

        $params = @{
            ListPath    = $ListPath
            Name        = $csvItem.name
            Category    = if ($csvItem.category) { $csvItem.category } else { "Imported" }
            Notes       = $csvItem.notes
            RuleType    = $ruleType
            Approved    = [bool]($csvItem.approved -eq "True" -or $csvItem.approved -eq $true)
        }

        switch ($ruleType) {
            "Publisher" {
                $params.Publisher = $csvItem.publisher
                $params.ProductName = if ($csvItem.productName) { $csvItem.productName } else { "*" }
                $params.BinaryName = if ($csvItem.binaryName) { $csvItem.binaryName } else { "*" }
            }
            "Hash" {
                $params.Hash = $csvItem.hash
                $params.HashSourceFile = $csvItem.name
            }
            "Path" {
                $params.Path = $csvItem.path
            }
        }

        try {
            Add-SoftwareListItem @params -ErrorAction SilentlyContinue | Out-Null
            $importCount++
        }
        catch {
            Write-Warning "Failed to import: $($csvItem.name) - $_"
        }
    }

    Write-Host "Imported $importCount items from CSV" -ForegroundColor Green
}


# =============================================================================
# Export Module Members (only effective when loaded as .psm1 module)
# When dot-sourced as .ps1, all functions are automatically available
# =============================================================================

# Check if running as module or dot-sourced script
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        # List Management
        'New-SoftwareList',
        'Get-SoftwareList',
        'Save-SoftwareList',
        'Add-SoftwareListItem',
        'Remove-SoftwareListItem',
        'Update-SoftwareListItem',

        # Import Functions
        'Import-ScanDataToSoftwareList',
        'Import-ExecutableToSoftwareList',
        'Import-AppLockerEventLog',
        'Import-InstalledPrograms',
        'Import-CertificateChainRules',
        'Scan-LocalFolder',

        # Rule Generation
        'Get-SoftwareListRules',
        'New-PublisherRuleFromListItem',
        'New-HashRuleFromListItem',
        'New-PathRuleFromListItem',

        # Query and Export
        'Get-SoftwareListSummary',
        'Find-SoftwareListItem',
        'Export-SoftwareListToCsv',
        'Import-SoftwareListFromCsv'
    )
}
