@IsTest
private class InventoryServiceTest {
    @TestSetup
    static void setupConfig() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.excludedObjects = null;
        config.excludedNamespaces = null;
        Clarity360SetupConfigService.save(config);
    }

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
        List<String> scoped = new List<String>{ 'FieldInventory__c' };
        InventoryService.RefreshChunkResult chunkOne = InventoryService.refreshInventoryChunkForScopedObjects(scoped, true, 0, 1);
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

    @IsTest
    static void runtimeObjectAndNamespaceExclusionsAreApplied() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.excludedObjects = 'Account';
        config.excludedNamespaces = 'ns1';
        Clarity360SetupConfigService.save(config);

        System.assertEquals(true, InventoryService.isObjectExcludedByRuntimeConfig('Account'));
        System.assertEquals(true, InventoryService.isObjectExcludedByRuntimeConfig('ns1__ManagedObject__c'));
        System.assertEquals(false, InventoryService.isObjectExcludedByRuntimeConfig('Contact'));
        System.assertEquals(true, InventoryService.isObjectExcludedByRuntimeConfig(null));
    }

    @IsTest
    static void recommendationScopeAndMetadataExclusionHelpersBehaveAsExpected() {
        System.assertEquals(true, InventoryService.isObjectInRecommendationScope('FieldInventory__c'));
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope('DefinitelyMissingObject__c', false));
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope('ApexClass', false));
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope(null));

        System.assertEquals(true, InventoryService.isExcludedMetadataObject('ApexClass'));
        System.assertEquals(true, InventoryService.isExcludedMetadataObject('ApexWidget'));
        System.assertEquals(false, InventoryService.isExcludedMetadataObject('Account'));
        System.assertEquals(true, InventoryService.isExcludedMetadataObject(null));
    }

    @IsTest
    static void chunkHelperHandlesOutOfRangeCursorAndScopedSelection() {
        InventoryService.RefreshChunkResult emptyChunk =
            InventoryService.refreshInventoryChunkForScopedObjects(new List<String>{ 'FieldInventory__c' }, true, 5, 1);
        System.assertEquals(0, emptyChunk.scannedObjectCount, 'Out-of-range cursor should not scan any objects.');
        System.assertEquals(false, emptyChunk.hasMore, 'Out-of-range cursor should not report more work.');

        List<String> scopedStandard = InventoryService.getScopedObjectNames(false, 5);
        System.assert(scopedStandard.size() > 0, 'Scoped object list should contain at least one object.');
        System.assertEquals(true, scopedStandard[0].equalsIgnoreCase('Account'), 'Account should be prioritized when standard objects are allowed.');
    }
}
