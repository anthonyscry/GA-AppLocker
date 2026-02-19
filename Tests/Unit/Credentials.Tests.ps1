#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Create a unique temp directory for credential storage so tests are isolated
    # from real data in %LOCALAPPDATA%\GA-AppLocker
    $script:TempCredPath = Join-Path $env:TEMP "GA-AppLocker-Tests-$([guid]::NewGuid().ToString('N'))"
    New-Item -Path $script:TempCredPath -ItemType Directory -Force | Out-Null

    # Helper: build a PSCredential for testing (DPAPI-safe, local machine only)
    function script:New-TestCred {
        param([string]$User = 'TestUser', [string]$Pass = 'TestPass123!')
        $ss = ConvertTo-SecureString $Pass -AsPlainText -Force
        return [System.Management.Automation.PSCredential]::new($User, $ss)
    }

    # Helper: unique profile name to avoid collisions between test runs
    function script:New-UniqueName {
        return "TestCred_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    }
}

AfterAll {
    if ($script:TempCredPath -and (Test-Path $script:TempCredPath)) {
        Remove-Item -Path $script:TempCredPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'New-CredentialProfile' -Tag @('Unit', 'Credentials') {

    BeforeEach {
        # Redirect all credential storage to the temp directory for every test
        Mock Get-AppLockerDataPath { return $script:TempCredPath } -ModuleName 'GA-AppLocker.Credentials'
    }

    AfterEach {
        # Remove all JSON files created during the test so tests are fully isolated
        Get-ChildItem -Path $script:TempCredPath -Filter '*.json' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path (Join-Path $script:TempCredPath 'Credentials') -Filter '*.json' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    It 'Returns Success=$true and a profile data object' {
        $name = New-UniqueName
        $result = New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 0
        $result.Success | Should -BeTrue
        $result.Data | Should -Not -BeNullOrEmpty
        $result.Error | Should -BeNullOrEmpty
    }

    It 'Profile data contains required fields: Id, Name, Username, Tier, TierName, Description, IsDefault, CreatedDate' {
        $name = New-UniqueName
        $result = New-CredentialProfile -Name $name -Credential (New-TestCred -User 'DOMAIN\Admin') -Tier 1 -Description 'Test desc'
        $result.Success | Should -BeTrue
        $result.Data.Id | Should -Not -BeNullOrEmpty
        $result.Data.Name | Should -Be $name
        $result.Data.Username | Should -Be 'DOMAIN\Admin'
        $result.Data.Tier | Should -Be 1
        $result.Data.TierName | Should -Not -BeNullOrEmpty
        $result.Data.Description | Should -Be 'Test desc'
        $result.Data.IsDefault | Should -Not -BeNullOrEmpty
        $result.Data.CreatedDate | Should -Not -BeNullOrEmpty
    }

    It 'Id field is a valid GUID format' {
        $name = New-UniqueName
        $result = New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 0
        $result.Success | Should -BeTrue
        { [guid]::Parse($result.Data.Id) } | Should -Not -Throw
    }

    It 'Tier 0 maps to TierName DomainController' {
        $result = New-CredentialProfile -Name (New-UniqueName) -Credential (New-TestCred) -Tier 0
        $result.Success | Should -BeTrue
        $result.Data.TierName | Should -Be 'DomainController'
    }

    It 'Tier 1 maps to TierName Server' {
        $result = New-CredentialProfile -Name (New-UniqueName) -Credential (New-TestCred) -Tier 1
        $result.Success | Should -BeTrue
        $result.Data.TierName | Should -Be 'Server'
    }

    It 'Tier 2 maps to TierName Workstation' {
        $result = New-CredentialProfile -Name (New-UniqueName) -Credential (New-TestCred) -Tier 2
        $result.Success | Should -BeTrue
        $result.Data.TierName | Should -Be 'Workstation'
    }

    It '-SetAsDefault sets IsDefault=$true on the profile' {
        $result = New-CredentialProfile -Name (New-UniqueName) -Credential (New-TestCred) -Tier 1 -SetAsDefault
        $result.Success | Should -BeTrue
        $result.Data.IsDefault | Should -BeTrue
    }

    It 'IsDefault is $false when -SetAsDefault is not specified' {
        $result = New-CredentialProfile -Name (New-UniqueName) -Credential (New-TestCred) -Tier 2
        $result.Success | Should -BeTrue
        $result.Data.IsDefault | Should -BeFalse
    }

    It 'Creates a JSON file on disk' {
        $name = New-UniqueName
        $result = New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 0
        $result.Success | Should -BeTrue
        $credPath = Join-Path $script:TempCredPath 'Credentials'
        $files = Get-ChildItem -Path $credPath -Filter '*.json' -ErrorAction SilentlyContinue
        @($files).Count | Should -BeGreaterThan 0
    }

    It 'Returns Success=$false and an error message when name already exists' {
        $name = New-UniqueName
        # Create the first profile
        New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 0 | Out-Null
        # Attempt to create a duplicate
        $result = New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 0
        $result.Success | Should -BeFalse
        $result.Error | Should -Match 'already exists'
    }
}

Describe 'Get-CredentialProfile' -Tag @('Unit', 'Credentials') {

    BeforeAll {
        Mock Get-AppLockerDataPath { return $script:TempCredPath } -ModuleName 'GA-AppLocker.Credentials'

        # Create a known set of profiles for retrieval tests
        $script:ProfileA_Name = "GetTest_A_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $script:ProfileB_Name = "GetTest_B_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $script:ProfileC_Name = "GetTest_C_$([guid]::NewGuid().ToString('N').Substring(0,8))"

        $rA = New-CredentialProfile -Name $script:ProfileA_Name -Credential (New-TestCred -User 'UserA') -Tier 0 -SetAsDefault
        $rB = New-CredentialProfile -Name $script:ProfileB_Name -Credential (New-TestCred -User 'UserB') -Tier 1
        $rC = New-CredentialProfile -Name $script:ProfileC_Name -Credential (New-TestCred -User 'UserC') -Tier 1

        $script:ProfileA_Id = $rA.Data.Id
        $script:ProfileB_Id = $rB.Data.Id
        $script:ProfileC_Id = $rC.Data.Id
    }

    AfterAll {
        # Clean up profiles created in this Describe block
        Get-ChildItem -Path (Join-Path $script:TempCredPath 'Credentials') -Filter '*.json' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    It 'Retrieves a profile by -Name' {
        $result = Get-CredentialProfile -Name $script:ProfileA_Name
        $result.Success | Should -BeTrue
        $result.Data | Should -Not -BeNullOrEmpty
        $result.Data.Name | Should -Be $script:ProfileA_Name
    }

    It 'Retrieves a profile by -Id' {
        $result = Get-CredentialProfile -Id $script:ProfileA_Id
        $result.Success | Should -BeTrue
        $result.Data | Should -Not -BeNullOrEmpty
        $result.Data.Id | Should -Be $script:ProfileA_Id
    }

    It 'Retrieves all profiles for a -Tier' {
        $result = Get-CredentialProfile -Tier 1
        $result.Success | Should -BeTrue
        $names = @($result.Data | Select-Object -ExpandProperty Name)
        $names | Should -Contain $script:ProfileB_Name
        $names | Should -Contain $script:ProfileC_Name
        $names | Should -Not -Contain $script:ProfileA_Name
    }

    It 'Returns all profiles when no parameters are given' {
        $result = Get-CredentialProfile
        $result.Success | Should -BeTrue
        $names = @($result.Data | Select-Object -ExpandProperty Name)
        $names | Should -Contain $script:ProfileA_Name
        $names | Should -Contain $script:ProfileB_Name
    }

    It 'Returns Success=$true and Data=$null for non-existent name' {
        $result = Get-CredentialProfile -Name 'NonExistentProfile_XYZABC'
        $result.Success | Should -BeTrue
        $result.Data | Should -BeNullOrEmpty
    }
}

Describe 'Get-CredentialForTier' -Tag @('Unit', 'Credentials') {

    BeforeAll {
        Mock Get-AppLockerDataPath { return $script:TempCredPath } -ModuleName 'GA-AppLocker.Credentials'

        # Cleanup any leftover profiles
        Get-ChildItem -Path (Join-Path $script:TempCredPath 'Credentials') -Filter '*.json' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    AfterEach {
        # Clean up profiles between tests
        Get-ChildItem -Path (Join-Path $script:TempCredPath 'Credentials') -Filter '*.json' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    It 'Returns a PSCredential object (Success=$true, Data is PSCredential)' {
        New-CredentialProfile -Name (New-UniqueName) -Credential (New-TestCred -User 'SrvUser') -Tier 1 | Out-Null
        $result = Get-CredentialForTier -Tier 1
        $result.Success | Should -BeTrue
        $result.Data | Should -BeOfType [System.Management.Automation.PSCredential]
    }

    It 'Prefers the default profile for a tier' {
        $nameA = New-UniqueName
        $nameB = New-UniqueName
        New-CredentialProfile -Name $nameA -Credential (New-TestCred -User 'NonDefault') -Tier 1 | Out-Null
        New-CredentialProfile -Name $nameB -Credential (New-TestCred -User 'DefaultUser') -Tier 1 -SetAsDefault | Out-Null
        $result = Get-CredentialForTier -Tier 1
        $result.Success | Should -BeTrue
        $result.Data.UserName | Should -Be 'DefaultUser'
    }

    It 'Falls back to first available when no default exists' {
        $name = New-UniqueName
        New-CredentialProfile -Name $name -Credential (New-TestCred -User 'FirstUser') -Tier 2 | Out-Null
        $result = Get-CredentialForTier -Tier 2
        $result.Success | Should -BeTrue
        $result.Data.UserName | Should -Be 'FirstUser'
    }

    It 'Returns Success=$false and an error when no profiles exist for the tier' {
        # Tier 0 has no profiles (cleanup happened in AfterEach)
        $result = Get-CredentialForTier -Tier 0
        $result.Success | Should -BeFalse
        $result.Error | Should -Not -BeNullOrEmpty
    }

    It '-ProfileName overrides tier-based lookup and returns the named profile credential' {
        $nameA = New-UniqueName
        $nameB = New-UniqueName
        New-CredentialProfile -Name $nameA -Credential (New-TestCred -User 'TierDefault') -Tier 1 -SetAsDefault | Out-Null
        New-CredentialProfile -Name $nameB -Credential (New-TestCred -User 'SpecificUser') -Tier 1 | Out-Null
        $result = Get-CredentialForTier -Tier 1 -ProfileName $nameB
        $result.Success | Should -BeTrue
        $result.Data.UserName | Should -Be 'SpecificUser'
    }

    It 'Updates LastUsed on the profile after retrieval' {
        $name = New-UniqueName
        New-CredentialProfile -Name $name -Credential (New-TestCred -User 'TrackUser') -Tier 2 | Out-Null

        # LastUsed should be null before first use
        $before = Get-CredentialProfile -Name $name
        $before.Data.LastUsed | Should -BeNullOrEmpty

        Get-CredentialForTier -Tier 2 | Out-Null

        # LastUsed should now be set
        $after = Get-CredentialProfile -Name $name
        $after.Data.LastUsed | Should -Not -BeNullOrEmpty
    }
}

Describe 'Remove-CredentialProfile' -Tag @('Unit', 'Credentials') {

    BeforeEach {
        Mock Get-AppLockerDataPath { return $script:TempCredPath } -ModuleName 'GA-AppLocker.Credentials'
    }

    AfterEach {
        Get-ChildItem -Path (Join-Path $script:TempCredPath 'Credentials') -Filter '*.json' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    It 'Removes a profile by -Name and returns Success=$true' {
        $name = New-UniqueName
        New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 0 | Out-Null
        $result = Remove-CredentialProfile -Name $name -Force
        $result.Success | Should -BeTrue
    }

    It 'Removes a profile by -Id and returns Success=$true' {
        $name = New-UniqueName
        $created = New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 1
        $result = Remove-CredentialProfile -Id $created.Data.Id -Force
        $result.Success | Should -BeTrue
    }

    It 'JSON file is deleted from disk after removal by name' {
        $name = New-UniqueName
        $created = New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 2
        $profileId = $created.Data.Id
        $credPath = Join-Path $script:TempCredPath 'Credentials'
        $filePath = Join-Path $credPath "$profileId.json"
        $filePath | Should -Exist
        Remove-CredentialProfile -Name $name -Force | Out-Null
        $filePath | Should -Not -Exist
    }

    It 'JSON file is deleted from disk after removal by id' {
        $name = New-UniqueName
        $created = New-CredentialProfile -Name $name -Credential (New-TestCred) -Tier 0
        $profileId = $created.Data.Id
        $credPath = Join-Path $script:TempCredPath 'Credentials'
        $filePath = Join-Path $credPath "$profileId.json"
        $filePath | Should -Exist
        Remove-CredentialProfile -Id $profileId -Force | Out-Null
        $filePath | Should -Not -Exist
    }

    It 'Returns Success=$false and an error for non-existent profile name' {
        $result = Remove-CredentialProfile -Name 'NonExistent_XYZABC_999' -Force
        $result.Success | Should -BeFalse
        $result.Error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-CredentialProfile function existence' -Tag @('Unit', 'Credentials') {
    It 'Test-CredentialProfile is exported from the module' {
        $cmd = Get-Command -Name 'Test-CredentialProfile' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }
}
