@IsTest
private class FullScanQueueableTest {
    private static void ensureSetupComplete() {
        List<Clarity360SetupConfig__c> rows = [SELECT Id FROM Clarity360SetupConfig__c LIMIT 1];
        if (rows.isEmpty()) {
            insert new Clarity360SetupConfig__c(
                IsSetupComplete__c = true,
                ScopeMode__c = 'CustomOnly',
                CoverageThreshold__c = 80
            );
        } else {
            rows[0].put('IsSetupComplete__c', true);
            rows[0].put('ScopeMode__c', 'CustomOnly');
            rows[0].put('CoverageThreshold__c', 80);
            update rows[0];
        }
        Clarity360Settings.resetCache();
    }

    @IsTest
    static void executeRunsInventoryPhaseInlineInTests() {
        ensureSetupComplete();
        FullScanQueueable.skipUsageBatchInTests = true;
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Queued',
            StartedOn__c = System.now()
        );
        insert job;

        Test.startTest();
        new FullScanQueueable(job.Id, true, 5, 10, 5).execute(null);
        Test.stopTest();

        ScanJob__c refreshed = [
            SELECT Status__c, FinishedOn__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        System.assertEquals('Completed', refreshed.Status__c);
        System.assertNotEquals(null, refreshed.FinishedOn__c);
        FullScanQueueable.skipUsageBatchInTests = false;
    }

    @IsTest
    static void executeHandlesMissingJobGracefully() {
        ScanJob__c deletedJob = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Queued',
            StartedOn__c = System.now()
        );
        insert deletedJob;
        Id missingJobId = deletedJob.Id;
        delete deletedJob;

        Test.startTest();
        new FullScanQueueable(missingJobId, true, 5, 10, 5).execute(null);
        Test.stopTest();

        System.assert(true, 'Missing scan job should be handled without bubbling an exception.');
    }
}
