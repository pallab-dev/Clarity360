public with sharing class MetadataComponentInventoryService {
    public class ComponentRecord {
        public String componentKey;
        public String componentType;
        public String apiName;
        public String displayName;
        public String namespacePrefix;
        public Boolean isActive = true;
        public Integer referenceCount = 0;
        public Integer activeSubscriberCount = 0;
        public Boolean monitoringEligible = false;
        public String sourceSummary;
        public String toolingStatus;
    }

    @TestVisible private static Map<String, ComponentRecord> testDiscoveredComponents;
    @TestVisible private static List<String> testApexBodies;
    @TestVisible private static List<String> testValidationFormulas;
    @TestVisible private static Map<String, Integer> testPlatformEventActiveSubscribers;

    public static void refreshAll(Integer maxRows) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(MetadataComponentInventory__c.SObjectType, 'MetadataInventoryRead');
        access.assertCreateable(MetadataComponentInventory__c.SObjectType, 'MetadataInventoryWrite');
        access.assertUpdateable(MetadataComponentInventory__c.SObjectType, 'MetadataInventoryWrite');
        access.assertDeleteable(MetadataComponentInventory__c.SObjectType, 'MetadataInventoryWrite');

        Map<String, ComponentRecord> components = discoverComponents();
        if (components.isEmpty()) {
            deactivateMissingComponents(new Set<String>(), System.now());
            return;
        }

        Integer safeMaxRows = (maxRows == null || maxRows <= 0) ? 500 : Math.min(maxRows, 5000);
        enrichWithToolingMetadata(components, safeMaxRows);
        enrichWithApexReferences(components, safeMaxRows);
        enrichWithValidationRuleReferences(components, safeMaxRows);
        enrichWithPlatformEventSubscribers(components, safeMaxRows);

        Datetime scannedAt = System.now();
        List<MetadataComponentInventory__c> upserts = new List<MetadataComponentInventory__c>();
        Set<String> generatedKeys = new Set<String>();
        for (ComponentRecord component : components.values()) {
            if (component == null || String.isBlank(component.componentKey)) {
                continue;
            }
            generatedKeys.add(component.componentKey);
            upserts.add(new MetadataComponentInventory__c(
                ComponentKey__c = component.componentKey,
                ComponentType__c = component.componentType,
                ApiName__c = component.apiName,
                DisplayName__c = component.displayName,
                NamespacePrefix__c = component.namespacePrefix,
                IsActive__c = component.isActive,
                ReferenceCount__c = component.referenceCount,
                ActiveSubscriberCount__c = component.activeSubscriberCount,
                MonitoringEligible__c = component.monitoringEligible,
                LastScannedOn__c = scannedAt,
                SourceSummary__c = buildSourceSummary(component)
            ));
        }

        if (!upserts.isEmpty()) {
            List<SObject> rawRows = new List<SObject>();
            rawRows.addAll(upserts);
            List<SObject> cleanedRows = access.stripForUpsert(rawRows);
            if (!cleanedRows.isEmpty()) {
                List<MetadataComponentInventory__c> cleanedUpserts = new List<MetadataComponentInventory__c>();
                for (SObject row : cleanedRows) {
                    cleanedUpserts.add((MetadataComponentInventory__c) row);
                }
                upsert cleanedUpserts ComponentKey__c;
            }
        }
        deactivateMissingComponents(generatedKeys, scannedAt);
    }

    private static void deactivateMissingComponents(Set<String> activeKeys, Datetime scannedAt) {
        List<MetadataComponentInventory__c> staleRows = [
            SELECT Id, ComponentKey__c, IsActive__c
            FROM MetadataComponentInventory__c
        ];
        List<MetadataComponentInventory__c> updates = new List<MetadataComponentInventory__c>();
        Set<Id> purgeIds = new Set<Id>();
        Boolean storageConstrained = InventoryService.isStorageConstrained();
        for (MetadataComponentInventory__c row : staleRows) {
            if (activeKeys.contains(row.ComponentKey__c)) {
                continue;
            }
            if (row.IsActive__c == true) {
                updates.add(new MetadataComponentInventory__c(
                    Id = row.Id,
                    IsActive__c = false,
                    LastScannedOn__c = scannedAt
                ));
            }
            if (storageConstrained) {
                purgeIds.add(row.Id);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
        if (!purgeIds.isEmpty()) {
            delete [SELECT Id FROM MetadataComponentInventory__c WHERE Id IN :purgeIds];
        }
    }

    private static Map<String, ComponentRecord> discoverComponents() {
        if (Test.isRunningTest() && testDiscoveredComponents != null) {
            return cloneComponents(testDiscoveredComponents);
        }

        Map<String, ComponentRecord> components = new Map<String, ComponentRecord>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String objectApiName : globalDescribe.keySet()) {
            Schema.SObjectType objectType = globalDescribe.get(objectApiName);
            if (objectType == null) {
                continue;
            }
            Schema.DescribeSObjectResult describe = objectType.getDescribe();
            if (describe == null || describe.isDeprecatedAndHidden()) {
                continue;
            }

            ComponentRecord component = null;
            if (describe.isCustomSetting()) {
                component = newComponent('Custom Setting', objectApiName, false);
            } else if (objectApiName.endsWith('__mdt')) {
                component = newComponent('Custom Metadata Type', objectApiName, false);
            } else if (objectApiName.endsWith('__e')) {
                component = newComponent('Platform Event', objectApiName, true);
            }

            if (component != null) {
                components.put(component.componentKey, component);
            }
        }
        return components;
    }

    private static ComponentRecord newComponent(String componentType, String apiName, Boolean monitoringEligible) {
        ComponentRecord component = new ComponentRecord();
        component.componentType = componentType;
        component.apiName = apiName;
        component.displayName = apiName;
        component.namespacePrefix = extractNamespacePrefix(apiName);
        component.monitoringEligible = monitoringEligible == true;
        component.componentKey = buildComponentKey(componentType, apiName);
        return component;
    }

    private static void enrichWithToolingMetadata(Map<String, ComponentRecord> components, Integer maxRows) {
        if (components == null || components.isEmpty()) {
            return;
        }
        Set<String> developerNames = new Set<String>();
        for (ComponentRecord component : components.values()) {
            developerNames.add(extractDeveloperName(component.apiName));
        }
        if (developerNames.isEmpty()) {
            return;
        }

        ToolingApiService.ToolingQueryResult result = ToolingApiService.query(
            'SELECT DeveloperName, NamespacePrefix, DeploymentStatus FROM CustomObject LIMIT ' + maxRows,
            maxRows
        );
        if (result == null || result.success != true || result.records == null) {
            return;
        }

        Map<String, String> statusByKey = new Map<String, String>();
        for (Map<String, Object> row : result.records) {
            String developerName = ToolingApiService.getString(row, 'DeveloperName');
            String namespacePrefix = ToolingApiService.getString(row, 'NamespacePrefix');
            String status = ToolingApiService.getString(row, 'DeploymentStatus');
            if (String.isBlank(developerName)) {
                continue;
            }
            statusByKey.put(buildToolingLookupKey(namespacePrefix, developerName), status);
        }

        for (ComponentRecord component : components.values()) {
            String lookupKey = buildToolingLookupKey(component.namespacePrefix, extractDeveloperName(component.apiName));
            if (statusByKey.containsKey(lookupKey)) {
                component.toolingStatus = statusByKey.get(lookupKey);
            }
        }
    }

    private static void enrichWithApexReferences(Map<String, ComponentRecord> components, Integer maxRows) {
        List<String> bodies = new List<String>();
        if (Test.isRunningTest() && testApexBodies != null) {
            bodies.addAll(testApexBodies);
        } else {
            for (ApexClass row : [SELECT Body FROM ApexClass LIMIT :maxRows]) {
                if (row.Body != null) {
                    bodies.add(row.Body);
                }
            }
            for (ApexTrigger row : [SELECT Body FROM ApexTrigger LIMIT :maxRows]) {
                if (row.Body != null) {
                    bodies.add(row.Body);
                }
            }
        }

        for (String body : bodies) {
            String normalized = safeLower(body);
            for (ComponentRecord component : components.values()) {
                if (containsToken(normalized, safeLower(component.apiName))) {
                    component.referenceCount++;
                }
            }
        }
    }

    private static void enrichWithValidationRuleReferences(Map<String, ComponentRecord> components, Integer maxRows) {
        List<String> formulas = new List<String>();
        if (Test.isRunningTest() && testValidationFormulas != null) {
            formulas.addAll(testValidationFormulas);
        } else {
            try {
                List<SObject> rules = Database.query(
                    'SELECT ErrorConditionFormula FROM ValidationRule LIMIT ' + maxRows
                );
                for (SObject row : rules) {
                    formulas.add((String) row.get('ErrorConditionFormula'));
                }
            } catch (Exception ex) {
                return;
            }
        }

        for (String formula : formulas) {
            String normalized = safeLower(formula);
            for (ComponentRecord component : components.values()) {
                if (component.componentType == 'Platform Event') {
                    continue;
                }
                if (containsToken(normalized, safeLower(component.apiName)) ||
                    containsToken(normalized, safeLower(extractDeveloperName(component.apiName)))) {
                    component.referenceCount++;
                }
            }
        }
    }

    private static void enrichWithPlatformEventSubscribers(Map<String, ComponentRecord> components, Integer maxRows) {
        Map<String, Integer> subscriberCounts = new Map<String, Integer>();
        if (Test.isRunningTest() && testPlatformEventActiveSubscribers != null) {
            subscriberCounts.putAll(testPlatformEventActiveSubscribers);
        } else {
            Set<String> eventApiNames = new Set<String>();
            for (ComponentRecord component : components.values()) {
                if (component.componentType == 'Platform Event') {
                    eventApiNames.add(component.apiName);
                }
            }
            if (eventApiNames.isEmpty()) {
                return;
            }
            for (ApexTrigger triggerRow : [
                SELECT TableEnumOrId, Status
                FROM ApexTrigger
                WHERE TableEnumOrId IN :eventApiNames
                LIMIT :maxRows
            ]) {
                if (String.valueOf(triggerRow.Status) != 'Active') {
                    continue;
                }
                String eventApiName = String.valueOf(triggerRow.TableEnumOrId);
                Integer current = subscriberCounts.containsKey(eventApiName) ? subscriberCounts.get(eventApiName) : 0;
                subscriberCounts.put(eventApiName, current + 1);
            }
        }

        for (ComponentRecord component : components.values()) {
            if (component.componentType != 'Platform Event') {
                continue;
            }
            Integer activeSubscribers = subscriberCounts.containsKey(component.apiName)
                ? subscriberCounts.get(component.apiName)
                : 0;
            component.activeSubscriberCount = activeSubscribers;
            component.referenceCount += activeSubscribers;
        }
    }

    private static String buildSourceSummary(ComponentRecord component) {
        List<String> parts = new List<String>{
            'Discovery=Describe',
            'ComponentType=' + component.componentType,
            'ApiName=' + component.apiName,
            'ReferenceCount=' + String.valueOf(component.referenceCount),
            'ActiveSubscriberCount=' + String.valueOf(component.activeSubscriberCount),
            'MonitoringEligible=' + String.valueOf(component.monitoringEligible)
        };
        if (!String.isBlank(component.namespacePrefix)) {
            parts.add('NamespacePrefix=' + component.namespacePrefix);
        }
        if (!String.isBlank(component.toolingStatus)) {
            parts.add('ToolingDeploymentStatus=' + component.toolingStatus);
        }
        return String.join(parts, '; ');
    }

    private static Map<String, ComponentRecord> cloneComponents(Map<String, ComponentRecord> source) {
        Map<String, ComponentRecord> cloned = new Map<String, ComponentRecord>();
        for (String key : source.keySet()) {
            ComponentRecord original = source.get(key);
            ComponentRecord copy = new ComponentRecord();
            copy.componentKey = original.componentKey;
            copy.componentType = original.componentType;
            copy.apiName = original.apiName;
            copy.displayName = original.displayName;
            copy.namespacePrefix = original.namespacePrefix;
            copy.isActive = original.isActive;
            copy.referenceCount = original.referenceCount;
            copy.activeSubscriberCount = original.activeSubscriberCount;
            copy.monitoringEligible = original.monitoringEligible;
            copy.sourceSummary = original.sourceSummary;
            copy.toolingStatus = original.toolingStatus;
            cloned.put(key, copy);
        }
        return cloned;
    }

    private static String buildComponentKey(String componentType, String apiName) {
        if (componentType == 'Custom Metadata Type') {
            return 'META.CMDT.' + apiName;
        }
        if (componentType == 'Custom Setting') {
            return 'META.CUSTOMSETTING.' + apiName;
        }
        if (componentType == 'Platform Event') {
            return 'META.PEVENT.' + apiName;
        }
        return 'META.COMPONENT.' + apiName;
    }

    private static String buildToolingLookupKey(String namespacePrefix, String developerName) {
        return (String.isBlank(namespacePrefix) ? '' : namespacePrefix.toLowerCase()) +
            ':' + (developerName == null ? '' : developerName.toLowerCase());
    }

    private static String extractDeveloperName(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        String normalized = apiName;
        if (normalized.endsWith('__mdt') || normalized.endsWith('__e') || normalized.endsWith('__c')) {
            normalized = normalized.substring(0, normalized.lastIndexOf('__'));
        }
        if (normalized.contains('__')) {
            List<String> parts = normalized.split('__');
            return parts.size() >= 2 ? parts[1] : parts[0];
        }
        return normalized;
    }

    private static String extractNamespacePrefix(String apiName) {
        if (String.isBlank(apiName) || !apiName.contains('__')) {
            return null;
        }
        List<String> parts = apiName.split('__');
        return parts.size() >= 3 ? parts[0] : null;
    }

    private static Boolean containsToken(String haystack, String needle) {
        if (String.isBlank(haystack) || String.isBlank(needle)) {
            return false;
        }
        String normalizedNeedle = needle.toLowerCase();
        String padded = ' ' + haystack.toLowerCase() + ' ';
        return padded.contains('.' + normalizedNeedle) ||
            padded.contains(' ' + normalizedNeedle + ' ') ||
            padded.contains('\'' + normalizedNeedle + '\'') ||
            padded.contains('"' + normalizedNeedle + '"') ||
            haystack.toLowerCase().contains(normalizedNeedle);
    }

    private static String safeLower(String input) {
        return input == null ? null : input.toLowerCase();
    }

    @TestVisible
    static void setTestDiscovery(Map<String, ComponentRecord> components) {
        testDiscoveredComponents = components;
    }

    @TestVisible
    static void setTestApexBodies(List<String> bodies) {
        testApexBodies = bodies;
    }

    @TestVisible
    static void setTestValidationFormulas(List<String> formulas) {
        testValidationFormulas = formulas;
    }

    @TestVisible
    static void setTestPlatformEventActiveSubscribers(Map<String, Integer> subscriberCounts) {
        testPlatformEventActiveSubscribers = subscriberCounts;
    }

    @TestVisible
    static void clearTestOverrides() {
        testDiscoveredComponents = null;
        testApexBodies = null;
        testValidationFormulas = null;
        testPlatformEventActiveSubscribers = null;
    }
}
