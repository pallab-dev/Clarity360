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
}
