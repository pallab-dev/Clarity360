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
    static void getRecentJobs_returnsPagedRows() {
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
    static void dashboardSummary_and_metadataRows_includeMetadataInventory() {
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
        System.assert(rows[0].whyVisible.contains('referenced'), 'Metadata row should explain why it is shown.');
        System.assert(!String.isBlank(rows[0].nextStep), 'Metadata row should include a next step.');
    }

    @IsTest
    static void getGlobalComponents_returnsInventoryRows() {
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
    static void runUsageScanV2_returnsOperationEnvelope() {
        ensureSetupComplete();
        Test.startTest();
        Clarity360DashboardController.OperationResult result = Clarity360DashboardController.runUsageScanV2('req-1');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null.');
        System.assertEquals(true, result.success, 'Envelope should indicate success.');
        System.assertEquals('USAGE_SCAN_QUEUED', result.messageCode);
    }

    @IsTest
    static void deleteCustomField_deletesWhenEligible() {
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
    static void deleteCustomField_blocksWhenInUse() {
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
    static void runAgentActionTest_explainRecommendation_returnsResult() {
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
    static void runAgentActionTest_highRiskAndRecentSummary_returnResults() {
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
    static void getAgentAssistantAvailability_returnsEnvelope() {
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
    static void askAgentAssistant_returnsSimpleEnglishResponse() {
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
    static void askAgentAssistant_supportsClarificationFollowUp() {
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
    static void askAgentAssistant_answersGenericQuestionFromData() {
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
}
