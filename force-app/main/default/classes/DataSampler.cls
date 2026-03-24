public with sharing class DataSampler {
    public static List<UsageSignal__c> scanObject(
        String objectApiName,
        List<FieldInventory__c> fieldInventories,
        Integer sampleLimit
    ) {
        List<UsageSignal__c> signals = new List<UsageSignal__c>();
        if (String.isBlank(objectApiName) || fieldInventories == null || fieldInventories.isEmpty()) {
            return signals;
        }

        Integer maxSamples = (sampleLimit == null || sampleLimit <= 0) ? 5000 : sampleLimit;
        if (!isSafeApiName(objectApiName)) {
            return signals;
        }
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectApiName)) {
            return signals;
        }

        Map<String, Schema.SObjectField> objectFields = globalDescribe.get(objectApiName).getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{ 'Id' };
        Map<String, Integer> nonNullCountByField = new Map<String, Integer>();
        Set<String> queryableFields = new Set<String>();

        for (FieldInventory__c inventory : fieldInventories) {
            if (String.isBlank(inventory.FieldApiName__c) || !objectFields.containsKey(inventory.FieldApiName__c)) {
                continue;
            }
            if (inventory.FieldApiName__c == 'Id') {
                continue;
            }
            if (!isSafeApiName(inventory.FieldApiName__c)) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = objectFields.get(inventory.FieldApiName__c).getDescribe();
            if (fieldDescribe.isAccessible() && fieldDescribe.isFilterable()) {
                queryableFields.add(inventory.FieldApiName__c);
                queryFields.add(inventory.FieldApiName__c);
                nonNullCountByField.put(inventory.FieldApiName__c, 0);
            }
        }

        List<SObject> sampledRecords = new List<SObject>();
        if (queryFields.size() > 1) {
            String soql = 'SELECT ' + String.join(queryFields, ',') + ' FROM ' + objectApiName + ' LIMIT ' + maxSamples;
            sampledRecords = Database.query(soql);

            for (SObject row : sampledRecords) {
                for (String fieldName : queryableFields) {
                    if (row.get(fieldName) != null) {
                        nonNullCountByField.put(fieldName, nonNullCountByField.get(fieldName) + 1);
                    }
                }
            }
        }

        Integer sampleSize = sampledRecords.size();
        Integer objectRecordCount = getObjectRecordCount(objectApiName);
        Integer minRecordThreshold = Clarity360Settings.get().minObjectRecordCount;
        Boolean meetsMinRecordThreshold = objectRecordCount >= minRecordThreshold;
        Datetime observedAt = System.now();
        Set<String> fieldApiNames = new Set<String>();
        for (FieldInventory__c inventoryRow : fieldInventories) {
            if (!String.isBlank(inventoryRow.FieldApiName__c)) {
                fieldApiNames.add(inventoryRow.FieldApiName__c);
            }
        }
        Map<String, DependencySignalService.FieldDependencySummary> dependencyByField =
            DependencySignalService.scan(objectApiName, fieldApiNames);
        Map<String, LayoutScanService.FieldLayoutSummary> layoutByField =
            LayoutScanService.scanObject(objectApiName, fieldApiNames);

        for (FieldInventory__c inventory : fieldInventories) {
            Boolean isQueryable = queryableFields.contains(inventory.FieldApiName__c);
            Integer nonNullCount = isQueryable ? nonNullCountByField.get(inventory.FieldApiName__c) : 0;
            Decimal nullRate = (sampleSize == 0) ? 100 : ((sampleSize - nonNullCount) * 100.0) / sampleSize;
            Boolean hasData = nonNullCount > 0;

            DependencySignalService.FieldDependencySummary dependency = dependencyByField.get(inventory.FieldApiName__c);
            if (dependency == null) {
                dependency = new DependencySignalService.FieldDependencySummary();
            }
            LayoutScanService.FieldLayoutSummary layoutSummary = layoutByField.get(inventory.FieldApiName__c);
            Boolean isOnLayout = layoutSummary != null && layoutSummary.isOnLayout == true;

            String evidence =
                'Sampled=' + sampleSize +
                '; NonNull=' + nonNullCount +
                '; HasData=' + hasData +
                '; ObjectRecordCount=' + objectRecordCount +
                '; MinObjectRecordCount=' + minRecordThreshold +
                '; MeetsMinRecordThreshold=' + meetsMinRecordThreshold +
                '; ActiveTriggerRefs=' + dependency.activeTriggerRefs +
                '; InactiveTriggerRefs=' + dependency.inactiveTriggerRefs +
                '; ActiveValidationRuleRefs=' + dependency.activeValidationRuleRefs +
                '; InactiveValidationRuleRefs=' + dependency.inactiveValidationRuleRefs +
                '; ActiveFlowRefs=' + dependency.activeFlowRefs +
                '; InactiveFlowRefs=' + dependency.inactiveFlowRefs +
                '; ApexClassRefs=' + dependency.apexClassRefs +
                '; IsOnLayout=' + isOnLayout +
                '; AvgApexCoveragePct=' + (
                    dependency.avgApexCoveragePct == null ? 'Unknown' : String.valueOf(dependency.avgApexCoveragePct)
                );
            if (!isQueryable) {
                evidence += '; FieldSkipped=NotQueryableOrInaccessible';
            }

            signals.add(new UsageSignal__c(
                FieldKey__c = inventory.FieldKey__c,
                FieldInventory__c = inventory.Id,
                SampleSize__c = sampleSize,
                NonNullCount__c = nonNullCount,
                NullRatePct__c = nullRate,
                IsOnLayout__c = isOnLayout,
                LastObservedOn__c = observedAt,
                EvidenceSummary__c = evidence
            ));
        }

        return signals;
    }

    private static Integer getObjectRecordCount(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return 0;
        }
        if (!isSafeApiName(objectApiName)) {
            return 0;
        }

        try {
            return Database.countQuery('SELECT COUNT() FROM ' + objectApiName);
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Boolean isSafeApiName(String apiName) {
        return !String.isBlank(apiName) && Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', apiName);
    }
}
