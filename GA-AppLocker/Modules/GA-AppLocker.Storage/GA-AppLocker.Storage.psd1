@{
    RootModule = 'GA-AppLocker.Storage.psm1'
    ModuleVersion = '2.0.0'
    GUID = 'a8b7c6d5-e4f3-4a2b-9c1d-0e8f7a6b5c4d'
    Author = 'GA-AppLocker Team'
    Description = 'JSON-based storage layer for GA-AppLocker rules and data'
    PowerShellVersion = '5.1'
    
    FunctionsToExport = @(
        # Rule Storage Operations (JSON-based)
        'Get-RuleStoragePath',
        'Get-RuleById',
        'Get-AllRules',
        'Add-Rule',
        'Update-Rule',
        'Remove-Rule',
        'Find-RuleByHash',
        'Find-RuleByPublisher',
        
        # Bulk Operations (Batch Rule Generation)
        'Get-RuleCounts',
        'Save-RulesBulk',
        'Add-RulesToIndex',
        'Get-ExistingRuleIndex',
        'Remove-RulesBulk',
        'Remove-RulesFromIndex',
        'Get-BatchPreview',
        'Update-RuleStatusInIndex',
        
        # Index Management
        'Reset-RulesIndexCache',
        'Rebuild-RulesIndex',
        
        # Index Watcher Functions
        'Start-RuleIndexWatcher',
        'Stop-RuleIndexWatcher',
        'Get-RuleIndexWatcherStatus',
        'Set-RuleIndexWatcherDebounce',
        'Invoke-RuleIndexRebuild',
        
        # Repository Pattern Functions
        'Get-RuleFromRepository',
        'Save-RuleToRepository',
        'Remove-RuleFromRepository',
        'Find-RulesInRepository',
        'Get-RuleCountsFromRepository',
        'Invoke-RuleBatchOperation',
        'Test-RuleExistsInRepository'
    )
    
    PrivateData = @{
        PSData = @{
            Tags = @('AppLocker', 'JSON', 'Storage')
        }
    }
}
