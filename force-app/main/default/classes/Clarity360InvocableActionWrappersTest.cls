@IsTest
private class Clarity360InvocableActionWrappersTest {
    private static Recommendation__c seedRecommendation() {
        FieldInventory__c inventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c',
            DataType__c = 'Checkbox',
            IsActive__c = true,
            IsCustomField__c = true,
            IncludedInScope__c = true,
            LastScannedOn__c = System.now()
        );
        insert inventory;

        Recommendation__c recommendation = new Recommendation__c(
            FieldKey__c = inventory.FieldKey__c,
            FieldInventory__c = inventory.Id,
            Action__c = 'Deprecate',
            ConfidenceScore__c = 91,
            RiskScore__c = 88,
            Status__c = 'Open',
            LastEvaluatedOn__c = System.now(),
            EvidenceSummary__c = 'Unused in sampled records.'
        );
        insert recommendation;

        insert new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-20),
            FinishedOn__c = System.now().addMinutes(-10),
            ScopeSummary__c = 'Scanned Account',
            ProgressPct__c = 100
        );
        return recommendation;
    }

    @IsTest
    static void invocableWrappersMapAgentResponses() {
        Recommendation__c recommendation = seedRecommendation();

        Clarity360ExplainRecommendationAction.Request explainRequest =
            new Clarity360ExplainRecommendationAction.Request();
        explainRequest.recommendationId = recommendation.Id;

        Clarity360HighRiskRecsAction.Request highRiskRequest =
            new Clarity360HighRiskRecsAction.Request();
        highRiskRequest.minRiskScore = 70;
        highRiskRequest.maxResults = 5;
        highRiskRequest.statusFilter = 'Open';

        Clarity360GetRecentScanSummaryAction.Request summaryRequest =
            new Clarity360GetRecentScanSummaryAction.Request();
        summaryRequest.lookbackDays = 30;

        Test.startTest();
        List<Clarity360ExplainRecommendationAction.Response> explainResponses =
            Clarity360ExplainRecommendationAction.run(
                new List<Clarity360ExplainRecommendationAction.Request>{ explainRequest }
            );
        List<Clarity360HighRiskRecsAction.Response> highRiskResponses =
            Clarity360HighRiskRecsAction.run(
                new List<Clarity360HighRiskRecsAction.Request>{ highRiskRequest }
            );
        List<Clarity360GetRecentScanSummaryAction.Response> summaryResponses =
            Clarity360GetRecentScanSummaryAction.run(
                new List<Clarity360GetRecentScanSummaryAction.Request>{ summaryRequest }
            );
        Test.stopTest();

        System.assertEquals(1, explainResponses.size());
        System.assertEquals(recommendation.Id, explainResponses[0].recommendationId);
        System.assertEquals('Deprecate', explainResponses[0].action);

        System.assertEquals(1, highRiskResponses.size());
        System.assertEquals('Open', highRiskResponses[0].status);
        System.assert(highRiskResponses[0].riskScore >= 70);

        System.assertEquals(1, summaryResponses.size());
        System.assertEquals('Completed', summaryResponses[0].status);
        System.assertEquals('Usage Scan', summaryResponses[0].action);
    }
}
