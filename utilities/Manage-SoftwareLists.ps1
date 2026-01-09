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

    # Find all scan data
    $computerFolders = Get-ChildItem -Path $ScanPath -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "*.csv") }

    if ($computerFolders.Count -eq 0) {
        throw "No scan data found in $ScanPath"
    }

    Write-Host "Loading scan data from $($computerFolders.Count) computers..." -ForegroundColor Cyan

    $allExecutables = @()
    foreach ($folder in $computerFolders) {
        $exePath = Join-Path $folder.FullName "Executables.csv"
        if (Test-Path $exePath) {
            $allExecutables += Import-Csv -Path $exePath
        }
    }

    Write-Host "  Found $($allExecutables.Count) total executables" -ForegroundColor Gray

    # Filter based on switches
    $toImport = $allExecutables
    if ($SignedOnly) {
        $toImport = $toImport | Where-Object { $_.IsSigned -eq "True" -and $_.Publisher }
    }
    if ($UnsignedOnly) {
        $toImport = $toImport | Where-Object { $_.IsSigned -ne "True" -and $_.Hash }
    }

    # Track what we've added for deduplication
    $addedPublishers = @{}
    $addedHashes = @{}
    $importCount = 0

    foreach ($exe in $toImport) {
        $ruleType = if ($exe.IsSigned -eq "True" -and $exe.Publisher) { "Publisher" } else { "Hash" }

        # Deduplicate if requested
        if ($Deduplicate -and $ruleType -eq "Publisher") {
            if ($addedPublishers.ContainsKey($exe.Publisher)) { continue }
            $addedPublishers[$exe.Publisher] = $true
        }
        if ($Deduplicate -and $ruleType -eq "Hash") {
            if ($addedHashes.ContainsKey($exe.Hash)) { continue }
            $addedHashes[$exe.Hash] = $true
        }

        # Check if already in list
        $exists = $list.items | Where-Object {
            ($_.publisher -eq $exe.Publisher -and $exe.Publisher) -or
            ($_.hash -eq $exe.Hash -and $exe.Hash)
        }
        if ($exists) { continue }

        # Extract product name from path
        $productName = if ($exe.Path -match "\\([^\\]+)\\[^\\]+$") { $matches[1] } else { "*" }

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
            hashSourceSize = [int64]$exe.Size
            path           = $exe.Path
            category       = $Category
            notes          = "Imported from scan: $($folder.Name)"
            approved       = [bool]$AutoApprove
            ruleType       = $ruleType
            added          = (Get-Date).ToString("o")
            addedBy        = $env:USERNAME
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

    $items = $list.items

    # Filter by approval status
    if ($ApprovedOnly) {
        $items = $items | Where-Object { $_.approved -eq $true }
    }

    # Filter by category
    if ($Category) {
        $items = $items | Where-Object { $_.category -eq $Category }
    }

    # Filter by rule type
    if ($RuleType -ne "All") {
        $items = $items | Where-Object { $_.ruleType -eq $RuleType }
    }

    $rules = @()

    foreach ($item in $items) {
        switch ($item.ruleType) {
            "Publisher" {
                $rule = New-PublisherRuleFromListItem -Item $item -Sid $UserOrGroupSid -Action $Action
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

    $summary = [PSCustomObject]@{
        Name             = $list.metadata.name
        Description      = $list.metadata.description
        Version          = $list.metadata.version
        Created          = $list.metadata.created
        Modified         = $list.metadata.modified
        TotalItems       = $list.items.Count
        ApprovedItems    = ($list.items | Where-Object { $_.approved -eq $true }).Count
        PendingItems     = ($list.items | Where-Object { $_.approved -ne $true }).Count
        PublisherRules   = ($list.items | Where-Object { $_.ruleType -eq "Publisher" }).Count
        HashRules        = ($list.items | Where-Object { $_.ruleType -eq "Hash" }).Count
        PathRules        = ($list.items | Where-Object { $_.ruleType -eq "Path" }).Count
        Categories       = ($list.items | Select-Object -ExpandProperty category -Unique)
        UniquePublishers = ($list.items | Where-Object { $_.publisher } | Select-Object -ExpandProperty publisher -Unique).Count
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
    $items = $list.items

    if ($Name) {
        $items = $items | Where-Object { $_.name -like $Name }
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

    $list.items | Select-Object name, publisher, productName, binaryName, hash, path, category, approved, ruleType, notes |
    Export-Csv -Path $OutputPath -NoTypeInformation

    Write-Host "Exported $($list.items.Count) items to: $OutputPath" -ForegroundColor Green
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
# Export Module Members (only when loaded as a module)
# =============================================================================

# Only export if being loaded as a module (not dot-sourced)
if ($MyInvocation.Line -notmatch '^\.\s') {
    try {
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
        ) -ErrorAction SilentlyContinue
    }
    catch {
        # Silently ignore - file is being dot-sourced, not loaded as module
    }
}
