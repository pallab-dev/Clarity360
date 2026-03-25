public with sharing class Clarity360SetupValidationService {
    private static final String TOOLING_HEALTH_QUERY = 'SELECT Id FROM ApexClass LIMIT 1';
    private static final List<String> REQUIRED_SETUP_FIELDS = new List<String>{
        'ScopeMode__c',
        'CoverageThreshold__c',
        'ExcludedObjects__c',
        'ExcludedNamespaces__c',
        'UseNamedCredential__c',
        'ScheduleEnabled__c',
        'ScheduleFrequency__c',
        'IsSetupComplete__c',
        'ConnectionStatus__c'
    };
    @TestVisible private static TestOverrides testOverrides;

    @TestVisible
    private class TestOverrides {
        public Clarity360Settings.ValidationResult developerValidation;
        public Clarity360Settings.ValidationResult runtimeValidation;
        public Clarity360Settings.RuntimeChoiceGuidance runtimeGuidance;
        public Boolean adminCanAdminister;
        public Boolean configCanRead;
        public Boolean configCanCreate;
        public Boolean configCanUpdate;
        public List<String> missingReadFields;
        public List<String> missingEditFields;
        public List<String> missingOperationalObjects;
        public Integer queueableLimit;
        public Boolean storageMetricsUnavailable;
        public Decimal storageLimit;
        public Decimal storageUsed;
        public Boolean coreComponentsAvailable;
        public Boolean agentClassesAvailable;
        public String agentRuntimeFailureMessage;
    }

    public class CheckItem {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public String remediation;
    }

    public class ReadinessResult {
        @AuraEnabled public String overallStatus;
        @AuraEnabled public List<CheckItem> checks = new List<CheckItem>();
    }

    public static ReadinessResult runReadinessChecks() {
        ReadinessResult result = new ReadinessResult();
        result.checks.add(checkDeveloperMetadataConfig());
        result.checks.add(checkUserRuntimeChoices());
        result.checks.add(checkAdminPrivileges());
        result.checks.add(checkConfigObjectPermissions());
        result.checks.add(checkConfigFieldPermissions());
        result.checks.add(checkOperationalObjectAccess());
        result.checks.add(checkAsyncCapacity());
        result.checks.add(checkStorageHealth());
        result.checks.add(checkCoreComponents());
        result.checks.add(checkNamedCredentialPresence());
        result.checks.add(checkToolingApiConnectivity());
        result.checks.add(checkAgentAssistantReadiness());

        Boolean hasBlocked = false;
        Boolean hasWarning = false;
        for (CheckItem item : result.checks) {
            if (item.status == 'Blocked') {
                hasBlocked = true;
            } else if (item.status == 'Warning') {
                hasWarning = true;
            }
        }
        result.overallStatus = hasBlocked ? 'Blocked' : (hasWarning ? 'Warning' : 'Ready');
        return result;
    }

    private static CheckItem checkDeveloperMetadataConfig() {
        Clarity360Settings.ValidationResult validation =
            testOverrides != null && testOverrides.developerValidation != null
                ? testOverrides.developerValidation
                : Clarity360Settings.validate();
        if (validation.valid == true) {
            return buildItem(
                'developerConfig',
                'Developer metadata config',
                'Ready',
                'Required Clarity360Config.Default metadata values are present.',
                'No action required.'
            );
        }

        return buildItem(
            'developerConfig',
            'Developer metadata config',
            'Blocked',
            String.join(validation.errors, ' '),
            'Fix Clarity360Config.Default metadata values. This is a package/developer configuration issue.'
        );
    }

    private static CheckItem checkUserRuntimeChoices() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        Clarity360Settings.ValidationResult validation =
            testOverrides != null && testOverrides.runtimeValidation != null
                ? testOverrides.runtimeValidation
                : Clarity360Settings.validateRuntimeSetupCompletion(config);
        if (validation.valid == true) {
            Clarity360Settings.RuntimeChoiceGuidance guidance =
                testOverrides != null && testOverrides.runtimeGuidance != null
                    ? testOverrides.runtimeGuidance
                    : Clarity360Settings.describeRuntimeChoiceGuidance(config);
            if (!guidance.warnings.isEmpty()) {
                return buildItem(
                    'runtimeChoices',
                    'Runtime setup choices',
                    'Warning',
                    String.join(guidance.warnings, ' '),
                    'Dashboard will use org defaults. Open Setup to optimize these choices if needed.'
                );
            }
            return buildItem(
                'runtimeChoices',
                'Runtime setup choices',
                'Ready',
                'Required runtime setup choices have been provided.',
                'No action required.'
            );
        }

        List<String> filteredErrors = new List<String>();
        for (String error : validation.errors) {
            if (error != null && !error.contains('Clarity360Config.Default')) {
                filteredErrors.add(error);
            }
        }
        if (filteredErrors.isEmpty()) {
            return buildItem(
                'runtimeChoices',
                'Runtime setup choices',
                'Ready',
                'User-owned setup values are structurally valid.',
                'No action required.'
            );
        }

        return buildItem(
            'runtimeChoices',
            'Runtime setup choices',
            'Blocked',
            String.join(filteredErrors, ' '),
            'Complete the required setup values before finishing onboarding or starting scans.'
        );
    }

    private static CheckItem checkAdminPrivileges() {
        if (testOverrides != null && testOverrides.adminCanAdminister != null) {
            Boolean canAdminister = testOverrides.adminCanAdminister == true;
            return buildItem(
                'adminPrivileges',
                'Admin privileges',
                canAdminister ? 'Ready' : 'Blocked',
                canAdminister
                    ? 'Running user has sufficient admin-level permissions.'
                    : 'Running user does not have required admin-level permissions.',
                'Assign a System Administrator profile or an equivalent permission set.'
            );
        }
        try {
            User running = [
                SELECT Profile.PermissionsModifyAllData, Profile.PermissionsCustomizeApplication
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            Boolean canAdminister =
                running.Profile.PermissionsModifyAllData ||
                running.Profile.PermissionsCustomizeApplication;

            if (!canAdminister) {
                Integer grants = [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :UserInfo.getUserId()
                    AND (
                        PermissionSet.PermissionsModifyAllData = true OR
                        PermissionSet.PermissionsCustomizeApplication = true
                    )
                ];
                canAdminister = grants > 0;
            }

            return buildItem(
                'adminPrivileges',
                'Admin privileges',
                canAdminister ? 'Ready' : 'Blocked',
                canAdminister
                    ? 'Running user has sufficient admin-level permissions.'
                    : 'Running user does not have required admin-level permissions.',
                'Assign a System Administrator profile or an equivalent permission set.'
            );
        } catch (Exception ex) {
            return buildItem(
                'adminPrivileges',
                'Admin privileges',
                'Warning',
                'Unable to fully validate admin privileges at runtime.',
                'Confirm the user can customize application metadata and run async jobs.'
            );
        }
    }

    private static CheckItem checkConfigObjectPermissions() {
        Boolean canRead;
        Boolean canCreate;
        Boolean canUpdate;
        if (testOverrides != null && testOverrides.configCanRead != null) {
            canRead = testOverrides.configCanRead;
            canCreate = testOverrides.configCanCreate == true;
            canUpdate = testOverrides.configCanUpdate == true;
        } else {
            Schema.DescribeSObjectResult describeResult = Clarity360SetupConfig__c.SObjectType.getDescribe();
            canRead = describeResult.isAccessible();
            canCreate = describeResult.isCreateable();
            canUpdate = describeResult.isUpdateable();
        }

        if (canRead && (canCreate || canUpdate)) {
            return buildItem(
                'configAccess',
                'Setup config object access',
                'Ready',
                'Runtime setup configuration object is readable and editable.',
                'No action required.'
            );
        }

        return buildItem(
            'configAccess',
            'Setup config object access',
            'Blocked',
            'Current user cannot read and edit Clarity360 setup config object.',
            'Grant read/edit access to Clarity360SetupConfig__c object.'
        );
    }

    private static CheckItem checkConfigFieldPermissions() {
        List<String> missingRead = new List<String>();
        List<String> missingEdit = new List<String>();
        if (testOverrides != null && testOverrides.missingReadFields != null) {
            missingRead.addAll(testOverrides.missingReadFields);
            if (testOverrides.missingEditFields != null) {
                missingEdit.addAll(testOverrides.missingEditFields);
            }
        } else {
            Map<String, Schema.SObjectField> fieldsByApi = Clarity360SetupConfig__c.SObjectType.getDescribe().fields.getMap();
            for (String fieldApi : REQUIRED_SETUP_FIELDS) {
                if (!fieldsByApi.containsKey(fieldApi)) {
                    missingRead.add(fieldApi + ' (missing)');
                    continue;
                }
                Schema.DescribeFieldResult describeField = fieldsByApi.get(fieldApi).getDescribe();
                if (!describeField.isAccessible()) {
                    missingRead.add(fieldApi);
                }
                if (!describeField.isUpdateable()) {
                    missingEdit.add(fieldApi);
                }
            }
        }

        if (missingRead.isEmpty() && missingEdit.isEmpty()) {
            return buildItem(
                'configFieldAccess',
                'Setup config field access',
                'Ready',
                'Required setup fields are readable and editable.',
                'No action required.'
            );
        }

        String message = 'Missing setup field permissions.';
        if (!missingRead.isEmpty()) {
            message += ' Read: ' + shortenList(missingRead, 5) + '.';
        }
        if (!missingEdit.isEmpty()) {
            message += ' Edit: ' + shortenList(missingEdit, 5) + '.';
        }

        return buildItem(
            'configFieldAccess',
            'Setup config field access',
            'Blocked',
            message,
            'Grant field-level security on Clarity360SetupConfig__c for setup users.'
        );
    }

    private static CheckItem checkOperationalObjectAccess() {
        List<String> missing = new List<String>();
        if (testOverrides != null && testOverrides.missingOperationalObjects != null) {
            missing.addAll(testOverrides.missingOperationalObjects);
        } else {
            if (!FieldInventory__c.SObjectType.getDescribe().isAccessible()) {
                missing.add('FieldInventory__c');
            }
            if (!UsageSignal__c.SObjectType.getDescribe().isAccessible()) {
                missing.add('UsageSignal__c');
            }
            if (!Recommendation__c.SObjectType.getDescribe().isAccessible()) {
                missing.add('Recommendation__c');
            }
            if (!ScanJob__c.SObjectType.getDescribe().isAccessible()) {
                missing.add('ScanJob__c');
            }
        }

        if (missing.isEmpty()) {
            return buildItem(
                'operationalAccess',
                'Operational object access',
                'Ready',
                'Core Clarity360 objects are readable.',
                'No action required.'
            );
        }

        return buildItem(
            'operationalAccess',
            'Operational object access',
            'Blocked',
            'Missing read access to: ' + String.join(missing, ', '),
            'Grant object permissions through profile or permission set assignment.'
        );
    }

    private static CheckItem checkAsyncCapacity() {
        Integer queueableLimit =
            testOverrides != null && testOverrides.queueableLimit != null
                ? testOverrides.queueableLimit
                : Limits.getLimitQueueableJobs();
        if (queueableLimit <= 0) {
            return buildItem(
                'asyncCapacity',
                'Async Apex capacity',
                'Blocked',
                'Queueable jobs are unavailable in current context.',
                'Enable async Apex usage and rerun readiness checks.'
            );
        }

        return buildItem(
            'asyncCapacity',
            'Async Apex capacity',
            'Ready',
            'Queueable jobs are available for scan orchestration.',
            'No action required.'
        );
    }

    private static CheckItem checkStorageHealth() {
        try {
            if (testOverrides != null) {
                if (testOverrides.storageMetricsUnavailable == true) {
                    return buildItem(
                        'storageHealth',
                        'Storage health',
                        'Warning',
                        'Data storage metrics are not available in this org context.',
                        'Review Setup > Company Information > Storage Usage.'
                    );
                }
                if (testOverrides.storageLimit != null || testOverrides.storageUsed != null) {
                    return buildStorageHealthItem(testOverrides.storageUsed, testOverrides.storageLimit);
                }
            }
            Map<String, System.OrgLimit> limitsByName = System.OrgLimits.getMap();
            System.OrgLimit dataStorage = limitsByName.get('DataStorageMB');
            if (dataStorage == null) {
                dataStorage = limitsByName.get('DataStorage');
            }
            if (dataStorage == null) {
                return buildItem(
                    'storageHealth',
                    'Storage health',
                    'Warning',
                    'Data storage metrics are not available in this org context.',
                    'Review Setup > Company Information > Storage Usage.'
                );
            }

            return buildStorageHealthItem(
                Decimal.valueOf(String.valueOf(dataStorage.getValue())),
                Decimal.valueOf(String.valueOf(dataStorage.getLimit()))
            );
        } catch (Exception ex) {
            return buildItem(
                'storageHealth',
                'Storage health',
                'Warning',
                'Unable to validate storage health.',
                'Review Setup > Company Information > Storage Usage.'
            );
        }
    }

    private static CheckItem checkCoreComponents() {
        Boolean hasCore =
            testOverrides != null && testOverrides.coreComponentsAvailable != null
                ? testOverrides.coreComponentsAvailable
                : Type.forName('ScanOrchestrator') != null && Type.forName('InventoryService') != null;
        return buildItem(
            'coreComponents',
            'Core package components',
            hasCore ? 'Ready' : 'Blocked',
            hasCore ? 'Core Clarity360 classes are available.' : 'Core Clarity360 classes are not resolvable.',
            'Reinstall or upgrade package and run post-install steps again.'
        );
    }

    private static CheckItem checkNamedCredentialPresence() {
        Clarity360Settings.RuntimeConfig runtimeConfig = Clarity360Settings.getRuntime();
        Boolean preferNamedCredential = runtimeConfig != null && runtimeConfig.useNamedCredential == true;

        try {
            Boolean namedCredentialPresent = ToolingApiService.hasNamedCredentialConfigured();
            if (!preferNamedCredential) {
                ToolingApiService.ToolingQueryResult sessionResult = ToolingApiService.queryWithMode(
                    TOOLING_HEALTH_QUERY,
                    1,
                    false,
                    false
                );
                if (sessionResult != null && sessionResult.success == true) {
                    return buildItem(
                        'namedCredential',
                        'Named Credential',
                        'Ready',
                        namedCredentialPresent
                            ? 'Session-preferred mode is working. Named Credential is available as optional fallback.'
                            : 'Session-preferred mode is working. Named Credential is optional for this org configuration.',
                        'No action required.'
                    );
                }

                return buildItem(
                    'namedCredential',
                    'Named Credential',
                    namedCredentialPresent ? 'Ready' : 'Warning',
                    namedCredentialPresent
                        ? 'Named Credential is available as fallback, but session-preferred mode could not be verified.'
                        : 'Session-preferred mode could not be verified and no Named Credential fallback was found.',
                    namedCredentialPresent
                        ? 'No action required, but verify session-based Tooling API access if scans fail.'
                        : 'Create Clarity360Tooling or restore session-based Tooling API access.'
                );
            }

            if (!namedCredentialPresent) {
                return buildItem(
                    'namedCredential',
                    'Named Credential',
                    'Warning',
                    'Named Credential is the preferred Tooling API mode, but Clarity360Tooling was not found.',
                    'Create Clarity360Tooling or switch setup to session-preferred mode.'
                );
            }

            ToolingApiService.ToolingQueryResult namedCredentialResult = ToolingApiService.queryWithMode(
                TOOLING_HEALTH_QUERY,
                1,
                true,
                false
            );
            if (namedCredentialResult != null && namedCredentialResult.success == true) {
                return buildItem(
                    'namedCredential',
                    'Named Credential',
                    'Ready',
                    'Named Credential-preferred mode is configured and working for Tooling API callouts.',
                    'No action required.'
                );
            }

            return buildItem(
                'namedCredential',
                'Named Credential',
                'Warning',
                'Clarity360Tooling is present, but Named Credential-preferred Tooling API access could not be verified.',
                'Check the Named Credential endpoint/authentication or switch setup to session-preferred mode.'
            );
        } catch (Exception ex) {
            return buildItem(
                'namedCredential',
                'Named Credential',
                'Warning',
                'Unable to verify named credential configuration.',
                'Create Clarity360Tooling or keep session fallback enabled.'
            );
        }
    }

    private static CheckItem checkToolingApiConnectivity() {
        Clarity360Settings.RuntimeConfig runtimeConfig = Clarity360Settings.getRuntime();
        Boolean preferNamedCredential = runtimeConfig != null && runtimeConfig.useNamedCredential == true;
        try {
            ToolingApiService.ToolingQueryResult result = ToolingApiService.queryWithMode(
                TOOLING_HEALTH_QUERY,
                1,
                preferNamedCredential,
                true
            );
            if (result != null && result.success == true) {
                return buildItem(
                    'toolingApi',
                    'Tooling API connectivity',
                    'Ready',
                    'Tooling API connectivity check passed for the configured callout mode.',
                    'No action required.'
                );
            }

            String errorDetail = (result == null || String.isBlank(result.errorMessage))
                ? 'Unknown callout failure.'
                : result.errorMessage;
            return buildItem(
                'toolingApi',
                'Tooling API connectivity',
                'Warning',
                'Tooling API connectivity is unavailable right now. ' + errorDetail,
                'This is optional for baseline setup. Configure Named Credential/session access and rerun checks when ready.'
            );
        } catch (Exception ex) {
            return buildItem(
                'toolingApi',
                'Tooling API connectivity',
                'Warning',
                'Tooling API connectivity is unavailable.',
                'This is optional for baseline setup. Verify Named Credential/session configuration and rerun readiness checks.'
            );
        }
    }

    private static CheckItem checkAgentAssistantReadiness() {
        try {
            Boolean hasAgentClasses =
                testOverrides != null && testOverrides.agentClassesAvailable != null
                    ? testOverrides.agentClassesAvailable
                    : Type.forName('Clarity360AgentActions') != null &&
                        Type.forName('Clarity360ExplainRecommendationAction') != null &&
                        Type.forName('Clarity360HighRiskRecsAction') != null &&
                        Type.forName('Clarity360GetRecentScanSummaryAction') != null;
            if (!hasAgentClasses) {
                return buildItem(
                    'agentAssistant',
                    'Agent assistant availability',
                    'Warning',
                    'Agentforce action classes are not fully available in this org.',
                    'Deploy Clarity360 agent action Apex classes and metadata.'
                );
            }

            // Runtime probe for the core read-only action path.
            Clarity360AgentActions.getRecentScanSummary(new List<Clarity360AgentActions.GetRecentScanSummaryRequest>{
                new Clarity360AgentActions.GetRecentScanSummaryRequest()
            });
            if (testOverrides != null && !String.isBlank(testOverrides.agentRuntimeFailureMessage)) {
                throw new AuraHandledException(testOverrides.agentRuntimeFailureMessage);
            }

            return buildItem(
                'agentAssistant',
                'Agent assistant availability',
                'Ready',
                'Agentforce action runtime path is available.',
                'No action required.'
            );
        } catch (Exception ex) {
            return buildItem(
                'agentAssistant',
                'Agent assistant availability',
                'Warning',
                'Agentforce action runtime check failed: ' + Clarity360SecureLog.sanitizeForUi(ex, 'Unavailable'),
                'Assign Apex/object permissions and confirm Agentforce actions are deployed.'
            );
        }
    }

    private static String shortenList(List<String> values, Integer maxItems) {
        if (values == null || values.isEmpty()) {
            return '';
        }
        Integer limitSize = Math.max(1, maxItems == null ? 5 : maxItems);
        List<String> copy = new List<String>();
        Integer size = Math.min(limitSize, values.size());
        for (Integer i = 0; i < size; i++) {
            copy.add(values[i]);
        }
        if (values.size() > size) {
            copy.add('+' + String.valueOf(values.size() - size) + ' more');
        }
        return String.join(copy, ', ');
    }

    private static CheckItem buildStorageHealthItem(Decimal usedValue, Decimal maxValue) {
        if (maxValue == null || maxValue <= 0) {
            return buildItem(
                'storageHealth',
                'Storage health',
                'Warning',
                'Data storage limit is unavailable.',
                'Review org limits and ensure sufficient free storage.'
            );
        }

        Decimal safeUsed = usedValue == null ? 0 : usedValue;
        Decimal usedPct = (safeUsed * 100) / maxValue;
        String usageSummary = String.valueOf(safeUsed.setScale(2)) + ' of ' + String.valueOf(maxValue.setScale(2)) +
            ' (' + String.valueOf(usedPct.setScale(2)) + '%)';
        if (usedPct >= 100) {
            return buildItem(
                'storageHealth',
                'Storage health',
                'Blocked',
                'Data storage is fully consumed: ' + usageSummary,
                'Free storage before running inventory and usage scans.'
            );
        }
        if (usedPct >= 90) {
            return buildItem(
                'storageHealth',
                'Storage health',
                'Warning',
                'Data storage is high: ' + usageSummary,
                'Free storage to prevent scan degradation or partial results.'
            );
        }

        return buildItem(
            'storageHealth',
            'Storage health',
            'Ready',
            'Storage usage is healthy: ' + usageSummary,
            'No action required.'
        );
    }

    private static CheckItem buildItem(String key, String label, String status, String message, String remediation) {
        CheckItem item = new CheckItem();
        item.key = key;
        item.label = label;
        item.status = status;
        item.message = message;
        item.remediation = remediation;
        return item;
    }

    @TestVisible
    static void setTestOverrides(TestOverrides overrides) {
        testOverrides = overrides;
    }

    @TestVisible
    static void clearTestOverrides() {
        testOverrides = null;
    }
}
