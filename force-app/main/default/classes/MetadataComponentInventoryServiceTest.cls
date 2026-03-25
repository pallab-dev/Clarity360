@IsTest
private class MetadataComponentInventoryServiceTest {
    @IsTest
    static void refreshAllBuildsInventoryFromMixedSources() {
        MetadataComponentInventoryService.ComponentRecord cmdt = new MetadataComponentInventoryService.ComponentRecord();
        cmdt.componentKey = 'META.CMDT.Clarity360Config__mdt';
        cmdt.componentType = 'Custom Metadata Type';
        cmdt.apiName = 'Clarity360Config__mdt';
        cmdt.displayName = 'Clarity360Config__mdt';

        MetadataComponentInventoryService.ComponentRecord customSetting = new MetadataComponentInventoryService.ComponentRecord();
        customSetting.componentKey = 'META.CUSTOMSETTING.LegacySetting__c';
        customSetting.componentType = 'Custom Setting';
        customSetting.apiName = 'LegacySetting__c';
        customSetting.displayName = 'LegacySetting__c';

        MetadataComponentInventoryService.ComponentRecord platformEvent = new MetadataComponentInventoryService.ComponentRecord();
        platformEvent.componentKey = 'META.PEVENT.CustomerSignal__e';
        platformEvent.componentType = 'Platform Event';
        platformEvent.apiName = 'CustomerSignal__e';
        platformEvent.displayName = 'CustomerSignal__e';
        platformEvent.monitoringEligible = true;

        Map<String, MetadataComponentInventoryService.ComponentRecord> discovered =
            new Map<String, MetadataComponentInventoryService.ComponentRecord>{
                cmdt.componentKey => cmdt,
                customSetting.componentKey => customSetting,
                platformEvent.componentKey => platformEvent
            };
        MetadataComponentInventoryService.setTestDiscovery(discovered);
        MetadataComponentInventoryService.setTestApexBodies(new List<String>{
            'Clarity360Config__mdt.getAll();',
            '$Setup.LegacySetting__c.Value__c;',
            'EventBus.publish(new CustomerSignal__e());'
        });
        MetadataComponentInventoryService.setTestValidationFormulas(new List<String>{
            '$Setup.LegacySetting__c.Enabled__c = true'
        });
        MetadataComponentInventoryService.setTestFlowDefinitions(new List<String>{
            '{"apiReferences":["Clarity360Config__mdt","LegacySetting__c","CustomerSignal__e"],"publisherType":"PlatformEvent"}'
        });
        MetadataComponentInventoryService.setTestPlatformEventActiveSubscribers(new Map<String, Integer>{
            'CustomerSignal__e' => 2
        });
        MetadataComponentInventoryService.setTestPlatformEventActivePublishers(new Map<String, Integer>{
            'CustomerSignal__e' => 1
        });

        ToolingApiService.ToolingQueryResult toolingResult = new ToolingApiService.ToolingQueryResult();
        toolingResult.records.add(new Map<String, Object>{
            'DeveloperName' => 'Clarity360Config',
            'NamespacePrefix' => null,
            'DeploymentStatus' => 'Deployed'
        });
        toolingResult.records.add(new Map<String, Object>{
            'DeveloperName' => 'CustomerSignal',
            'NamespacePrefix' => null,
            'DeploymentStatus' => 'Deployed'
        });
        ToolingApiService.setTestQueryResult(toolingResult);

        Test.startTest();
        MetadataComponentInventoryService.refreshAll(200);
        Test.stopTest();

        Map<String, MetadataComponentInventory__c> rowsByKey = new Map<String, MetadataComponentInventory__c>();
        for (MetadataComponentInventory__c row : [
            SELECT ComponentKey__c, ComponentType__c, ApiName__c, ReferenceCount__c,
                ActiveSubscriberCount__c, ActivePublisherCount__c, MonitoringEligible__c, IsActive__c, SourceSummary__c
            FROM MetadataComponentInventory__c
        ]) {
            rowsByKey.put(row.ComponentKey__c, row);
        }

        System.assertEquals(3, rowsByKey.size(), 'Expected three metadata inventory rows.');
        System.assertEquals(2, rowsByKey.get('META.CMDT.Clarity360Config__mdt').ReferenceCount__c.intValue());
        System.assertEquals(3, rowsByKey.get('META.CUSTOMSETTING.LegacySetting__c').ReferenceCount__c.intValue());
        System.assertEquals(5, rowsByKey.get('META.PEVENT.CustomerSignal__e').ReferenceCount__c.intValue());
        System.assertEquals(2, rowsByKey.get('META.PEVENT.CustomerSignal__e').ActiveSubscriberCount__c.intValue());
        System.assertEquals(1, rowsByKey.get('META.PEVENT.CustomerSignal__e').ActivePublisherCount__c.intValue());
        System.assertEquals(true, rowsByKey.get('META.PEVENT.CustomerSignal__e').MonitoringEligible__c);
        System.assertEquals(true, rowsByKey.get('META.PEVENT.CustomerSignal__e').IsActive__c);
        System.assert(rowsByKey.get('META.PEVENT.CustomerSignal__e').SourceSummary__c.contains('ActivePublisherCount=1'));
        System.assert(rowsByKey.get('META.CMDT.Clarity360Config__mdt').SourceSummary__c.contains('ToolingDeploymentStatus=Deployed'));

        MetadataComponentInventoryService.clearTestOverrides();
        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void refreshAllDetectsPublisherAliasesInApexAndFlowMetadata() {
        MetadataComponentInventoryService.ComponentRecord platformEvent = new MetadataComponentInventoryService.ComponentRecord();
        platformEvent.componentKey = 'META.PEVENT.OrderSignal__e';
        platformEvent.componentType = 'Platform Event';
        platformEvent.apiName = 'OrderSignal__e';
        platformEvent.displayName = 'OrderSignal__e';
        platformEvent.monitoringEligible = true;

        MetadataComponentInventoryService.setTestDiscovery(
            new Map<String, MetadataComponentInventoryService.ComponentRecord>{
                platformEvent.componentKey => platformEvent
            }
        );
        MetadataComponentInventoryService.setTestApexBodies(new List<String>{
            'OrderSignal__e evt = new OrderSignal__e(); EventBus.publish(evt);',
            'List<OrderSignal__e> batched = new List<OrderSignal__e>(); EventBus.publish(batched);'
        });
        MetadataComponentInventoryService.setTestFlowDefinitions(new List<String>{
            '{"publisherType":"PlatformEvent","eventDeveloperName":"OrderSignal"}'
        });

        Test.startTest();
        MetadataComponentInventoryService.refreshAll(200);
        Test.stopTest();

        MetadataComponentInventory__c row = [
            SELECT ReferenceCount__c, ActivePublisherCount__c, ActiveSubscriberCount__c, SourceSummary__c
            FROM MetadataComponentInventory__c
            WHERE ComponentKey__c = 'META.PEVENT.OrderSignal__e'
            LIMIT 1
        ];

        System.assertEquals(3, row.ActivePublisherCount__c.intValue());
        System.assertEquals(0, row.ActiveSubscriberCount__c.intValue());
        System.assertEquals(6, row.ReferenceCount__c.intValue());
        System.assert(row.SourceSummary__c.contains('ActivePublisherCount=3'));

        MetadataComponentInventoryService.clearTestOverrides();
        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void refreshAllDeactivatesRowsWhenNothingIsDiscovered() {
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.CUSTOMSETTING.StaleSetting__c',
            ComponentType__c = 'Custom Setting',
            ApiName__c = 'StaleSetting__c',
            DisplayName__c = 'StaleSetting__c',
            IsActive__c = true,
            LastScannedOn__c = System.now().addDays(-5)
        );

        MetadataComponentInventoryService.setTestDiscovery(
            new Map<String, MetadataComponentInventoryService.ComponentRecord>()
        );

        Test.startTest();
        MetadataComponentInventoryService.refreshAll(50);
        Test.stopTest();

        MetadataComponentInventory__c staleRow = [
            SELECT IsActive__c, LastScannedOn__c
            FROM MetadataComponentInventory__c
            WHERE ComponentKey__c = 'META.CUSTOMSETTING.StaleSetting__c'
            LIMIT 1
        ];
        System.assertEquals(false, staleRow.IsActive__c);
        System.assertNotEquals(null, staleRow.LastScannedOn__c);

        MetadataComponentInventoryService.clearTestOverrides();
        ToolingApiService.clearTestOverrides();
    }
}
