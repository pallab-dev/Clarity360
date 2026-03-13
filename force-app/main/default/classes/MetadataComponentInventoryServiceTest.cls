@IsTest
private class MetadataComponentInventoryServiceTest {
    @IsTest
    static void refreshAll_buildsInventoryFromMixedSources() {
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
        MetadataComponentInventoryService.setTestPlatformEventActiveSubscribers(new Map<String, Integer>{
            'CustomerSignal__e' => 2
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
                ActiveSubscriberCount__c, MonitoringEligible__c, IsActive__c, SourceSummary__c
            FROM MetadataComponentInventory__c
        ]) {
            rowsByKey.put(row.ComponentKey__c, row);
        }

        System.assertEquals(3, rowsByKey.size(), 'Expected three metadata inventory rows.');
        System.assertEquals(1, rowsByKey.get('META.CMDT.Clarity360Config__mdt').ReferenceCount__c.intValue());
        System.assertEquals(2, rowsByKey.get('META.CUSTOMSETTING.LegacySetting__c').ReferenceCount__c.intValue());
        System.assertEquals(3, rowsByKey.get('META.PEVENT.CustomerSignal__e').ReferenceCount__c.intValue());
        System.assertEquals(2, rowsByKey.get('META.PEVENT.CustomerSignal__e').ActiveSubscriberCount__c.intValue());
        System.assertEquals(true, rowsByKey.get('META.PEVENT.CustomerSignal__e').MonitoringEligible__c);
        System.assertEquals(true, rowsByKey.get('META.PEVENT.CustomerSignal__e').IsActive__c);
        System.assert(rowsByKey.get('META.CMDT.Clarity360Config__mdt').SourceSummary__c.contains('ToolingDeploymentStatus=Deployed'));

        MetadataComponentInventoryService.clearTestOverrides();
        ToolingApiService.clearTestOverrides();
    }
}
