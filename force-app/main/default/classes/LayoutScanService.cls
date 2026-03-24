public with sharing class LayoutScanService {
    public class FieldLayoutSummary {
        public Boolean isOnLayout = false;
        public Set<String> layoutNames = new Set<String>();
    }

    @TestVisible private static Map<String, Object> testMetadataByLayoutName;

    public static Map<String, FieldLayoutSummary> scanObject(String objectApiName, Set<String> fieldApiNames) {
        return scanObject(objectApiName, fieldApiNames, false);
    }

    public static Map<String, FieldLayoutSummary> scanObject(
        String objectApiName,
        Set<String> fieldApiNames,
        Boolean includeLayoutNames
    ) {
        Map<String, FieldLayoutSummary> result = initializeResult(fieldApiNames);
        if (String.isBlank(objectApiName) || fieldApiNames == null || fieldApiNames.isEmpty()) {
            return result;
        }

        Clarity360Settings.RuntimeConfig runtime = Clarity360Settings.getRuntime();
        if (runtime == null || runtime.enableLayoutScan != true) {
            return result;
        }

        Map<String, Object> metadataByLayoutName = loadLayoutMetadataByName(objectApiName);
        if (metadataByLayoutName.isEmpty()) {
            return result;
        }

        for (String layoutName : metadataByLayoutName.keySet()) {
            Set<String> matchedFields = new Set<String>();
            collectFieldMatches(metadataByLayoutName.get(layoutName), fieldApiNames, matchedFields);
            for (String fieldApiName : matchedFields) {
                FieldLayoutSummary summary = result.get(fieldApiName);
                if (summary == null) {
                    summary = new FieldLayoutSummary();
                    result.put(fieldApiName, summary);
                }
                summary.isOnLayout = true;
                if (includeLayoutNames == true) {
                    summary.layoutNames.add(layoutName);
                }
            }
        }

        return result;
    }

    public static List<String> getLayoutNamesForField(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return new List<String>();
        }
        Map<String, FieldLayoutSummary> byField = scanObject(objectApiName, new Set<String>{ fieldApiName }, true);
        FieldLayoutSummary summary = byField.get(fieldApiName);
        if (summary == null || summary.layoutNames.isEmpty()) {
            return new List<String>();
        }
        List<String> layoutNames = new List<String>();
        layoutNames.addAll(summary.layoutNames);
        layoutNames.sort();
        return layoutNames;
    }

    private static Map<String, FieldLayoutSummary> initializeResult(Set<String> fieldApiNames) {
        Map<String, FieldLayoutSummary> result = new Map<String, FieldLayoutSummary>();
        for (String fieldApiName : fieldApiNames == null ? new Set<String>() : fieldApiNames) {
            result.put(fieldApiName, new FieldLayoutSummary());
        }
        return result;
    }

    private static Map<String, Object> loadLayoutMetadataByName(String objectApiName) {
        if (Test.isRunningTest() && testMetadataByLayoutName != null) {
            return new Map<String, Object>(testMetadataByLayoutName);
        }

        Map<String, Object> metadataByLayoutName = new Map<String, Object>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.queryWithMode(
            'SELECT Id, Name, TableEnumOrId, Metadata FROM Layout ' +
            'WHERE TableEnumOrId = \'' + String.escapeSingleQuotes(objectApiName) + '\' ' +
            'ORDER BY Name',
            500,
            true,
            true
        );
        if (queryResult == null || queryResult.success != true || queryResult.records == null) {
            return metadataByLayoutName;
        }

        for (Map<String, Object> row : queryResult.records) {
            String rowObjectName = ToolingApiService.getString(row, 'TableEnumOrId');
            if (!String.isBlank(rowObjectName) && rowObjectName != objectApiName) {
                continue;
            }
            String layoutName = ToolingApiService.getString(row, 'Name');
            if (String.isBlank(layoutName) || !row.containsKey('Metadata')) {
                continue;
            }
            metadataByLayoutName.put(layoutName, row.get('Metadata'));
        }
        return metadataByLayoutName;
    }

    private static void collectFieldMatches(Object node, Set<String> targetFields, Set<String> matchedFields) {
        if (node == null || targetFields == null || targetFields.isEmpty() || matchedFields == null) {
            return;
        }

        if (node instanceof Map<String, Object>) {
            Map<String, Object> nodeMap = (Map<String, Object>) node;
            String directField = ToolingApiService.getString(nodeMap, 'field');
            if (!String.isBlank(directField) && targetFields.contains(directField)) {
                matchedFields.add(directField);
            }
            for (Object value : nodeMap.values()) {
                collectFieldMatches(value, targetFields, matchedFields);
            }
            return;
        }

        if (node instanceof List<Object>) {
            for (Object item : (List<Object>) node) {
                collectFieldMatches(item, targetFields, matchedFields);
            }
        }
    }

    @TestVisible
    static void setTestMetadataByLayoutName(Map<String, Object> value) {
        testMetadataByLayoutName = value;
    }

    @TestVisible
    static void clearTestOverrides() {
        testMetadataByLayoutName = null;
    }
}
