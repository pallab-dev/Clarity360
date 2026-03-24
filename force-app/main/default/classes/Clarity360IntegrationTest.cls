@IsTest
private class Clarity360IntegrationTest {
    @IsTest
    static void setupWizardStateIsAccessible() {
        Test.startTest();
        Clarity360SetupWizardController.SetupState state = Clarity360SetupWizardController.getSetupState();
        Test.stopTest();

        System.assertNotEquals(null, state, 'Setup state should be returned.');
        System.assertNotEquals(null, state.config, 'Runtime config should be available.');
        System.assertNotEquals(null, state.readiness, 'Readiness result should be available.');
    }

    @IsTest
    static void scheduleSyncHandlesDisabledConfig() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.isSetupComplete = true;
        config.enableScheduledScan = false;
        config.scheduleEnabled = false;
        config.scheduleFrequency = null;
        Clarity360SetupConfigService.save(config);

        Test.startTest();
        Clarity360ScheduleService.syncSchedule();
        Integer scheduledJobs = [
            SELECT COUNT()
            FROM CronTrigger
            WHERE CronJobDetail.Name = :Clarity360ScheduleService.JOB_NAME
        ];
        Test.stopTest();

        System.assertEquals(0, scheduledJobs, 'Disabled schedule config should not leave scheduled jobs behind.');
    }

    @IsTest
    static void recentScanSummaryReturnsLatestJob() {
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c',
            DataType__c = 'Checkbox',
            IsActive__c = true,
            IsCustomField__c = true,
            IncludedInScope__c = true,
            LastScannedOn__c = System.now().addMinutes(-30)
        );
        insert inventory;

        insert new UsageSignal__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            SampleSize__c = 100,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            LastObservedOn__c = System.now().addMinutes(-25),
            EvidenceSummary__c = 'Integration usage signal.'
        );

        insert new Recommendation__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            Action__c = 'Deprecate',
            ConfidenceScore__c = 95,
            RiskScore__c = 92,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now().addMinutes(-20),
            EvidenceSummary__c = 'Integration recommendation record.'
        );

        ScanJob__c latestJob = new ScanJob__c(
            JobType__c = 'Recommendation Rebuild',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-15),
            FinishedOn__c = System.now().addMinutes(-10),
            ScopeSummary__c = 'Integration scan summary.',
            ProgressPct__c = 100
        );
        insert latestJob;
        Test.setCreatedDate(latestJob.Id, System.now().addMinutes(-10));

        Clarity360AgentActions.GetRecentScanSummaryRequest request =
            new Clarity360AgentActions.GetRecentScanSummaryRequest();
        request.lookbackDays = 7;

        Test.startTest();
        List<Clarity360AgentActions.AgentActionResult> results =
            Clarity360AgentActions.getRecentScanSummary(
                new List<Clarity360AgentActions.GetRecentScanSummaryRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One integration summary envelope should be returned.');
        System.assertEquals('Completed', results[0].status, 'Latest integration scan should be completed.');
        System.assertEquals('Recommendation Rebuild', results[0].action, 'Latest integration scan should be surfaced.');
    }

    @IsTest
    static void fullScanCompletesWithSetupConfig() {
        ScanOrchestrator.skipUsageBatchInTests = true;
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.isSetupComplete = true;
        config.scopeMode = 'CustomOnly';
        Clarity360SetupConfigService.save(config);

        Test.startTest();
        Id jobId = ScanOrchestrator.runFullScan();
        Test.stopTest();
        ScanOrchestrator.skipUsageBatchInTests = false;

        ScanJob__c job = [
            SELECT Status__c
            FROM ScanJob__c
            WHERE Id = :jobId
            LIMIT 1
        ];
        System.assert(
            job.Status__c == 'Completed' || job.Status__c == 'Partial',
            'Full scan should finish with a terminal status.'
        );
    }
}
