public with sharing class Clarity360SetupOrchestratorService {
    public class InitialRunResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id inventoryJobId;
        @AuraEnabled public String inventoryStatus;
        @AuraEnabled public Id usageJobId;
        @AuraEnabled public String usageStatus;
        @AuraEnabled public String message;
    }

    public static InitialRunResult runInitial(Boolean runUsageScan, String requestId) {
        InitialRunResult result = new InitialRunResult();
        try {
            ScanOrchestrator.StartResult inventoryResult =
                ScanOrchestrator.runInventoryOnlyV2(null, null, requestId);
            result.inventoryJobId = inventoryResult.jobId;
            result.inventoryStatus = inventoryResult.status;

            if (runUsageScan == true) {
                String usageRequestId = String.isBlank(requestId) ? null : requestId + '-usage';
                ScanOrchestrator.StartResult usageResult =
                    ScanOrchestrator.runUsageScanOnlyV2(null, null, usageRequestId);
                result.usageJobId = usageResult.jobId;
                result.usageStatus = usageResult.status;
            }

            result.success = true;
            result.message = 'Initial run started successfully.';
            return result;
        } catch (Exception ex) {
            Clarity360SecureLog.error('SetupOrchestrator.runInitial', ex);
            result.success = false;
            result.message = Clarity360SecureLog.sanitizeForUi(ex, 'Initial run failed.');
            return result;
        }
    }
}
