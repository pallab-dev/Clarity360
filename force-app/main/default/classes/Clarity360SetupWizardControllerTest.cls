@IsTest
private class Clarity360SetupWizardControllerTest {
    @IsTest
    static void getSetupStateReturnsDefaults() {
        Test.startTest();
        Clarity360SetupWizardController.SetupState state = Clarity360SetupWizardController.getSetupState();
        Test.stopTest();

        System.assertNotEquals(null, state, 'State should be returned.');
        System.assertNotEquals(null, state.config, 'Default config should be provided.');
        System.assertEquals(false, state.isSetupComplete, 'Setup should be incomplete by default.');
        System.assertNotEquals(null, state.readiness, 'Readiness details should be returned.');
        System.assert(state.readiness.checks.size() > 0, 'At least one readiness check should exist.');
        Set<String> readinessKeys = new Set<String>();
        for (Clarity360SetupValidationService.CheckItem item : state.readiness.checks) {
            readinessKeys.add(item.key);
        }
        System.assert(readinessKeys.contains('storageHealth'), 'Storage check should be present.');
        System.assert(readinessKeys.contains('configFieldAccess'), 'Field-level access check should be present.');
        System.assert(readinessKeys.contains('namedCredential'), 'Named credential check should be present.');
        System.assert(readinessKeys.contains('toolingApi'), 'Tooling API check should be present.');
        System.assert(readinessKeys.contains('agentAssistant'), 'Agent assistant readiness check should be present.');
    }

    @IsTest
    static void saveRuntimeConfigMarksComplete() {
        Clarity360SetupConfigService.SetupConfigDTO input = new Clarity360SetupConfigService.SetupConfigDTO();
        input.scopeMode = 'CustomOnly';
        input.coverageThreshold = 80;
        input.includeStandardObjects = false;
        input.useNamedCredential = false;
        input.enableUsageSampling = false;
        input.enableDependencyAnalysis = false;
        input.enableLayoutScan = false;
        input.enableGlobalRecommendations = false;
        input.enableDeletionGuardrails = false;

        Test.startTest();
        Clarity360SetupWizardController.SaveResult saveResult =
            Clarity360SetupWizardController.saveRuntimeConfig(input, true);
        Test.stopTest();

        System.assertEquals(true, saveResult.success, 'Save should succeed.');
        System.assertEquals(true, saveResult.config.isSetupComplete, 'Save should mark setup complete.');
        System.assertNotEquals(null, saveResult.config.lastSetupRunOn, 'Completion timestamp should be set.');

        Clarity360SetupConfig__c persisted = [
            SELECT IsSetupComplete__c,
                CoverageThreshold__c,
                UseNamedCredential__c,
                EnableUsageSampling__c,
                EnableDependencyAnalysis__c,
                EnableLayoutScan__c,
                EnableGlobalRecommendations__c,
                EnableDeletionGuardrails__c
            FROM Clarity360SetupConfig__c
            LIMIT 1
        ];
        System.assertEquals(true, persisted.IsSetupComplete__c);
        System.assertEquals(80, persisted.CoverageThreshold__c);
        System.assertEquals(false, persisted.UseNamedCredential__c);
        System.assertEquals(false, persisted.EnableUsageSampling__c);
        System.assertEquals(false, persisted.EnableDependencyAnalysis__c);
        System.assertEquals(false, persisted.EnableLayoutScan__c);
        System.assertEquals(false, persisted.EnableGlobalRecommendations__c);
        System.assertEquals(false, persisted.EnableDeletionGuardrails__c);
    }

    @IsTest
    static void saveSetupChoicesPersistsBooleanScopeAndCoverage() {
        Test.startTest();
        Clarity360SetupWizardController.SaveResult saveResult =
            Clarity360SetupWizardController.saveSetupChoices(
                true,
                82,
                'Task',
                'pkg',
                false,
                false,
                null,
                false
            );
        Test.stopTest();

        System.assertEquals(true, saveResult.success, 'Save should succeed.');
        System.assertEquals(true, saveResult.config.includeStandardObjects, 'Boolean scope choice should persist.');
        System.assertEquals('IncludeStandard', saveResult.config.scopeMode, 'Scope mode should be derived from the boolean toggle.');
        System.assertEquals(82, saveResult.config.coverageThreshold, 'Coverage threshold should persist.');

        Clarity360SetupConfig__c persisted = [
            SELECT IncludeStandardObjects__c, ScopeMode__c, CoverageThreshold__c, ExcludedObjects__c, ExcludedNamespaces__c
            FROM Clarity360SetupConfig__c
            LIMIT 1
        ];
        System.assertEquals(true, persisted.IncludeStandardObjects__c);
        System.assertEquals('IncludeStandard', persisted.ScopeMode__c);
        System.assertEquals(82, persisted.CoverageThreshold__c);
        System.assertEquals('Task', persisted.ExcludedObjects__c);
        System.assertEquals('pkg', persisted.ExcludedNamespaces__c);
    }

    @IsTest
    static void saveRuntimeConfigRejectsInvalidCoverageThreshold() {
        Clarity360SetupConfigService.SetupConfigDTO input = new Clarity360SetupConfigService.SetupConfigDTO();
        input.scopeMode = 'CustomOnly';
        input.coverageThreshold = 120;

        Test.startTest();
        Boolean didThrow = false;
        try {
            Clarity360SetupWizardController.saveRuntimeConfig(input, false);
            System.assert(false, 'Expected save to fail validation.');
        } catch (AuraHandledException ex) {
            didThrow = true;
            System.assertNotEquals(null, ex, 'Validation should surface an AuraHandledException.');
        }
        Test.stopTest();
        System.assertEquals(true, didThrow, 'Invalid coverage should fail validation.');
    }

    @IsTest
    static void saveRuntimeConfigAppliesDefaultsWhenCompleting() {
        Clarity360SetupConfigService.SetupConfigDTO input = new Clarity360SetupConfigService.SetupConfigDTO();
        input.useNamedCredential = false;

        Test.startTest();
        Clarity360SetupWizardController.SaveResult saveResult =
            Clarity360SetupWizardController.saveRuntimeConfig(input, true);
        Test.stopTest();

        System.assertEquals(true, saveResult.success, 'Save should succeed.');
        System.assertEquals(true, saveResult.config.isSetupComplete, 'Setup should be marked complete.');
        System.assertEquals(null, saveResult.config.scopeMode, 'Unset scope mode should remain unset in saved config.');
        System.assertEquals(null, saveResult.config.coverageThreshold, 'Unset coverage should remain unset in saved config.');
    }

    @IsTest
    static void saveRuntimeConfigPersistsIncludeStandardSelection() {
        Clarity360SetupConfigService.SetupConfigDTO input = new Clarity360SetupConfigService.SetupConfigDTO();
        input.includeStandardObjects = true;
        input.scopeMode = null;

        Test.startTest();
        Clarity360SetupWizardController.SaveResult saveResult =
            Clarity360SetupWizardController.saveRuntimeConfig(input, false);
        Test.stopTest();

        System.assertEquals('IncludeStandard', saveResult.config.scopeMode, 'Include-standard choice should persist as scope mode.');
        System.assertEquals(true, saveResult.config.includeStandardObjects, 'Include-standard flag should persist.');
    }

    @IsTest
    static void saveRuntimeConfigScopeModeWinsOverStaleBooleanFlag() {
        Clarity360SetupConfigService.SetupConfigDTO input = new Clarity360SetupConfigService.SetupConfigDTO();
        input.scopeMode = 'CustomOnly';
        input.includeStandardObjects = true;

        Test.startTest();
        Clarity360SetupWizardController.SaveResult saveResult =
            Clarity360SetupWizardController.saveRuntimeConfig(input, false);
        Test.stopTest();

        System.assertEquals('CustomOnly', saveResult.config.scopeMode, 'Scope mode should remain the authoritative runtime choice.');
        System.assertEquals(false, saveResult.config.includeStandardObjects, 'Legacy include-standard flag should be derived from scope mode.');
    }

    @IsTest
    static void getSetupStatePrefersLatestConfigRecord() {
        insert new Clarity360SetupConfig__c(
            ScopeMode__c = 'CustomOnly',
            IncludeStandardObjects__c = false
        );
        insert new Clarity360SetupConfig__c(
            ScopeMode__c = 'IncludeStandard',
            IncludeStandardObjects__c = true
        );

        Test.startTest();
        Clarity360SetupWizardController.SetupState state = Clarity360SetupWizardController.getSetupState();
        Test.stopTest();

        System.assertEquals('IncludeStandard', state.config.scopeMode, 'Wizard should load the latest setup record when duplicates exist.');
        System.assertEquals(true, state.config.includeStandardObjects, 'Derived include-standard flag should match the loaded scope.');
    }

    @IsTest
    static void getSetupStateDoesNotWarnWhenUserExplicitlyChoosesVisibleFields() {
        Clarity360SetupConfigService.SetupConfigDTO input = new Clarity360SetupConfigService.SetupConfigDTO();
        input.scopeMode = 'CustomOnly';
        input.coverageThreshold = 75;

        Clarity360SetupConfigService.save(input);

        Test.startTest();
        Clarity360SetupWizardController.SetupState state = Clarity360SetupWizardController.getSetupState();
        Test.stopTest();

        Clarity360SetupValidationService.CheckItem runtimeChoices;
        for (Clarity360SetupValidationService.CheckItem item : state.readiness.checks) {
            if (item.key == 'runtimeChoices') {
                runtimeChoices = item;
                break;
            }
        }

        System.assertNotEquals(null, runtimeChoices, 'Runtime choices check should be present.');
        System.assertEquals('Ready', runtimeChoices.status, 'Explicitly chosen visible fields should not warn.');
    }

    @IsTest
    static void getSetupStateWarnsOnlyForUnconfiguredVisibleFields() {
        Clarity360SetupConfigService.SetupConfigDTO input = new Clarity360SetupConfigService.SetupConfigDTO();
        input.useNamedCredential = false;

        Clarity360SetupConfigService.save(input);

        Test.startTest();
        Clarity360SetupWizardController.SetupState state = Clarity360SetupWizardController.getSetupState();
        Test.stopTest();

        Clarity360SetupValidationService.CheckItem runtimeChoices;
        for (Clarity360SetupValidationService.CheckItem item : state.readiness.checks) {
            if (item.key == 'runtimeChoices') {
                runtimeChoices = item;
                break;
            }
        }

        System.assertNotEquals(null, runtimeChoices, 'Runtime choices check should be present.');
        System.assertEquals('Warning', runtimeChoices.status, 'Only unconfigured visible fields should warn.');
        System.assert(runtimeChoices.message.contains('Coverage threshold is currently using the org default'));
    }

    @IsTest
    static void runInitialRunStartsInventoryJob() {
        Test.startTest();
        Clarity360SetupOrchestratorService.InitialRunResult result =
            Clarity360SetupWizardController.runInitialRun(false, 'setup-req-1');
        Test.stopTest();

        System.assertEquals(true, result.success, 'Initial run should start successfully.');
        System.assertNotEquals(null, result.inventoryStatus, 'Inventory status should be set.');
    }

    @IsTest
    static void runConnectionTestReturnsPassedWithMock() {
        ToolingApiService.ToolingQueryResult queryResult = new ToolingApiService.ToolingQueryResult();
        queryResult.success = true;
        queryResult.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '00D000000000001' }
        };
        ToolingApiService.setTestQueryResult(queryResult);

        Test.startTest();
        Clarity360SetupConnectionService.ConnectionTestResult result =
            Clarity360SetupWizardController.runConnectionTest(true);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Connection test should pass with mocked tooling response.');
        System.assertEquals('Passed', result.status);
        ToolingApiService.clearTestOverrides();
    }
}
