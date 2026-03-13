public with sharing class Clarity360HighRiskRecsAction {
    public class Request {
        @InvocableVariable(label='Minimum Risk Score' description='Minimum recommendation risk score (0-100).')
        public Decimal minRiskScore;

        @InvocableVariable(label='Max Results' description='Max rows to return (1-25).')
        public Integer maxResults;

        @InvocableVariable(label='Recommendation Status' description='Optional status filter: Open, Accepted, or Dismissed.')
        public String statusFilter;
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
        label='Get High Risk Recommendations'
        description='Returns the highest risk Clarity360 recommendations for admin follow-up.'
    )
    public static List<Response> run(
        List<Request> requests
    ) {
        List<Clarity360AgentActions.GetHighRiskRecommendationsRequest> coreRequests =
            new List<Clarity360AgentActions.GetHighRiskRecommendationsRequest>();
        if (requests != null) {
            for (Request request : requests) {
                Clarity360AgentActions.GetHighRiskRecommendationsRequest coreRequest =
                    new Clarity360AgentActions.GetHighRiskRecommendationsRequest();
                coreRequest.minRiskScore = (request == null) ? null : request.minRiskScore;
                coreRequest.maxResults = (request == null) ? null : request.maxResults;
                coreRequest.statusFilter = (request == null) ? null : request.statusFilter;
                coreRequests.add(coreRequest);
            }
        }

        List<Clarity360AgentActions.AgentActionResult> coreResults =
            Clarity360AgentActions.getHighRiskRecommendations(coreRequests);
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
