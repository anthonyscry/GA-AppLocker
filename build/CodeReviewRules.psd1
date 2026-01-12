# =============================================================================
# GA-AppLocker Code Review Rules Configuration
# =============================================================================
# Centralized configuration for PSScriptAnalyzer rules used across:
# - GitHub Actions workflows (build.yml)
# - Local validation (Invoke-LocalValidation.ps1)
# - Build scripts (Build-AppLocker.ps1)
#
# Modify this file to change code review rules project-wide.
# =============================================================================

@{
    # Rules to exclude from code quality analysis
    # These rules are intentionally excluded for this project
    ExcludedRules = @(
        # CLI tools use Write-Host for user feedback - this is intentional
        'PSAvoidUsingWriteHost'

        # Project uses scriptblock-reset indentation style
        'PSUseConsistentIndentation'

        # Conflicts with scriptblock indentation style
        'PSUseConsistentWhitespace'

        # BOM not required for UTF-8 in modern systems
        'PSUseBOMForUnicodeEncodedFile'
    )

    # Security-focused rules to always include
    SecurityRules = @(
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSAvoidUsingUsernameAndPasswordParams'
        'PSAvoidUsingComputerNameHardcoded'
        'PSUsePSCredentialType'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingCmdletAliases'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidGlobalVars'
        'PSAvoidUsingEmptyCatchBlock'
    )

    # Patterns to detect potential hardcoded secrets
    SecretPatterns = @(
        @{ Name = 'Potential API Key'; Pattern = '(?i)(api[_-]?key|apikey)\s*[=:]\s*[''"][a-zA-Z0-9]{20,}[''"]' }
        @{ Name = 'Potential Password'; Pattern = '(?i)(password|pwd|passwd)\s*[=:]\s*[''"][^''"]{8,}[''"]' }
        @{ Name = 'Potential Token'; Pattern = '(?i)(token|secret|bearer)\s*[=:]\s*[''"][a-zA-Z0-9_-]{20,}[''"]' }
        @{ Name = 'Potential Connection String'; Pattern = '(?i)(connectionstring|connstr)\s*[=:]\s*[''"][^''"]+[''"]' }
    )

    # Severity levels to report
    SeverityLevels = @('Error', 'Warning')

    # File patterns to exclude from analysis
    ExcludePaths = @(
        '\\Tests\\'
        '\\\.git\\'
        '\\node_modules\\'
    )

    # File extensions to analyze
    IncludeExtensions = @('.ps1', '.psm1', '.psd1')
}
