@IsTest
private class UsageScanBatchTest {
    @IsTest
    static void batchProcessesSignalsAndCompletesJob() {
        Clarity360SetupConfig__c config = new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            ScopeMode__c = 'IncludeStandard',
            IncludeStandardObjects__c = true,
            CoverageThreshold__c = 80
        );
        insert config;
        Clarity360Settings.resetCache();

        insert new Account(Name = 'Coverage Account');
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Name',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Name',
            DataType__c = 'String',
            IsActive__c = true,
            IncludedInScope__c = true,
            LastScannedOn__c = System.now()
        );
        insert inventory;

        MetadataComponentInventoryService.setTestDiscovery(
            new Map<String, MetadataComponentInventoryService.ComponentRecord>()
        );
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Running',
            StartedOn__c = System.now()
        );
        insert job;

        UsageScanBatch batch = new UsageScanBatch(100, 5, job.Id);

        Test.startTest();
        Iterable<String> started = batch.start(null);
        List<String> objects = new List<String>();
        for (String name : started) {
            objects.add(name);
        }
        batch.execute(null, new List<String>{ 'Account' });
        batch.finish(null);
        Test.stopTest();

        System.assert(objects.contains('Account'));
        System.assertEquals(1, [SELECT COUNT() FROM UsageSignal__c WHERE FieldKey__c = 'Account.Name']);

        ScanJob__c refreshed = [
            SELECT Status__c, ProgressPct__c, FinishedOn__c, TotalObjects__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        System.assertEquals('Completed', refreshed.Status__c);
        System.assertEquals(100, Integer.valueOf(refreshed.ProgressPct__c));
        System.assertNotEquals(null, refreshed.FinishedOn__c);
        System.assert(refreshed.TotalObjects__c >= 1);

        MetadataComponentInventoryService.clearTestOverrides();
    }
}
