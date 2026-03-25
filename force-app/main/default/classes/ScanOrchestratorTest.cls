@IsTest
private class ScanOrchestratorTest {
    @TestSetup
    static void setupRuntimeConfig() {
        insert new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            ScopeMode__c = 'CustomOnly',
            CoverageThreshold__c = 80,
            UseNamedCredential__c = false
        );
    }

    @IsTest
    static void runInventoryOnlyCompletesJob() {
        Test.startTest();
        Id jobId = ScanOrchestrator.runInventoryOnly(false, 5);
        Test.stopTest();

        ScanJob__c job = [
            SELECT Id, Status__c, FinishedOn__c
            FROM ScanJob__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals('Completed', job.Status__c);
        System.assertNotEquals(null, job.FinishedOn__c);
    }

    @IsTest
    static void runFullScanCreatesAndFinishesJob() {
        ScanOrchestrator.skipUsageBatchInTests = true;
        Test.startTest();
        Id jobId = ScanOrchestrator.runFullScan();
        Test.stopTest();
        ScanOrchestrator.skipUsageBatchInTests = false;

        ScanJob__c job = [
            SELECT Id, Status__c
            FROM ScanJob__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assert(
            job.Status__c == 'Completed' || job.Status__c == 'Partial',
            'Job should finish as completed or partial depending on object accessibility in test context.'
        );
    }

    @IsTest
    static void inventoryScopeSummaryPreservesReportTokens() {
        String merged = InventoryRefreshQueueable.preserveNonInventoryTokens(
            'customObjectsOnly=true; reportRequested=true; reportMode=Requester; reportRecipient=ops@example.com; requestId=123',
            'InventoryObjects=4; InventoryFields=30; Inactivated=2'
        );

        System.assert(merged.contains('InventoryObjects=4'));
        System.assert(merged.contains('reportRequested=true'));
        System.assert(merged.contains('reportMode=Requester'));
        System.assert(merged.contains('reportRecipient=ops@example.com'));
        System.assert(merged.contains('requestId=123'));
    }

    @IsTest
    static void runFullScanV2StoresExplicitRecipient() {
        ScanOrchestrator.skipUsageBatchInTests = true;
        Test.startTest();
        ScanOrchestrator.StartResult result = ScanOrchestrator.runFullScanV2('req-report', true, 'ops@example.com');
        Test.stopTest();
        ScanOrchestrator.skipUsageBatchInTests = false;

        ScanJob__c job = [
            SELECT ScopeSummary__c, ReportMode__c
            FROM ScanJob__c
            WHERE Id = :result.jobId
            LIMIT 1
        ];

        System.assertEquals('Requester', job.ReportMode__c);
        System.assert(job.ScopeSummary__c.contains('reportRecipient=ops@example.com'));
    }

    @IsTest
    static void runInventoryOnlyV2ReusesExistingQueuedJob() {
        Test.startTest();
        ScanOrchestrator.StartResult first = ScanOrchestrator.runInventoryOnlyV2(false, 5, 'req-a');
        ScanOrchestrator.StartResult second = ScanOrchestrator.runInventoryOnlyV2(false, 5, 'req-b');
        Test.stopTest();

        System.assertNotEquals(null, first.jobId, 'First run should create or reuse a job id.');
        System.assertEquals(first.jobId, second.jobId, 'Second run should reuse existing queued/running inventory job.');
        System.assertEquals(true, second.reusedJob, 'Second run should indicate reuse.');
    }

    @IsTest
    static void runScheduledFullScanStoresScheduledReportModeAndSanitizesRecipient() {
        Clarity360SetupConfig__c config = [
            SELECT Id, EnableScheduledReports__c, ScheduledReportRecipient__c
            FROM Clarity360SetupConfig__c
            LIMIT 1
        ];
        config.EnableScheduledReports__c = true;
        config.ScheduledReportRecipient__c = 'ops@example.com';
        update config;
        Clarity360Settings.resetCache();

        ScanOrchestrator.skipUsageBatchInTests = true;
        Test.startTest();
        ScanOrchestrator.StartResult result = ScanOrchestrator.runScheduledFullScan();
        Test.stopTest();
        ScanOrchestrator.skipUsageBatchInTests = false;

        ScanJob__c job = [
            SELECT ReportMode__c, ScopeSummary__c
            FROM ScanJob__c
            WHERE Id = :result.jobId
            LIMIT 1
        ];

        System.assertEquals('Scheduled', job.ReportMode__c);
        System.assert(job.ScopeSummary__c.contains('reportRequested=true'));
        System.assert(job.ScopeSummary__c.contains('reportMode=Scheduled'));
        System.assert(job.ScopeSummary__c.contains('reportRecipient=ops@example.com'));
    }

    @IsTest
    static void runUsageScanOnlyV2CreatesRunningJobWithRequestToken() {
        Test.startTest();
        ScanOrchestrator.StartResult result = ScanOrchestrator.runUsageScanOnlyV2(25, 3, 'usage-req-1');
        Test.stopTest();

        System.assertEquals(false, result.reusedJob);
        System.assertEquals('Running', result.status);

        ScanJob__c job = [
            SELECT ScopeSummary__c, Status__c
            FROM ScanJob__c
            WHERE Id = :result.jobId
            LIMIT 1
        ];
        System.assert(job.Status__c == 'Running' || job.Status__c == 'Completed');
        System.assert(job.ScopeSummary__c.contains('sampleLimit=25'));
        System.assert(job.ScopeSummary__c.contains('maxObjects=3'));
        System.assert(job.ScopeSummary__c.contains('requestId=usage-req-1'));
    }

    @IsTest
    static void sanitizeReportRecipientTrimsSeparatorsAndLength() {
        System.assertEquals(null, ScanOrchestrator.sanitizeReportRecipient('   '));
        System.assertEquals('ops@example.comteam@example.com', ScanOrchestrator.sanitizeReportRecipient(' ops@example.com;\r\nteam@example.com '));
        System.assertEquals(
            80,
            ScanOrchestrator.sanitizeReportRecipient('abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz').length()
        );
    }

    @IsTest
    static void runFullScanWithoutReportLeavesReportTokensOut() {
        ScanOrchestrator.skipUsageBatchInTests = true;
        Test.startTest();
        ScanOrchestrator.StartResult result = ScanOrchestrator.runFullScanV2('no-report', false, 'ops@example.com');
        Test.stopTest();
        ScanOrchestrator.skipUsageBatchInTests = false;

        ScanJob__c job = [
            SELECT ScopeSummary__c, ReportMode__c
            FROM ScanJob__c
            WHERE Id = :result.jobId
            LIMIT 1
        ];

        System.assertEquals(null, job.ReportMode__c);
        System.assertEquals(false, job.ScopeSummary__c.contains('reportRequested=true'));
        System.assert(job.ScopeSummary__c.contains('requestId=no-report'));
    }

    @IsTest
    static void runFullScanV2ReusesExistingQueuedJobForSameRequest() {
        ScanOrchestrator.skipUsageBatchInTests = true;
        Test.startTest();
        ScanOrchestrator.StartResult first = ScanOrchestrator.runFullScanV2('reuse-request', true);
        ScanOrchestrator.StartResult second = ScanOrchestrator.runFullScanV2('reuse-request', true);
        Test.stopTest();
        ScanOrchestrator.skipUsageBatchInTests = false;

        System.assertEquals(first.jobId, second.jobId);
        System.assertEquals(true, second.reusedJob);
    }

    @IsTest
    static void wrapperMethodsReturnJobIdentifiers() {
        ScanOrchestrator.skipUsageBatchInTests = true;
        Test.startTest();
        Id inventoryJobId = ScanOrchestrator.runInventoryOnly(true, 2);
        Id usageJobId = ScanOrchestrator.runUsageScanOnly(5, 1);
        Id fullJobId = ScanOrchestrator.runFullScan();
        Test.stopTest();
        ScanOrchestrator.skipUsageBatchInTests = false;

        System.assertNotEquals(null, inventoryJobId);
        System.assertNotEquals(null, usageJobId);
        System.assertNotEquals(null, fullJobId);
    }

    @IsTest
    static void helperMethodsPreserveTokensAndCleanupDerivedData() {
        insert new UsageSignal__c(
            FieldKey__c = 'Account.Legacy__c',
            SampleSize__c = 1,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            LastObservedOn__c = System.now()
        );
        insert new Recommendation__c(
            FieldKey__c = 'Account.Legacy__c',
            Action__c = 'Investigate Dependencies',
            ConfidenceScore__c = 50,
            RiskScore__c = 50,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now()
        );
        insert new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now()
        );

        System.assertEquals('', ScanOrchestrator.requestToken(null));
        System.assertEquals('; requestId=req-7', ScanOrchestrator.requestToken('req-7'));
        System.assertEquals('', ScanOrchestrator.reportToken(null, 'ops@example.com'));
        System.assert(
            ScanOrchestrator.reportToken('Requester', 'ops@example.com;\nteam@example.com')
                .contains('reportRecipient=ops@example.comteam@example.com')
        );

        ScanOrchestrator.deleteChunk('Invalid-Object', 10);
        ScanOrchestrator.deleteChunk('UsageSignal__c', 100);
        ScanOrchestrator.deleteChunk('Recommendation__c', 100);
        ScanOrchestrator.deleteOldScanJobs(100);

        System.assertEquals(0, [SELECT COUNT() FROM UsageSignal__c WHERE FieldKey__c = 'Account.Legacy__c']);
        System.assertEquals(0, [SELECT COUNT() FROM Recommendation__c WHERE FieldKey__c = 'Account.Legacy__c']);
        System.assertEquals(0, [SELECT COUNT() FROM ScanJob__c WHERE JobType__c = 'Usage Scan']);
    }
}
