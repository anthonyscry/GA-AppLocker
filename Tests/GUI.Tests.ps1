<#
.SYNOPSIS
    Pester tests for GA-AppLocker GUI components.

.DESCRIPTION
    Tests GUI executable validation, startup benchmarks, and template components.
    These tests verify that the compiled EXE meets quality standards.
#>

BeforeAll {
    # Project root
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ExePath = Join-Path $script:ProjectRoot "GA-AppLocker.exe"
    $script:GuiScriptPath = Join-Path $script:ProjectRoot "src\GUI\GA-AppLocker-Portable.ps1"
}

#region EXE Validation Tests

Describe 'GA-AppLocker.exe Validation' {
    Context 'File Existence and Properties' {
        It 'EXE file exists in project root' {
            Test-Path $script:ExePath | Should -BeTrue -Because "GA-AppLocker.exe should be in the project root"
        }

        It 'EXE file is not empty' {
            if (Test-Path $script:ExePath) {
                $fileInfo = Get-Item $script:ExePath
                $fileInfo.Length | Should -BeGreaterThan 0 -Because "EXE should have content"
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }

        It 'EXE file is reasonably sized (between 1MB and 50MB)' {
            if (Test-Path $script:ExePath) {
                $fileInfo = Get-Item $script:ExePath
                $sizeMB = $fileInfo.Length / 1MB
                $sizeMB | Should -BeGreaterThan 1 -Because "EXE should be at least 1MB (PS2EXE compiled)"
                $sizeMB | Should -BeLessThan 50 -Because "EXE should not be bloated"
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }
    }

    Context 'PE Header Validation' {
        It 'EXE has valid PE header (MZ signature)' {
            if (Test-Path $script:ExePath) {
                $bytes = [System.IO.File]::ReadAllBytes($script:ExePath)
                # MZ header: 0x4D 0x5A
                $bytes[0] | Should -Be 0x4D -Because "First byte should be 'M'"
                $bytes[1] | Should -Be 0x5A -Because "Second byte should be 'Z'"
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }

        It 'EXE is marked as 64-bit' {
            if (Test-Path $script:ExePath) {
                # Check PE header for machine type
                $bytes = [System.IO.File]::ReadAllBytes($script:ExePath)
                # PE header offset is at 0x3C
                $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
                # Machine type is at PE offset + 4
                $machineType = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
                # 0x8664 = AMD64/x64
                $machineType | Should -Be 0x8664 -Because "EXE should be compiled for 64-bit"
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }
    }

    Context 'Version Information' {
        It 'EXE has version information embedded' {
            if (Test-Path $script:ExePath) {
                $versionInfo = (Get-Item $script:ExePath).VersionInfo
                $versionInfo.FileVersion | Should -Not -BeNullOrEmpty -Because "EXE should have version info"
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }

        It 'EXE version matches expected format (x.x.x.x)' {
            if (Test-Path $script:ExePath) {
                $versionInfo = (Get-Item $script:ExePath).VersionInfo
                $versionInfo.FileVersion | Should -Match '^\d+\.\d+\.\d+\.\d+$' -Because "Version should be in x.x.x.x format"
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }

        It 'EXE has product name set' {
            if (Test-Path $script:ExePath) {
                $versionInfo = (Get-Item $script:ExePath).VersionInfo
                $versionInfo.ProductName | Should -Not -BeNullOrEmpty -Because "Product name should be set"
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }
    }

    Context 'Code Signing (Optional)' {
        It 'EXE signature status is retrievable' {
            if (Test-Path $script:ExePath) {
                # This test just verifies we can check the signature, not that it's signed
                { Get-AuthenticodeSignature $script:ExePath } | Should -Not -Throw
            } else {
                Set-ItResult -Skipped -Because "EXE file not found"
            }
        }
    }
}

#endregion

#region GUI Script Validation

Describe 'GA-AppLocker-Portable.ps1 Validation' {
    Context 'Script Structure' {
        It 'GUI script file exists' {
            Test-Path $script:GuiScriptPath | Should -BeTrue
        }

        It 'Script has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:GuiScriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0 -Because "Script should have no syntax errors"
        }

        It 'Script contains DPI awareness code' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match 'DpiAwareness|SetProcessDpiAwareness' -Because "GUI should have DPI awareness"
        }

        It 'Script contains async helpers' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match 'Start-AsyncOperation|RunspacePool' -Because "GUI should have async helpers embedded"
        }

        It 'Script contains error handling wrapper' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match 'try\s*\{[\s\S]*ShowDialog[\s\S]*\}\s*catch' -Because "GUI should have error handling around ShowDialog"
        }

        It 'Script has version constant defined' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match '\$Script:AppVersion\s*=' -Because "Version constant should be defined"
        }
    }

    Context 'Required Components' {
        It 'Script loads WPF assemblies' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match 'PresentationFramework' -Because "WPF assemblies should be loaded"
        }

        It 'Script defines XAML content' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match '\[xml\]\$xaml' -Because "XAML should be defined"
        }

        It 'Script has navigation functions' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match 'function Switch-Page' -Because "Navigation should be implemented"
        }

        It 'Script has logging functions' {
            $content = Get-Content $script:GuiScriptPath -Raw
            $content | Should -Match 'function Write-Log' -Because "Logging should be implemented"
        }
    }
}

#endregion

#region Startup Benchmark

Describe 'GUI Startup Benchmark' {
    Context 'Performance Metrics' {
        It 'GUI script can be parsed in under 5 seconds' {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:GuiScriptPath,
                [ref]$null,
                [ref]$null
            )
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000 -Because "Script parsing should be fast"
        }

        It 'GUI script file size is reasonable (under 500KB)' {
            $fileInfo = Get-Item $script:GuiScriptPath
            $sizeKB = $fileInfo.Length / 1KB
            $sizeKB | Should -BeLessThan 500 -Because "Script should not be excessively large"
        }
    }
}

#endregion
