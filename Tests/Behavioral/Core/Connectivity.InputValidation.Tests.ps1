#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Behavioral Connectivity: Test-PingConnectivity input validation' -Tag @('Behavioral','Core') {
    It 'Rejects invalid hostname and skips WMI ping' {
        Mock Get-WmiObject { }

        $result = Test-PingConnectivity -Hostnames @('bad&name')

        $result['bad&name'] | Should -BeFalse
        Assert-MockCalled Get-WmiObject -Times 0 -Exactly
    }

    It 'Rejects empty and whitespace hostnames and skips WMI ping' {
        Mock Get-WmiObject { }

        $result = Test-PingConnectivity -Hostnames @('', ' ')

        $result[''] | Should -BeFalse
        $result[' '] | Should -BeFalse
        Assert-MockCalled Get-WmiObject -Times 0 -Exactly
    }

    It 'Skips null hostname without WMI ping' {
        Mock Get-WmiObject { }

        { Test-PingConnectivity -Hostnames @($null) } | Should -Not -Throw

        Assert-MockCalled Get-WmiObject -Times 0 -Exactly
    }

    It 'Derives TimeoutMs from TimeoutSeconds when only seconds provided' {
        Mock Get-WmiObject { [PSCustomObject]@{ StatusCode = 0 } }

        $result = Test-PingConnectivity -Hostnames @('host1') -TimeoutSeconds 1

        $result['host1'] | Should -BeTrue
        Assert-MockCalled Get-WmiObject -Times 1 -Exactly -ParameterFilter {
            $Filter -match 'Timeout=1000'
        }
    }
}

Describe 'Behavioral Connectivity: Test-MachineConnectivity null hostname handling' -Tag @('Behavioral','Core') {
    It 'Handles null hostname without throwing' {
        $machines = @(
            [PSCustomObject]@{ Hostname = $null }
        )

        { Test-MachineConnectivity -Machines $machines -TestWinRM:$false } | Should -Not -Throw

        $result = Test-MachineConnectivity -Machines $machines -TestWinRM:$false
        $result.Success | Should -BeTrue
        $result.Data.Count | Should -Be 1
        $result.Data[0].IsOnline | Should -BeFalse
        $result.Data[0].WinRMStatus | Should -Be 'Offline'
    }

    It 'Ignores null machine objects' {
        Mock Get-WmiObject { [PSCustomObject]@{ StatusCode = 0 } }

        $machines = @(
            $null,
            [PSCustomObject]@{ Hostname = 'host1' }
        )

        $result = Test-MachineConnectivity -Machines $machines -TestWinRM:$false

        $result.Success | Should -BeTrue
        $result.Data.Count | Should -Be 1
        $result.Summary.TotalMachines | Should -Be 1
    }
}

Describe 'Behavioral Connectivity: Test-PingConnectivity throttle safeguards' -Tag @('Behavioral','Core') {
    It 'Clamps ThrottleLimit to at least 1 for runspace pool' {
        $path = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Discovery\Functions\Test-MachineConnectivity.ps1'
        $content = Get-Content $path -Raw

        $content | Should -Match '\$effectiveThrottle\s*=\s*if\s*\(\$ThrottleLimit\s*-gt\s*0\)'
    }

    It 'Scales parallel ping deadline by batch count' {
        $path = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Discovery\Functions\Test-MachineConnectivity.ps1'
        $content = Get-Content $path -Raw

        $pattern = '(?s)\$batchCount\s*=\s*\[Math\]::Ceiling\(\$Hostnames\.Count\s*/\s*\$effectiveThrottle\).*?\$deadline\s*=\s*\[datetime\]::Now\.AddSeconds\(\(\$timeoutSecondsForDeadline\s*\*\s*\$batchCount\)\s*\+\s*10\)'
        $content | Should -Match $pattern
    }

    It 'Derives deadline from TimeoutMs' {
        $path = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Discovery\Functions\Test-MachineConnectivity.ps1'
        $content = Get-Content $path -Raw

        $pattern = '\$timeoutSecondsForDeadline\s*=\s*\[Math\]::Ceiling\(\$TimeoutMs\s*/\s*1000\)'
        $content | Should -Match $pattern
    }
}
