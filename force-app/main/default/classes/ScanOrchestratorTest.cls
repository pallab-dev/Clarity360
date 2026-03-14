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
        FullScanQueueable.skipUsageBatchInTests = true;
        Test.startTest();
        Id jobId = ScanOrchestrator.runFullScan();
        Test.stopTest();
        FullScanQueueable.skipUsageBatchInTests = false;

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
