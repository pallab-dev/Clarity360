public with sharing class Clarity360SetupWizardController {
    public class SetupState {
        @AuraEnabled public Boolean isSetupComplete;
        @AuraEnabled public Clarity360SetupConfigService.SetupConfigDTO config;
        @AuraEnabled public Clarity360SetupValidationService.ReadinessResult readiness;
    }

    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Clarity360SetupConfigService.SetupConfigDTO config;
    }

    @AuraEnabled
    public static SetupState getSetupState() {
        SetupState state = new SetupState();
        state.config = Clarity360SetupConfigService.load();
        state.isSetupComplete = state.config != null && state.config.isSetupComplete == true;
        state.readiness = Clarity360SetupValidationService.runReadinessChecks();
        return state;
    }

    @AuraEnabled
    public static Boolean isSetupComplete() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        return config != null && config.isSetupComplete == true;
    }

    @AuraEnabled(cacheable=true)
    public static Clarity360SetupConfigService.SetupConfigDTO getRuntimeConfig() {
        return Clarity360SetupConfigService.load();
    }

    @AuraEnabled
    public static Clarity360SetupValidationService.ReadinessResult runReadinessChecks() {
        return Clarity360SetupValidationService.runReadinessChecks();
    }

    @AuraEnabled
    public static Clarity360SetupConnectionService.ConnectionTestResult runConnectionTest(Boolean useNamedCredential) {
        return Clarity360SetupConnectionService.testConnection(useNamedCredential);
    }

    @AuraEnabled
    public static SaveResult saveRuntimeConfig(
        Clarity360SetupConfigService.SetupConfigDTO input,
        Boolean markSetupComplete
    ) {
        return saveInternal(input, markSetupComplete);
    }

    @AuraEnabled
    public static SaveResult saveSetupChoices(
        Boolean includeStandardObjects,
        Decimal coverageThreshold,
        String excludedObjects,
        String excludedNamespaces,
        Boolean useNamedCredential,
        Boolean enableScheduledScan,
        String scheduleFrequency,
        Boolean enableScheduledReports,
        String scheduledReportRecipient,
        Boolean markSetupComplete
    ) {
        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        if (input == null) {
            input = new Clarity360SetupConfigService.SetupConfigDTO();
        }
        input.includeStandardObjects = includeStandardObjects == true;
        input.scopeMode = includeStandardObjects == true ? 'IncludeStandard' : 'CustomOnly';
        input.coverageThreshold = coverageThreshold;
        input.excludedObjects = excludedObjects;
        input.excludedNamespaces = excludedNamespaces;
        input.useNamedCredential = useNamedCredential;
        input.enableScheduledScan = enableScheduledScan;
        input.scheduleEnabled = enableScheduledScan;
        input.scheduleFrequency = scheduleFrequency;
        input.enableScheduledReports = enableScheduledReports;
        input.scheduledReportRecipient = scheduledReportRecipient;
        return saveInternal(input, markSetupComplete);
    }

    private static SaveResult saveInternal(
        Clarity360SetupConfigService.SetupConfigDTO input,
        Boolean markSetupComplete
    ) {
        SaveResult result = new SaveResult();
        try {
            Clarity360SetupConfigService.SetupConfigDTO safeInput =
                (input == null) ? Clarity360SetupConfigService.load() : input;
            if (markSetupComplete == true) {
                Clarity360SetupConfigService.SetupConfigDTO completionCandidate = new Clarity360SetupConfigService.SetupConfigDTO();
                completionCandidate.id = safeInput.id;
                completionCandidate.isSetupComplete = true;
                completionCandidate.scopeMode = safeInput.scopeMode;
                completionCandidate.includeStandardObjects = safeInput.includeStandardObjects;
                completionCandidate.excludedNamespaces = safeInput.excludedNamespaces;
                completionCandidate.excludedObjects = safeInput.excludedObjects;
                completionCandidate.coverageThreshold = safeInput.coverageThreshold;
                completionCandidate.scheduleEnabled = safeInput.scheduleEnabled;
                completionCandidate.scheduleFrequency = safeInput.scheduleFrequency;
                completionCandidate.useNamedCredential = safeInput.useNamedCredential;
                completionCandidate.connectionStatus = safeInput.connectionStatus;
                completionCandidate.lastSetupRunOn = System.now();
                completionCandidate.enableUsageSampling = safeInput.enableUsageSampling;
                completionCandidate.enableDependencyAnalysis = safeInput.enableDependencyAnalysis;
                completionCandidate.enableLayoutScan = safeInput.enableLayoutScan;
                completionCandidate.enableScheduledScan = safeInput.enableScheduledScan;
                completionCandidate.enableScheduledReports = safeInput.enableScheduledReports;
                completionCandidate.enableGlobalRecommendations = safeInput.enableGlobalRecommendations;
                completionCandidate.enableDeletionGuardrails = safeInput.enableDeletionGuardrails;
                completionCandidate.scheduledReportRecipient = safeInput.scheduledReportRecipient;
                Clarity360Settings.ValidationResult validation =
                    Clarity360Settings.validateRuntimeSetupCompletion(completionCandidate);
                if (validation.valid != true) {
                    throw new AuraHandledException(String.join(validation.errors, ' '));
                }
                safeInput.isSetupComplete = true;
                safeInput.lastSetupRunOn = System.now();
            }
            result.config = Clarity360SetupConfigService.save(safeInput);
            Clarity360ScheduleService.syncSchedule();
            result.success = true;
            result.message = 'Setup configuration saved.';
            return result;
        } catch (AuraHandledException handledEx) {
            throw handledEx;
        } catch (Exception ex) {
            Clarity360SecureLog.error('SetupWizard.saveRuntimeConfig', ex);
            throw new AuraHandledException(Clarity360SecureLog.sanitizeForUi(ex, 'Failed to save setup configuration.'));
        }
    }

    @AuraEnabled
    public static Clarity360SetupOrchestratorService.InitialRunResult runInitialRun(Boolean runUsageScan, String requestId) {
        return Clarity360SetupOrchestratorService.runInitial(runUsageScan, requestId);
    }
}
