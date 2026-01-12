<#
.SYNOPSIS
    Pester tests for Test-RuleHealth.ps1 script.

.DESCRIPTION
    Tests rule health checking functionality including path validation,
    publisher validation, hash validation, conflict detection, and SID validation.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\src\Utilities\Test-RuleHealth.ps1'
    $script:FixturesPath = Join-Path $PSScriptRoot 'Fixtures'

    # Import error handling for test utilities
    $errorHandlingPath = Join-Path $PSScriptRoot '..\src\Utilities\ErrorHandling.psm1'
    if (Test-Path $errorHandlingPath) {
        Import-Module $errorHandlingPath -Force
    }

    # Create temp directory for test outputs
    $script:TestRoot = Join-Path $env:TEMP "GA-AppLocker-RuleHealth-Tests-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestRoot) {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Test-RuleHealth.ps1' {
    Context 'With valid policy' {
        BeforeAll {
            $script:ValidPolicy = Join-Path $script:FixturesPath 'SamplePolicy1.xml'
        }

        It 'Runs without error' {
            { & $script:ScriptPath -PolicyPath $script:ValidPolicy -Quiet } | Should -Not -Throw
        }

        It 'Returns a result object' {
            $result = & $script:ScriptPath -PolicyPath $script:ValidPolicy -Quiet
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'HealthScore'
            $result.PSObject.Properties.Name | Should -Contain 'TotalRules'
        }

        It 'Has HealthScore between 0 and 100' {
            $result = & $script:ScriptPath -PolicyPath $script:ValidPolicy -Quiet
            $result.HealthScore | Should -BeGreaterOrEqual 0
            $result.HealthScore | Should -BeLessOrEqual 100
        }
    }

    Context 'With policy containing issues' {
        BeforeAll {
            $script:IssuePolicy = Join-Path $script:FixturesPath 'PolicyWithIssues.xml'
        }

        It 'Detects overly permissive path rules' {
            $result = & $script:ScriptPath -PolicyPath $script:IssuePolicy -Quiet
            $criticalIssues = $result.Issues | Where-Object { $_.IssueType -eq 'OverlyPermissive' }
            $criticalIssues | Should -Not -BeNullOrEmpty
        }

        It 'Detects wildcard publisher rules' {
            $result = & $script:ScriptPath -PolicyPath $script:IssuePolicy -Quiet
            $wildcardIssues = $result.Issues | Where-Object { $_.IssueType -eq 'WildcardPublisher' }
            $wildcardIssues | Should -Not -BeNullOrEmpty
        }

        It 'Detects conflicting allow/deny rules' {
            $result = & $script:ScriptPath -PolicyPath $script:IssuePolicy -Quiet
            $conflictIssues = $result.Issues | Where-Object { $_.IssueType -eq 'ConflictingRules' }
            $conflictIssues | Should -Not -BeNullOrEmpty
        }

        It 'Reports critical issues correctly' {
            $result = & $script:ScriptPath -PolicyPath $script:IssuePolicy -Quiet
            $result.CriticalCount | Should -BeGreaterThan 0
        }

        It 'Has reduced health score for problematic policy' {
            $result = & $script:ScriptPath -PolicyPath $script:IssuePolicy -Quiet
            $result.HealthScore | Should -BeLessThan 100
        }
    }

    Context 'With non-existent path validation' {
        BeforeAll {
            # Create a policy with paths that definitely don't exist
            $script:BadPathPolicy = Join-Path $script:TestRoot 'badpath.xml'
            @"
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FilePathRule Id="test-id" Name="Bad Path" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="Z:\NonExistent\Path\ThatDoesNotExist\$(Get-Random)\*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@ | Out-File -FilePath $script:BadPathPolicy -Encoding UTF8
        }

        It 'Detects paths that do not exist' {
            $result = & $script:ScriptPath -PolicyPath $script:BadPathPolicy -Quiet
            $pathIssues = $result.Issues | Where-Object { $_.IssueType -eq 'PathNotFound' }
            $pathIssues | Should -Not -BeNullOrEmpty
        }
    }

    Context 'With output path specified' {
        It 'Creates a JSON report file' {
            $validPolicy = Join-Path $script:FixturesPath 'SamplePolicy1.xml'
            $outputDir = Join-Path $script:TestRoot 'reports'
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

            & $script:ScriptPath -PolicyPath $validPolicy -OutputPath $outputDir -Quiet

            $reports = Get-ChildItem -Path $outputDir -Filter 'health-report-*.json'
            $reports | Should -Not -BeNullOrEmpty
        }

        It 'Report contains valid JSON' {
            $validPolicy = Join-Path $script:FixturesPath 'SamplePolicy1.xml'
            $outputDir = Join-Path $script:TestRoot 'reports2'
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

            & $script:ScriptPath -PolicyPath $validPolicy -OutputPath $outputDir -Quiet

            $report = Get-ChildItem -Path $outputDir -Filter 'health-report-*.json' | Select-Object -First 1
            { Get-Content $report.FullName -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context 'With invalid input' {
        It 'Throws for non-existent policy file' {
            { & $script:ScriptPath -PolicyPath 'C:\NonExistent\Policy.xml' } | Should -Throw
        }
    }

    Context 'Health score calculation' {
        It 'Deducts 20 points per critical issue' {
            $result = & $script:ScriptPath -PolicyPath (Join-Path $script:FixturesPath 'PolicyWithIssues.xml') -Quiet
            # PolicyWithIssues.xml has at least 2 critical issues (OverlyPermissive, WildcardPublisher)
            # Score should be <= 60 (100 - 20 - 20)
            $result.HealthScore | Should -BeLessOrEqual 60
        }
    }
}

Describe 'Test-RuleHealth Internal Functions' {
    BeforeAll {
        # Load the script to get access to internal functions
        # We need to dot-source to access private functions
        $script:ScriptContent = Get-Content $script:ScriptPath -Raw

        # Create a valid XML for testing
        $script:TestXml = [xml]@"
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FilePathRule Id="test1" Name="Windows" UserOrGroupSid="S-1-5-18" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="test2" Name="Everyone Allow" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
    }

    Context 'Rule counting' {
        It 'Correctly counts rules in policy' {
            $validPolicy = Join-Path $script:FixturesPath 'SamplePolicy1.xml'
            $result = & $script:ScriptPath -PolicyPath $validPolicy -Quiet
            $result.TotalRules | Should -BeGreaterThan 0
        }
    }
}
