public with sharing class Clarity360SetupConnectionService {
    private static final String TOOLING_HEALTH_QUERY = 'SELECT Id FROM ApexClass LIMIT 1';

    public class ConnectionTestResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String status;
        @AuraEnabled public String mode;
        @AuraEnabled public String message;
    }

    public static ConnectionTestResult testConnection(Boolean preferNamedCredential) {
        ConnectionTestResult result = new ConnectionTestResult();
        result.mode = preferNamedCredential == false ? 'SessionPreferred' : 'NamedCredentialPreferred';

        try {
            ToolingApiService.ToolingQueryResult queryResult =
                ToolingApiService.queryWithMode(TOOLING_HEALTH_QUERY, 1, preferNamedCredential, true);
            if (queryResult != null && queryResult.success == true) {
                result.success = true;
                result.status = 'Passed';
                result.message = 'Tooling API connectivity check passed.';
                return result;
            }

            result.success = false;
            result.status = 'Failed';
            result.message = queryResult == null ? 'Connection test failed.' : queryResult.errorMessage;
            return result;
        } catch (Exception ex) {
            result.success = false;
            result.status = 'Failed';
            result.message = Clarity360SecureLog.sanitizeForUi(ex, 'Connection test failed.');
            return result;
        }
    }
}
