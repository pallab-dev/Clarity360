public with sharing class Clarity360SetupConfigService {
    public class SetupConfigDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Boolean isSetupComplete;
        @AuraEnabled public String scopeMode;
        @AuraEnabled public Boolean includeStandardObjects;
        @AuraEnabled public String excludedNamespaces;
        @AuraEnabled public String excludedObjects;
        @AuraEnabled public Decimal coverageThreshold;
        @AuraEnabled public Boolean scheduleEnabled;
        @AuraEnabled public String scheduleFrequency;
        @AuraEnabled public Boolean useNamedCredential;
        @AuraEnabled public String connectionStatus;
        @AuraEnabled public Datetime lastSetupRunOn;
        @AuraEnabled public Boolean enableUsageSampling;
        @AuraEnabled public Boolean enableDependencyAnalysis;
        @AuraEnabled public Boolean enableLayoutScan;
        @AuraEnabled public Boolean enableScheduledScan;
        @AuraEnabled public Boolean enableGlobalRecommendations;
        @AuraEnabled public Boolean enableDeletionGuardrails;
    }

    public static SetupConfigDTO load() {
        List<Clarity360SetupConfig__c> rows = queryLatestConfig();

        if (rows.isEmpty()) {
            return defaultDto();
        }
        return toDto(rows[0]);
    }

    public static SetupConfigDTO save(SetupConfigDTO input) {
        SetupConfigDTO safeInput = normalizeForPersistence((input == null) ? defaultDto() : input);
        validate(safeInput);

        Clarity360SetupConfig__c target = findTargetRecord(safeInput.id);

        Boolean existingSetupComplete = target.Id == null ? false : target.IsSetupComplete__c;
        target.IsSetupComplete__c = (safeInput.isSetupComplete == null)
            ? safeBoolean(existingSetupComplete, false)
            : safeBoolean(safeInput.isSetupComplete, false);
        target.ScopeMode__c = safeInput.scopeMode;
        target.IncludeStandardObjects__c = safeInput.includeStandardObjects;
        target.ExcludedNamespaces__c = trimToLength(safeInput.excludedNamespaces, 32768);
        target.ExcludedObjects__c = trimToLength(safeInput.excludedObjects, 32768);
        target.CoverageThreshold__c = safeInput.coverageThreshold;
        Boolean scheduleToggle = safeBoolean(safeInput.enableScheduledScan, false) || safeBoolean(safeInput.scheduleEnabled, false);
        target.ScheduleEnabled__c = scheduleToggle;
        target.ScheduleFrequency__c = String.isBlank(safeInput.scheduleFrequency) ? null : safeInput.scheduleFrequency;
        target.UseNamedCredential__c = safeBoolean(safeInput.useNamedCredential, false);
        target.ConnectionStatus__c = String.isBlank(safeInput.connectionStatus) ? 'Unknown' : safeInput.connectionStatus;
        target.LastSetupRunOn__c = safeInput.lastSetupRunOn;
        target.EnableUsageSampling__c = safeBoolean(safeInput.enableUsageSampling, target.EnableUsageSampling__c);
        target.EnableDependencyAnalysis__c =
            safeBoolean(safeInput.enableDependencyAnalysis, target.EnableDependencyAnalysis__c);
        target.EnableLayoutScan__c = safeBoolean(safeInput.enableLayoutScan, target.EnableLayoutScan__c);
        target.EnableScheduledScan__c = scheduleToggle;
        target.EnableGlobalRecommendations__c =
            safeBoolean(safeInput.enableGlobalRecommendations, target.EnableGlobalRecommendations__c);
        target.EnableDeletionGuardrails__c =
            safeBoolean(safeInput.enableDeletionGuardrails, target.EnableDeletionGuardrails__c);

        upsert target;
        return toDto(target);
    }

    private static void validate(SetupConfigDTO input) {
        if (!String.isBlank(input.scopeMode) && !isSupportedScopeMode(input.scopeMode)) {
            throw new AuraHandledException('Scope mode must be CustomOnly or IncludeStandard.');
        }
        Decimal coverage = input.coverageThreshold;
        if (coverage != null && (coverage < 0 || coverage > 100)) {
            throw new AuraHandledException('Coverage threshold must be between 0 and 100.');
        }
        if ((input.enableScheduledScan == true || input.scheduleEnabled == true) && String.isBlank(input.scheduleFrequency)) {
            throw new AuraHandledException('Schedule frequency is required when scheduled scans are enabled.');
        }
    }

    private static SetupConfigDTO defaultDto() {
        SetupConfigDTO dto = new SetupConfigDTO();
        dto.isSetupComplete = false;
        dto.scopeMode = null;
        dto.includeStandardObjects = false;
        dto.excludedNamespaces = '';
        dto.excludedObjects = '';
        dto.coverageThreshold = null;
        dto.scheduleEnabled = false;
        dto.scheduleFrequency = null;
        dto.useNamedCredential = false;
        dto.connectionStatus = 'Unknown';
        dto.enableUsageSampling = null;
        dto.enableDependencyAnalysis = null;
        dto.enableLayoutScan = null;
        dto.enableScheduledScan = false;
        dto.enableGlobalRecommendations = null;
        dto.enableDeletionGuardrails = null;
        return dto;
    }

    private static SetupConfigDTO toDto(Clarity360SetupConfig__c row) {
        SetupConfigDTO dto = defaultDto();
        dto.id = row.Id;
        dto.isSetupComplete = row.IsSetupComplete__c;
        dto.scopeMode = normalizeScopeMode(row.ScopeMode__c, row.IncludeStandardObjects__c);
        dto.includeStandardObjects = dto.scopeMode == 'IncludeStandard';
        dto.excludedNamespaces = row.ExcludedNamespaces__c;
        dto.excludedObjects = row.ExcludedObjects__c;
        dto.coverageThreshold = (row.CoverageThreshold__c == null) ? dto.coverageThreshold : row.CoverageThreshold__c;
        dto.scheduleEnabled = row.ScheduleEnabled__c;
        dto.scheduleFrequency = row.ScheduleFrequency__c;
        dto.useNamedCredential = row.UseNamedCredential__c;
        dto.connectionStatus = row.ConnectionStatus__c;
        dto.lastSetupRunOn = row.LastSetupRunOn__c;
        dto.enableUsageSampling = row.EnableUsageSampling__c;
        dto.enableDependencyAnalysis = row.EnableDependencyAnalysis__c;
        dto.enableLayoutScan = row.EnableLayoutScan__c;
        dto.enableScheduledScan = row.EnableScheduledScan__c;
        dto.enableGlobalRecommendations = row.EnableGlobalRecommendations__c;
        dto.enableDeletionGuardrails = row.EnableDeletionGuardrails__c;
        return dto;
    }

    private static Boolean safeBoolean(Boolean value, Boolean fallback) {
        return value == null ? fallback : value;
    }

    private static String trimToLength(String value, Integer maxLen) {
        if (String.isBlank(value)) {
            return null;
        }
        if (value.length() <= maxLen) {
            return value;
        }
        return value.substring(0, maxLen);
    }

    private static Boolean isSupportedScopeMode(String scopeMode) {
        String normalized = normalizeScopeMode(scopeMode);
        return normalized == 'CustomOnly' || normalized == 'IncludeStandard';
    }

    private static SetupConfigDTO normalizeForPersistence(SetupConfigDTO input) {
        SetupConfigDTO normalized = new SetupConfigDTO();
        normalized.id = input.id;
        normalized.isSetupComplete = input.isSetupComplete;
        normalized.scopeMode = normalizeScopeMode(input.scopeMode, input.includeStandardObjects);
        normalized.includeStandardObjects = normalized.scopeMode == 'IncludeStandard';
        normalized.excludedNamespaces = input.excludedNamespaces;
        normalized.excludedObjects = input.excludedObjects;
        normalized.coverageThreshold = input.coverageThreshold;
        normalized.scheduleEnabled = input.scheduleEnabled;
        normalized.scheduleFrequency = input.scheduleFrequency;
        normalized.useNamedCredential = input.useNamedCredential;
        normalized.connectionStatus = input.connectionStatus;
        normalized.lastSetupRunOn = input.lastSetupRunOn;
        normalized.enableUsageSampling = input.enableUsageSampling;
        normalized.enableDependencyAnalysis = input.enableDependencyAnalysis;
        normalized.enableLayoutScan = input.enableLayoutScan;
        normalized.enableScheduledScan = input.enableScheduledScan;
        normalized.enableGlobalRecommendations = input.enableGlobalRecommendations;
        normalized.enableDeletionGuardrails = input.enableDeletionGuardrails;
        return normalized;
    }

    private static String normalizeScopeMode(String scopeMode) {
        return normalizeScopeMode(scopeMode, null);
    }

    private static String normalizeScopeMode(String scopeMode, Boolean includeStandardObjects) {
        if (!String.isBlank(scopeMode)) {
            return scopeMode.trim();
        }
        return includeStandardObjects == true ? 'IncludeStandard' : null;
    }

    private static Boolean inferIncludeStandardObjects(SetupConfigDTO input) {
        String normalized = normalizeScopeMode(input.scopeMode, input.includeStandardObjects);
        if (normalized == 'IncludeStandard') {
            return true;
        }
        if (normalized == 'CustomOnly') {
            return false;
        }
        return safeBoolean(input.includeStandardObjects, false);
    }

    private static Clarity360SetupConfig__c findTargetRecord(Id preferredId) {
        if (preferredId != null) {
            List<Clarity360SetupConfig__c> exactRows = [
                SELECT Id,
                    IsSetupComplete__c,
                    ScopeMode__c,
                    IncludeStandardObjects__c,
                    ExcludedNamespaces__c,
                    ExcludedObjects__c,
                    CoverageThreshold__c,
                    ScheduleEnabled__c,
                    ScheduleFrequency__c,
                    UseNamedCredential__c,
                    ConnectionStatus__c,
                    LastSetupRunOn__c,
                    EnableUsageSampling__c,
                    EnableDependencyAnalysis__c,
                    EnableLayoutScan__c,
                    EnableScheduledScan__c,
                    EnableGlobalRecommendations__c,
                    EnableDeletionGuardrails__c
                FROM Clarity360SetupConfig__c
                WHERE Id = :preferredId
                LIMIT 1
            ];
            if (!exactRows.isEmpty()) {
                return exactRows[0];
            }
        }

        List<Clarity360SetupConfig__c> latestRows = queryLatestConfig();
        if (!latestRows.isEmpty()) {
            return latestRows[0];
        }
        return new Clarity360SetupConfig__c();
    }

    private static List<Clarity360SetupConfig__c> queryLatestConfig() {
        return [
            SELECT Id,
                IsSetupComplete__c,
                ScopeMode__c,
                IncludeStandardObjects__c,
                ExcludedNamespaces__c,
                ExcludedObjects__c,
                CoverageThreshold__c,
                ScheduleEnabled__c,
                ScheduleFrequency__c,
                UseNamedCredential__c,
                ConnectionStatus__c,
                LastSetupRunOn__c,
                EnableUsageSampling__c,
                EnableDependencyAnalysis__c,
                EnableLayoutScan__c,
                EnableScheduledScan__c,
                EnableGlobalRecommendations__c,
                EnableDeletionGuardrails__c
            FROM Clarity360SetupConfig__c
            ORDER BY LastModifiedDate DESC, CreatedDate DESC
            LIMIT 1
        ];
    }
}
