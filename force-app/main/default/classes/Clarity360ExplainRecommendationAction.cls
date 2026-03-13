public with sharing class Clarity360ExplainRecommendationAction {
    public class Request {
        @InvocableVariable(label='Recommendation Id' description='Recommendation__c record Id to explain.')
        public Id recommendationId;

        @InvocableVariable(label='Field Key' description='Fallback lookup key (for example: Account.Legacy_Flag__c).')
        public String fieldKey;
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
        label='Explain Recommendation'
        description='Explains why Clarity360 produced a recommendation for a field.'
    )
    public static List<Response> run(
        List<Request> requests
    ) {
        List<Clarity360AgentActions.ExplainRecommendationRequest> coreRequests =
            new List<Clarity360AgentActions.ExplainRecommendationRequest>();
        if (requests != null) {
            for (Request request : requests) {
                Clarity360AgentActions.ExplainRecommendationRequest coreRequest =
                    new Clarity360AgentActions.ExplainRecommendationRequest();
                coreRequest.recommendationId = (request == null) ? null : request.recommendationId;
                coreRequest.fieldKey = (request == null) ? null : request.fieldKey;
                coreRequests.add(coreRequest);
            }
        }

        List<Clarity360AgentActions.AgentActionResult> coreResults =
            Clarity360AgentActions.explainRecommendation(coreRequests);
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
