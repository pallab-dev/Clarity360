public with sharing class Clarity360Settings {
    private static final String DEFAULT_CONFIG_DEVELOPER_NAME = 'Default';

    public class ConfigurationException extends Exception {}

    public class Values {
        public Boolean metadataPresent = false;
        public Boolean enableFieldRecommendations;
        public Boolean enableTriggerScan;
        public Boolean enableValidationRuleScan;
        public Boolean enableFlowAndProcessScan;
        public Boolean enableWorkflowRuleScan;
        public Boolean enableApexCoverageScan;
        public Integer minObjectRecordCount;
        public Decimal apexCoverageThresholdPct;
        public Integer maxToolingRows;
        public Integer samplingLimit;
        public Integer maxInventoryObjects;
        public Integer maxScanObjects;
    }

    public class ValidationResult {
        public Boolean valid = true;
        public List<String> errors = new List<String>();
    }

    public class RuntimeChoiceGuidance {
        public List<String> warnings = new List<String>();
    }

    public class RuntimeConfig {
        public Boolean includeStandardObjects = false;
        public Boolean useNamedCredential = false;
        public Boolean enableLayoutScan = false;
        public Boolean enableScheduledScan = false;
        public Boolean enableScheduledReports = false;
        public String excludedObjects;
        public String excludedNamespaces;
        public String scheduleFrequency;
        public String scheduledReportRecipient;
        public Decimal coverageThreshold;

        public Boolean enableFieldRecommendations;
        public Boolean enableTriggerScan;
        public Boolean enableValidationRuleScan;
        public Boolean enableFlowAndProcessScan;
        public Boolean enableWorkflowRuleScan;
        public Boolean enableApexCoverageScan;
        public Integer minObjectRecordCount;
        public Decimal apexCoverageThresholdPct;
        public Integer maxToolingRows;
        public Integer samplingLimit;
        public Integer maxInventoryObjects;
        public Integer maxScanObjects;
    }

    private static Values cached;
    private static RuntimeConfig cachedRuntime;

    public static Values get() {
        if (cached != null) {
            return cached;
        }

        try {
            List<SObject> rows = Database.query(
                'SELECT DeveloperName,' +
                ' EnableFieldRecommendations__c,' +
                ' EnableTriggerScan__c,' +
                ' EnableValidationRuleScan__c,' +
                ' EnableFlowAndProcessScan__c,' +
                ' EnableWorkflowRuleScan__c,' +
                ' EnableApexCoverageScan__c,' +
                ' MinObjectRecordCount__c,' +
                ' ApexCoverageThresholdPct__c,' +
                ' MaxToolingRows__c,' +
                ' SamplingLimit__c,' +
                ' MaxInventoryObjects__c,' +
                ' MaxScanObjects__c' +
                ' FROM Clarity360Config__mdt' +
                ' WHERE DeveloperName = \'' + DEFAULT_CONFIG_DEVELOPER_NAME + '\'' +
                ' LIMIT 1'
            );

            if (rows.isEmpty()) {
                cached = new Values();
                return cached;
            }

            SObject row = rows[0];
            Values values = new Values();
            values.metadataPresent = true;
            applyMetadataValues(values, row);
            cached = values;
            return cached;
        } catch (Exception ex) {
            cached = new Values();
            return cached;
        }
    }

    public static ValidationResult validate() {
        ValidationResult result = new ValidationResult();
        Values values = get();
        if (values == null || values.metadataPresent != true) {
            addError(result, 'Clarity360Config.Default metadata record is missing.');
            return result;
        }

        requireBoolean(result, values.enableFieldRecommendations, 'EnableFieldRecommendations__c');
        requireBoolean(result, values.enableTriggerScan, 'EnableTriggerScan__c');
        requireBoolean(result, values.enableValidationRuleScan, 'EnableValidationRuleScan__c');
        requireBoolean(result, values.enableFlowAndProcessScan, 'EnableFlowAndProcessScan__c');
        requireBoolean(result, values.enableWorkflowRuleScan, 'EnableWorkflowRuleScan__c');
        requireBoolean(result, values.enableApexCoverageScan, 'EnableApexCoverageScan__c');
        requirePositiveInteger(result, values.minObjectRecordCount, 'MinObjectRecordCount__c');
        requirePositiveInteger(result, values.maxToolingRows, 'MaxToolingRows__c');
        requirePositiveInteger(result, values.samplingLimit, 'SamplingLimit__c');
        requirePositiveInteger(result, values.maxInventoryObjects, 'MaxInventoryObjects__c');
        requirePositiveInteger(result, values.maxScanObjects, 'MaxScanObjects__c');
        if (values.apexCoverageThresholdPct == null || values.apexCoverageThresholdPct < 0 || values.apexCoverageThresholdPct > 100) {
            addError(result, 'ApexCoverageThresholdPct__c must be between 0 and 100.');
        }
        return result;
    }

    public static Values getRequired() {
        ValidationResult validation = validate();
        if (validation.valid == true) {
            return get();
        }
        throw new ConfigurationException(String.join(validation.errors, ' '));
    }

    public static RuntimeConfig getRuntime() {
        if (cachedRuntime != null) {
            return cachedRuntime;
        }

        RuntimeConfig runtime = new RuntimeConfig();
        Values metadata = get();
        if (metadata != null) {
            applyRuntimeMetadata(runtime, metadata);
        }

        Clarity360SetupConfigService.SetupConfigDTO userSettings = Clarity360SetupConfigService.load();
        if (userSettings != null) {
            String effectiveScope = effectiveScopeMode(userSettings);
            runtime.includeStandardObjects = effectiveScope == 'IncludeStandard';
            runtime.useNamedCredential = userSettings.useNamedCredential == true;
            runtime.enableLayoutScan = userSettings.enableLayoutScan == true;
            runtime.enableScheduledScan = userSettings.enableScheduledScan == true || userSettings.scheduleEnabled == true;
            runtime.enableScheduledReports = userSettings.enableScheduledReports == true;
            runtime.excludedObjects = userSettings.excludedObjects;
            runtime.excludedNamespaces = userSettings.excludedNamespaces;
            runtime.scheduleFrequency = userSettings.scheduleFrequency;
            runtime.scheduledReportRecipient = userSettings.scheduledReportRecipient;
            runtime.coverageThreshold = effectiveCoverageThreshold(userSettings);
        }

        cachedRuntime = runtime;
        return cachedRuntime;
    }

    public static ValidationResult validateRuntimeSetupCompletion() {
        return validateRuntimeSetupCompletion(Clarity360SetupConfigService.load());
    }

    public static ValidationResult validateRuntimeSetupCompletion(Clarity360SetupConfigService.SetupConfigDTO config) {
        ValidationResult result = new ValidationResult();
        ValidationResult metadataValidation = validate();
        if (metadataValidation.valid != true) {
            for (String error : metadataValidation.errors) {
                addError(result, error);
            }
        }

        if (config == null) {
            addError(result, 'Setup configuration record is missing.');
            return result;
        }
        if ((config.enableScheduledScan == true || config.scheduleEnabled == true) && String.isBlank(config.scheduleFrequency)) {
            addError(result, 'Schedule frequency must be chosen when scheduled scans are enabled.');
        }
        return result;
    }

    public static RuntimeChoiceGuidance describeRuntimeChoiceGuidance() {
        return describeRuntimeChoiceGuidance(Clarity360SetupConfigService.load());
    }

    public static RuntimeChoiceGuidance describeRuntimeChoiceGuidance(Clarity360SetupConfigService.SetupConfigDTO config) {
        RuntimeChoiceGuidance guidance = new RuntimeChoiceGuidance();
        if (config == null) {
            return guidance;
        }

        Decimal defaultCoverage = defaultCoverageThreshold();
        if (config.coverageThreshold == null && defaultCoverage != null) {
            guidance.warnings.add(
                'Coverage threshold is currently using the org default (' +
                String.valueOf(defaultCoverage.setScale(2)) +
                '%).'
            );
        }
        return guidance;
    }

    public static RuntimeConfig getRequiredRuntime() {
        ValidationResult validation = validateRuntimeSetupCompletion();
        if (validation.valid == true) {
            return getRuntime();
        }
        throw new ConfigurationException(String.join(validation.errors, ' '));
    }

    @TestVisible
    static void resetCache() {
        cached = null;
        cachedRuntime = null;
    }

    private static String defaultScopeMode() {
        return 'CustomOnly';
    }

    private static Decimal defaultCoverageThreshold() {
        Values values = get();
        if (values != null && values.apexCoverageThresholdPct != null) {
            return values.apexCoverageThresholdPct;
        }
        return 75;
    }

    private static String effectiveScopeMode(Clarity360SetupConfigService.SetupConfigDTO config) {
        if (config == null) {
            return defaultScopeMode();
        }
        if (config.includeStandardObjects == true) {
            return 'IncludeStandard';
        }
        if (!String.isBlank(config.scopeMode)) {
            return config.scopeMode.trim();
        }
        return defaultScopeMode();
    }

    private static Decimal effectiveCoverageThreshold(Clarity360SetupConfigService.SetupConfigDTO config) {
        if (config != null && config.coverageThreshold != null) {
            return config.coverageThreshold;
        }
        return defaultCoverageThreshold();
    }

    private static Integer toInteger(Decimal input) {
        return input == null ? null : Integer.valueOf(input.intValue());
    }

    private static void applyMetadataValues(Values values, SObject row) {
        values.enableFieldRecommendations = (Boolean) row.get('EnableFieldRecommendations__c');
        values.enableTriggerScan = (Boolean) row.get('EnableTriggerScan__c');
        values.enableValidationRuleScan = (Boolean) row.get('EnableValidationRuleScan__c');
        values.enableFlowAndProcessScan = (Boolean) row.get('EnableFlowAndProcessScan__c');
        values.enableWorkflowRuleScan = (Boolean) row.get('EnableWorkflowRuleScan__c');
        values.enableApexCoverageScan = (Boolean) row.get('EnableApexCoverageScan__c');
        values.minObjectRecordCount = toInteger((Decimal) row.get('MinObjectRecordCount__c'));
        values.apexCoverageThresholdPct = (Decimal) row.get('ApexCoverageThresholdPct__c');
        values.maxToolingRows = toInteger((Decimal) row.get('MaxToolingRows__c'));
        values.samplingLimit = toInteger((Decimal) row.get('SamplingLimit__c'));
        values.maxInventoryObjects = toInteger((Decimal) row.get('MaxInventoryObjects__c'));
        values.maxScanObjects = toInteger((Decimal) row.get('MaxScanObjects__c'));
    }

    private static void applyRuntimeMetadata(RuntimeConfig runtime, Values metadata) {
        runtime.enableFieldRecommendations = metadata.enableFieldRecommendations;
        runtime.enableTriggerScan = metadata.enableTriggerScan;
        runtime.enableValidationRuleScan = metadata.enableValidationRuleScan;
        runtime.enableFlowAndProcessScan = metadata.enableFlowAndProcessScan;
        runtime.enableWorkflowRuleScan = metadata.enableWorkflowRuleScan;
        runtime.enableApexCoverageScan = metadata.enableApexCoverageScan;
        runtime.minObjectRecordCount = metadata.minObjectRecordCount;
        runtime.apexCoverageThresholdPct = metadata.apexCoverageThresholdPct;
        runtime.maxToolingRows = metadata.maxToolingRows;
        runtime.samplingLimit = metadata.samplingLimit;
        runtime.maxInventoryObjects = metadata.maxInventoryObjects;
        runtime.maxScanObjects = metadata.maxScanObjects;
    }

    private static void requireBoolean(ValidationResult result, Boolean value, String fieldName) {
        if (value == null) {
            addError(result, fieldName + ' is required in Clarity360Config.Default.');
        }
    }

    private static void requirePositiveInteger(ValidationResult result, Integer value, String fieldName) {
        if (value == null || value <= 0) {
            addError(result, fieldName + ' must be a positive number in Clarity360Config.Default.');
        }
    }

    private static void addError(ValidationResult result, String message) {
        result.valid = false;
        result.errors.add(message);
    }
}
