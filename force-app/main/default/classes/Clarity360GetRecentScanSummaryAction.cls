public with sharing class Clarity360GetRecentScanSummaryAction {
    public class Request {
        @InvocableVariable(label='Lookback Days' description='Only include data from the last N days (1-365).')
        public Integer lookbackDays;
    }

    public class Response {
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

    @InvocableMethod(
        label='Get Recent Scan Summary'
        description='Returns a summary of the latest Clarity360 scan activity and recommendation posture.'
    )
    public static List<Response> run(
        List<Request> requests
    ) {
        List<Clarity360AgentActions.GetRecentScanSummaryRequest> coreRequests =
            new List<Clarity360AgentActions.GetRecentScanSummaryRequest>();
        if (requests != null) {
            for (Request request : requests) {
                Clarity360AgentActions.GetRecentScanSummaryRequest coreRequest =
                    new Clarity360AgentActions.GetRecentScanSummaryRequest();
                coreRequest.lookbackDays = (request == null) ? null : request.lookbackDays;
                coreRequests.add(coreRequest);
            }
        }

        List<Clarity360AgentActions.AgentActionResult> coreResults =
            Clarity360AgentActions.getRecentScanSummary(coreRequests);
        return mapResults(coreResults);
    }

    private static List<Response> mapResults(List<Clarity360AgentActions.AgentActionResult> coreResults) {
        List<Response> responses = new List<Response>();
        if (coreResults == null) {
            return responses;
        }

        for (Clarity360AgentActions.AgentActionResult core : coreResults) {
            Response response = new Response();
            response.action = (core == null) ? null : core.action;
            response.confidenceScore = (core == null) ? null : core.confidenceScore;
            response.riskScore = (core == null) ? null : core.riskScore;
            response.explanation = (core == null) ? null : core.explanation;
            response.status = (core == null) ? null : core.status;
            response.summary = (core == null) ? null : core.summary;
            response.recommendationId = (core == null) ? null : core.recommendationId;
            response.fieldKey = (core == null) ? null : core.fieldKey;
            responses.add(response);
        }
        return responses;
    }
}
