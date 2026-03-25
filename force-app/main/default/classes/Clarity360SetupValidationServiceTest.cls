@IsTest
private class Clarity360SetupValidationServiceTest {
    private static void upsertRuntimeConfig(Boolean useNamedCredential, Boolean scheduledScanEnabled, String scheduleFrequency, Decimal coverageThreshold) {
        List<Clarity360SetupConfig__c> configs = [SELECT Id, IsSetupComplete__c, ScopeMode__c, UseNamedCredential__c,
            EnableScheduledScan__c, ScheduleEnabled__c, ScheduleFrequency__c, CoverageThreshold__c
            FROM Clarity360SetupConfig__c];
        if (configs.isEmpty()) {
            configs.add(new Clarity360SetupConfig__c());
        }
        for (Clarity360SetupConfig__c config : configs) {
            config.IsSetupComplete__c = false;
            config.ScopeMode__c = 'CustomOnly';
            config.UseNamedCredential__c = useNamedCredential;
            config.EnableScheduledScan__c = scheduledScanEnabled;
            config.ScheduleEnabled__c = scheduledScanEnabled;
            config.ScheduleFrequency__c = scheduleFrequency;
            config.CoverageThreshold__c = coverageThreshold;
        }
        upsert configs;
        Clarity360Settings.resetCache();
    }

    private static Map<String, Clarity360SetupValidationService.CheckItem> runChecksByKey() {
        Clarity360SetupValidationService.ReadinessResult readiness =
            Clarity360SetupValidationService.runReadinessChecks();

        Map<String, Clarity360SetupValidationService.CheckItem> byKey =
            new Map<String, Clarity360SetupValidationService.CheckItem>();
        for (Clarity360SetupValidationService.CheckItem item : readiness.checks) {
            byKey.put(item.key, item);
        }
        byKey.put('overall', new Clarity360SetupValidationService.CheckItem());
        byKey.get('overall').status = readiness.overallStatus;
        return byKey;
    }

    @IsTest
    static void readinessChecksReflectRuntimeWarningsAndAgentAvailability() {
        upsertRuntimeConfig(true, true, null, null);

        ToolingApiService.ToolingQueryResult namedCredentialProbe = new ToolingApiService.ToolingQueryResult();
        namedCredentialProbe.success = false;
        namedCredentialProbe.errorMessage = 'Named credential probe failed.';
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = true;
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            namedCredentialProbe,
            toolingProbe
        });

        Test.startTest();
        Clarity360SetupValidationService.ReadinessResult readiness =
            Clarity360SetupValidationService.runReadinessChecks();
        Test.stopTest();

        Map<String, Clarity360SetupValidationService.CheckItem> byKey =
            new Map<String, Clarity360SetupValidationService.CheckItem>();
        for (Clarity360SetupValidationService.CheckItem item : readiness.checks) {
            byKey.put(item.key, item);
        }

        System.assertEquals('Blocked', byKey.get('runtimeChoices').status);
        System.assertEquals('Warning', byKey.get('namedCredential').status);
        System.assertEquals('Warning', byKey.get('toolingApi').status);
        System.assertEquals('Ready', byKey.get('agentAssistant').status);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void readinessChecksReturnReadyWhenSessionModePasses() {
        upsertRuntimeConfig(false, false, null, 80);

        ToolingApiService.ToolingQueryResult sessionProbe = new ToolingApiService.ToolingQueryResult();
        sessionProbe.success = true;
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = true;
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        Test.startTest();
        Clarity360SetupValidationService.ReadinessResult readiness =
            Clarity360SetupValidationService.runReadinessChecks();
        Test.stopTest();

        Map<String, Clarity360SetupValidationService.CheckItem> byKey =
            new Map<String, Clarity360SetupValidationService.CheckItem>();
        for (Clarity360SetupValidationService.CheckItem item : readiness.checks) {
            byKey.put(item.key, item);
        }

        System.assertEquals('Ready', byKey.get('runtimeChoices').status);
        System.assertEquals('Ready', byKey.get('namedCredential').status);
        System.assertEquals('Ready', byKey.get('toolingApi').status);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void readinessChecksWarnWhenSessionAndToolingProbesFail() {
        upsertRuntimeConfig(false, false, null, 80);

        ToolingApiService.ToolingQueryResult sessionProbe = new ToolingApiService.ToolingQueryResult();
        sessionProbe.success = false;
        sessionProbe.errorMessage = 'Session unavailable.';
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = false;
        toolingProbe.errorMessage = 'Tooling unavailable.';
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        Test.startTest();
        Clarity360SetupValidationService.ReadinessResult readiness =
            Clarity360SetupValidationService.runReadinessChecks();
        Test.stopTest();

        Map<String, Clarity360SetupValidationService.CheckItem> byKey =
            new Map<String, Clarity360SetupValidationService.CheckItem>();
        for (Clarity360SetupValidationService.CheckItem item : readiness.checks) {
            byKey.put(item.key, item);
        }

        System.assertEquals('Warning', byKey.get('namedCredential').status);
        System.assertEquals('Warning', byKey.get('toolingApi').status);
        System.assertEquals('Blocked', readiness.overallStatus);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void readinessChecksWarnWhenCoverageThresholdUsesDefault() {
        upsertRuntimeConfig(false, false, null, null);

        ToolingApiService.ToolingQueryResult sessionProbe = new ToolingApiService.ToolingQueryResult();
        sessionProbe.success = true;
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = true;
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        Test.startTest();
        Clarity360SetupValidationService.ReadinessResult readiness =
            Clarity360SetupValidationService.runReadinessChecks();
        Test.stopTest();

        Map<String, Clarity360SetupValidationService.CheckItem> byKey =
            new Map<String, Clarity360SetupValidationService.CheckItem>();
        for (Clarity360SetupValidationService.CheckItem item : readiness.checks) {
            byKey.put(item.key, item);
        }

        System.assertEquals('Warning', byKey.get('runtimeChoices').status);
        System.assert(byKey.get('runtimeChoices').message.contains('Coverage threshold is currently using the org default'));
        System.assertEquals('Ready', byKey.get('namedCredential').status);
        System.assertEquals('Ready', byKey.get('toolingApi').status);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void readinessChecksReturnReadyWhenNamedCredentialPreferredModePasses() {
        upsertRuntimeConfig(true, false, null, 80);

        ToolingApiService.ToolingQueryResult namedCredentialProbe = new ToolingApiService.ToolingQueryResult();
        namedCredentialProbe.success = true;
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = true;
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            namedCredentialProbe,
            toolingProbe
        });

        Test.startTest();
        Clarity360SetupValidationService.ReadinessResult readiness =
            Clarity360SetupValidationService.runReadinessChecks();
        Test.stopTest();

        Map<String, Clarity360SetupValidationService.CheckItem> byKey =
            new Map<String, Clarity360SetupValidationService.CheckItem>();
        for (Clarity360SetupValidationService.CheckItem item : readiness.checks) {
            byKey.put(item.key, item);
        }

        System.assertEquals('Ready', byKey.get('runtimeChoices').status);
        System.assertEquals('Warning', byKey.get('namedCredential').status);
        System.assertEquals('Ready', byKey.get('toolingApi').status);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void readinessChecksBlockWhenScheduledScanLacksFrequency() {
        upsertRuntimeConfig(false, true, null, 80);

        ToolingApiService.ToolingQueryResult sessionProbe = new ToolingApiService.ToolingQueryResult();
        sessionProbe.success = true;
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = true;
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        Test.startTest();
        Clarity360SetupValidationService.ReadinessResult readiness =
            Clarity360SetupValidationService.runReadinessChecks();
        Test.stopTest();

        Map<String, Clarity360SetupValidationService.CheckItem> byKey =
            new Map<String, Clarity360SetupValidationService.CheckItem>();
        for (Clarity360SetupValidationService.CheckItem item : readiness.checks) {
            byKey.put(item.key, item);
        }

        System.assertEquals('Blocked', byKey.get('runtimeChoices').status);
        System.assert(byKey.get('runtimeChoices').message.contains('Schedule frequency must be chosen'));

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void readinessChecksCoverBlockedInfrastructureBranches() {
        upsertRuntimeConfig(false, false, null, 80);

        Clarity360Settings.ValidationResult developerValidation = new Clarity360Settings.ValidationResult();
        developerValidation.valid = false;
        developerValidation.errors.add('Developer metadata is invalid.');

        Clarity360Settings.ValidationResult runtimeValidation = new Clarity360Settings.ValidationResult();
        runtimeValidation.valid = false;
        runtimeValidation.errors.add('Clarity360Config.Default metadata record is missing.');

        Clarity360SetupValidationService.TestOverrides overrides = new Clarity360SetupValidationService.TestOverrides();
        overrides.developerValidation = developerValidation;
        overrides.runtimeValidation = runtimeValidation;
        overrides.adminCanAdminister = false;
        overrides.configCanRead = false;
        overrides.configCanCreate = false;
        overrides.configCanUpdate = false;
        overrides.missingReadFields = new List<String>{ 'ScopeMode__c', 'CoverageThreshold__c', 'ExcludedObjects__c', 'UseNamedCredential__c', 'ScheduleFrequency__c', 'ConnectionStatus__c (missing)' };
        overrides.missingEditFields = new List<String>{ 'ScopeMode__c', 'CoverageThreshold__c' };
        overrides.missingOperationalObjects = new List<String>{ 'FieldInventory__c', 'Recommendation__c' };
        overrides.queueableLimit = 0;
        overrides.storageMetricsUnavailable = true;
        overrides.coreComponentsAvailable = false;
        overrides.agentClassesAvailable = false;
        Clarity360SetupValidationService.setTestOverrides(overrides);

        ToolingApiService.ToolingQueryResult sessionProbe = new ToolingApiService.ToolingQueryResult();
        sessionProbe.success = false;
        sessionProbe.errorMessage = 'Session unavailable.';
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = false;
        toolingProbe.errorMessage = 'Tooling unavailable.';
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        Map<String, Clarity360SetupValidationService.CheckItem> byKey = runChecksByKey();

        System.assertEquals('Blocked', byKey.get('developerConfig').status);
        System.assertEquals('Ready', byKey.get('runtimeChoices').status);
        System.assertEquals('Blocked', byKey.get('adminPrivileges').status);
        System.assertEquals('Blocked', byKey.get('configAccess').status);
        System.assertEquals('Blocked', byKey.get('configFieldAccess').status);
        System.assert(byKey.get('configFieldAccess').message.contains('+1 more'));
        System.assertEquals('Blocked', byKey.get('operationalAccess').status);
        System.assertEquals('Blocked', byKey.get('asyncCapacity').status);
        System.assertEquals('Warning', byKey.get('storageHealth').status);
        System.assertEquals('Blocked', byKey.get('coreComponents').status);
        System.assertEquals('Warning', byKey.get('agentAssistant').status);
        System.assertEquals('Blocked', byKey.get('overall').status);

        Clarity360SetupValidationService.clearTestOverrides();
        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void readinessChecksCoverStorageAndAgentRuntimeBranches() {
        upsertRuntimeConfig(false, false, null, 80);

        Clarity360SetupValidationService.TestOverrides overrides = new Clarity360SetupValidationService.TestOverrides();
        overrides.storageUsed = 100;
        overrides.storageLimit = 100;
        overrides.agentClassesAvailable = true;
        overrides.agentRuntimeFailureMessage = 'Agent runtime unavailable';
        Clarity360SetupValidationService.setTestOverrides(overrides);

        ToolingApiService.ToolingQueryResult sessionProbe = new ToolingApiService.ToolingQueryResult();
        sessionProbe.success = true;
        ToolingApiService.ToolingQueryResult toolingProbe = new ToolingApiService.ToolingQueryResult();
        toolingProbe.success = false;
        toolingProbe.errorMessage = 'Tooling timeout.';
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        Map<String, Clarity360SetupValidationService.CheckItem> byKey = runChecksByKey();

        System.assertEquals('Blocked', byKey.get('storageHealth').status);
        System.assert(byKey.get('storageHealth').message.contains('fully consumed'));
        System.assertEquals('Warning', byKey.get('toolingApi').status);
        System.assert(byKey.get('toolingApi').message.contains('Tooling timeout.'));
        System.assertEquals('Warning', byKey.get('agentAssistant').status);
        System.assert(byKey.get('agentAssistant').message.contains('runtime check failed'));

        overrides.storageUsed = 95;
        overrides.storageLimit = 100;
        overrides.agentRuntimeFailureMessage = null;
        Clarity360SetupValidationService.setTestOverrides(overrides);
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        byKey = runChecksByKey();
        System.assertEquals('Warning', byKey.get('storageHealth').status);
        System.assert(byKey.get('storageHealth').message.contains('Data storage is high'));

        overrides.storageUsed = 25;
        overrides.storageLimit = 100;
        Clarity360SetupValidationService.setTestOverrides(overrides);
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            sessionProbe,
            toolingProbe
        });

        byKey = runChecksByKey();
        System.assertEquals('Ready', byKey.get('storageHealth').status);
        System.assert(byKey.get('storageHealth').message.contains('Storage usage is healthy'));

        Clarity360SetupValidationService.clearTestOverrides();
        ToolingApiService.clearTestOverrides();
    }
}
