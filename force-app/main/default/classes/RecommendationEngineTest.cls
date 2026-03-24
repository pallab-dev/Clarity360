@IsTest
private class RecommendationEngineTest {
    private static void ensureRuntimeSetup() {
        Clarity360Settings.resetCache();
        List<Clarity360SetupConfig__c> existing = [SELECT Id FROM Clarity360SetupConfig__c LIMIT 1];
        if (existing.isEmpty()) {
            insert new Clarity360SetupConfig__c(
                IsSetupComplete__c = true,
                ScopeMode__c = 'IncludeStandard',
                IncludeStandardObjects__c = true,
                CoverageThreshold__c = 80
            );
        } else {
            existing[0].IsSetupComplete__c = true;
            existing[0].ScopeMode__c = 'IncludeStandard';
            existing[0].IncludeStandardObjects__c = true;
            existing[0].CoverageThreshold__c = 80;
            update existing[0];
        }
    }

    private static Map<String, Object> buildToolingTriggerRow(String name, String status, String objectName, String body) {
        String idSuffix = name.length() >= 3 ? name.substring(0, 3) : name;
        return new Map<String, Object>{
            'Id' => '01q000000000' + idSuffix,
            'Name' => name,
            'Status' => status,
            'TableEnumOrId' => objectName,
            'Body' => body
        };
    }

    @IsTest
    static void buildFromSignalsGeneratesExpectedAction() {
        ensureRuntimeSetup();
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Active__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Active__c'
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
            FieldKey__c = 'Account.SLA__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'SLA__c'
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
            FieldKey__c = 'Case.Product__c',
            ObjectApiName__c = 'Case',
            FieldApiName__c = 'Product__c'
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
    static void buildFromSignalsKeepsCustomLookupFieldsInInvestigateMode() {
        ensureRuntimeSetup();
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.ParentSignal__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'ParentSignal__c'
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
                'ApexClassRefs=0; AvgApexCoveragePct=85'
        );

        List<Recommendation__c> recommendations = RecommendationEngine.buildFromSignals(
            new List<UsageSignal__c>{ signal },
            new Map<Id, FieldInventory__c>{ inventory.Id => inventory }
        );

        System.assertEquals(1, recommendations.size());
        System.assertEquals('Investigate Dependencies', recommendations[0].Action__c);
        System.assert(recommendations[0].EvidenceSummary__c.contains('DeleteSafeCustomField=false'));
    }

    @IsTest
    static void buildFromSignalsKeepsOnLayoutFieldsOutOfDeprecate() {
        ensureRuntimeSetup();
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Active__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Active__c'
        );
        insert inventory;

        UsageSignal__c signal = new UsageSignal__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            SampleSize__c = 100,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = true,
            EvidenceSummary__c =
                'Sampled=100; NonNull=0; HasData=false; ObjectRecordCount=250; MeetsMinRecordThreshold=true; ' +
                'ActiveTriggerRefs=0; InactiveTriggerRefs=0; ' +
                'ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ActiveFlowRefs=0; InactiveFlowRefs=0; ' +
                'ApexClassRefs=0; AvgApexCoveragePct=85'
        );

        List<Recommendation__c> recommendations = RecommendationEngine.buildFromSignals(
            new List<UsageSignal__c>{ signal },
            new Map<Id, FieldInventory__c>{ inventory.Id => inventory }
        );

        System.assertEquals(1, recommendations.size());
        System.assertEquals('Investigate Dependencies', recommendations[0].Action__c);
        System.assert(recommendations[0].EvidenceSummary__c.contains('IsOnLayout=true'));
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

    @IsTest
    static void buildGlobalTriggerRecommendationsFlagsMultipleTriggersAndMixedDml() {
        ensureRuntimeSetup();
        ToolingApiService.ToolingQueryResult result = new ToolingApiService.ToolingQueryResult();
        result.records.add(buildToolingTriggerRow(
            'AccountInlineTrigger',
            'Active',
            'Account',
            'trigger AccountInlineTrigger on Account (before update) { update new List<Account>(); }'
        ));
        result.records.add(buildToolingTriggerRow(
            'AccountMixedDmlTrigger',
            'Active',
            'Account',
            'trigger AccountMixedDmlTrigger on Account (after update) { update new List<User>(); }'
        ));
        ToolingApiService.setTestQueryResult(result);

        Test.startTest();
        List<Recommendation__c> recommendations = RecommendationEngine.buildGlobalTriggerRecommendations(System.now(), 50);
        Test.stopTest();
        ToolingApiService.clearTestOverrides();

        System.assertEquals(2, recommendations.size());
        Map<String, Recommendation__c> byKey = new Map<String, Recommendation__c>();
        for (Recommendation__c row : recommendations) {
            byKey.put(row.FieldKey__c, row);
            System.assertEquals('Investigate Dependencies', row.Action__c);
            System.assert(row.EvidenceSummary__c.contains('ActiveTriggerCountForObject=2'));
            System.assert(row.EvidenceSummary__c.contains('HasMultipleActiveTriggers=true'));
        }
        System.assert(byKey.get('GLOBAL.TRIGGER.AccountInlineTrigger').EvidenceSummary__c.contains('LacksHandlerFramework=true'));
        System.assert(byKey.get('GLOBAL.TRIGGER.AccountMixedDmlTrigger').EvidenceSummary__c.contains('MixedDmlSignal=true'));
    }

    @IsTest
    static void buildGlobalTriggerRecommendationsFlagsInactiveTrigger() {
        ensureRuntimeSetup();
        ToolingApiService.ToolingQueryResult result = new ToolingApiService.ToolingQueryResult();
        result.records.add(buildToolingTriggerRow(
            'LegacyLeadTrigger',
            'Inactive',
            'Lead',
            'trigger LegacyLeadTrigger on Lead (before insert) { TriggerHandler.run(); }'
        ));
        ToolingApiService.setTestQueryResult(result);

        Test.startTest();
        List<Recommendation__c> recommendations = RecommendationEngine.buildGlobalTriggerRecommendations(System.now(), 50);
        Test.stopTest();
        ToolingApiService.clearTestOverrides();

        System.assertEquals(1, recommendations.size());
        System.assert(recommendations[0].EvidenceSummary__c.contains('ComponentStatus=Inactive'));
        System.assert(recommendations[0].EvidenceSummary__c.contains('Reason=Inactive trigger'));
    }

    @IsTest
    static void heuristicHelpersDetectCrudFlsAndActionableApexClasses() {
        ensureRuntimeSetup();

        String secureBody =
            'public with sharing class SecureService {' +
            ' public static void run(){ if (Schema.SObjectType.Account.fields.Name.isUpdateable()) { } }' +
            '}';
        String insecureBody =
            'public without sharing class LegacyService {' +
            ' public static void run(){ List<Account> rows = [SELECT Id FROM Account]; }' +
            '}';
        String testBody =
            '@IsTest private class LegacyServiceTest { static testMethod void testRun() {} }';

        System.assertEquals(true, RecommendationEngine.hasCrudOrFlsSignal(secureBody));
        System.assertEquals(false, RecommendationEngine.hasCrudOrFlsSignal(insecureBody));
        System.assertEquals(true, RecommendationEngine.isActionableApexClass('SecureService', secureBody, null));
        System.assertEquals(true, RecommendationEngine.isActionableApexClass('LegacyService', insecureBody, null));
        System.assertEquals(false, RecommendationEngine.isActionableApexClass('LegacyServiceTest', testBody, null));
        System.assertEquals(false, RecommendationEngine.isActionableApexClass('PkgService', secureBody, 'pkg'));
        System.assertEquals('with sharing', RecommendationEngine.extractSharingKeyword(secureBody));
        System.assertEquals('without sharing', RecommendationEngine.extractSharingKeyword(insecureBody));
        System.assertEquals(true, RecommendationEngine.isFlowEntryApexClass('@InvocableMethod public static void run() {}'));
    }

    @IsTest
    static void heuristicHelpersDetectTriggerSignals() {
        ensureRuntimeSetup();

        String inlineTriggerBody =
            'trigger ContactInlineTrigger on Contact (before update) { update Trigger.new; }';
        String handlerTriggerBody =
            'trigger ContactHandlerTrigger on Contact (before update) { ContactTriggerHandler.run(); }';
        String mixedDmlBody =
            'trigger ContactMixedDml on Contact (after update) { update new List<User>(); }';

        System.assertEquals(true, RecommendationEngine.hasTriggerWithoutHandlerFramework(inlineTriggerBody));
        System.assertEquals(false, RecommendationEngine.hasTriggerWithoutHandlerFramework(handlerTriggerBody));
        System.assertEquals(true, RecommendationEngine.hasMixedDmlSignal(mixedDmlBody));
        System.assertEquals(false, RecommendationEngine.hasMixedDmlSignal(handlerTriggerBody));
    }

    @IsTest
    static void heuristicHelpersFlagInactiveMetadataByAge() {
        ensureRuntimeSetup();

        System.assertEquals(false, RecommendationEngine.shouldFlagInactiveMetadata(true, 'Active', System.now().addDays(-400)));
        System.assertEquals(true, RecommendationEngine.shouldFlagInactiveMetadata(false, 'Obsolete', System.now()));
        System.assertEquals(true, RecommendationEngine.shouldFlagInactiveMetadata(false, 'Draft', System.now().addDays(-5)));
        System.assertEquals(true, RecommendationEngine.shouldFlagInactiveMetadata(false, null, System.now().addDays(-200)));
        System.assertEquals(false, RecommendationEngine.shouldFlagInactiveMetadata(false, null, System.now().addDays(-20)));
    }

    @IsTest
    static void rebuildAllRecommendationsBuildsValidationFlowAndWorkflowRowsFromTooling() {
        ensureRuntimeSetup();

        ToolingApiService.ToolingQueryResult triggerResult = new ToolingApiService.ToolingQueryResult();
        triggerResult.records.add(buildToolingTriggerRow(
            'AccountHandlerTrigger',
            'Active',
            'Account',
            'trigger AccountHandlerTrigger on Account (before update) { AccountTriggerHandler.run(); }'
        ));

        ToolingApiService.ToolingQueryResult validationResult = new ToolingApiService.ToolingQueryResult();
        validationResult.records.add(new Map<String, Object>{
            'Id' => '03d000000000001',
            'ValidationName' => 'LegacyRule',
            'Active' => false,
            'LastModifiedDate' => String.valueOf(System.now().addDays(-240)),
            'EntityDefinition' => new Map<String, Object>{ 'QualifiedApiName' => 'Account' }
        });

        ToolingApiService.ToolingQueryResult flowResult = new ToolingApiService.ToolingQueryResult();
        flowResult.records.add(new Map<String, Object>{
            'Id' => '301000000000001',
            'MasterLabel' => 'Legacy Account Flow',
            'DeveloperName' => 'Legacy_Account_Flow',
            'Status' => 'Draft',
            'ProcessType' => 'Flow',
            'VersionNumber' => 3,
            'LastModifiedDate' => String.valueOf(System.now().addDays(-240))
        });

        ToolingApiService.ToolingQueryResult workflowResult = new ToolingApiService.ToolingQueryResult();
        workflowResult.records.add(new Map<String, Object>{
            'Id' => '04a000000000001',
            'Name' => 'LegacyWorkflow',
            'Active' => false,
            'LastModifiedDate' => String.valueOf(System.now().addDays(-240)),
            'TableEnumOrId' => 'Account'
        });

        ToolingApiService.ToolingQueryResult coverageResult = new ToolingApiService.ToolingQueryResult();
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            triggerResult,
            validationResult,
            flowResult,
            workflowResult,
            coverageResult
        });

        Test.startTest();
        RecommendationEngine.rebuildAllRecommendations(50);
        Test.stopTest();

        Map<String, Recommendation__c> rowsByKey = new Map<String, Recommendation__c>();
        for (Recommendation__c row : [
            SELECT FieldKey__c, Action__c, EvidenceSummary__c
            FROM Recommendation__c
            WHERE FieldKey__c IN (
                'GLOBAL.VALRULE.03d000000000001',
                'GLOBAL.FLOW.301000000000001',
                'GLOBAL.WORKFLOW.04a000000000001'
            )
        ]) {
            rowsByKey.put(row.FieldKey__c, row);
        }

        System.assertEquals('Investigate Dependencies', rowsByKey.get('GLOBAL.VALRULE.03d000000000001').Action__c);
        System.assert(rowsByKey.get('GLOBAL.VALRULE.03d000000000001').EvidenceSummary__c.contains('ComponentType=ValidationRule'));
        System.assert(rowsByKey.get('GLOBAL.FLOW.301000000000001').EvidenceSummary__c.contains('ComponentType=Flow'));
        System.assert(rowsByKey.get('GLOBAL.WORKFLOW.04a000000000001').EvidenceSummary__c.contains('ComponentType=WorkflowRule'));

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void rebuildAllRecommendationsFallsBackWhenInventoryLinkIsMissing() {
        ensureRuntimeSetup();
        insert new UsageSignal__c(
            FieldKey__c = 'Account.Legacy_Fallback__c',
            SampleSize__c = 120,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            LastObservedOn__c = System.now(),
            EvidenceSummary__c = 'HasData=false; ObjectRecordCount=250; MeetsMinRecordThreshold=true'
        );

        Test.startTest();
        RecommendationEngine.rebuildAllRecommendations(20);
        Test.stopTest();

        Recommendation__c row = [
            SELECT FieldKey__c, Action__c, EvidenceSummary__c
            FROM Recommendation__c
            WHERE FieldKey__c = 'Account.Legacy_Fallback__c'
            LIMIT 1
        ];
        System.assertEquals('Deprecate', row.Action__c);
        System.assert(row.EvidenceSummary__c.contains('Fallback=SignalOnly'));
    }

    @IsTest
    static void buildGlobalMetadataInventoryRecommendationsCoversMultipleDecisionBranches() {
        ensureRuntimeSetup();
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.CMDT.EmptyConfig__mdt',
            ComponentType__c = 'Custom Metadata Type',
            ApiName__c = 'EmptyConfig__mdt',
            DisplayName__c = 'EmptyConfig__mdt',
            ReferenceCount__c = 0,
            IsActive__c = true,
            LastScannedOn__c = System.now()
        );
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.CUSTOMSETTING.SingleSetting__c',
            ComponentType__c = 'Custom Setting',
            ApiName__c = 'SingleSetting__c',
            DisplayName__c = 'SingleSetting__c',
            ReferenceCount__c = 1,
            IsActive__c = true,
            LastScannedOn__c = System.now()
        );
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.PEVENT.Idle_Event__e',
            ComponentType__c = 'Platform Event',
            ApiName__c = 'Idle_Event__e',
            DisplayName__c = 'Idle Event',
            ReferenceCount__c = 0,
            ActiveSubscriberCount__c = 0,
            ActivePublisherCount__c = 0,
            MonitoringEligible__c = true,
            IsActive__c = true,
            LastScannedOn__c = System.now()
        );

        Test.startTest();
        List<Recommendation__c> rows = RecommendationEngine.buildGlobalMetadataInventoryRecommendations(System.now());
        Test.stopTest();

        System.assertEquals(3, rows.size());
        Map<String, Recommendation__c> rowsByKey = new Map<String, Recommendation__c>();
        for (Recommendation__c row : rows) {
            rowsByKey.put(row.FieldKey__c, row);
        }
        System.assertEquals('Deprecate', rowsByKey.get('GLOBAL.CMDT.EmptyConfig__mdt').Action__c);
        System.assertEquals('Investigate Dependencies', rowsByKey.get('GLOBAL.CUSTOMSETTING.SingleSetting__c').Action__c);
        System.assert(rowsByKey.get('GLOBAL.PEVENT.Idle_Event__e').EvidenceSummary__c.contains('ActivePublisherCount=0'));
    }

    @IsTest
    static void buildGlobalApexCoverageRecommendationsReturnsCoverageScopedRows() {
        ensureRuntimeSetup();
        Clarity360Settings.RuntimeConfig runtime = Clarity360Settings.getRequiredRuntime();

        Test.startTest();
        List<Recommendation__c> rows = RecommendationEngine.buildGlobalApexCoverageRecommendations(System.now(), 25, runtime);
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Apex coverage scan should return scoped recommendations in the package org.');
        Boolean foundScopedRow = false;
        for (Recommendation__c row : rows) {
            if (row.FieldKey__c != null && row.FieldKey__c.startsWith('GLOBAL.APEXCLASS.')) {
                foundScopedRow = true;
                System.assert(row.EvidenceSummary__c.contains('CoverageBand='));
                break;
            }
        }
        System.assertEquals(true, foundScopedRow);
    }
}
