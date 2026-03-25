/**
 * @description Shared read-only action logic for Agentforce Admin Copilot.
 *
 * Note: Apex allows only one @InvocableMethod per class.
 * Thin wrapper classes expose each method as a separate Agentforce custom action.
 */
public with sharing class Clarity360AgentActions {
    private static final Integer DEFAULT_RESULT_LIMIT = 5;
    private static final Integer MAX_RESULT_LIMIT = 25;
    private static final Decimal DEFAULT_MIN_RISK = 70;
    private static final Set<String> ALLOWED_RECOMMENDATION_STATUSES = new Set<String>{
        'Open',
        'Accepted',
        'Dismissed'
    };

    /**
     * @description Request envelope for the explain recommendation action.
     */
    public class ExplainRecommendationRequest {
        @InvocableVariable(label='Recommendation Id' description='Recommendation__c record Id to explain.')
        public Id recommendationId;

        @InvocableVariable(label='Field Key' description='Fallback lookup key (for example: Account.Legacy_Flag__c).')
        public String fieldKey;
    }

    /**
     * @description Request envelope for the high-risk recommendations action.
     */
    public class GetHighRiskRecommendationsRequest {
        @InvocableVariable(label='Minimum Risk Score' description='Minimum recommendation risk score (0-100).')
        public Decimal minRiskScore;

        @InvocableVariable(label='Max Results' description='Max rows to return (1-25).')
        public Integer maxResults;

        @InvocableVariable(label='Recommendation Status' description='Optional status filter: Open, Accepted, or Dismissed.')
        public String statusFilter;
    }

    /**
     * @description Request envelope for the recent scan summary action.
     */
    public class GetRecentScanSummaryRequest {
        @InvocableVariable(label='Lookback Days' description='Only include data from the last N days (1-365).')
        public Integer lookbackDays;
    }

    /**
     * @description Unified response envelope returned by agent actions.
     */
    public class AgentActionResult {
        @InvocableVariable(label='Action')
        public String action;

        @InvocableVariable(label='Confidence Score')
        public Decimal confidenceScore;

        @InvocableVariable(label='Risk Score')
        public Decimal riskScore;

        @InvocableVariable(label='Explanation')
        public String explanation;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Summary')
        public String summary;

        @InvocableVariable(label='Recommendation Id')
        public Id recommendationId;

        @InvocableVariable(label='Field Key')
        public String fieldKey;
    }

    /**
     * @description Returns a human-readable explanation for a recommendation.
     * @param requests The recommendations to explain.
     * @return The action result envelopes for the supplied requests.
     */
    public static List<AgentActionResult> explainRecommendation(List<ExplainRecommendationRequest> requests) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(Recommendation__c.SObjectType, 'ExplainRecommendation');

        List<AgentActionResult> results = new List<AgentActionResult>();
        if (requests == null || requests.isEmpty()) {
            results.add(buildInvalidInputResult('ExplainRecommendation', 'No input provided.'));
            return results;
        }

        for (ExplainRecommendationRequest request : requests) {
            Recommendation__c row = findRecommendationForExplain(request);
            if (row == null) {
                AgentActionResult notFound = new AgentActionResult();
                notFound.action = 'ExplainRecommendation';
                notFound.status = 'Not Found';
                notFound.summary = 'No matching recommendation found.';
                notFound.explanation = 'Provide a valid Recommendation Id or Field Key.';
                results.add(notFound);
                continue;
            }

            AgentActionResult output = new AgentActionResult();
            output.action = safeString(row.Action__c, 'Unknown');
            output.confidenceScore = safeDecimal(row.ConfidenceScore__c, 0);
            output.riskScore = safeDecimal(row.RiskScore__c, 0);
            output.explanation = safeString(row.EvidenceSummary__c, 'No evidence summary captured for this recommendation.');
            output.status = safeString(row.Status__c, 'Unknown');
            output.summary = 'Recommendation for ' + safeString(row.FieldKey__c, 'unknown field') +
                ': action=' + output.action + ', status=' + output.status + '.';
            output.recommendationId = row.Id;
            output.fieldKey = row.FieldKey__c;
            results.add(output);
        }

        return results;
    }

    /**
     * @description Returns the highest-risk recommendations that match the supplied filters.
     * @param requests The high-risk recommendation requests.
     * @return The action result envelopes for the supplied requests.
     */
    public static List<AgentActionResult> getHighRiskRecommendations(List<GetHighRiskRecommendationsRequest> requests) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(Recommendation__c.SObjectType, 'GetHighRiskRecommendations');

        List<AgentActionResult> results = new List<AgentActionResult>();
        List<GetHighRiskRecommendationsRequest> safeRequests =
            (requests == null || requests.isEmpty()) ? new List<GetHighRiskRecommendationsRequest>{ new GetHighRiskRecommendationsRequest() } : requests;

        for (GetHighRiskRecommendationsRequest request : safeRequests) {
            Decimal minRiskScore = clampDecimal(request == null ? null : request.minRiskScore, DEFAULT_MIN_RISK, 0, 100);
            Integer rowLimit = clampInteger(request == null ? null : request.maxResults, DEFAULT_RESULT_LIMIT, 1, MAX_RESULT_LIMIT);
            String statusFilter = sanitizeRecommendationStatus(request == null ? null : request.statusFilter);

            List<Recommendation__c> rows;
            if (String.isBlank(statusFilter)) {
                rows = [
                    SELECT Id, FieldKey__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c
                    FROM Recommendation__c
                    WHERE RiskScore__c >= :minRiskScore
                    ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                    LIMIT :rowLimit
                ];
            } else {
                rows = [
                    SELECT Id, FieldKey__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c
                    FROM Recommendation__c
                    WHERE RiskScore__c >= :minRiskScore
                        AND Status__c = :statusFilter
                    ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                    LIMIT :rowLimit
                ];
            }

            if (rows.isEmpty()) {
                AgentActionResult noRows = new AgentActionResult();
                noRows.action = 'GetHighRiskRecommendations';
                noRows.status = 'No Data';
                noRows.summary = 'No recommendations matched the requested risk threshold.';
                noRows.explanation = 'Try a lower minimum risk score or remove status filtering.';
                results.add(noRows);
                continue;
            }

            for (Recommendation__c row : rows) {
                AgentActionResult output = new AgentActionResult();
                output.action = safeString(row.Action__c, 'Unknown');
                output.confidenceScore = safeDecimal(row.ConfidenceScore__c, 0);
                output.riskScore = safeDecimal(row.RiskScore__c, 0);
                output.explanation = safeString(row.EvidenceSummary__c, 'No evidence summary captured for this recommendation.');
                output.status = safeString(row.Status__c, 'Unknown');
                output.summary = 'High-risk recommendation for ' + safeString(row.FieldKey__c, 'unknown field') + '.';
                output.recommendationId = row.Id;
                output.fieldKey = row.FieldKey__c;
                results.add(output);
            }
        }

        return results;
    }

    /**
     * @description Returns a summary of the most recent scan activity.
     * @param requests The recent-scan summary requests.
     * @return The action result envelopes for the supplied requests.
     */
    public static List<AgentActionResult> getRecentScanSummary(List<GetRecentScanSummaryRequest> requests) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(ScanJob__c.SObjectType, 'GetRecentScanSummary');
        access.assertReadable(Recommendation__c.SObjectType, 'GetRecentScanSummary');
        access.assertReadable(UsageSignal__c.SObjectType, 'GetRecentScanSummary');

        List<AgentActionResult> results = new List<AgentActionResult>();
        List<GetRecentScanSummaryRequest> safeRequests =
            (requests == null || requests.isEmpty()) ? new List<GetRecentScanSummaryRequest>{ new GetRecentScanSummaryRequest() } : requests;

        for (GetRecentScanSummaryRequest request : safeRequests) {
            Integer lookbackDays = clampInteger(request == null ? null : request.lookbackDays, 30, 1, 365);
            Datetime lookbackStart = System.now().addDays(-lookbackDays);

            List<ScanJob__c> latestJobs = [
                SELECT Id, JobType__c, Status__c, StartedOn__c, FinishedOn__c, ScopeSummary__c, ErrorMessage__c
                FROM ScanJob__c
                WHERE CreatedDate >= :lookbackStart
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (latestJobs.isEmpty()) {
                AgentActionResult noScan = new AgentActionResult();
                noScan.action = 'GetRecentScanSummary';
                noScan.status = 'No Data';
                noScan.summary = 'No scan jobs found in the last ' + String.valueOf(lookbackDays) + ' day(s).';
                noScan.explanation = 'Run Inventory Refresh or Usage Scan to generate fresh scan telemetry.';
                results.add(noScan);
                continue;
            }

            ScanJob__c latestJob = latestJobs[0];
            Integer openRecommendations = [
                SELECT COUNT()
                FROM Recommendation__c
                WHERE Status__c = 'Open' AND LastEvaluatedOn__c >= :lookbackStart
            ];
            Integer highRiskOpenRecommendations = [
                SELECT COUNT()
                FROM Recommendation__c
                WHERE Status__c = 'Open'
                    AND RiskScore__c >= :DEFAULT_MIN_RISK
                    AND LastEvaluatedOn__c >= :lookbackStart
            ];
            Integer usageSignals = [
                SELECT COUNT()
                FROM UsageSignal__c
                WHERE LastObservedOn__c >= :lookbackStart
            ];
            AggregateResult avgRiskResult = [
                SELECT AVG(RiskScore__c) avgRisk
                FROM Recommendation__c
                WHERE Status__c = 'Open' AND LastEvaluatedOn__c >= :lookbackStart
            ];

            Decimal avgRisk = safeDecimal((Decimal) avgRiskResult.get('avgRisk'), 0);
            String fallbackExplanation = String.isBlank(latestJob.ErrorMessage__c)
                ? safeString(latestJob.ScopeSummary__c, 'No scope summary captured.')
                : latestJob.ErrorMessage__c;

            AgentActionResult output = new AgentActionResult();
            output.action = safeString(latestJob.JobType__c, 'Unknown');
            output.confidenceScore = 100;
            output.riskScore = avgRisk;
            output.explanation = fallbackExplanation;
            output.status = safeString(latestJob.Status__c, 'Unknown');
            output.summary =
                'Latest scan: ' + output.action +
                ' (' + output.status + '). Open recommendations=' + String.valueOf(openRecommendations) +
                ', high-risk open recommendations=' + String.valueOf(highRiskOpenRecommendations) +
                ', usage signals observed=' + String.valueOf(usageSignals) + '.';
            results.add(output);
        }

        return results;
    }

    private static Recommendation__c findRecommendationForExplain(ExplainRecommendationRequest request) {
        if (request == null) {
            return null;
        }
        if (request.recommendationId != null) {
            List<Recommendation__c> byId = [
                SELECT Id, FieldKey__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c
                FROM Recommendation__c
                WHERE Id = :request.recommendationId
                LIMIT 1
            ];
            return byId.isEmpty() ? null : byId[0];
        }
        if (String.isBlank(request.fieldKey)) {
            return null;
        }

        List<Recommendation__c> byFieldKey = [
            SELECT Id, FieldKey__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c
            FROM Recommendation__c
            WHERE FieldKey__c = :request.fieldKey
            ORDER BY LastEvaluatedOn__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        return byFieldKey.isEmpty() ? null : byFieldKey[0];
    }

    private static AgentActionResult buildInvalidInputResult(String actionName, String message) {
        AgentActionResult output = new AgentActionResult();
        output.action = actionName;
        output.status = 'Invalid Input';
        output.summary = message;
        output.explanation = 'Verify the action inputs and try again.';
        output.confidenceScore = 0;
        output.riskScore = 0;
        return output;
    }

    private static String sanitizeRecommendationStatus(String statusFilter) {
        if (String.isBlank(statusFilter)) {
            return null;
        }
        String trimmed = statusFilter.trim();
        if (ALLOWED_RECOMMENDATION_STATUSES.contains(trimmed)) {
            return trimmed;
        }
        return null;
    }

    private static Decimal clampDecimal(Decimal value, Decimal defaultValue, Decimal minValue, Decimal maxValue) {
        Decimal safeValue = (value == null) ? defaultValue : value;
        if (safeValue < minValue) {
            return minValue;
        }
        if (safeValue > maxValue) {
            return maxValue;
        }
        return safeValue;
    }

    private static Integer clampInteger(Integer value, Integer defaultValue, Integer minValue, Integer maxValue) {
        Integer safeValue = (value == null) ? defaultValue : value;
        if (safeValue < minValue) {
            return minValue;
        }
        if (safeValue > maxValue) {
            return maxValue;
        }
        return safeValue;
    }

    private static Decimal safeDecimal(Decimal value, Decimal fallbackValue) {
        return (value == null) ? fallbackValue : value;
    }

    private static String safeString(String value, String fallbackValue) {
        return String.isBlank(value) ? fallbackValue : value;
    }
}
