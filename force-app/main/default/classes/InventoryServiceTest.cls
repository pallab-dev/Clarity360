@IsTest
private class InventoryServiceTest {
    @TestSetup
    static void setupConfig() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.excludedObjects = null;
        config.excludedNamespaces = null;
        config.includeStandardObjects = false;
        Clarity360SetupConfigService.save(config);
        Clarity360Settings.resetCache();
    }

    @IsTest
    static void refreshInventoryCreatesRecords() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.includeStandardObjects = true;
        Clarity360SetupConfigService.save(config);
        Clarity360Settings.resetCache();

        Test.startTest();
        InventoryService.RefreshChunkResult result =
            InventoryService.refreshInventoryChunkForScopedObjects(new List<String>{ 'Account' }, false, 0, 1);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should be returned.');
        System.assertEquals(1, result.scannedObjectCount, 'The scoped object should be scanned when standard objects are enabled.');

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
        Clarity360Settings.resetCache();

        System.assertEquals(true, InventoryService.isObjectExcludedByRuntimeConfig('Account'));
        System.assertEquals(true, InventoryService.isObjectExcludedByRuntimeConfig('ns1__ManagedObject__c'));
        System.assertEquals(false, InventoryService.isObjectExcludedByRuntimeConfig('Contact'));
        System.assertEquals(true, InventoryService.isObjectExcludedByRuntimeConfig(null));
    }

    @IsTest
    static void recommendationScopeAndMetadataExclusionHelpersBehaveAsExpected() {
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope('FieldInventory__c'));
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope('DefinitelyMissingObject__c', false));
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope('ApexClass', false));
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope('Account', false));
        System.assertEquals(false, InventoryService.isObjectInRecommendationScope(null));

        System.assertEquals(true, InventoryService.isExcludedMetadataObject('ApexClass'));
        System.assertEquals(true, InventoryService.isExcludedMetadataObject('ApexWidget'));
        System.assertEquals(true, InventoryService.isExcludedMetadataObject('Clarity360Config__mdt'));
        System.assertEquals(true, InventoryService.isExcludedMetadataObject('FieldInventory__c'));
        System.assertEquals(false, InventoryService.isExcludedMetadataObject('Account'));
        System.assertEquals(true, InventoryService.isExcludedMetadataObject(null));
    }

    @IsTest
    static void standardObjectsRequireRuntimeOptInForRecommendationScope() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.includeStandardObjects = true;
        Clarity360SetupConfigService.save(config);
        Clarity360Settings.resetCache();

        System.assertEquals(true, InventoryService.isObjectInRecommendationScope('Account', false));
    }

    @IsTest
    static void fieldEligibilityExcludesSystemAndCompoundComponentFields() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.includeStandardObjects = true;
        Clarity360SetupConfigService.save(config);
        Clarity360Settings.resetCache();

        System.assertEquals(false, InventoryService.isFieldInScope('Account', 'CreatedDate'));
        System.assertEquals(false, InventoryService.isFieldInScope('Account', 'OwnerId'));
        System.assertEquals(false, InventoryService.isFieldInScope('Account', 'ShippingState'));
        System.assertEquals(false, InventoryService.isFieldInScope('Account', 'ShippingLatitude'));
        System.assertEquals(false, InventoryService.isFieldInScope('Account', 'Name'));
        System.assertEquals(false, InventoryService.isFieldInScope('FieldInventory__c', 'FieldApiName__c'));
    }

    @IsTest
    static void refreshInventoryInactivatesPreviouslyScannedStandardFields() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.includeStandardObjects = true;
        Clarity360SetupConfigService.save(config);
        Clarity360Settings.resetCache();

        insert new FieldInventory__c(
            FieldKey__c = 'Account.Name',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Name',
            IsActive__c = true
        );

        Test.startTest();
        InventoryService.RefreshChunkResult result =
            InventoryService.refreshInventoryChunkForScopedObjects(new List<String>{ 'Account' }, false, 0, 1);
        Test.stopTest();

        System.assertEquals(1, result.scannedObjectCount);
        FieldInventory__c staleRow = [
            SELECT IsActive__c
            FROM FieldInventory__c
            WHERE FieldKey__c = 'Account.Name'
            LIMIT 1
        ];
        System.assertEquals(false, staleRow.IsActive__c, 'Standard native fields should be inactivated after custom-only inventory refresh.');
    }

    @IsTest
    static void chunkHelperHandlesOutOfRangeCursorAndScopedSelection() {
        InventoryService.RefreshChunkResult emptyChunk =
            InventoryService.refreshInventoryChunkForScopedObjects(new List<String>{ 'FieldInventory__c' }, true, 5, 1);
        System.assertEquals(0, emptyChunk.scannedObjectCount, 'Out-of-range cursor should not scan any objects.');
        System.assertEquals(false, emptyChunk.hasMore, 'Out-of-range cursor should not report more work.');
    }
}
