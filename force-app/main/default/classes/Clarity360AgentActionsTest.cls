@IsTest
private class Clarity360AgentActionsTest {
    private class TestDataBundle {
        Id highRiskRecommendationId;
        String highRiskFieldKey;
    }

    private static TestDataBundle seedData() {
        FieldInventory__c highRiskInventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c',
            DataType__c = 'Checkbox',
            IsActive__c = true,
            IsCustomField__c = true,
            IncludedInScope__c = true,
            LastScannedOn__c = System.now()
        );
        FieldInventory__c mediumRiskInventory = new FieldInventory__c(
            FieldKey__c = 'Account.Optional_Code__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Optional_Code__c',
            DataType__c = 'Text',
            IsActive__c = true,
            IsCustomField__c = true,
            IncludedInScope__c = true,
            LastScannedOn__c = System.now()
        );
        insert new List<FieldInventory__c>{ highRiskInventory, mediumRiskInventory };

        insert new List<UsageSignal__c>{
            new UsageSignal__c(
                FieldKey__c = highRiskInventory.FieldKey__c,
                FieldInventory__c = highRiskInventory.Id,
                SampleSize__c = 500,
                NonNullCount__c = 0,
                NullRatePct__c = 100,
                IsOnLayout__c = false,
                LastObservedOn__c = System.now().addHours(-1),
                EvidenceSummary__c = 'Sampled=500; NonNull=0; HasData=false; ActiveTriggerRefs=0; ApexClassRefs=0'
            ),
            new UsageSignal__c(
                FieldKey__c = mediumRiskInventory.FieldKey__c,
                FieldInventory__c = mediumRiskInventory.Id,
                SampleSize__c = 300,
                NonNullCount__c = 250,
                NullRatePct__c = 16.67,
                IsOnLayout__c = true,
                LastObservedOn__c = System.now().addHours(-2),
                EvidenceSummary__c = 'Sampled=300; NonNull=250; HasData=true; ActiveTriggerRefs=1; ApexClassRefs=2'
            )
        };

        Recommendation__c highRiskRecommendation = new Recommendation__c(
            FieldKey__c = highRiskInventory.FieldKey__c,
            FieldInventory__c = highRiskInventory.Id,
            Action__c = 'Deprecate',
            ConfidenceScore__c = 95,
            RiskScore__c = 92,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now().addHours(-1),
            EvidenceSummary__c = 'Unused for sampled records and not on active layouts.'
        );
        Recommendation__c mediumRiskRecommendation = new Recommendation__c(
            FieldKey__c = mediumRiskInventory.FieldKey__c,
            FieldInventory__c = mediumRiskInventory.Id,
            Action__c = 'Keep',
            ConfidenceScore__c = 82,
            RiskScore__c = 25,
            Status__c = 'Accepted',
            LastEvaluatedOn__c = System.now().addHours(-3),
            EvidenceSummary__c = 'Field is frequently used and appears on layouts.'
        );
        insert new List<Recommendation__c>{ highRiskRecommendation, mediumRiskRecommendation };

        insert new List<ScanJob__c>{
            new ScanJob__c(
                JobType__c = 'Usage Scan',
                Status__c = 'Completed',
                StartedOn__c = System.now().addHours(-2),
                FinishedOn__c = System.now().addHours(-1),
                ScopeSummary__c = 'Scanned Account and Contact with 800 sampled records.',
                ProgressPct__c = 100
            ),
            new ScanJob__c(
                JobType__c = 'Recommendation Rebuild',
                Status__c = 'Completed',
                StartedOn__c = System.now().addMinutes(-30),
                FinishedOn__c = System.now().addMinutes(-20),
                ScopeSummary__c = 'Rebuilt recommendations from latest usage signals.',
                ProgressPct__c = 100
            )
        };

        List<ScanJob__c> jobs = [
            SELECT Id, JobType__c
            FROM ScanJob__c
            WHERE JobType__c IN ('Usage Scan', 'Recommendation Rebuild')
        ];
        for (ScanJob__c job : jobs) {
            if (job.JobType__c == 'Usage Scan') {
                Test.setCreatedDate(job.Id, System.now().addHours(-2));
            } else if (job.JobType__c == 'Recommendation Rebuild') {
                Test.setCreatedDate(job.Id, System.now().addMinutes(-30));
            }
        }

        TestDataBundle bundle = new TestDataBundle();
        bundle.highRiskRecommendationId = highRiskRecommendation.Id;
        bundle.highRiskFieldKey = highRiskRecommendation.FieldKey__c;
        return bundle;
    }

    @IsTest
    static void explainRecommendationReturnsStructuredRowForRecommendationId() {
        TestDataBundle bundle = seedData();

        Clarity360AgentActions.ExplainRecommendationRequest request =
            new Clarity360AgentActions.ExplainRecommendationRequest();
        request.recommendationId = bundle.highRiskRecommendationId;

        Test.startTest();
        List<Clarity360AgentActions.AgentActionResult> results =
            Clarity360AgentActions.explainRecommendation(
                new List<Clarity360AgentActions.ExplainRecommendationRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One action result should be returned.');
        System.assertEquals('Deprecate', results[0].action, 'The action should reflect the recommendation action.');
        System.assertEquals('Open', results[0].status, 'The recommendation status should be preserved.');
        System.assertEquals(bundle.highRiskRecommendationId, results[0].recommendationId, 'The recommendation Id should match the seeded record.');
        System.assert(results[0].summary.contains(bundle.highRiskFieldKey), 'The summary should mention the high-risk field key.');
    }

    @IsTest
    static void explainRecommendationIsNullSafeForMissingInput() {
        Test.startTest();
        List<Clarity360AgentActions.AgentActionResult> results =
            Clarity360AgentActions.explainRecommendation(null);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'A null input should return a single envelope.');
        System.assertEquals('Invalid Input', results[0].status, 'The status should explain the invalid input.');
        System.assertEquals('ExplainRecommendation', results[0].action, 'The action should indicate the request type.');
    }

    @IsTest
    static void getHighRiskRecommendationsFiltersAndReturnsRows() {
        seedData();

        Clarity360AgentActions.GetHighRiskRecommendationsRequest request =
            new Clarity360AgentActions.GetHighRiskRecommendationsRequest();
        request.minRiskScore = 70;
        request.maxResults = 10;
        request.statusFilter = 'Open';

        Test.startTest();
        List<Clarity360AgentActions.AgentActionResult> results =
            Clarity360AgentActions.getHighRiskRecommendations(
                new List<Clarity360AgentActions.GetHighRiskRecommendationsRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One recommendation should match the filters.');
        System.assertEquals('Open', results[0].status, 'The returned recommendation should remain open.');
        System.assert(results[0].riskScore >= 70, 'The returned recommendation should satisfy the minimum risk score.');
        System.assertEquals('Deprecate', results[0].action, 'The recommended action should match the seeded data.');
    }

    @IsTest
    static void getHighRiskRecommendationsReturnsNoDataEnvelopeWhenNoRowsMatch() {
        seedData();

        Clarity360AgentActions.GetHighRiskRecommendationsRequest request =
            new Clarity360AgentActions.GetHighRiskRecommendationsRequest();
        request.minRiskScore = 99;
        request.statusFilter = 'Dismissed';

        Test.startTest();
        List<Clarity360AgentActions.AgentActionResult> results =
            Clarity360AgentActions.getHighRiskRecommendations(
                new List<Clarity360AgentActions.GetHighRiskRecommendationsRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One envelope should be returned when no rows match.');
        System.assertEquals('No Data', results[0].status, 'The status should indicate no rows matched.');
        System.assertEquals('GetHighRiskRecommendations', results[0].action, 'The action should identify the request type.');
    }

    @IsTest
    static void getRecentScanSummaryReturnsLatestJobSummary() {
        seedData();

        Clarity360AgentActions.GetRecentScanSummaryRequest request =
            new Clarity360AgentActions.GetRecentScanSummaryRequest();
        request.lookbackDays = 30;

        Test.startTest();
        List<Clarity360AgentActions.AgentActionResult> results =
            Clarity360AgentActions.getRecentScanSummary(
                new List<Clarity360AgentActions.GetRecentScanSummaryRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One summary envelope should be returned.');
        System.assertEquals('Completed', results[0].status, 'The latest job should be marked completed.');
        System.assertEquals('Recommendation Rebuild', results[0].action, 'The most recent job should be returned.');
        System.assert(results[0].summary.contains('Open recommendations=1'), 'The summary should include the open recommendation count.');
    }

    @IsTest
    static void getRecentScanSummaryReturnsNoDataWhenLookbackExcludesJobs() {
        insert new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addDays(-15),
            FinishedOn__c = System.now().addDays(-15).addHours(1),
            ScopeSummary__c = 'Old run',
            ProgressPct__c = 100
        );
        ScanJob__c oldJob = [
            SELECT Id
            FROM ScanJob__c
            WHERE ScopeSummary__c = 'Old run'
            LIMIT 1
        ];
        Test.setCreatedDate(oldJob.Id, System.now().addDays(-15));

        Clarity360AgentActions.GetRecentScanSummaryRequest request =
            new Clarity360AgentActions.GetRecentScanSummaryRequest();
        request.lookbackDays = 1;

        Test.startTest();
        List<Clarity360AgentActions.AgentActionResult> results =
            Clarity360AgentActions.getRecentScanSummary(
                new List<Clarity360AgentActions.GetRecentScanSummaryRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One envelope should be returned.');
        System.assertEquals('No Data', results[0].status, 'Lookback should exclude the old job.');
        System.assertEquals('GetRecentScanSummary', results[0].action, 'The action should identify the summary request.');
    }
}
