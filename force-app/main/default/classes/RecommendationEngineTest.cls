@IsTest
private class RecommendationEngineTest {
    private static void ensureRuntimeSetup() {
        List<Clarity360SetupConfig__c> existing = [SELECT Id FROM Clarity360SetupConfig__c LIMIT 1];
        if (existing.isEmpty()) {
            insert new Clarity360SetupConfig__c(
                IsSetupComplete__c = true,
                ScopeMode__c = 'CustomOnly',
                CoverageThreshold__c = 80
            );
        } else {
            existing[0].IsSetupComplete__c = true;
            existing[0].ScopeMode__c = 'CustomOnly';
            existing[0].CoverageThreshold__c = 80;
            update existing[0];
        }
    }

    @IsTest
    static void buildFromSignalsGeneratesExpectedAction() {
        ensureRuntimeSetup();
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Test_Field__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Test_Field__c'
        );
        insert inventory;

        UsageSignal__c signal = new UsageSignal__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            SampleSize__c = 100,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            EvidenceSummary__c =
                'Sampled=100; NonNull=0; HasData=false; ObjectRecordCount=250; MeetsMinRecordThreshold=true; ' +
                'ActiveTriggerRefs=0; InactiveTriggerRefs=0; ' +
                'ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ActiveFlowRefs=0; InactiveFlowRefs=0; ' +
                'ApexClassRefs=1; AvgApexCoveragePct=85'
        );

        List<Recommendation__c> recommendations = RecommendationEngine.buildFromSignals(
            new List<UsageSignal__c>{ signal },
            new Map<Id, FieldInventory__c>{ inventory.Id => inventory }
        );

        System.assertEquals(1, recommendations.size(), 'One recommendation should be generated.');
        System.assertEquals('Deprecate', recommendations[0].Action__c);
        System.assertEquals('Open', recommendations[0].Status__c);
    }

    @IsTest
    static void buildFromSignalsGoldenDatasetKeepsWhenBelowNullThreshold() {
        ensureRuntimeSetup();
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Health_Score__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Health_Score__c'
        );
        insert inventory;

        UsageSignal__c signal = new UsageSignal__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            SampleSize__c = 100,
            NonNullCount__c = 50,
            NullRatePct__c = 50,
            IsOnLayout__c = false,
            EvidenceSummary__c =
                'Sampled=100; NonNull=50; HasData=true; ObjectRecordCount=100; MeetsMinRecordThreshold=true; ' +
                'ActiveTriggerRefs=0; InactiveTriggerRefs=0; ' +
                'ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ActiveFlowRefs=0; InactiveFlowRefs=0; ' +
                'ApexClassRefs=0; AvgApexCoveragePct=Unknown'
        );

        List<Recommendation__c> recommendations = RecommendationEngine.buildFromSignals(
            new List<UsageSignal__c>{ signal },
            new Map<Id, FieldInventory__c>{ inventory.Id => inventory }
        );

        System.assertEquals(1, recommendations.size());
        System.assertEquals('Keep', recommendations[0].Action__c);
        System.assert(recommendations[0].EvidenceSummary__c.contains('SuggestedAction=Keep'));
    }

    @IsTest
    static void buildFromSignalsGoldenDatasetInvestigatesWhenSampleMissing() {
        ensureRuntimeSetup();
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Stage_Indicator__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Stage_Indicator__c'
        );
        insert inventory;

        UsageSignal__c signal = new UsageSignal__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            SampleSize__c = 0,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            EvidenceSummary__c =
                'Sampled=0; NonNull=0; HasData=false; ObjectRecordCount=10; MeetsMinRecordThreshold=true; ' +
                'ActiveTriggerRefs=0; InactiveTriggerRefs=0; ' +
                'ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ActiveFlowRefs=0; InactiveFlowRefs=0; ' +
                'ApexClassRefs=0; AvgApexCoveragePct=Unknown'
        );

        List<Recommendation__c> recommendations = RecommendationEngine.buildFromSignals(
            new List<UsageSignal__c>{ signal },
            new Map<Id, FieldInventory__c>{ inventory.Id => inventory }
        );

        System.assertEquals(1, recommendations.size());
        System.assertEquals('Investigate Dependencies', recommendations[0].Action__c);
        System.assertEquals('Open', recommendations[0].Status__c);
    }

    @IsTest
    static void rebuildAllRecommendationsGeneratesMetadataInventoryRecommendations() {
        ensureRuntimeSetup();

        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.CUSTOMSETTING.LegacySetting__c',
            ComponentType__c = 'Custom Setting',
            ApiName__c = 'LegacySetting__c',
            DisplayName__c = 'LegacySetting__c',
            ReferenceCount__c = 0,
            ActiveSubscriberCount__c = 0,
            MonitoringEligible__c = false,
            LastScannedOn__c = System.now(),
            SourceSummary__c = 'Discovery=Describe'
        );
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.PEVENT.CustomerSignal__e',
            ComponentType__c = 'Platform Event',
            ApiName__c = 'CustomerSignal__e',
            DisplayName__c = 'CustomerSignal__e',
            ReferenceCount__c = 1,
            ActiveSubscriberCount__c = 0,
            MonitoringEligible__c = true,
            LastScannedOn__c = System.now(),
            SourceSummary__c = 'Discovery=Describe'
        );

        Test.startTest();
        RecommendationEngine.rebuildAllRecommendations(50);
        Test.stopTest();

        Map<String, Recommendation__c> recsByKey = new Map<String, Recommendation__c>();
        for (Recommendation__c row : [
            SELECT FieldKey__c, Action__c
            FROM Recommendation__c
            WHERE FieldKey__c IN ('GLOBAL.CUSTOMSETTING.LegacySetting__c', 'GLOBAL.PEVENT.CustomerSignal__e')
        ]) {
            recsByKey.put(row.FieldKey__c, row);
        }

        System.assertEquals('Deprecate', recsByKey.get('GLOBAL.CUSTOMSETTING.LegacySetting__c').Action__c);
        System.assertEquals('Investigate Dependencies', recsByKey.get('GLOBAL.PEVENT.CustomerSignal__e').Action__c);
    }
}
