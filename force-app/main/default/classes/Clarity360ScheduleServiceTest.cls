@IsTest
private class Clarity360ScheduleServiceTest {
    private class NullSetupConfigLoader extends ScanOrchestratorSchedulable.SetupConfigLoader {
        public override Clarity360SetupConfigService.SetupConfigDTO load() {
            return null;
        }
    }

    private class ThrowingSetupConfigLoader extends ScanOrchestratorSchedulable.SetupConfigLoader {
        public override Clarity360SetupConfigService.SetupConfigDTO load() {
            throw new AuraHandledException('Simulated config failure');
        }
    }

    @TestSetup
    static void resetSchedulableDefaults() {
        ScanOrchestratorSchedulable.skipFullScanInTests = false;
        ScanOrchestratorSchedulable.setupConfigLoader = new ScanOrchestratorSchedulable.SetupConfigLoader();
        ScanOrchestratorSchedulable.fullScanRunner = new ScanOrchestratorSchedulable.FullScanRunner();
        FullScanQueueable.skipUsageBatchInTests = false;
    }

    @IsTest
    static void syncScheduleCreatesScheduledJob() {
        ScanOrchestratorSchedulable.skipFullScanInTests = true;
        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        input.isSetupComplete = true;
        input.enableScheduledScan = true;
        input.scheduleEnabled = true;
        input.scheduleFrequency = 'Weekly';
        Clarity360SetupConfigService.save(input);

        Test.startTest();
        Clarity360ScheduleService.syncSchedule();
        List<CronTrigger> scheduled = [
            SELECT Id, CronJobDetail.Name, CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = :Clarity360ScheduleService.JOB_NAME
        ];
        System.assertEquals(1, scheduled.size());
        System.assertEquals('0 0 2 ? * SUN', scheduled[0].CronExpression);
        Test.stopTest();
        ScanOrchestratorSchedulable.skipFullScanInTests = false;
    }

    @IsTest
    static void syncScheduleRemovesScheduledJob() {
        ScanOrchestratorSchedulable.skipFullScanInTests = true;
        System.schedule(
            Clarity360ScheduleService.JOB_NAME,
            Clarity360ScheduleService.cronForFrequency('Weekly'),
            new ScanOrchestratorSchedulable()
        );

        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        input.isSetupComplete = true;
        input.enableScheduledScan = false;
        input.scheduleEnabled = false;
        input.scheduleFrequency = null;
        Clarity360SetupConfigService.save(input);

        Clarity360ScheduleService.syncSchedule();
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :Clarity360ScheduleService.JOB_NAME],
            'Disabling scheduled scans should abort the existing scheduled job.'
        );
        ScanOrchestratorSchedulable.skipFullScanInTests = false;
    }

    @IsTest
    static void schedulableSkipsRunWhenTestBypassEnabled() {
        delete [SELECT Id FROM ScanJob__c];
        ScanOrchestratorSchedulable.skipFullScanInTests = true;

        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        input.isSetupComplete = true;
        input.enableScheduledScan = true;
        input.scheduleFrequency = 'Weekly';
        Clarity360SetupConfigService.save(input);

        Test.startTest();
        new ScanOrchestratorSchedulable().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM ScanJob__c],
            'Skip flag should prevent scheduled full scan execution in tests.'
        );
        ScanOrchestratorSchedulable.skipFullScanInTests = false;
    }

    @IsTest
    static void schedulableRunsFullScanWhenConfigEnabled() {
        delete [SELECT Id FROM ScanJob__c];
        ScanOrchestratorSchedulable.skipFullScanInTests = false;
        FullScanQueueable.skipUsageBatchInTests = true;

        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        input.isSetupComplete = true;
        input.enableScheduledScan = true;
        input.scheduleFrequency = 'Weekly';
        Clarity360SetupConfigService.save(input);

        Test.startTest();
        new ScanOrchestratorSchedulable().execute(null);
        Test.stopTest();

        Integer jobCount = [SELECT COUNT() FROM ScanJob__c];
        System.assert(jobCount > 0, 'Enabled scheduled scan should enqueue a scan job.');
        FullScanQueueable.skipUsageBatchInTests = false;
    }

    @IsTest
    static void schedulableDoesNothingWhenConfigDisabled() {
        delete [SELECT Id FROM ScanJob__c];
        ScanOrchestratorSchedulable.skipFullScanInTests = false;

        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        input.isSetupComplete = true;
        input.enableScheduledScan = false;
        Clarity360SetupConfigService.save(input);

        Test.startTest();
        new ScanOrchestratorSchedulable().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM ScanJob__c],
            'Disabled scheduled scan config should not create a scan job.'
        );
    }

    @IsTest
    static void schedulableDoesNothingWhenConfigLoaderReturnsNull() {
        delete [SELECT Id FROM ScanJob__c];
        ScanOrchestratorSchedulable.setupConfigLoader = new NullSetupConfigLoader();

        Test.startTest();
        new ScanOrchestratorSchedulable().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM ScanJob__c],
            'Null setup config should safely skip scheduled execution.'
        );
    }

    @IsTest
    static void schedulableSwallowsConfigLoadExceptions() {
        delete [SELECT Id FROM ScanJob__c];
        ScanOrchestratorSchedulable.setupConfigLoader = new ThrowingSetupConfigLoader();

        Test.startTest();
        new ScanOrchestratorSchedulable().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM ScanJob__c],
            'Config load exceptions should be swallowed without creating scan jobs.'
        );
    }

    @IsTest
    static void defaultSetupConfigLoaderLoadsPersistedConfig() {
        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        input.isSetupComplete = true;
        input.enableScheduledScan = true;
        input.scheduleFrequency = 'Weekly';
        Clarity360SetupConfigService.save(input);

        Clarity360SetupConfigService.SetupConfigDTO loaded =
            new ScanOrchestratorSchedulable.SetupConfigLoader().load();

        System.assertEquals(true, loaded.isSetupComplete, 'Default loader should delegate to setup config service.');
        System.assertEquals(true, loaded.enableScheduledScan, 'Default loader should return scheduled scan flag.');
        System.assertEquals('Weekly', loaded.scheduleFrequency, 'Default loader should return persisted schedule frequency.');
    }

    @IsTest
    static void defaultFullScanRunnerDispatchesFullScan() {
        delete [SELECT Id FROM ScanJob__c];
        FullScanQueueable.skipUsageBatchInTests = true;

        Test.startTest();
        new ScanOrchestratorSchedulable.FullScanRunner().run();
        Test.stopTest();

        Integer jobCount = [SELECT COUNT() FROM ScanJob__c WHERE JobType__c = 'Full Scan'];
        System.assert(jobCount > 0, 'Default full scan runner should dispatch a full scan job.');
        FullScanQueueable.skipUsageBatchInTests = false;
    }
}
