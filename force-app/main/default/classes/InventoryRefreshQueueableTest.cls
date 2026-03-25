@IsTest
private class InventoryRefreshQueueableTest {
    @IsTest
    static void buildInventoryScopeSummaryReturnsStandaloneSummaryWithoutJob() {
        InventoryRefreshQueueable queueable = new InventoryRefreshQueueable(
            null,
            true,
            5,
            new List<String>{ 'Account' },
            0,
            0,
            0,
            0
        );

        System.assertEquals(
            'InventoryObjects=2; InventoryFields=7; Inactivated=1',
            queueable.buildInventoryScopeSummary(2, 7, 1)
        );
    }

    @IsTest
    static void buildInventoryScopeSummaryPreservesReportTokensForExistingJob() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Inventory Refresh',
            Status__c = 'Running',
            StartedOn__c = System.now(),
            ScopeSummary__c = 'reportRequested=true; reportMode=Requester; reportRecipient=ops@example.com; requestId=req-123'
        );
        insert job;

        InventoryRefreshQueueable queueable = new InventoryRefreshQueueable(
            job.Id,
            true,
            5,
            new List<String>{ 'Account' },
            0,
            0,
            0,
            0
        );

        String merged = queueable.buildInventoryScopeSummary(3, 11, 2);
        System.assert(merged.contains('InventoryObjects=3'));
        System.assert(merged.contains('InventoryFields=11'));
        System.assert(merged.contains('Inactivated=2'));
        System.assert(merged.contains('reportMode=Requester'));
        System.assert(merged.contains('reportRecipient=ops@example.com'));
        System.assert(merged.contains('requestId=req-123'));
    }

    @IsTest
    static void buildInventoryScopeSummaryFallsBackWhenJobNoLongerExists() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Inventory Refresh',
            Status__c = 'Running',
            StartedOn__c = System.now()
        );
        insert job;
        Id deletedJobId = job.Id;
        delete job;

        InventoryRefreshQueueable queueable = new InventoryRefreshQueueable(
            deletedJobId,
            true,
            5,
            new List<String>{ 'Account' },
            0,
            0,
            0,
            0
        );

        System.assertEquals(
            'InventoryObjects=1; InventoryFields=2; Inactivated=3',
            queueable.buildInventoryScopeSummary(1, 2, 3)
        );
    }

    @IsTest
    static void preserveNonInventoryTokensSkipsBlanksAndOldInventoryValues() {
        String merged = InventoryRefreshQueueable.preserveNonInventoryTokens(
            ' ; InventoryObjects=4; InventoryFields=6; Inactivated=1; reportRequested=true; ; requestId=req-2 ',
            'InventoryObjects=9; InventoryFields=12; Inactivated=0'
        );

        System.assertEquals(
            'InventoryObjects=9; InventoryFields=12; Inactivated=0; reportRequested=true; requestId=req-2',
            merged
        );
    }

    @IsTest
    static void executeMarksInventoryOnlyJobCompletedEvenWhenScopedObjectIsMissing() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Inventory Refresh',
            Status__c = 'Queued',
            StartedOn__c = System.now()
        );
        insert job;

        Test.startTest();
        new InventoryRefreshQueueable(
            job.Id,
            true,
            1,
            new List<String>{ 'DefinitelyMissingObject__c' },
            0,
            0,
            0,
            0
        ).execute(null);
        Test.stopTest();

        ScanJob__c refreshed = [
            SELECT Status__c, ProgressPct__c, ScopeSummary__c, FinishedOn__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        System.assertEquals('Completed', refreshed.Status__c);
        System.assertEquals(100, refreshed.ProgressPct__c);
        System.assert(refreshed.ScopeSummary__c.contains('InventoryObjects=0'));
        System.assertNotEquals(null, refreshed.FinishedOn__c);
    }

    @IsTest
    static void executeLaunchesUsageBatchWhenRequested() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Queued',
            StartedOn__c = System.now()
        );
        insert job;

        Test.startTest();
        new InventoryRefreshQueueable(
            job.Id,
            true,
            1,
            new List<String>{ 'DefinitelyMissingObject__c' },
            0,
            0,
            0,
            0,
            true,
            10,
            2,
            false
        ).execute(null);
        Test.stopTest();

        ScanJob__c refreshed = [
            SELECT Status__c, ScopeSummary__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        System.assert(refreshed.Status__c == 'Running' || refreshed.Status__c == 'Completed');
        System.assert(refreshed.ScopeSummary__c.contains('InventoryObjects=0'));
    }

    @IsTest
    static void updateProgressStoresRunningSummaryAndPercent() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Inventory Refresh',
            Status__c = 'Queued',
            StartedOn__c = System.now(),
            ScopeSummary__c = 'reportRequested=true; requestId=req-9'
        );
        insert job;

        InventoryRefreshQueueable queueable = new InventoryRefreshQueueable(
            job.Id,
            true,
            5,
            new List<String>{ 'Account' },
            0,
            0,
            0,
            0
        );
        queueable.updateProgress(10, 4, 11, 2);

        ScanJob__c refreshed = [
            SELECT Status__c, ProgressPct__c, ScopeSummary__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        System.assertEquals('Running', refreshed.Status__c);
        System.assertEquals(40, refreshed.ProgressPct__c);
        System.assert(refreshed.ScopeSummary__c.contains('InventoryObjects=4'));
        System.assert(refreshed.ScopeSummary__c.contains('requestId=req-9'));
    }

    @IsTest
    static void markFailedStoresFailureDetails() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Inventory Refresh',
            Status__c = 'Running',
            StartedOn__c = System.now()
        );
        insert job;

        InventoryRefreshQueueable queueable = new InventoryRefreshQueueable(
            job.Id,
            true,
            5,
            new List<String>{ 'Account' },
            0,
            0,
            0,
            0
        );
        queueable.markFailed(new IllegalArgumentException('Inventory exploded'));

        ScanJob__c refreshed = [
            SELECT Status__c, FinishedOn__c, ErrorMessage__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        System.assertEquals('Failed', refreshed.Status__c);
        System.assertNotEquals(null, refreshed.FinishedOn__c);
        System.assertEquals('Inventory exploded', refreshed.ErrorMessage__c);
    }

    @IsTest
    static void executeMarksJobCompletedWhenUsageBatchIsSkippedInTests() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Queued',
            StartedOn__c = System.now(),
            ScopeSummary__c = 'reportRequested=true; reportMode=Scheduled'
        );
        insert job;

        Test.startTest();
        new InventoryRefreshQueueable(
            job.Id,
            true,
            1,
            new List<String>{ 'DefinitelyMissingObject__c' },
            0,
            0,
            0,
            0,
            true,
            10,
            2,
            true
        ).execute(null);
        Test.stopTest();

        ScanJob__c refreshed = [
            SELECT Status__c, ProgressPct__c, FinishedOn__c, ScopeSummary__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        System.assertEquals('Completed', refreshed.Status__c);
        System.assertEquals(100, refreshed.ProgressPct__c);
        System.assertNotEquals(null, refreshed.FinishedOn__c);
        System.assert(refreshed.ScopeSummary__c.contains('reportMode=Scheduled'));
        System.assert(refreshed.ScopeSummary__c.contains('InventoryObjects=0'));
    }
}
