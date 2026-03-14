@IsTest
private class InventoryServiceTest {
    @IsTest
    static void refreshInventoryCreatesRecords() {
        Test.startTest();
        InventoryService.RefreshResult result = InventoryService.refreshInventory(false, 5);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should be returned.');
        System.assert(result.scannedObjectCount > 0, 'At least one object should be scanned.');

        Integer inventoryCount = [SELECT COUNT() FROM FieldInventory__c];
        System.assert(inventoryCount > 0, 'Inventory should have records after refresh.');

        Integer metadataNoiseCount = [
            SELECT COUNT()
            FROM FieldInventory__c
            WHERE ObjectApiName__c IN ('ApexClass', 'ApexTrigger')
            OR ObjectApiName__c LIKE 'Apex%'
        ];
        System.assertEquals(0, metadataNoiseCount, 'Metadata objects should not remain in inventory scope.');
    }

    @IsTest
    static void refreshInventoryChunkAdvancesCursor() {
        List<String> scoped = InventoryService.getScopedObjectNames(false, 6);
        System.assert(scoped.size() > 0, 'Expected scoped objects in test context.');

        InventoryService.RefreshChunkResult chunkOne = InventoryService.refreshInventoryChunkForScopedObjects(scoped, false, 0, 1);
        System.assertEquals(1, chunkOne.scannedObjectCount, 'Chunk should process exactly one object.');
        System.assertEquals(1, chunkOne.nextIndex, 'Cursor should move forward by chunk size.');
        System.assert(chunkOne.totalObjects >= 1, 'Total objects should be populated.');
    }

    @IsTest
    static void cleanupExcludedInventoryMarksInventoryInactiveAndRemovesDerivedRows() {
        insert new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c'
        );
        insert new UsageSignal__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            SampleSize__c = 10,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            LastObservedOn__c = System.now(),
            EvidenceSummary__c = 'HasData=false'
        );
        insert new Recommendation__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            Status__c = 'Open'
        );

        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.excludedObjects = 'Account';
        Clarity360SetupConfigService.save(config);

        Test.startTest();
        InventoryService.cleanupExcludedInventory(new List<String>());
        Test.stopTest();

        FieldInventory__c retained = [
            SELECT IsActive__c
            FROM FieldInventory__c
            WHERE FieldKey__c = 'Account.Legacy_Flag__c'
            LIMIT 1
        ];
        System.assertEquals(false, retained.IsActive__c, 'Excluded inventory should be marked inactive.');
        System.assertEquals(0, [SELECT COUNT() FROM UsageSignal__c WHERE FieldKey__c = 'Account.Legacy_Flag__c'], 'Usage signals for excluded inventory should be removed.');
        System.assertEquals(0, [SELECT COUNT() FROM Recommendation__c WHERE FieldKey__c = 'Account.Legacy_Flag__c'], 'Recommendations for excluded inventory should be removed.');
    }
}
