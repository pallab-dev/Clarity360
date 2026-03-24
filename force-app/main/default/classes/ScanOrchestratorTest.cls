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
}
