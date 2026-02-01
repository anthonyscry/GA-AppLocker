# DEAD CODE — These functions are never called from the GUI or any module.
# Retained for potential future CLI usage. Removed from module exports.
#region ===== REPORTING & POWERBI EXPORT (UNUSED) =====
<#
.SYNOPSIS
    Reporting and PowerBI export functionality for GA-AppLocker.

.DESCRIPTION
    Exports data in formats suitable for Power BI, Excel, and generates
    HTML reports for compliance and audit purposes.


    .EXAMPLE
    Export-AppLockerReport
    # Export AppLockerReport
    #>

function Export-AppLockerReport {
    <#
    .SYNOPSIS
        Exports a comprehensive HTML report of AppLocker data.

    .DESCRIPTION
        Exports a comprehensive HTML report of AppLocker data. Writes output to the specified path.

    .PARAMETER OutputPath
        Path to save the HTML report.

    .PARAMETER IncludeRules
        Include rules section.

    .PARAMETER IncludePolicies
        Include policies section.

    .PARAMETER IncludeAuditLog
        Include recent audit log.

    .PARAMETER AuditDays
        Number of days of audit history to include.

    .EXAMPLE
        Export-AppLockerReport -OutputPath 'C:\Reports\applocker-report.html'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [switch]$IncludeRules = $true,
        [switch]$IncludePolicies = $true,
        [switch]$IncludeAuditLog = $true,
        [int]$AuditDays = 30
    )

    try {
        $reportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $domain = try { [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName } catch { 'Unknown' }
        
        # Gather data
        $ruleStats = @{ Total = 0; Approved = 0; Pending = 0; Rejected = 0; Review = 0 }
        $rules = @()
        if ($IncludeRules -and (Get-Command 'Get-AllRules' -ErrorAction SilentlyContinue)) {
            $rulesResult = Get-AllRules -Take 100000
            if ($rulesResult.Success) {
                $rules = @($rulesResult.Data)
                $ruleStats.Total = $rules.Count
                $ruleStats.Approved = @($rules | Where-Object Status -eq 'Approved').Count
                $ruleStats.Pending = @($rules | Where-Object Status -eq 'Pending').Count
                $ruleStats.Rejected = @($rules | Where-Object Status -eq 'Rejected').Count
                $ruleStats.Review = @($rules | Where-Object Status -eq 'Review').Count
            }
        }
        
        $policies = @()
        if ($IncludePolicies -and (Get-Command 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
            $policiesResult = Get-AllPolicies
            if ($policiesResult.Success) {
                $policies = @($policiesResult.Data)
            }
        }
        
        $auditLog = @()
        if ($IncludeAuditLog -and (Get-Command 'Get-AuditLog' -ErrorAction SilentlyContinue)) {
            $auditResult = Get-AuditLog -StartDate (Get-Date).AddDays(-$AuditDays) -Last 500
            if ($auditResult.Success) {
                $auditLog = @($auditResult.Data)
            }
        }
        
        # Generate HTML
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>GA-AppLocker Report - $reportDate</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 40px; background: #f5f5f5; }
        .header { background: #0078D4; color: white; padding: 30px; border-radius: 8px; margin-bottom: 30px; }
        .header h1 { margin: 0; font-size: 28px; }
        .header p { margin: 5px 0 0; opacity: 0.9; }
        .section { background: white; padding: 25px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { margin-top: 0; color: #333; border-bottom: 2px solid #0078D4; padding-bottom: 10px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .stat-card { background: #f8f8f8; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-card .value { font-size: 36px; font-weight: bold; color: #0078D4; }
        .stat-card .label { color: #666; font-size: 12px; text-transform: uppercase; }
        .stat-card.success .value { color: #107C10; }
        .stat-card.warning .value { color: #FF8C00; }
        .stat-card.error .value { color: #D13438; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; }
        th { background: #f8f8f8; font-weight: 600; color: #333; }
        tr:hover { background: #f8f9fa; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 4px; font-size: 11px; font-weight: 600; }
        .badge-approved { background: #107C10; color: white; }
        .badge-pending { background: #FF8C00; color: white; }
        .badge-rejected { background: #D13438; color: white; }
        .badge-review { background: #0078D4; color: white; }
        .badge-active { background: #107C10; color: white; }
        .badge-draft { background: #888; color: white; }
        .footer { text-align: center; color: #666; margin-top: 30px; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>GA-AppLocker Report</h1>
        <p>Generated: $reportDate | Domain: $domain | Computer: $env:COMPUTERNAME</p>
    </div>
    
    <div class="section">
        <h2>Summary</h2>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="value">$($ruleStats.Total)</div>
                <div class="label">Total Rules</div>
            </div>
            <div class="stat-card success">
                <div class="value">$($ruleStats.Approved)</div>
                <div class="label">Approved</div>
            </div>
            <div class="stat-card warning">
                <div class="value">$($ruleStats.Pending)</div>
                <div class="label">Pending</div>
            </div>
            <div class="stat-card error">
                <div class="value">$($ruleStats.Rejected)</div>
                <div class="label">Rejected</div>
            </div>
            <div class="stat-card">
                <div class="value">$($policies.Count)</div>
                <div class="label">Policies</div>
            </div>
        </div>
    </div>
"@
        
        # Rules section
        if ($IncludeRules -and $rules.Count -gt 0) {
            $html += @"
    
    <div class="section">
        <h2>Rules ($($rules.Count))</h2>
        <table>
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Type</th>
                    <th>Collection</th>
                    <th>Status</th>
                    <th>Created</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($rule in ($rules | Select-Object -First 100)) {
                $statusClass = switch ($rule.Status) {
                    'Approved' { 'approved' }
                    'Pending' { 'pending' }
                    'Rejected' { 'rejected' }
                    'Review' { 'review' }
                    default { '' }
                }
                $createdDate = if ($rule.CreatedDate) { 
                    try { ([datetime]$rule.CreatedDate).ToString('yyyy-MM-dd') } catch { $rule.CreatedDate }
                } else { '-' }
                
                $html += @"
                <tr>
                    <td>$([System.Web.HttpUtility]::HtmlEncode($rule.Name))</td>
                    <td>$($rule.RuleType)</td>
                    <td>$($rule.CollectionType)</td>
                    <td><span class="badge badge-$statusClass">$($rule.Status)</span></td>
                    <td>$createdDate</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
    </div>
"@
        }
        
        # Policies section
        if ($IncludePolicies -and $policies.Count -gt 0) {
            $html += @"
    
    <div class="section">
        <h2>Policies ($($policies.Count))</h2>
        <table>
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Status</th>
                    <th>Rules</th>
                    <th>Created</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($policy in $policies) {
                $statusClass = if ($policy.Status -eq 'Active') { 'active' } else { 'draft' }
                $createdDate = if ($policy.CreatedAt) {
                    try { ([datetime]$policy.CreatedAt).ToString('yyyy-MM-dd') } catch { $policy.CreatedAt }
                } else { '-' }
                
                $html += @"
                <tr>
                    <td>$([System.Web.HttpUtility]::HtmlEncode($policy.Name))</td>
                    <td><span class="badge badge-$statusClass">$($policy.Status)</span></td>
                    <td>$($policy.RuleCount)</td>
                    <td>$createdDate</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
    </div>
"@
        }
        
        # Audit log section
        if ($IncludeAuditLog -and $auditLog.Count -gt 0) {
            $html += @"
    
    <div class="section">
        <h2>Recent Activity (Last $AuditDays Days)</h2>
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>User</th>
                    <th>Action</th>
                    <th>Target</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($entry in ($auditLog | Select-Object -First 50)) {
                $timestamp = try { ([datetime]$entry.Timestamp).ToString('yyyy-MM-dd HH:mm') } catch { $entry.Timestamp }
                $html += @"
                <tr>
                    <td>$timestamp</td>
                    <td>$([System.Web.HttpUtility]::HtmlEncode($entry.User))</td>
                    <td>$([System.Web.HttpUtility]::HtmlEncode($entry.Action))</td>
                    <td>$([System.Web.HttpUtility]::HtmlEncode($entry.Target))</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
    </div>
"@
        }
        
        $html += @"
    
    <div class="footer">
        <p>Generated by GA-AppLocker Dashboard v1.0.0</p>
    </div>
</body>
</html>
"@
        
        # Ensure output directory exists
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        $html | Set-Content $OutputPath -Encoding UTF8 -Force
        
        # Audit log
        if (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue) {
            Write-AuditLog -Action 'ReportGenerated' -Category 'System' -Target $OutputPath `
                -Details "Rules: $($rules.Count), Policies: $($policies.Count)" | Out-Null
        }
        
        return @{
            Success = $true
            Data = @{
                Path = $OutputPath
                RuleCount = $rules.Count
                PolicyCount = $policies.Count
                AuditEntries = $auditLog.Count
            }
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

function Export-ForPowerBI {
    <#
    .SYNOPSIS
        Exports data in formats optimized for Power BI.

    .DESCRIPTION
        Exports data in formats optimized for Power BI. Writes output to the specified path.

    .PARAMETER OutputDirectory
        Directory to save the export files.

    .PARAMETER IncludeRules
        Export rules data.

    .PARAMETER IncludePolicies
        Export policies data.

    .PARAMETER IncludeAuditLog
        Export audit log data.

    .PARAMETER Format
        Export format: CSV or JSON.

    .EXAMPLE
        Export-ForPowerBI -OutputDirectory 'C:\PowerBI\Data' -Format CSV
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputDirectory,

        [switch]$IncludeRules = $true,
        [switch]$IncludePolicies = $true,
        [switch]$IncludeAuditLog = $true,

        [ValidateSet('CSV', 'JSON')]
        [string]$Format = 'CSV'
    )

    try {
        if (-not (Test-Path $OutputDirectory)) {
            New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        }
        
        $exportedFiles = @()
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        
        # Export Rules
        if ($IncludeRules -and (Get-Command 'Get-AllRules' -ErrorAction SilentlyContinue)) {
            $rulesResult = Get-AllRules
            if ($rulesResult.Success -and $rulesResult.Data) {
                $rulesData = $rulesResult.Data | Select-Object `
                    Id, Name, RuleType, CollectionType, Action, Status, `
                    PublisherName, ProductName, FileName, FileVersion, `
                    Hash, Path, CreatedDate, ModifiedDate
                
                $rulesPath = Join-Path $OutputDirectory "rules_$timestamp.$($Format.ToLower())"
                
                if ($Format -eq 'CSV') {
                    $rulesData | Export-Csv -Path $rulesPath -NoTypeInformation -Force
                } else {
                    $rulesData | ConvertTo-Json -Depth 10 | Set-Content $rulesPath -Force
                }
                
                $exportedFiles += @{ Type = 'Rules'; Path = $rulesPath; Count = $rulesData.Count }
            }
        }
        
        # Export Policies
        if ($IncludePolicies -and (Get-Command 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
            $policiesResult = Get-AllPolicies
            if ($policiesResult.Success -and $policiesResult.Data) {
                $policiesData = $policiesResult.Data | Select-Object `
                    Id, Name, Description, Status, Version, RuleCount, `
                    EnforcementMode, CreatedAt, ModifiedAt
                
                $policiesPath = Join-Path $OutputDirectory "policies_$timestamp.$($Format.ToLower())"
                
                if ($Format -eq 'CSV') {
                    $policiesData | Export-Csv -Path $policiesPath -NoTypeInformation -Force
                } else {
                    $policiesData | ConvertTo-Json -Depth 10 | Set-Content $policiesPath -Force
                }
                
                $exportedFiles += @{ Type = 'Policies'; Path = $policiesPath; Count = $policiesData.Count }
            }
        }
        
        # Export Audit Log
        if ($IncludeAuditLog -and (Get-Command 'Get-AuditLog' -ErrorAction SilentlyContinue)) {
            $auditResult = Get-AuditLog -Last 10000
            if ($auditResult.Success -and $auditResult.Data) {
                $auditData = $auditResult.Data | Select-Object `
                    Id, Timestamp, User, Computer, Action, Category, Target, Details
                
                $auditPath = Join-Path $OutputDirectory "audit_log_$timestamp.$($Format.ToLower())"
                
                if ($Format -eq 'CSV') {
                    $auditData | Export-Csv -Path $auditPath -NoTypeInformation -Force
                } else {
                    $auditData | ConvertTo-Json -Depth 10 | Set-Content $auditPath -Force
                }
                
                $exportedFiles += @{ Type = 'AuditLog'; Path = $auditPath; Count = $auditData.Count }
            }
        }
        
        # Create summary/stats file for dashboards
        $statsPath = Join-Path $OutputDirectory "summary_$timestamp.$($Format.ToLower())"
        $domainName = try { [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName } catch { 'Unknown' }
        $rulesTotal = if ($rulesResult.Success -and $rulesResult.Data) { $rulesResult.Data.Count } else { 0 }
        $rulesApproved = if ($rulesResult.Success -and $rulesResult.Data) { @($rulesResult.Data | Where-Object Status -eq 'Approved').Count } else { 0 }
        $rulesPending = if ($rulesResult.Success -and $rulesResult.Data) { @($rulesResult.Data | Where-Object Status -eq 'Pending').Count } else { 0 }
        $policiesTotal = if ($policiesResult.Success -and $policiesResult.Data) { $policiesResult.Data.Count } else { 0 }
        
        $stats = @{
            ExportDate = Get-Date -Format 'o'
            Domain = $domainName
            Computer = $env:COMPUTERNAME
            User = "$env:USERDOMAIN\$env:USERNAME"
            RulesTotal = $rulesTotal
            RulesApproved = $rulesApproved
            RulesPending = $rulesPending
            PoliciesTotal = $policiesTotal
        }
        
        if ($Format -eq 'CSV') {
            [PSCustomObject]$stats | Export-Csv -Path $statsPath -NoTypeInformation -Force
        } else {
            $stats | ConvertTo-Json | Set-Content $statsPath -Force
        }
        $exportedFiles += @{ Type = 'Summary'; Path = $statsPath; Count = 1 }
        
        # Audit log
        if (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue) {
            Write-AuditLog -Action 'PowerBIExport' -Category 'System' -Target $OutputDirectory `
                -Details "Exported $($exportedFiles.Count) files in $Format format" | Out-Null
        }
        
        return @{
            Success = $true
            Data = @{
                OutputDirectory = $OutputDirectory
                Format = $Format
                Files = $exportedFiles
            }
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
