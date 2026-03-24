@IsTest
private class Clarity360DashboardControllerTest {
    private static void ensureSetupComplete() {
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
    static void getRecentJobsReturnsPagedRows() {
        List<ScanJob__c> jobsToInsert = new List<ScanJob__c>();
        for (Integer i = 0; i < 12; i++) {
            jobsToInsert.add(new ScanJob__c(
                JobType__c = 'Usage Scan',
                Status__c = 'Completed',
                StartedOn__c = System.now().addMinutes(-i),
                FinishedOn__c = System.now().addMinutes(-i + 1)
            ));
        }
        insert jobsToInsert;

        Test.startTest();
        Clarity360DashboardController.RecentJobsPage firstPage = Clarity360DashboardController.getRecentJobs(1, 5);
        Clarity360DashboardController.RecentJobsPage thirdPage = Clarity360DashboardController.getRecentJobs(3, 5);
        Clarity360DashboardController.RecentJobsPage overflowPage = Clarity360DashboardController.getRecentJobs(99, 5);
        Clarity360DashboardController.RecentJobsPage defaultPage = Clarity360DashboardController.getRecentJobs(null, null);
        Test.stopTest();

        System.assertEquals(12, firstPage.totalCount);
        System.assertEquals(1, firstPage.pageNumber);
        System.assertEquals(5, firstPage.pageSize);
        System.assertEquals(5, firstPage.jobs.size());

        System.assertEquals(3, thirdPage.pageNumber);
        System.assertEquals(2, thirdPage.jobs.size());

        System.assertEquals(3, overflowPage.pageNumber, 'Page number should clamp to the last available page.');
        System.assertEquals(2, overflowPage.jobs.size());

        System.assertEquals(1, defaultPage.pageNumber);
        System.assertEquals(5, defaultPage.pageSize);
        System.assertEquals(5, defaultPage.jobs.size());
    }

    @IsTest
    static void getAdminHygieneSnapshotReturnsAllSections() {
        Test.startTest();
        Clarity360DashboardController.AdminHygieneSnapshot snapshot =
            Clarity360DashboardController.getAdminHygieneSnapshot();
        Test.stopTest();

        System.assertNotEquals(null, snapshot);
        System.assertEquals(3, snapshot.sections.size(), 'Only directly actionable hygiene categories should be returned.');
        System.assertEquals('inactiveUsers', snapshot.sections[0].key);
        System.assertEquals('unassignedPermissionSets', snapshot.sections[1].key);
        System.assertEquals('unassignedPermissionSetGroups', snapshot.sections[2].key);
        System.assert(snapshot.inactiveUserCount >= 0);
        System.assertEquals(0, snapshot.unusedProfileCount, 'Profiles are intentionally excluded because Apex cannot safely separate standard profiles from actionable custom ones.');
        System.assert(snapshot.unassignedPermissionSetCount >= 0);
        System.assertEquals(0, snapshot.emptyRoleCount);
        System.assertEquals(0, snapshot.emptyGroupOrQueueCount);
    }

    @IsTest
    static void dashboardSummaryAndMetadataRowsIncludeMetadataInventory() {
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.CMDT.Clarity360Config__mdt',
            ComponentType__c = 'Custom Metadata Type',
            ApiName__c = 'Clarity360Config__mdt',
            DisplayName__c = 'Clarity360Config__mdt',
            ReferenceCount__c = 2,
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
            ActiveSubscriberCount__c = 1,
            ActivePublisherCount__c = 1,
            MonitoringEligible__c = true,
            LastScannedOn__c = System.now(),
            SourceSummary__c = 'Discovery=Describe'
        );

        Test.startTest();
        Clarity360DashboardController.DashboardSummary summary = Clarity360DashboardController.getDashboardSummary();
        List<Clarity360DashboardController.MetadataComponentRow> rows =
            Clarity360DashboardController.getMetadataComponents(null, 10);
        Test.stopTest();

        System.assertEquals(2, summary.metadataComponentCount);
        System.assertEquals(2, summary.referencedMetadataComponentCount);
        System.assertEquals(1, summary.platformEventComponentCount);
        System.assertEquals(2, rows.size());
        System.assertEquals('Custom Metadata Type', rows[0].componentType, 'Rows should sort by reference count desc, then recency.');
        System.assertEquals(1, rows[1].activePublisherCount);
        System.assert(rows[1].whyVisible.contains('publishers'));
        System.assert(rows[0].whyVisible.contains('referenced'), 'Metadata row should explain why it is shown.');
        System.assert(!String.isBlank(rows[0].nextStep), 'Metadata row should include a next step.');
    }

    @IsTest
    static void getMonitoringSnapshotReturnsTrendRows() {
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.PEVENT.CustomerSignal__e',
            ComponentType__c = 'Platform Event',
            ApiName__c = 'CustomerSignal__e',
            DisplayName__c = 'CustomerSignal__e',
            ReferenceCount__c = 2,
            ActiveSubscriberCount__c = 1,
            ActivePublisherCount__c = 2,
            MonitoringEligible__c = true,
            LastScannedOn__c = System.now(),
            SourceSummary__c = 'Discovery=Describe'
        );
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.PEVENT.IdleSignal__e',
            ComponentType__c = 'Platform Event',
            ApiName__c = 'IdleSignal__e',
            DisplayName__c = 'IdleSignal__e',
            ReferenceCount__c = 0,
            ActiveSubscriberCount__c = 0,
            ActivePublisherCount__c = 0,
            MonitoringEligible__c = true,
            LastScannedOn__c = System.now(),
            SourceSummary__c = 'Discovery=Describe; MonitoringEligible=true'
        );
        insert new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-15),
            FinishedOn__c = System.now().addMinutes(-5),
            GovernorSummary__c = 'TxnCount=2; AvgCpuMs=150.00; AvgHeapKb=50.00; SoqlTotal=35; AsyncActiveJobs=4; DailyApiRequestsPct=18.50; DailyAsyncApexPct=25.00'
        );

        Test.startTest();
        Clarity360DashboardController.MonitoringSnapshot snapshot =
            Clarity360DashboardController.getMonitoringSnapshot();
        Test.stopTest();

        System.assertEquals(2, snapshot.platformEventCount);
        System.assertEquals(1, snapshot.activePlatformSubscriberCount);
        System.assertEquals(2, snapshot.activePlatformPublisherCount);
        System.assert(snapshot.asyncJobsToday >= 0, 'Monitoring snapshot should expose today async job count.');
        System.assert(!snapshot.scanTrends.isEmpty(), 'Trend rows should be returned when scan jobs contain governor summaries.');
        System.assertEquals(150, snapshot.scanTrends[0].avgCpuMs);
        System.assertEquals(35, snapshot.scanTrends[0].totalSoqlQueries);
    }

    @IsTest
    static void getMonitoringDetailReturnsPlatformEventAndScanTrendDetails() {
        MetadataComponentInventory__c eventRow = new MetadataComponentInventory__c(
            ComponentKey__c = 'META.PEVENT.CustomerSignal__e',
            ComponentType__c = 'Platform Event',
            ApiName__c = 'CustomerSignal__e',
            DisplayName__c = 'CustomerSignal__e',
            ReferenceCount__c = 1,
            ActiveSubscriberCount__c = 1,
            ActivePublisherCount__c = 2,
            MonitoringEligible__c = true,
            LastScannedOn__c = System.now(),
            SourceSummary__c = 'Discovery=Describe; ActivePublisherCount=2; ActiveSubscriberCount=1'
        );
        insert eventRow;

        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-15),
            FinishedOn__c = System.now().addMinutes(-5),
            GovernorSummary__c = 'TxnCount=2; AvgCpuMs=150.00; AvgHeapKb=50.00; SoqlTotal=35; AsyncActiveJobs=4; DailyApiRequestsPct=18.50; DailyAsyncApexPct=25.00'
        );
        insert job;

        Test.startTest();
        Clarity360DashboardController.MonitoringDetail eventDetail =
            Clarity360DashboardController.getMonitoringDetail('platformEvent', eventRow.Id);
        Clarity360DashboardController.MonitoringDetail trendDetail =
            Clarity360DashboardController.getMonitoringDetail('scanTrend', job.Id);
        Test.stopTest();

        System.assertEquals('CustomerSignal__e', eventDetail.title);
        System.assertEquals('Platform Event', eventDetail.subtitle);
        System.assert(eventDetail.items.size() >= 5, 'Platform event detail should include persisted summary items.');
        System.assertEquals(job.JobType__c, trendDetail.subtitle);
        System.assert(trendDetail.items.size() >= 5, 'Scan trend detail should expose parsed governor summary values.');
    }

    @IsTest
    static void getGlobalComponentsReturnsInventoryRows() {
        Clarity360DashboardController.GlobalComponentRow validationRow = new Clarity360DashboardController.GlobalComponentRow();
        validationRow.key = 'Validation Rule|Account_Legacy_Check|Account';
        validationRow.componentType = 'Validation Rule';
        validationRow.componentName = 'Account Legacy Check';
        validationRow.status = 'Inactive';
        validationRow.objectName = 'Account';
        validationRow.detail = 'Validation rule metadata';

        Clarity360DashboardController.GlobalComponentRow triggerRow = new Clarity360DashboardController.GlobalComponentRow();
        triggerRow.key = 'Trigger|AccountCleanupTrigger|';
        triggerRow.componentType = 'Trigger';
        triggerRow.componentName = 'AccountCleanupTrigger';
        triggerRow.status = 'Active';
        triggerRow.detail = 'Trigger metadata';

        Clarity360DashboardController.testGlobalComponents = new List<Clarity360DashboardController.GlobalComponentRow>{
            validationRow,
            triggerRow
        };

        Test.startTest();
        List<Clarity360DashboardController.GlobalComponentRow> rows =
            Clarity360DashboardController.getGlobalComponents(50);
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('Validation Rule', rows[0].componentType);
        System.assertEquals('Inactive', rows[0].status);
        System.assertEquals('Account', rows[0].objectName);

        Clarity360DashboardController.testGlobalComponents = null;
    }

    @IsTest
    static void actionableApexInventoryFilterMatchesGovernanceIntent() {
        ApexClass flowEntryClass = new ApexClass(
            Name = 'FlowEntryService',
            Body = 'public with sharing class FlowEntryService { @InvocableMethod public static void run() {} }'
        );
        ApexClass lowSignalClass = new ApexClass(
            Name = 'Clarity360PostInstallHandler',
            Body = 'public without sharing class Clarity360PostInstallHandler { public static void run() {} }'
        );
        ApexClass testClass = new ApexClass(
            Name = 'LegacyUtilityTest',
            Body = '@IsTest private class LegacyUtilityTest { static testMethod void testRun() {} }'
        );

        System.assertEquals(
            true,
            Clarity360DashboardController.isActionableApexClassForInventory(flowEntryClass, new Set<String>()),
            'Non-test classes with a real body should remain in Apex coverage scope.'
        );
        System.assertEquals(
            true,
            Clarity360DashboardController.isActionableApexClassForInventory(lowSignalClass, new Set<String>()),
            'Standalone utility classes should be included when they are non-test, non-namespaced, and have a body.'
        );
        System.assertEquals(
            false,
            Clarity360DashboardController.isActionableApexClassForInventory(testClass, new Set<String>()),
            'Test classes must stay out of the inventory scope.'
        );
    }

    @IsTest
    static void globalComponentStatusesCollapseToActiveOrInactive() {
        System.assertEquals('Active', Clarity360DashboardController.normalizeBinaryComponentStatus('Active'));
        System.assertEquals('Inactive', Clarity360DashboardController.normalizeBinaryComponentStatus('Inactive'));
        System.assertEquals('Inactive', Clarity360DashboardController.normalizeBinaryComponentStatus('InvalidDraft'));
        System.assertEquals('Inactive', Clarity360DashboardController.normalizeBinaryComponentStatus('Draft'));
        System.assertEquals('Inactive', Clarity360DashboardController.normalizeBinaryComponentStatus(null));
        System.assertEquals('Inactive', Clarity360DashboardController.normalizeGlobalComponentStatus('Flow', 'InvalidDraft'));
        System.assertEquals('Inactive | Coverage Pending', Clarity360DashboardController.normalizeGlobalComponentStatus('Trigger', 'Draft | Coverage Pending'));
        System.assertEquals('86.00%', Clarity360DashboardController.normalizeGlobalComponentStatus('Apex Class', '86.00%'));
        System.assertEquals('Coverage Pending', Clarity360DashboardController.normalizeGlobalComponentStatus('Apex Class', null));
        System.assertEquals('18%', Clarity360DashboardController.formatCoverageLabel('18.181818181818181818'));
        System.assertEquals('50%', Clarity360DashboardController.formatCoverageLabel('50'));

        System.assertEquals(
            'Inactive',
            Clarity360DashboardController.deriveWorkflowRuleStatus(new Map<String, Object>()),
            'Workflow rules without active metadata should collapse to Inactive.'
        );
    }

    @IsTest
    static void runUsageScanV2ReturnsOperationEnvelope() {
        ensureSetupComplete();
        Test.startTest();
        Clarity360DashboardController.OperationResult result = Clarity360DashboardController.runUsageScanV2('req-1');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null.');
        System.assertEquals(true, result.success, 'Envelope should indicate success.');
        System.assertEquals('USAGE_SCAN_QUEUED', result.messageCode);
    }

    @IsTest
    static void runInventoryAndFullScanReturnOperationEnvelopes() {
        ensureSetupComplete();
        ScanOrchestrator.skipUsageBatchInTests = true;

        Test.startTest();
        Clarity360DashboardController.OperationResult inventoryResult =
            Clarity360DashboardController.runInventoryRefreshV2('inventory-1');
        Clarity360DashboardController.OperationResult fullScanResult =
            Clarity360DashboardController.runFullScanV2('full-1', false, null);
        Test.stopTest();

        System.assertEquals(true, inventoryResult.success);
        System.assertEquals('INVENTORY_SCAN_QUEUED', inventoryResult.messageCode);
        System.assertEquals(true, fullScanResult.success);
        System.assertEquals('FULL_SCAN_QUEUED', fullScanResult.messageCode);
        ScanOrchestrator.skipUsageBatchInTests = false;
    }

    @IsTest
    static void recommendationFilteringAndSignalLookupReturnExpectedRows() {
        ensureSetupComplete();

        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c'
        );
        insert inventory;

        insert new Recommendation__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            Action__c = 'Deprecate',
            ConfidenceScore__c = 90,
            RiskScore__c = 80,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'Legacy field'
        );
        insert new UsageSignal__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            SampleSize__c = 10,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            LastObservedOn__c = System.now(),
            EvidenceSummary__c = 'HasData=false'
        );

        Test.startTest();
        List<Clarity360DashboardController.RecommendationRow> filtered =
            Clarity360DashboardController.getRecommendations('Deprecate', 'Open', 'Account', 10);
        List<UsageSignal__c> signals = Clarity360DashboardController.getSignalsForField(inventory.FieldKey__c);
        Test.stopTest();

        System.assertEquals(1, filtered.size());
        System.assertEquals(inventory.FieldKey__c, filtered[0].fieldKey);
        System.assertEquals(1, signals.size());
    }

    @IsTest
    static void monitoringDetailSupportsSalesforceSignalAndAsyncTodayViews() {
        Test.startTest();
        Clarity360DashboardController.MonitoringDetail asyncToday =
            Clarity360DashboardController.getMonitoringDetail('asyncToday', 'today');
        Clarity360DashboardController.MonitoringDetail scheduledJobs =
            Clarity360DashboardController.getMonitoringDetail('salesforceSignal', 'scheduled-jobs');
        Test.stopTest();

        System.assertEquals('asyncToday', asyncToday.detailType);
        System.assert(asyncToday.items.size() >= 1);
        System.assertEquals('salesforceSignal', scheduledJobs.detailType);
        System.assertEquals('Scheduled Jobs', scheduledJobs.title);
    }

    @IsTest
    static void globalComponentSectionsGroupRowsByType() {
        Clarity360DashboardController.GlobalComponentRow validationRow = new Clarity360DashboardController.GlobalComponentRow();
        validationRow.key = 'Validation Rule|LegacyRule|Account';
        validationRow.fieldKey = 'GLOBAL.VALRULE.LegacyRule';
        validationRow.componentType = 'Validation Rule';
        validationRow.componentName = 'LegacyRule';
        validationRow.status = 'Inactive';
        validationRow.objectName = 'Account';

        Clarity360DashboardController.GlobalComponentRow flowRow = new Clarity360DashboardController.GlobalComponentRow();
        flowRow.key = 'Flow|LegacyFlow|';
        flowRow.fieldKey = 'GLOBAL.FLOW.LegacyFlow';
        flowRow.componentType = 'Flow';
        flowRow.componentName = 'LegacyFlow';
        flowRow.status = 'Inactive';

        Clarity360DashboardController.testGlobalComponents =
            new List<Clarity360DashboardController.GlobalComponentRow>{ validationRow, flowRow };

        Test.startTest();
        List<Clarity360DashboardController.GlobalComponentSection> sections =
            Clarity360DashboardController.getGlobalComponentSections(10);
        Test.stopTest();

        System.assertEquals(2, sections.size());
        System.assertEquals(true, sections[0].count >= 1);
        Clarity360DashboardController.testGlobalComponents = null;
    }

    @IsTest
    static void getGlobalComponentsLoadsRealInventoryPaths() {
        ensureSetupComplete();
        ApexTrigger existingTrigger = [SELECT Id, Name, Status FROM ApexTrigger LIMIT 1];

        ToolingApiService.ToolingQueryResult triggerResult = new ToolingApiService.ToolingQueryResult();
        triggerResult.records.add(new Map<String, Object>{
            'Id' => existingTrigger.Id,
            'Name' => existingTrigger.Name,
            'Status' => String.valueOf(existingTrigger.Status)
        });
        ToolingApiService.ToolingQueryResult validationResult = new ToolingApiService.ToolingQueryResult();
        validationResult.records.add(new Map<String, Object>{
            'Id' => '03d000000000091',
            'ValidationName' => 'Legacy Validation',
            'Active' => false,
            'EntityDefinition' => new Map<String, Object>{ 'QualifiedApiName' => 'Account' }
        });
        ToolingApiService.ToolingQueryResult flowResult = new ToolingApiService.ToolingQueryResult();
        flowResult.records.add(new Map<String, Object>{
            'Id' => '301000000000091',
            'MasterLabel' => 'Legacy Flow',
            'Status' => 'Draft',
            'ProcessType' => 'Flow',
            'VersionNumber' => 1
        });
        flowResult.records.add(new Map<String, Object>{
            'Id' => '301000000000092',
            'MasterLabel' => 'Legacy Flow',
            'Status' => 'Active',
            'ProcessType' => 'Flow',
            'VersionNumber' => 2
        });
        ToolingApiService.ToolingQueryResult workflowResult = new ToolingApiService.ToolingQueryResult();
        workflowResult.records.add(new Map<String, Object>{
            'Id' => '04a000000000091',
            'Name' => 'Legacy Workflow',
            'TableEnumOrId' => 'Account',
            'Metadata' => new Map<String, Object>{ 'active' => true }
        });
        ToolingApiService.ToolingQueryResult emptyResult = new ToolingApiService.ToolingQueryResult();
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            triggerResult,
            emptyResult,
            emptyResult,
            validationResult,
            flowResult,
            workflowResult,
            emptyResult,
            emptyResult,
            triggerResult,
            emptyResult,
            emptyResult,
            validationResult,
            flowResult,
            workflowResult,
            emptyResult,
            emptyResult
        });

        Test.startTest();
        List<Clarity360DashboardController.GlobalComponentRow> rows =
            Clarity360DashboardController.getGlobalComponents(50);
        List<Clarity360DashboardController.GlobalComponentSection> sections =
            Clarity360DashboardController.getGlobalComponentSections(50);
        Test.stopTest();

        System.assert(!rows.isEmpty());
        Set<String> componentTypes = new Set<String>();
        for (Clarity360DashboardController.GlobalComponentRow row : rows) {
            componentTypes.add(row.componentType);
        }
        System.assert(componentTypes.contains('Trigger'));
        System.assert(componentTypes.contains('Validation Rule'));
        System.assert(componentTypes.contains('Flow'));
        System.assert(componentTypes.contains('Workflow Rule'));
        System.assert(componentTypes.contains('Apex Class'));
        System.assert(!sections.isEmpty());

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void getMetadataComponentsFiltersAndBuildsActionText() {
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.CMDT.LegacyConfig__mdt',
            ComponentType__c = 'Custom Metadata Type',
            ApiName__c = 'LegacyConfig__mdt',
            DisplayName__c = 'LegacyConfig__mdt',
            ReferenceCount__c = 0,
            MonitoringEligible__c = false,
            IsActive__c = true,
            LastScannedOn__c = System.now()
        );
        insert new MetadataComponentInventory__c(
            ComponentKey__c = 'META.PEVENT.Signal_Event__e',
            ComponentType__c = 'Platform Event',
            ApiName__c = 'Signal_Event__e',
            DisplayName__c = 'Signal Event',
            ReferenceCount__c = 0,
            ActiveSubscriberCount__c = 0,
            ActivePublisherCount__c = 1,
            MonitoringEligible__c = true,
            IsActive__c = true,
            LastScannedOn__c = System.now(),
            SourceSummary__c = 'Discovery=Describe'
        );

        Test.startTest();
        List<Clarity360DashboardController.MetadataComponentRow> filtered =
            Clarity360DashboardController.getMetadataComponents('Platform Event<script>', 10);
        Test.stopTest();

        System.assertEquals(1, filtered.size());
        System.assertEquals('Platform Event', filtered[0].componentType);
        System.assert(filtered[0].whyVisible.contains('publisher'));
        System.assert(!String.isBlank(filtered[0].nextStep));
    }

    @IsTest
    static void deleteCustomFieldDeletesWhenEligible() {
        ensureSetupComplete();
        String fieldKey = 'Account.Legacy_Flag__c';
        insert new FieldInventory__c(FieldKey__c = fieldKey, ObjectApiName__c = 'Account', FieldApiName__c = 'Legacy_Flag__c');
        insert new UsageSignal__c(
            FieldKey__c = fieldKey,
            SampleSize__c = 100,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            LastObservedOn__c = System.now(),
            EvidenceSummary__c =
                'HasData=false; ActiveTriggerRefs=0; InactiveTriggerRefs=0; ' +
                'ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ApexClassRefs=0'
        );
        insert new Recommendation__c(FieldKey__c = fieldKey, Status__c = 'Open');

        ToolingApiService.ToolingQueryResult queryResult = new ToolingApiService.ToolingQueryResult();
        queryResult.records.add(new Map<String, Object>{
            'MetadataComponentId' => '00N000000000001',
            'NamespacePrefix' => null
        });
        ToolingApiService.ToolingMutationResult deleteResult = new ToolingApiService.ToolingMutationResult();
        deleteResult.success = true;
        deleteResult.statusCode = 204;
        ToolingApiService.setTestQueryResult(queryResult);
        ToolingApiService.setTestDeleteResult(deleteResult);

        Test.startTest();
        Clarity360DashboardController.FieldDeleteResult result = Clarity360DashboardController.deleteCustomField(fieldKey);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Delete should succeed.');
        System.assertEquals(true, result.deleted, 'Delete flag should be true.');
        System.assertEquals(0, [SELECT COUNT() FROM UsageSignal__c WHERE FieldKey__c = :fieldKey]);
        System.assertEquals(0, [SELECT COUNT() FROM Recommendation__c WHERE FieldKey__c = :fieldKey]);
        System.assertEquals(0, [SELECT COUNT() FROM FieldInventory__c WHERE FieldKey__c = :fieldKey]);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void deleteCustomFieldBlocksWhenInUse() {
        ensureSetupComplete();
        String fieldKey = 'Account.Legacy_Flag__c';
        insert new UsageSignal__c(
            FieldKey__c = fieldKey,
            SampleSize__c = 100,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            LastObservedOn__c = System.now(),
            EvidenceSummary__c = 'HasData=false; ActiveTriggerRefs=1; InactiveTriggerRefs=0; ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ApexClassRefs=0'
        );

        Test.startTest();
        Clarity360DashboardController.FieldDeleteResult result = Clarity360DashboardController.deleteCustomField(fieldKey);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Delete should be blocked when field is referenced.');
        System.assertEquals(false, result.deleted, 'Delete flag should remain false.');
        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void getFieldDetailEvidenceReturnsLayoutNames() {
        ensureSetupComplete();
        Clarity360SetupConfig__c config = [SELECT Id, EnableLayoutScan__c FROM Clarity360SetupConfig__c LIMIT 1];
        config.EnableLayoutScan__c = true;
        update config;
        Clarity360Settings.resetCache();

        String fieldKey = 'Account.Legacy_Flag__c';
        insert new FieldInventory__c(
            FieldKey__c = fieldKey,
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c'
        );
        insert new UsageSignal__c(
            FieldKey__c = fieldKey,
            SampleSize__c = 50,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            LastObservedOn__c = System.now(),
            EvidenceSummary__c = 'HasData=false; IsOnLayout=false'
        );

        LayoutScanService.setTestMetadataByLayoutName(new Map<String, Object>{
            'Account Layout' => new Map<String, Object>{
                'layoutSections' => new List<Object>{
                    new Map<String, Object>{
                        'layoutColumns' => new List<Object>{
                            new Map<String, Object>{
                                'layoutItems' => new List<Object>{
                                    new Map<String, Object>{ 'field' => 'Legacy_Flag__c' }
                                }
                            }
                        }
                    }
                }
            }
        });

        Test.startTest();
        Clarity360DashboardController.FieldDetailEvidence detail =
            Clarity360DashboardController.getFieldDetailEvidence(fieldKey);
        Test.stopTest();

        System.assertEquals(true, detail.isOnLayout);
        System.assertEquals(1, detail.signalHistoryCount);
        System.assertEquals(true, detail.layoutNames.contains('Account Layout'));

        LayoutScanService.clearTestOverrides();
    }

    @IsTest
    static void runAgentActionTestExplainRecommendationReturnsResult() {
        ensureSetupComplete();

        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c'
        );
        insert inventory;

        Recommendation__c rec = new Recommendation__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            Action__c = 'Deprecate',
            ConfidenceScore__c = 90,
            RiskScore__c = 88,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'Unused and not present on active layouts.'
        );
        insert rec;

        Test.startTest();
        List<Clarity360DashboardController.AgentActionTestResult> results =
            Clarity360DashboardController.runAgentActionTest(
                'ExplainRecommendation',
                rec.Id,
                null,
                null,
                null,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One explain result should be returned.');
        System.assertEquals('Deprecate', results[0].action);
        System.assertEquals('Open', results[0].status);
        System.assertEquals(rec.Id, results[0].recommendationId);
    }

    @IsTest
    static void runAgentActionTestHighRiskAndRecentSummaryReturnResults() {
        ensureSetupComplete();

        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Obsolete_Code__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Obsolete_Code__c'
        );
        insert inventory;

        insert new UsageSignal__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            SampleSize__c = 200,
            NonNullCount__c = 0,
            NullRatePct__c = 100,
            IsOnLayout__c = false,
            LastObservedOn__c = System.now(),
            EvidenceSummary__c = 'Sampled=200; NonNull=0; HasData=false'
        );

        insert new Recommendation__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            Action__c = 'Deprecate',
            ConfidenceScore__c = 95,
            RiskScore__c = 92,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'High risk and low observed usage.'
        );

        insert new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-30),
            FinishedOn__c = System.now().addMinutes(-20),
            ScopeSummary__c = 'Scanned Account usage.',
            ProgressPct__c = 100
        );

        Test.startTest();
        List<Clarity360DashboardController.AgentActionTestResult> highRiskResults =
            Clarity360DashboardController.runAgentActionTest(
                'GetHighRiskRecommendations',
                null,
                null,
                70,
                5,
                'Open',
                null
            );
        List<Clarity360DashboardController.AgentActionTestResult> summaryResults =
            Clarity360DashboardController.runAgentActionTest(
                'GetRecentScanSummary',
                null,
                null,
                null,
                null,
                null,
                30
            );
        Test.stopTest();

        System.assert(!highRiskResults.isEmpty(), 'High risk action should return at least one row.');
        System.assertEquals('Open', highRiskResults[0].status);
        System.assert(highRiskResults[0].riskScore >= 70);

        System.assert(!summaryResults.isEmpty(), 'Recent scan summary should return at least one row.');
        System.assertEquals('Completed', summaryResults[0].status);
    }

    @IsTest
    static void getAgentAssistantAvailabilityReturnsEnvelope() {
        Test.startTest();
        Clarity360DashboardController.AgentAssistantAvailability availability =
            Clarity360DashboardController.getAgentAssistantAvailability();
        Test.stopTest();

        System.assertNotEquals(null, availability, 'Availability envelope should be returned.');
        System.assertNotEquals(null, availability.available, 'Availability flag should be set.');
        System.assert(!String.isBlank(availability.mode), 'Mode should be populated.');
        System.assert(!String.isBlank(availability.message), 'Message should be populated.');
    }

    @IsTest
    static void askAgentAssistantReturnsSimpleEnglishResponse() {
        ensureSetupComplete();

        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Code__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Code__c'
        );
        insert inventory;

        insert new Recommendation__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            Action__c = 'Deprecate',
            ConfidenceScore__c = 90,
            RiskScore__c = 85,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'Field is unused in sampled data.'
        );

        Test.startTest();
        Clarity360DashboardController.AgentAssistantChatResponse response =
            Clarity360DashboardController.askAgentAssistant('Explain Account.Legacy_Code__c', null);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Chat response should not be null.');
        System.assertEquals('Success', response.status);
        System.assertEquals('ExplainRecommendation', response.actionUsed);
        System.assert(response.responseText.contains('Reason'), 'Response should include explanation text.');
    }

    @IsTest
    static void askAgentAssistantSupportsClarificationFollowUp() {
        ensureSetupComplete();

        insert new Recommendation__c(
            FieldKey__c = 'GLOBAL.TRIGGER.AccountCleanupTrigger',
            Action__c = 'Deprecate',
            ConfidenceScore__c = 88,
            RiskScore__c = 76,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'ComponentType=Trigger; ComponentStatus=Inactive'
        );

        Test.startTest();
        Clarity360DashboardController.AgentAssistantChatResponse first =
            Clarity360DashboardController.askAgentAssistant('Can I delete inactive things?', null);
        Clarity360DashboardController.AgentAssistantChatResponse second =
            Clarity360DashboardController.askAgentAssistant('triggers', first.nextContext);
        Test.stopTest();

        System.assertEquals('Needs Clarification', first.status);
        System.assertEquals('deleteInactive', first.nextContext);
        System.assertEquals('GeneralRecommendations', second.actionUsed);
        System.assert(second.responseText.contains('recommendations for triggers'));
    }

    @IsTest
    static void askAgentAssistantAnswersGenericQuestionFromData() {
        ensureSetupComplete();

        insert new Recommendation__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            Action__c = 'Deprecate',
            ConfidenceScore__c = 81,
            RiskScore__c = 74,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'Field has no usage in sampled transactions.'
        );

        insert new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-5),
            FinishedOn__c = System.now().addMinutes(-1),
            ProgressPct__c = 100
        );

        Test.startTest();
        Clarity360DashboardController.AgentAssistantChatResponse response =
            Clarity360DashboardController.askAgentAssistant('What should I clean up in this app?', null);
        Test.stopTest();

        System.assertEquals('Success', response.status);
        System.assertEquals('AskClarity360Data', response.actionUsed);
        System.assert(response.responseText.contains('Here is what I found in your Clarity360 data'));
    }

    @IsTest
    static void askAgentAssistantReturnsScanSummaryResponse() {
        ensureSetupComplete();
        insert new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addDays(-2),
            FinishedOn__c = System.now().addDays(-2).addMinutes(10),
            ProgressPct__c = 100
        );

        Test.startTest();
        Clarity360DashboardController.AgentAssistantChatResponse response =
            Clarity360DashboardController.askAgentAssistant('show me the recent scan summary for the last 7 days', null);
        Test.stopTest();

        System.assertEquals('Success', response.status);
        System.assertEquals('GetRecentScanSummary', response.actionUsed);
        System.assert(response.responseText.contains('Latest scan'));
    }

    @IsTest
    static void askAgentAssistantReturnsHighRiskSummary() {
        ensureSetupComplete();
        insert new Recommendation__c(
            FieldKey__c = 'GLOBAL.TRIGGER.LegacyCleanupTrigger',
            Action__c = 'Investigate Dependencies',
            ConfidenceScore__c = 91,
            RiskScore__c = 92,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'ComponentType=Trigger; ComponentStatus=Inactive'
        );

        Test.startTest();
        Clarity360DashboardController.AgentAssistantChatResponse response =
            Clarity360DashboardController.askAgentAssistant('top 3 risky items above 80', null);
        Test.stopTest();

        System.assertEquals('Success', response.status);
        System.assertEquals('GetHighRiskRecommendations', response.actionUsed);
        System.assert(response.responseText.contains('high-risk'));
    }

    @IsTest
    static void askAgentAssistantHandlesBlankAndNoMatchQuestions() {
        ensureSetupComplete();

        Test.startTest();
        Clarity360DashboardController.AgentAssistantChatResponse blankResponse =
            Clarity360DashboardController.askAgentAssistant('   ', null);
        Clarity360DashboardController.AgentAssistantChatResponse noMatchResponse =
            Clarity360DashboardController.askAgentAssistant('tell me about obscure zebra metadata', null);
        Test.stopTest();

        System.assertEquals('Invalid Input', blankResponse.status);
        System.assertEquals('AskClarity360Data', noMatchResponse.actionUsed);
        System.assert(noMatchResponse.responseText.contains('could not find a direct match'));
    }
}
