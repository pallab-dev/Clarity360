public with sharing class InventoryService {
    private static final Decimal STORAGE_PRESSURE_PCT = 95;
    private static final Integer MAX_FIELDS_PER_OBJECT = 200;
    private static final Set<String> INTERNAL_APPLICATION_OBJECTS = new Set<String>{
        'clarity360setupconfig__c',
        'fieldinventory__c',
        'metadatacomponentinventory__c',
        'recommendation__c',
        'scanjob__c',
        'usagesignal__c'
    };
    private static final Set<String> EXCLUDED_METADATA_OBJECTS = new Set<String>{
        'apexclass',
        'apexcomponent',
        'apexpage',
        'apextrigger',
        'appmenuitem',
        'entitydefinition',
        'fielddefinition',
        'flow',
        'validationrule',
        'workflowrule'
    };
    private static final Set<Schema.DisplayType> EXCLUDED_FIELD_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.Address,
        Schema.DisplayType.Base64,
        Schema.DisplayType.Location
    };

    public class RefreshResult {
        @AuraEnabled public Integer scannedObjectCount;
        @AuraEnabled public Integer upsertedFieldCount;
        @AuraEnabled public Integer inactivatedFieldCount;
    }

    public class RefreshChunkResult {
        @AuraEnabled public Integer scannedObjectCount;
        @AuraEnabled public Integer upsertedFieldCount;
        @AuraEnabled public Integer inactivatedFieldCount;
        @AuraEnabled public Integer nextIndex;
        @AuraEnabled public Integer totalObjects;
        @AuraEnabled public Boolean hasMore;
    }

    public static RefreshResult refreshInventory(Boolean customObjectsOnly, Integer maxObjects) {
        RefreshResult result = new RefreshResult();
        result.scannedObjectCount = 0;
        result.upsertedFieldCount = 0;
        result.inactivatedFieldCount = 0;

        Integer cursor = 0;
        while (true) {
            RefreshChunkResult chunk = refreshInventoryChunk(customObjectsOnly, maxObjects, cursor, 25);
            result.scannedObjectCount += chunk.scannedObjectCount;
            result.upsertedFieldCount += chunk.upsertedFieldCount;
            result.inactivatedFieldCount += chunk.inactivatedFieldCount;
            if (chunk.hasMore != true) {
                break;
            }
            cursor = chunk.nextIndex;
        }

        return result;
    }

    public static RefreshChunkResult refreshInventoryChunk(
        Boolean customObjectsOnly,
        Integer maxObjects,
        Integer startIndex,
        Integer chunkSize
    ) {
        Boolean customOnly = (customObjectsOnly == null) ? true : customObjectsOnly;
        List<String> scopedObjectNames = getScopedObjectNames(customOnly, maxObjects);
        return refreshInventoryChunkForScopedObjects(scopedObjectNames, customOnly, startIndex, chunkSize);
    }

    public static RefreshChunkResult refreshInventoryChunkForScopedObjects(
        List<String> scopedObjectNames,
        Boolean customObjectsOnly,
        Integer startIndex,
        Integer chunkSize
    ) {
        Boolean customOnly = (customObjectsOnly == null) ? true : customObjectsOnly;
        Integer safeStart = (startIndex == null || startIndex < 0) ? 0 : startIndex;
        Integer safeChunkSize = (chunkSize == null || chunkSize <= 0) ? 25 : Math.min(chunkSize, 50);
        List<String> safeObjects = scopedObjectNames == null ? new List<String>() : scopedObjectNames;
        Integer totalObjects = safeObjects.size();
        Integer endIndex = Math.min(safeStart + safeChunkSize, totalObjects);

        RefreshChunkResult result = new RefreshChunkResult();
        result.scannedObjectCount = 0;
        result.upsertedFieldCount = 0;
        result.inactivatedFieldCount = 0;
        result.totalObjects = totalObjects;
        result.nextIndex = endIndex;
        result.hasMore = endIndex < totalObjects;

        if (safeStart >= totalObjects) {
            result.nextIndex = totalObjects;
            result.hasMore = false;
            return result;
        }

        for (Integer i = safeStart; i < endIndex; i++) {
            String objectName = safeObjects[i];
            ObjectRefreshResult objectResult = refreshSingleObject(objectName, customOnly);
            result.scannedObjectCount++;
            result.upsertedFieldCount += objectResult.upsertedFieldCount;
            result.inactivatedFieldCount += objectResult.inactivatedFieldCount;
        }
        return result;
    }

    private static Boolean isObjectInScope(Schema.DescribeSObjectResult sObjectDescribe, Boolean customOnly) {
        if (isExcludedMetadataObject(sObjectDescribe.getName())) {
            return false;
        }
        if (isObjectExcludedByRuntimeConfig(sObjectDescribe.getName())) {
            return false;
        }
        if (!sObjectDescribe.isQueryable()) {
            return false;
        }
        if (sObjectDescribe.isDeprecatedAndHidden()) {
            return false;
        }
        if (!sObjectDescribe.isAccessible()) {
            return false;
        }
        if (customOnly && !sObjectDescribe.isCustom()) {
            return false;
        }
        if (!isObjectInRecommendationScope(sObjectDescribe.getName(), sObjectDescribe.isCustom())) {
            return false;
        }

        return true;
    }

    private class ObjectRefreshResult {
        public Integer upsertedFieldCount = 0;
        public Integer inactivatedFieldCount = 0;
    }

    private static ObjectRefreshResult refreshSingleObject(String objectName, Boolean customOnly) {
        ObjectRefreshResult result = new ObjectRefreshResult();
        if (String.isBlank(objectName)) {
            return result;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objectType = globalDescribe.get(objectName);
        if (objectType == null) {
            return result;
        }
        Schema.DescribeSObjectResult sObjectDescribe = objectType.getDescribe();
        if (!isObjectInScope(sObjectDescribe, customOnly)) {
            return result;
        }

        Datetime scannedAt = System.now();

        List<FieldInventory__c> upserts = new List<FieldInventory__c>();
        Set<String> generatedFieldKeys = new Set<String>();
        Map<String, Schema.SObjectField> fields = sObjectDescribe.fields.getMap();
        List<String> fieldNames = new List<String>(fields.keySet());
        fieldNames.sort();
        fieldNames.sort(new CustomFieldFirstComparator(fields));
        Integer includedFieldsForObject = 0;

        for (String fieldName : fieldNames) {
            // Guardrail for low-storage orgs: cap inventory volume per object.
            if (includedFieldsForObject >= MAX_FIELDS_PER_OBJECT) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
            if (!isFieldInScope(sObjectDescribe, fieldDescribe)) {
                continue;
            }

            String fieldKey = objectName + '.' + fieldName;
            upserts.add(new FieldInventory__c(
                FieldKey__c = fieldKey,
                ObjectApiName__c = objectName,
                FieldApiName__c = fieldName,
                DataType__c = String.valueOf(fieldDescribe.getType()),
                IsCustomField__c = fieldDescribe.isCustom(),
                IncludedInScope__c = true,
                NamespacePrefix__c = extractNamespacePrefix(fieldName),
                IsActive__c = true,
                LastScannedOn__c = scannedAt
            ));
            generatedFieldKeys.add(fieldKey);
            includedFieldsForObject++;
        }

        if (!upserts.isEmpty()) {
            List<SObject> rawRows = new List<SObject>();
            rawRows.addAll(upserts);
            List<SObject> cleanedRows = Clarity360AccessControlService.get().stripForUpsert(rawRows);
            if (!cleanedRows.isEmpty()) {
                List<FieldInventory__c> cleanedUpserts = new List<FieldInventory__c>();
                for (SObject row : cleanedRows) {
                    cleanedUpserts.add((FieldInventory__c) row);
                }
                upsert cleanedUpserts FieldKey__c;
                result.upsertedFieldCount = cleanedUpserts.size();
            }
        }

        List<FieldInventory__c> staleRows = [
            SELECT Id, FieldKey__c, IsActive__c
            FROM FieldInventory__c
            WHERE ObjectApiName__c = :objectName
        ];
        List<FieldInventory__c> deactivations = new List<FieldInventory__c>();
        Set<String> staleKeys = new Set<String>();
        for (FieldInventory__c row : staleRows) {
            if (!generatedFieldKeys.contains(row.FieldKey__c)) {
                staleKeys.add(row.FieldKey__c);
                if (row.IsActive__c == true) {
                    deactivations.add(new FieldInventory__c(
                        Id = row.Id,
                        IsActive__c = false,
                        LastScannedOn__c = scannedAt
                    ));
                }
            }
        }
        if (!deactivations.isEmpty()) {
            update deactivations;
            result.inactivatedFieldCount = deactivations.size();
        }
        if (!staleKeys.isEmpty()) {
            purgeDerivedRowsForFieldKeys(staleKeys);
            purgeInactiveInventoryIfStorageConstrained(staleKeys);
        }

        return result;
    }

    public static List<String> getScopedObjectNames(Boolean customObjectsOnly, Integer maxObjects) {
        Boolean customOnly = (customObjectsOnly == null) ? true : customObjectsOnly;
        Integer objectLimit = (maxObjects == null || maxObjects <= 0) ? 200 : maxObjects;

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        List<String> objectNames = new List<String>(globalDescribe.keySet());
        objectNames.sort();
        Integer accountIndex = objectNames.indexOf('Account');
        if (accountIndex >= 0) {
            objectNames.remove(accountIndex);
            objectNames.add(0, 'Account');
        }

        List<String> scoped = new List<String>();
        for (String objectName : objectNames) {
            if (scoped.size() >= objectLimit) {
                break;
            }
            Schema.SObjectType objectType = globalDescribe.get(objectName);
            if (objectType == null) {
                continue;
            }
            Schema.DescribeSObjectResult sObjectDescribe = objectType.getDescribe();
            if (!isObjectInScope(sObjectDescribe, customOnly)) {
                continue;
            }
            scoped.add(objectName);
        }
        return scoped;
    }

    public static Boolean isObjectExcludedByRuntimeConfig(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return true;
        }

        Clarity360Settings.RuntimeConfig runtime = Clarity360Settings.getRuntime();
        Set<String> excludedObjects = parseDelimitedValues(runtime.excludedObjects);
        if (excludedObjects.contains(objectApiName.trim().toLowerCase())) {
            return true;
        }

        String namespacePrefix = extractNamespacePrefix(objectApiName);
        if (String.isBlank(namespacePrefix)) {
            return false;
        }
        Set<String> excludedNamespaces = parseDelimitedValues(runtime.excludedNamespaces);
        return excludedNamespaces.contains(namespacePrefix.toLowerCase());
    }

    public static void cleanupExcludedInventory(List<String> scopedObjectNames) {
        Set<String> allowedObjects = new Set<String>();
        for (String objectName : (scopedObjectNames == null ? new List<String>() : scopedObjectNames)) {
            if (!String.isBlank(objectName)) {
                allowedObjects.add(objectName);
            }
        }

        List<FieldInventory__c> inventoryRows = [
            SELECT Id, FieldKey__c, ObjectApiName__c
            FROM FieldInventory__c
        ];
        if (inventoryRows.isEmpty()) {
            return;
        }

        List<FieldInventory__c> inventoryUpdates = new List<FieldInventory__c>();
        Set<String> keysToRemove = new Set<String>();
        Datetime scannedAt = System.now();
        for (FieldInventory__c row : inventoryRows) {
            if (!allowedObjects.contains(row.ObjectApiName__c)) {
                inventoryUpdates.add(new FieldInventory__c(
                    Id = row.Id,
                    IsActive__c = false,
                    LastScannedOn__c = scannedAt
                ));
                if (!String.isBlank(row.FieldKey__c)) {
                    keysToRemove.add(row.FieldKey__c);
                }
            }
        }

        purgeDerivedRowsForFieldKeys(keysToRemove);
        if (!inventoryUpdates.isEmpty()) {
            update inventoryUpdates;
            purgeInactiveInventoryIfStorageConstrained(keysToRemove);
        }
    }

    private static void purgeDerivedRowsForFieldKeys(Set<String> fieldKeys) {
        if (fieldKeys == null || fieldKeys.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM UsageSignal__c WHERE FieldKey__c IN :fieldKeys];
        delete [SELECT Id FROM Recommendation__c WHERE FieldKey__c IN :fieldKeys];
    }

    private static void purgeInactiveInventoryIfStorageConstrained(Set<String> fieldKeys) {
        if (!isStorageConstrained() || fieldKeys == null || fieldKeys.isEmpty()) {
            return;
        }
        delete [
            SELECT Id
            FROM FieldInventory__c
            WHERE FieldKey__c IN :fieldKeys
            AND IsActive__c = false
        ];
    }

    public static Boolean isStorageConstrained() {
        try {
            Map<String, System.OrgLimit> limitsByName = System.OrgLimits.getMap();
            System.OrgLimit dataStorage = limitsByName.get('DataStorageMB');
            if (dataStorage == null) {
                dataStorage = limitsByName.get('DataStorage');
            }
            if (dataStorage == null || dataStorage.getLimit() == null || dataStorage.getLimit() <= 0) {
                return false;
            }
            Decimal pctUsed = (dataStorage.getValue() * 100.0) / dataStorage.getLimit();
            return pctUsed >= STORAGE_PRESSURE_PCT;
        } catch (Exception ex) {
            return false;
        }
    }

    public static Boolean isObjectInRecommendationScope(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return false;
        }
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objectType = globalDescribe.get(objectApiName);
        if (objectType == null) {
            return false;
        }
        Schema.DescribeSObjectResult describe = objectType.getDescribe();
        return isObjectInRecommendationScope(describe.getName(), describe.isCustom());
    }

    public static Boolean isObjectInRecommendationScope(String objectApiName, Boolean isCustomObject) {
        if (String.isBlank(objectApiName)) {
            return false;
        }
        if (isExcludedMetadataObject(objectApiName)) {
            return false;
        }
        Clarity360Settings.RuntimeConfig runtime = Clarity360Settings.getRuntime();
        if (isCustomObject != true && (runtime == null || runtime.includeStandardObjects != true)) {
            return false;
        }
        Schema.DescribeSObjectResult describe = getDescribe(objectApiName);
        if (describe == null) {
            return false;
        }
        if (isSpecialUseObject(describe)) {
            return false;
        }
        if (isCustomObject == true) {
            return true;
        }
        if (describe.isCustom()) {
            return false;
        }
        return hasAnyEligibleField(describe);
    }

    public static Boolean isExcludedMetadataObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return true;
        }
        String normalized = objectApiName.trim().toLowerCase();
        if (INTERNAL_APPLICATION_OBJECTS.contains(normalized)) {
            return true;
        }
        if (EXCLUDED_METADATA_OBJECTS.contains(normalized)) {
            return true;
        }
        if (normalized.endsWith('__mdt')) {
            return true;
        }
        return normalized.startsWith('apex');
    }

    private static Schema.DescribeSObjectResult getDescribe(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objectType = globalDescribe.get(objectApiName);
        return objectType == null ? null : objectType.getDescribe();
    }

    private static Boolean hasAnyCustomField(Schema.DescribeSObjectResult sObjectDescribe) {
        if (sObjectDescribe == null) {
            return false;
        }
        for (Schema.SObjectField fieldRef : sObjectDescribe.fields.getMap().values()) {
            if (fieldRef.getDescribe().isCustom()) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static Boolean isFieldInScope(String objectApiName, String fieldApiName) {
        Schema.DescribeSObjectResult describe = getDescribe(objectApiName);
        if (describe == null || String.isBlank(fieldApiName)) {
            return false;
        }
        Schema.SObjectField fieldRef = describe.fields.getMap().get(fieldApiName);
        return fieldRef == null ? false : isFieldInScope(describe, fieldRef.getDescribe());
    }

    private static Boolean hasAnyEligibleField(Schema.DescribeSObjectResult sObjectDescribe) {
        if (sObjectDescribe == null) {
            return false;
        }
        if (isExcludedMetadataObject(sObjectDescribe.getName()) || isSpecialUseObject(sObjectDescribe)) {
            return false;
        }
        Map<String, Schema.SObjectField> fieldsByName = sObjectDescribe.fields.getMap();
        for (String fieldName : fieldsByName.keySet()) {
            if (!isEligibleCustomFieldApi(fieldName)) {
                continue;
            }
            if (isManagedComponent(fieldName)) {
                continue;
            }
            if (isFieldInScope(sObjectDescribe, fieldsByName.get(fieldName).getDescribe())) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isFieldInScope(
        Schema.DescribeSObjectResult objectDescribe,
        Schema.DescribeFieldResult fieldDescribe
    ) {
        if (objectDescribe == null || fieldDescribe == null) {
            return false;
        }
        if (isExcludedMetadataObject(objectDescribe.getName())) {
            return false;
        }
        if (fieldDescribe.isDeprecatedAndHidden()) {
            return false;
        }
        if (!fieldDescribe.isAccessible()) {
            return false;
        }
        if (!isEligibleCustomFieldApi(fieldDescribe.getName())) {
            return false;
        }
        if (isManagedComponent(fieldDescribe.getName())) {
            return false;
        }
        if (fieldDescribe.getType() != null && EXCLUDED_FIELD_TYPES.contains(fieldDescribe.getType())) {
            return false;
        }
        if (!fieldDescribe.isCustom()) {
            return false;
        }
        if (isCompoundComponentField(fieldDescribe)) {
            return false;
        }
        if (isSpecialUseObject(objectDescribe)) {
            return false;
        }
        return true;
    }

    private static Boolean isEligibleCustomFieldApi(String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            return false;
        }
        return fieldApiName.trim().toLowerCase().endsWith('__c');
    }

    private static Boolean isCompoundComponentField(Schema.DescribeFieldResult fieldDescribe) {
        if (fieldDescribe == null) {
            return false;
        }
        try {
            return !String.isBlank(fieldDescribe.getCompoundFieldName());
        } catch (Exception ex) {
            return false;
        }
    }

    private static Boolean isSpecialUseObject(Schema.DescribeSObjectResult sObjectDescribe) {
        if (sObjectDescribe == null) {
            return true;
        }
        String objectName = sObjectDescribe.getName();
        String normalized = objectName == null ? '' : objectName.toLowerCase();
        if (normalized.endsWith('__b') || normalized.endsWith('__x') || normalized.endsWith('__e')) {
            return true;
        }
        return sObjectDescribe.isCustomSetting();
    }

    private class CustomFieldFirstComparator implements Comparator<String> {
        private Map<String, Schema.SObjectField> fieldsByName;

        CustomFieldFirstComparator(Map<String, Schema.SObjectField> fieldsByName) {
            this.fieldsByName = fieldsByName == null ? new Map<String, Schema.SObjectField>() : fieldsByName;
        }

        public Integer compare(String left, String right) {
            Boolean leftCustom = isCustom(left);
            Boolean rightCustom = isCustom(right);
            if (leftCustom != rightCustom) {
                return leftCustom ? -1 : 1;
            }
            String leftValue = String.valueOf(left).toLowerCase();
            String rightValue = String.valueOf(right).toLowerCase();
            if (leftValue == rightValue) {
                return 0;
            }
            return leftValue < rightValue ? -1 : 1;
        }

        private Boolean isCustom(String fieldName) {
            if (String.isBlank(fieldName) || !fieldsByName.containsKey(fieldName)) {
                return false;
            }
            return fieldsByName.get(fieldName).getDescribe().isCustom();
        }
    }

    private static Set<String> parseDelimitedValues(String rawValues) {
        Set<String> values = new Set<String>();
        if (String.isBlank(rawValues)) {
            return values;
        }
        for (String token : rawValues.split('[,;\\n\\r]+')) {
            String normalized = token == null ? null : token.trim().toLowerCase();
            if (!String.isBlank(normalized)) {
                values.add(normalized);
            }
        }
        return values;
    }

    private static String extractNamespacePrefix(String objectApiName) {
        if (String.isBlank(objectApiName) || !objectApiName.contains('__')) {
            return null;
        }
        List<String> parts = objectApiName.split('__');
        return parts.size() >= 3 ? parts[0] : null;
    }

    private static Boolean isManagedComponent(String apiName) {
        return !String.isBlank(extractNamespacePrefix(apiName));
    }

}
