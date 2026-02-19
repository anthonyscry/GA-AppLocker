function Invoke-AppLockerPolicyValidation {
    <#
    .SYNOPSIS
        Runs complete validation pipeline on an AppLocker policy.

    .DESCRIPTION
        Executes all validation checks in sequence:
        1. XML Schema validation
        2. GUID validation (format, uppercase, uniqueness)
        3. SID validation (format, well-known resolution)
        4. Rule condition validation (publisher, hash, path)
        5. Live import test (Microsoft parser)

    .PARAMETER XmlPath
        Path to the AppLocker policy XML file.

    .PARAMETER StopOnFirstError
        If specified, stops validation on first error found.

    .PARAMETER OutputReport
        Path to save detailed validation report as JSON.

    .OUTPUTS
        [PSCustomObject] with complete validation results including
        OverallSuccess, CanBeImported, TotalErrors, TotalWarnings,
        and individual stage results.

    .EXAMPLE
        Invoke-AppLockerPolicyValidation -XmlPath "C:\Policies\new-policy.xml"

    .EXAMPLE
        Invoke-AppLockerPolicyValidation -XmlPath "C:\Policies\new-policy.xml" -OutputReport "C:\Reports\validation.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$XmlPath,

        [switch]$StopOnFirstError,

        [string]$OutputReport
    )

    $overallResult = [PSCustomObject]@{
        PolicyPath      = $XmlPath
        ValidationTime  = Get-Date
        OverallSuccess  = $false
        CanBeImported   = $false
        TotalErrors     = 0
        TotalWarnings   = 0
        SchemaResult    = $null
        GuidResult      = $null
        SidResult       = $null
        ConditionResult = $null
        ImportResult    = $null
        Summary         = ""
    }

    Write-Host "`n======================================================================" -ForegroundColor Cyan
    Write-Host "         AppLocker Policy Validation Pipeline                         " -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "`nValidating: $XmlPath`n" -ForegroundColor White

    # 1. Schema Validation
    Write-Host "[1/5] XML Schema Validation..." -ForegroundColor Yellow -NoNewline
    $overallResult.SchemaResult = Test-AppLockerXmlSchema -XmlPath $XmlPath
    if ($overallResult.SchemaResult.Success) {
        Write-Host " PASSED" -ForegroundColor Green
        Write-Host "      Rule Collections: $($overallResult.SchemaResult.Details.RuleCollections -join ', ')"
        Write-Host "      Total Rules: $($overallResult.SchemaResult.Details.TotalRules)"
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        foreach ($err in $overallResult.SchemaResult.Errors) {
            Write-Host "      ERROR: $err" -ForegroundColor Red
        }
        if ($StopOnFirstError) { return $overallResult }
    }
    $overallResult.TotalErrors += $overallResult.SchemaResult.Errors.Count
    $overallResult.TotalWarnings += $overallResult.SchemaResult.Warnings.Count

    # 2. GUID Validation
    Write-Host "[2/5] GUID Validation..." -ForegroundColor Yellow -NoNewline
    $overallResult.GuidResult = Test-AppLockerRuleGuids -XmlPath $XmlPath
    if ($overallResult.GuidResult.Success) {
        Write-Host " PASSED" -ForegroundColor Green
        Write-Host "      Unique GUIDs: $($overallResult.GuidResult.UniqueGuids)"
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        foreach ($err in $overallResult.GuidResult.Errors) {
            Write-Host "      ERROR: $err" -ForegroundColor Red
        }
        if ($StopOnFirstError) { return $overallResult }
    }
    $overallResult.TotalErrors += $overallResult.GuidResult.Errors.Count

    # 3. SID Validation
    Write-Host "[3/5] SID Validation..." -ForegroundColor Yellow -NoNewline
    $overallResult.SidResult = Test-AppLockerRuleSids -XmlPath $XmlPath
    if ($overallResult.SidResult.Success) {
        Write-Host " PASSED" -ForegroundColor Green
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        foreach ($err in $overallResult.SidResult.Errors) {
            Write-Host "      ERROR: $err" -ForegroundColor Red
        }
        if ($StopOnFirstError) { return $overallResult }
    }
    $overallResult.TotalErrors += $overallResult.SidResult.Errors.Count

    # 4. Rule Condition Validation
    Write-Host "[4/5] Rule Condition Validation..." -ForegroundColor Yellow -NoNewline
    $overallResult.ConditionResult = Test-AppLockerRuleConditions -XmlPath $XmlPath
    if ($overallResult.ConditionResult.Success) {
        Write-Host " PASSED" -ForegroundColor Green
        Write-Host "      Publisher Rules: $($overallResult.ConditionResult.RuleStats.Publisher)"
        Write-Host "      Hash Rules: $($overallResult.ConditionResult.RuleStats.Hash)"
        Write-Host "      Path Rules: $($overallResult.ConditionResult.RuleStats.Path)"
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        foreach ($err in $overallResult.ConditionResult.Errors) {
            Write-Host "      ERROR: $err" -ForegroundColor Red
        }
        if ($StopOnFirstError) { return $overallResult }
    }
    foreach ($warn in $overallResult.ConditionResult.Warnings) {
        Write-Host "      WARNING: $warn" -ForegroundColor Yellow
    }
    $overallResult.TotalErrors += $overallResult.ConditionResult.Errors.Count
    $overallResult.TotalWarnings += $overallResult.ConditionResult.Warnings.Count

    # 5. Live Import Test
    Write-Host "[5/5] Live Import Test..." -ForegroundColor Yellow -NoNewline
    $overallResult.ImportResult = Test-AppLockerPolicyImport -XmlPath $XmlPath
    if ($overallResult.ImportResult.Success) {
        Write-Host " PASSED" -ForegroundColor Green
        $overallResult.CanBeImported = $true
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "      ERROR: $($overallResult.ImportResult.Error)" -ForegroundColor Red
        $overallResult.TotalErrors++
    }

    # Summary
    $overallResult.OverallSuccess = ($overallResult.TotalErrors -eq 0)

    Write-Host "`n======================================================================" -ForegroundColor Cyan
    if ($overallResult.OverallSuccess) {
        Write-Host "  VALIDATION PASSED - Policy can be imported to AppLocker" -ForegroundColor Green
        $overallResult.Summary = "PASSED"
    }
    else {
        Write-Host "  VALIDATION FAILED - $($overallResult.TotalErrors) error(s), $($overallResult.TotalWarnings) warning(s)" -ForegroundColor Red
        $overallResult.Summary = "FAILED: $($overallResult.TotalErrors) errors"
    }
    Write-Host "======================================================================`n" -ForegroundColor Cyan

    # Export report if requested
    if ($OutputReport) {
        $overallResult | ConvertTo-Json -Depth 3 | Out-File $OutputReport -Encoding UTF8
        Write-Host "Report saved to: $OutputReport" -ForegroundColor Gray
    }

    return $overallResult
}
