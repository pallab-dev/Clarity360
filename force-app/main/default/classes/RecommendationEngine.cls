public with sharing class RecommendationEngine {
    public static void rebuildAllRecommendations(Integer maxRows) {
        Integer rowLimit = (maxRows == null || maxRows <= 0) ? 10000 : maxRows;
        Clarity360Settings.RuntimeConfig runtime = Clarity360Settings.getRequiredRuntime();

        List<UsageSignal__c> signals = [
            SELECT Id, FieldKey__c, FieldInventory__c, SampleSize__c, NonNullCount__c, NullRatePct__c, IsOnLayout__c, EvidenceSummary__c
            FROM UsageSignal__c
            ORDER BY LastObservedOn__c DESC
            LIMIT :rowLimit
        ];

        Set<Id> inventoryIds = new Set<Id>();
        for (UsageSignal__c signal : signals) {
            if (signal.FieldInventory__c != null) {
                inventoryIds.add(signal.FieldInventory__c);
            }
        }

        Map<Id, FieldInventory__c> inventoryById = new Map<Id, FieldInventory__c>();
        if (!inventoryIds.isEmpty()) {
            inventoryById = new Map<Id, FieldInventory__c>([
                SELECT Id, FieldKey__c, ObjectApiName__c, FieldApiName__c, IsActive__c
                FROM FieldInventory__c
                WHERE Id IN :inventoryIds
                AND IsActive__c = true
            ]);
        }

        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        List<Recommendation__c> fieldRecommendations = buildFromSignals(signals, inventoryById, runtime);
        // Fallback path for orgs where inventory linkage is incomplete but usage signals exist.
        if (fieldRecommendations.isEmpty() && !signals.isEmpty()) {
            fieldRecommendations = buildFromSignalsWithoutInventory(signals, runtime);
        }
        recommendations.addAll(fieldRecommendations);
        List<Recommendation__c> globalRecommendations = buildGlobalComponentRecommendations(runtime);
        recommendations.addAll(globalRecommendations);

        removeIneligibleRecommendations(signals, recommendations);
        removeMetadataFieldRecommendations();
        removeStaleGlobalRecommendations(globalRecommendations);
        if (!recommendations.isEmpty()) {
            List<SObject> rawRows = new List<SObject>();
            rawRows.addAll(recommendations);
            List<SObject> cleanedRows = Clarity360AccessControlService.get().stripForUpsert(rawRows);
            if (!cleanedRows.isEmpty()) {
                List<Recommendation__c> cleanedRecommendations = new List<Recommendation__c>();
                for (SObject row : cleanedRows) {
                    cleanedRecommendations.add((Recommendation__c) row);
                }
                upsert cleanedRecommendations FieldKey__c;
            }
        }
    }

    public static List<Recommendation__c> buildFromSignals(
        List<UsageSignal__c> signals,
        Map<Id, FieldInventory__c> inventoryById
    ) {
        return buildFromSignals(signals, inventoryById, Clarity360Settings.getRequiredRuntime());
    }

    private static List<Recommendation__c> buildFromSignals(
        List<UsageSignal__c> signals,
        Map<Id, FieldInventory__c> inventoryById,
        Clarity360Settings.RuntimeConfig runtime
    ) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        if (runtime.enableFieldRecommendations != true) {
            return recommendations;
        }
        if (signals == null || signals.isEmpty()) {
            return recommendations;
        }

        Integer minRecordThreshold = runtime.minObjectRecordCount;
        Decimal apexCoverageThreshold =
            (runtime.coverageThreshold != null)
                ? runtime.coverageThreshold
                : runtime.apexCoverageThresholdPct;
        Decimal lowUsageNullRateThreshold = 90;

        Datetime evaluatedAt = System.now();
        EvidenceParser parser = EvidenceParser.get();
        for (UsageSignal__c signal : signals) {
            if (signal == null || String.isBlank(signal.FieldKey__c) || signal.FieldKey__c.startsWith('GLOBAL.')) {
                continue;
            }
            FieldInventory__c inventory = (inventoryById == null) ? null : inventoryById.get(signal.FieldInventory__c);
            if (inventory == null) {
                continue;
            }
            if (!InventoryService.isObjectInRecommendationScope(inventory.ObjectApiName__c, inventory.ObjectApiName__c != null && inventory.ObjectApiName__c.endsWith('__c'))) {
                continue;
            }

            String action = 'Investigate Dependencies';
            Decimal confidence = 75;
            Decimal risk = 30;
            Decimal nullRate = (signal.NullRatePct__c == null) ? 100 : signal.NullRatePct__c;
            Map<String, String> parsedEvidence = parser.parse(signal.EvidenceSummary__c);
            Boolean hasData = extractBoolean(
                parsedEvidence,
                'HasData',
                signal.NonNullCount__c != null && signal.NonNullCount__c > 0
            );
            Integer objectRecordCount = extractInteger(parsedEvidence, 'ObjectRecordCount');
            Boolean meetsMinRecordThresholdFromEvidence = extractBoolean(
                parsedEvidence,
                'MeetsMinRecordThreshold',
                objectRecordCount >= minRecordThreshold
            );
            Integer sampleSize = signal.SampleSize__c == null ? 0 : signal.SampleSize__c.intValue();
            Boolean meetsMinRecordThreshold = meetsMinRecordThresholdFromEvidence || sampleSize >= minRecordThreshold;

            Integer activeTriggerRefs = extractInteger(parsedEvidence, 'ActiveTriggerRefs');
            Integer inactiveTriggerRefs = extractInteger(parsedEvidence, 'InactiveTriggerRefs');
            Integer activeValidationRuleRefs = extractInteger(parsedEvidence, 'ActiveValidationRuleRefs');
            Integer activeFlowRefs = extractInteger(parsedEvidence, 'ActiveFlowRefs');
            Integer activeDependencyCount = activeTriggerRefs + activeValidationRuleRefs + activeFlowRefs;
            Integer inactiveDependencyCount = inactiveTriggerRefs +
                extractInteger(parsedEvidence, 'InactiveValidationRuleRefs') +
                extractInteger(parsedEvidence, 'InactiveFlowRefs');
            if (!meetsMinRecordThreshold && activeDependencyCount == 0 && inactiveDependencyCount == 0) {
                continue;
            }

            Decimal avgApexCoveragePct = extractDecimal(parsedEvidence, 'AvgApexCoveragePct');
            Integer apexClassRefs = extractInteger(parsedEvidence, 'ApexClassRefs');
            if (runtime.enableApexCoverageScan != true) {
                avgApexCoveragePct = null;
                apexClassRefs = 0;
            }

            if (signal.SampleSize__c == null || signal.SampleSize__c == 0) {
                action = 'Investigate Dependencies';
                confidence = 40;
                risk = 85;
            } else if (hasData) {
                if (!meetsMinRecordThreshold || nullRate < lowUsageNullRateThreshold) {
                    action = 'Keep';
                    confidence = 85;
                    risk = 25;
                    if (activeDependencyCount > 0) {
                        risk = Math.min(100, risk + (activeDependencyCount * 5));
                    }
                } else {
                    action = 'Investigate Dependencies';
                    confidence = 70;
                    risk = 60;
                    if (activeDependencyCount > 0) {
                        risk = Math.min(100, risk + (activeDependencyCount * 5));
                    }
                }
            } else if (
                meetsMinRecordThreshold &&
                activeDependencyCount == 0 &&
                (avgApexCoveragePct == null || avgApexCoveragePct >= apexCoverageThreshold)
            ) {
                action = 'Deprecate';
                confidence = (avgApexCoveragePct == null) ? 75 : 90;
                risk = (avgApexCoveragePct == null) ? 35 : 15;
            } else {
                action = 'Investigate Dependencies';
                confidence = 55;
                risk = 65;
            }

            if (activeDependencyCount == 0 && inactiveDependencyCount > 0 && action == 'Deprecate') {
                action = 'Investigate Dependencies';
                confidence = 65;
                risk = Math.max(risk, 45);
            }

            if (isManagedPackageFieldApi(inventory.FieldApiName__c)) {
                risk = Math.min(100, risk + 30);
                if (action == 'Deprecate') {
                    action = 'Investigate Dependencies';
                    confidence = 55;
                }
            } else if (!isCustomFieldApi(inventory.FieldApiName__c)) {
                risk = Math.min(100, risk + 25);
                if (action == 'Deprecate') {
                    action = 'Investigate Dependencies';
                    confidence = 55;
                }
            }

            String evidence = signal.EvidenceSummary__c;
            evidence += '; NullRatePct=' + String.valueOf(nullRate);
            evidence += '; SuggestedAction=' + action;
            evidence += '; ActiveDependencyCount=' + activeDependencyCount;
            evidence += '; InactiveDependencyCount=' + inactiveDependencyCount;
            evidence += '; ObjectRecordCount=' + objectRecordCount;
            evidence += '; MinObjectRecordCount=' + minRecordThreshold;
            evidence += '; MeetsMinRecordThreshold=' + meetsMinRecordThreshold;
            evidence += '; ApexClassRefs=' + apexClassRefs;
            evidence += '; AvgApexCoveragePct=' + (avgApexCoveragePct == null ? 'Unknown' : String.valueOf(avgApexCoveragePct));
            evidence += '; CoverageThreshold=' + apexCoverageThreshold;
            evidence += '; LowUsageNullRateThreshold=' + lowUsageNullRateThreshold;

            recommendations.add(new Recommendation__c(
                FieldKey__c = signal.FieldKey__c,
                FieldInventory__c = inventory.Id,
                Action__c = action,
                ConfidenceScore__c = confidence,
                RiskScore__c = risk,
                EvidenceSummary__c = evidence,
                Status__c = 'Open',
                LastEvaluatedOn__c = evaluatedAt
            ));
        }

        return recommendations;
    }

    private static List<Recommendation__c> buildFromSignalsWithoutInventory(
        List<UsageSignal__c> signals,
        Clarity360Settings.RuntimeConfig runtime
    ) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        if (runtime.enableFieldRecommendations != true) {
            return recommendations;
        }
        if (signals == null || signals.isEmpty()) {
            return recommendations;
        }

        Integer minRecordThreshold = runtime.minObjectRecordCount;
        Decimal lowUsageNullRateThreshold = 90;
        Datetime evaluatedAt = System.now();
        EvidenceParser parser = EvidenceParser.get();
        for (UsageSignal__c signal : signals) {
            if (signal == null || String.isBlank(signal.FieldKey__c) || signal.FieldKey__c.startsWith('GLOBAL.')) {
                continue;
            }
            String objectApiName = extractObjectFromFieldKey(signal.FieldKey__c);
            if (!InventoryService.isObjectInRecommendationScope(objectApiName)) {
                continue;
            }

            Map<String, String> parsedEvidence = parser.parse(signal.EvidenceSummary__c);
            Boolean hasData = extractBoolean(
                parsedEvidence,
                'HasData',
                signal.NonNullCount__c != null && signal.NonNullCount__c > 0
            );
            Integer objectRecordCount = extractInteger(parsedEvidence, 'ObjectRecordCount');
            Boolean meetsMinRecordThresholdFromEvidence = extractBoolean(
                parsedEvidence,
                'MeetsMinRecordThreshold',
                objectRecordCount >= minRecordThreshold
            );
            Integer sampleSize = signal.SampleSize__c == null ? 0 : signal.SampleSize__c.intValue();
            Boolean meetsMinRecordThreshold = meetsMinRecordThresholdFromEvidence || sampleSize >= minRecordThreshold;

            // Noise guard: skip empty objects with no observed data.
            if (!hasData && (objectRecordCount == null || objectRecordCount <= 0) && sampleSize <= 0) {
                continue;
            }

            String action;
            Decimal confidence;
            Decimal risk;
            if (signal.SampleSize__c == null || signal.SampleSize__c == 0) {
                action = 'Investigate Dependencies';
                confidence = 40;
                risk = 85;
            } else if (hasData) {
                Decimal nullRate = signal.NullRatePct__c == null ? 100 : signal.NullRatePct__c;
                if (!meetsMinRecordThreshold || nullRate < lowUsageNullRateThreshold) {
                    action = 'Keep';
                    confidence = 85;
                    risk = 25;
                } else {
                    action = 'Investigate Dependencies';
                    confidence = 70;
                    risk = 60;
                }
            } else if (meetsMinRecordThreshold) {
                action = 'Deprecate';
                confidence = 70;
                risk = 35;
            } else {
                action = 'Investigate Dependencies';
                confidence = 55;
                risk = 60;
            }

            String evidence = String.valueOf(signal.EvidenceSummary__c);
            if (String.isBlank(evidence)) {
                evidence = 'Fallback=SignalOnly';
            } else {
                evidence += '; Fallback=SignalOnly';
            }
            evidence += '; SuggestedAction=' + action;
            evidence += '; MinObjectRecordCount=' + minRecordThreshold;
            evidence += '; MeetsMinRecordThreshold=' + meetsMinRecordThreshold;
            evidence += '; LowUsageNullRateThreshold=' + lowUsageNullRateThreshold;

            recommendations.add(new Recommendation__c(
                FieldKey__c = signal.FieldKey__c,
                Action__c = action,
                ConfidenceScore__c = confidence,
                RiskScore__c = risk,
                EvidenceSummary__c = evidence,
                Status__c = 'Open',
                LastEvaluatedOn__c = evaluatedAt
            ));
        }

        return recommendations;
    }

    private static void removeIneligibleRecommendations(
        List<UsageSignal__c> signals,
        List<Recommendation__c> recommendations
    ) {
        Set<String> signalKeys = new Set<String>();
        for (UsageSignal__c signal : signals) {
            if (!String.isBlank(signal.FieldKey__c)) {
                signalKeys.add(signal.FieldKey__c);
            }
        }

        Set<String> generatedKeys = new Set<String>();
        for (Recommendation__c recommendation : recommendations) {
            if (!String.isBlank(recommendation.FieldKey__c)) {
                generatedKeys.add(recommendation.FieldKey__c);
            }
        }

        Set<String> keysToDelete = new Set<String>();
        keysToDelete.addAll(signalKeys);
        keysToDelete.removeAll(generatedKeys);
        if (keysToDelete.isEmpty()) {
            return;
        }

        List<Recommendation__c> staleRecommendations = [
            SELECT Id
            FROM Recommendation__c
            WHERE FieldKey__c IN :keysToDelete
        ];
        if (!staleRecommendations.isEmpty()) {
            delete staleRecommendations;
        }
    }

    private static List<Recommendation__c> buildGlobalComponentRecommendations(
        Clarity360Settings.RuntimeConfig runtime
    ) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        Datetime evaluatedAt = System.now();
        Integer maxRows = runtime.maxToolingRows;

        if (runtime.enableTriggerScan == true) {
            recommendations.addAll(buildGlobalTriggerRecommendations(evaluatedAt, maxRows));
        }

        if (runtime.enableValidationRuleScan == true) {
            recommendations.addAll(buildGlobalValidationRecommendations(evaluatedAt, maxRows));
        }

        if (runtime.enableFlowAndProcessScan == true) {
            recommendations.addAll(buildGlobalFlowRecommendations(evaluatedAt, maxRows));
        }

        if (runtime.enableWorkflowRuleScan == true) {
            recommendations.addAll(buildGlobalWorkflowRuleRecommendations(evaluatedAt, maxRows));
        }

        if (runtime.enableApexCoverageScan == true) {
            recommendations.addAll(buildGlobalApexCoverageRecommendations(evaluatedAt, maxRows, runtime));
        }
        recommendations.addAll(buildGlobalMetadataInventoryRecommendations(evaluatedAt));

        return recommendations;
    }

    private static List<Recommendation__c> buildGlobalTriggerRecommendations(Datetime evaluatedAt, Integer maxRows) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();

        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.query(
            'SELECT Id, Name, Status FROM ApexTrigger ORDER BY Name',
            maxRows
        );

        if (queryResult.success && !queryResult.records.isEmpty()) {
            for (Map<String, Object> row : queryResult.records) {
                String name = ToolingApiService.getString(row, 'Name');
                if (String.isBlank(name)) {
                    continue;
                }
                String status = ToolingApiService.getString(row, 'Status');
                Boolean isActive = status == 'Active';
                if (isActive) {
                    continue;
                }
                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.TRIGGER.' + name,
                    Action__c = 'Investigate Dependencies',
                    ConfidenceScore__c = 85,
                    RiskScore__c = 45,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=Trigger; ComponentName=' + name +
                        '; ComponentStatus=' + status +
                        '; Source=ToolingAPI',
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
            return recommendations;
        }

        for (ApexTrigger triggerRow : [SELECT Name, Status FROM ApexTrigger LIMIT :maxRows]) {
            String status = String.valueOf(triggerRow.Status);
            Boolean isActive = status == 'Active';
            if (isActive) {
                continue;
            }
            recommendations.add(new Recommendation__c(
                FieldKey__c = 'GLOBAL.TRIGGER.' + triggerRow.Name,
                Action__c = 'Investigate Dependencies',
                ConfidenceScore__c = 85,
                RiskScore__c = 45,
                EvidenceSummary__c =
                    'Scope=Global; ComponentType=Trigger; ComponentName=' + triggerRow.Name +
                    '; ComponentStatus=' + status +
                    '; Source=SOQLFallback',
                Status__c = 'Open',
                LastEvaluatedOn__c = evaluatedAt
            ));
        }

        return recommendations;
    }

    private static List<Recommendation__c> buildGlobalValidationRecommendations(Datetime evaluatedAt, Integer maxRows) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.query(
            'SELECT Id, ValidationName, Active, EntityDefinition.QualifiedApiName FROM ValidationRule ORDER BY ValidationName',
            maxRows
        );

        if (queryResult.success && !queryResult.records.isEmpty()) {
            for (Map<String, Object> row : queryResult.records) {
                String id = ToolingApiService.getString(row, 'Id');
                String ruleName = ToolingApiService.getString(row, 'ValidationName');
                String objectName = ToolingApiService.getNestedString(row, 'EntityDefinition', 'QualifiedApiName');
                Boolean active = ToolingApiService.getBoolean(row, 'Active');
                Boolean isActive = active == true;
                if (String.isBlank(ruleName)) {
                    ruleName = String.isBlank(id) ? 'UnnamedValidationRule' : id;
                }

                if (isActive) {
                    continue;
                }
                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.VALRULE.' + sanitizeKey(id),
                    Action__c = 'Investigate Dependencies',
                    ConfidenceScore__c = 75,
                    RiskScore__c = 40,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=ValidationRule; ComponentName=' + ruleName +
                        '; Object=' + objectName +
                        '; ComponentStatus=' + (isActive ? 'Active' : 'Inactive') +
                        '; Source=ToolingAPI',
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
            return recommendations;
        }

        try {
            List<SObject> fallbackRows = Database.query(
                'SELECT Id, Active, ValidationName, EntityDefinition.QualifiedApiName FROM ValidationRule LIMIT ' + maxRows
            );
            for (SObject row : fallbackRows) {
                String id = String.valueOf(row.get('Id'));
                String ruleName = String.valueOf(row.get('ValidationName'));
                if (String.isBlank(ruleName)) {
                    ruleName = String.isBlank(id) ? 'UnnamedValidationRule' : id;
                }
                String objectName = null;
                try {
                    SObject entity = row.getSObject('EntityDefinition');
                    objectName = entity == null ? null : String.valueOf(entity.get('QualifiedApiName'));
                } catch (Exception ignored) {
                    objectName = null;
                }
                Boolean isActive = (Boolean) row.get('Active');
                if (isActive) {
                    continue;
                }
                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.VALRULE.' + sanitizeKey(id),
                    Action__c = 'Investigate Dependencies',
                    ConfidenceScore__c = 75,
                    RiskScore__c = 40,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=ValidationRule; ComponentName=' + ruleName +
                        '; Object=' + objectName +
                        '; ComponentStatus=' + (isActive ? 'Active' : 'Inactive') +
                        '; Source=SOQLFallback',
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
        } catch (Exception ex) {
            // Ignore when validation metadata objects are not queryable in the runtime context.
        }
        return recommendations;
    }

    private static List<Recommendation__c> buildGlobalFlowRecommendations(Datetime evaluatedAt, Integer maxRows) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.query(
            'SELECT Id, MasterLabel, DeveloperName, Status, ProcessType, VersionNumber FROM Flow ORDER BY DeveloperName, VersionNumber DESC',
            maxRows
        );

        if (queryResult.success && !queryResult.records.isEmpty()) {
            Map<String, Map<String, Object>> bestByDefinition = new Map<String, Map<String, Object>>();
            for (Map<String, Object> row : queryResult.records) {
                String developerName = ToolingApiService.getString(row, 'DeveloperName');
                String processType = ToolingApiService.getString(row, 'ProcessType');
                if (String.isBlank(developerName)) {
                    continue;
                }
                String key = developerName + '|' + String.valueOf(processType);
                if (!bestByDefinition.containsKey(key) || isBetterFlowRow(row, bestByDefinition.get(key))) {
                    bestByDefinition.put(key, row);
                }
            }

            for (Map<String, Object> row : bestByDefinition.values()) {
                String id = ToolingApiService.getString(row, 'Id');
                String name = ToolingApiService.getString(row, 'MasterLabel');
                String developerName = ToolingApiService.getString(row, 'DeveloperName');
                String status = ToolingApiService.getString(row, 'Status');
                String processType = ToolingApiService.getString(row, 'ProcessType');
                if (String.isBlank(name)) {
                    name = developerName;
                }

                Boolean isActive = status == 'Active';
                String componentType = processType == 'Workflow' ? 'ProcessBuilder' : 'Flow';
                if (isActive) {
                    continue;
                }
                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.FLOW.' + sanitizeKey(id),
                    Action__c = 'Investigate Dependencies',
                    ConfidenceScore__c = 75,
                    RiskScore__c = 35,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=' + componentType + '; ComponentName=' + name +
                        '; ProcessType=' + processType +
                        '; ComponentStatus=' + status +
                        '; Source=ToolingAPI',
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
            return recommendations;
        }

        try {
            List<SObject> fallbackRows = Database.query(
                'SELECT Id, MasterLabel, DeveloperName, Status, ProcessType, VersionNumber FROM Flow LIMIT ' + maxRows
            );
            Map<String, SObject> bestFallbackByDefinition = new Map<String, SObject>();
            for (SObject row : fallbackRows) {
                String developerName = String.valueOf(row.get('DeveloperName'));
                String processType = String.valueOf(row.get('ProcessType'));
                if (String.isBlank(developerName)) {
                    continue;
                }
                String key = developerName + '|' + processType;
                if (!bestFallbackByDefinition.containsKey(key)) {
                    bestFallbackByDefinition.put(key, row);
                } else if (isBetterFlowRowFallback(row, bestFallbackByDefinition.get(key))) {
                    bestFallbackByDefinition.put(key, row);
                }
            }

            for (SObject row : bestFallbackByDefinition.values()) {
                String status = String.valueOf(row.get('Status'));
                String processType = String.valueOf(row.get('ProcessType'));
                String name = String.valueOf(row.get('MasterLabel'));
                if (String.isBlank(name)) {
                    name = String.valueOf(row.get('DeveloperName'));
                }
                Boolean isActive = status == 'Active';
                String componentType = processType == 'Workflow' ? 'ProcessBuilder' : 'Flow';
                if (isActive) {
                    continue;
                }
                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.FLOW.' + sanitizeKey(String.valueOf(row.get('Id'))),
                    Action__c = 'Investigate Dependencies',
                    ConfidenceScore__c = 75,
                    RiskScore__c = 35,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=' + componentType + '; ComponentName=' + name +
                        '; ProcessType=' + processType +
                        '; ComponentStatus=' + status +
                        '; Source=SOQLFallback',
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
        } catch (Exception ex) {
            // Ignore when flow metadata objects are not queryable in the runtime context.
        }

        return recommendations;
    }

    private static List<Recommendation__c> buildGlobalWorkflowRuleRecommendations(Datetime evaluatedAt, Integer maxRows) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.query(
            'SELECT Id, Name, Active, TableEnumOrId FROM WorkflowRule ORDER BY Name',
            maxRows
        );

        if (queryResult.success && !queryResult.records.isEmpty()) {
            for (Map<String, Object> row : queryResult.records) {
                String id = ToolingApiService.getString(row, 'Id');
                String name = ToolingApiService.getString(row, 'Name');
                String objectName = ToolingApiService.getString(row, 'TableEnumOrId');
                Boolean active = ToolingApiService.getBoolean(row, 'Active');
                Boolean isActive = active == true;
                if (String.isBlank(name)) {
                    name = id;
                }

                if (isActive) {
                    continue;
                }
                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.WORKFLOW.' + sanitizeKey(id),
                    Action__c = 'Investigate Dependencies',
                    ConfidenceScore__c = 75,
                    RiskScore__c = 35,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=WorkflowRule; ComponentName=' + name +
                        '; Object=' + objectName +
                        '; ComponentStatus=' + (isActive ? 'Active' : 'Inactive') +
                        '; Source=ToolingAPI',
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
            return recommendations;
        }

        try {
            List<SObject> fallbackRows = Database.query(
                'SELECT Id, Name, Active, TableEnumOrId FROM WorkflowRule LIMIT ' + maxRows
            );
            for (SObject row : fallbackRows) {
                Boolean isActive = (Boolean) row.get('Active');
                if (isActive) {
                    continue;
                }
                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.WORKFLOW.' + sanitizeKey(String.valueOf(row.get('Id'))),
                    Action__c = 'Investigate Dependencies',
                    ConfidenceScore__c = 75,
                    RiskScore__c = 35,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=WorkflowRule; ComponentName=' + String.valueOf(row.get('Name')) +
                        '; Object=' + String.valueOf(row.get('TableEnumOrId')) +
                        '; ComponentStatus=' + (isActive ? 'Active' : 'Inactive') +
                        '; Source=SOQLFallback',
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
        } catch (Exception ex) {
            // Ignore when workflow rule metadata objects are not queryable in the runtime context.
        }

        return recommendations;
    }

    private static List<Recommendation__c> buildGlobalApexCoverageRecommendations(
        Datetime evaluatedAt,
        Integer maxRows,
        Clarity360Settings.RuntimeConfig runtime
    ) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        Decimal coverageThreshold =
            (runtime.coverageThreshold != null)
                ? runtime.coverageThreshold
                : runtime.apexCoverageThresholdPct;

        try {
            List<ApexClass> classes = [SELECT Id, Name, Body FROM ApexClass LIMIT :maxRows];
            Map<Id, Decimal> coverageByClassId = queryApexCoveragePct(new Map<Id, ApexClass>(classes).keySet());

            for (ApexClass classRow : classes) {
                if (classRow.Name == null) {
                    continue;
                }
                if (classRow.Body != null && classRow.Body.toLowerCase().contains('@istest')) {
                    continue;
                }
                if (!isActionableApexClass(classRow.Name, classRow.Body)) {
                    continue;
                }

                Boolean hasCoverageData = coverageByClassId.containsKey(classRow.Id);
                Decimal coveragePct = hasCoverageData ? coverageByClassId.get(classRow.Id) : null;
                String coverageText = hasCoverageData ? String.valueOf(coveragePct) : 'Unavailable';
                String action = 'Investigate Dependencies';
                Decimal confidence = 55;
                Decimal risk = 70;
                String coverageBand = 'Unknown';
                if (hasCoverageData) {
                    if (coveragePct >= coverageThreshold) {
                        action = 'Keep';
                        confidence = 92;
                        risk = 15;
                        coverageBand = 'Good';
                    } else if (coveragePct >= Math.max(0, coverageThreshold - 20)) {
                        action = 'Investigate Dependencies';
                        confidence = 80;
                        risk = 55;
                        coverageBand = 'Borderline';
                    } else {
                        action = 'Investigate Dependencies';
                        confidence = 95;
                        risk = 95;
                        coverageBand = 'Low';
                    }
                }

                recommendations.add(new Recommendation__c(
                    FieldKey__c = 'GLOBAL.APEXCLASS.' + classRow.Name,
                    Action__c = action,
                    ConfidenceScore__c = confidence,
                    RiskScore__c = risk,
                    EvidenceSummary__c =
                        'Scope=Global; ComponentType=ApexClass; ComponentName=' + classRow.Name +
                        '; CoveragePct=' + coverageText +
                        '; HasCoverageData=' + String.valueOf(hasCoverageData) +
                        '; CoverageBand=' + coverageBand +
                        '; CoverageThreshold=' + coverageThreshold,
                    Status__c = 'Open',
                    LastEvaluatedOn__c = evaluatedAt
                ));
            }
        } catch (Exception ex) {
            // Ignore if ApexClass or coverage metadata is unavailable in context.
        }

        return recommendations;
    }

    private static List<Recommendation__c> buildGlobalMetadataInventoryRecommendations(Datetime evaluatedAt) {
        List<Recommendation__c> recommendations = new List<Recommendation__c>();
        List<MetadataComponentInventory__c> rows = [
            SELECT ComponentKey__c, ComponentType__c, ApiName__c, DisplayName__c, ReferenceCount__c,
                ActiveSubscriberCount__c, MonitoringEligible__c, SourceSummary__c
            FROM MetadataComponentInventory__c
            WHERE IsActive__c = true
            ORDER BY ReferenceCount__c ASC, ApiName__c ASC
            LIMIT 1000
        ];

        for (MetadataComponentInventory__c row : rows) {
            if (String.isBlank(row.ComponentKey__c) || String.isBlank(row.ApiName__c) || String.isBlank(row.ComponentType__c)) {
                continue;
            }

            Integer referenceCount = row.ReferenceCount__c == null ? 0 : row.ReferenceCount__c.intValue();
            Integer activeSubscribers = row.ActiveSubscriberCount__c == null ? 0 : row.ActiveSubscriberCount__c.intValue();
            String action = null;
            Decimal confidence = null;
            Decimal risk = null;
            String reason = null;

            if (row.ComponentType__c == 'Custom Metadata Type' || row.ComponentType__c == 'Custom Setting') {
                if (referenceCount == 0) {
                    action = 'Deprecate';
                    confidence = 82;
                    risk = 25;
                    reason = 'No references detected in scanned Apex or validation rules.';
                } else if (referenceCount <= 1) {
                    action = 'Investigate Dependencies';
                    confidence = 68;
                    risk = 45;
                    reason = 'Only one lightweight reference was detected in the current scan scope.';
                }
            } else if (row.ComponentType__c == 'Platform Event') {
                if (activeSubscribers == 0) {
                    action = 'Investigate Dependencies';
                    confidence = referenceCount == 0 ? 80 : 72;
                    risk = referenceCount == 0 ? 35 : 50;
                    reason = referenceCount == 0
                        ? 'No Apex references or active subscribers were detected.'
                        : 'References exist, but no active platform-event subscribers were detected.';
                }
            }

            if (action == null) {
                continue;
            }

            recommendations.add(new Recommendation__c(
                FieldKey__c = buildMetadataRecommendationKey(row.ComponentType__c, row.ApiName__c),
                Action__c = action,
                ConfidenceScore__c = confidence,
                RiskScore__c = risk,
                EvidenceSummary__c =
                    'Scope=Global; ComponentType=' + row.ComponentType__c +
                    '; ComponentName=' + row.DisplayName__c +
                    '; ComponentApiName=' + row.ApiName__c +
                    '; ReferenceCount=' + String.valueOf(referenceCount) +
                    '; ActiveSubscriberCount=' + String.valueOf(activeSubscribers) +
                    '; MonitoringEligible=' + String.valueOf(row.MonitoringEligible__c) +
                    '; Reason=' + reason +
                    (String.isBlank(row.SourceSummary__c) ? '' : '; ' + row.SourceSummary__c),
                Status__c = 'Open',
                LastEvaluatedOn__c = evaluatedAt
            ));
        }

        return recommendations;
    }

    private static Boolean isActionableApexClass(String className, String body) {
        if (String.isBlank(className)) {
            return false;
        }
        if (className.endsWith('Test')) {
            return false;
        }
        if (String.isBlank(body)) {
            return false;
        }
        String loweredBody = body.toLowerCase();
        // Skip interfaces and enums: they don't represent concrete executable classes for this recommendation.
        if (Pattern.matches('(?s).*\\binterface\\b.*', loweredBody) || Pattern.matches('(?s).*\\benum\\b.*', loweredBody)) {
            return false;
        }
        // Require at least one method signature to avoid flagging marker/placeholder artifacts.
        if (!Pattern.matches('(?s).*\\b(public|private|protected|global)\\s+(static\\s+)?[A-Za-z0-9_<>,\\[\\]]+\\s+[A-Za-z0-9_]+\\s*\\(.*', body)) {
            return false;
        }
        return true;
    }

    private static String buildMetadataRecommendationKey(String componentType, String apiName) {
        if (componentType == 'Custom Metadata Type') {
            return 'GLOBAL.CMDT.' + apiName;
        }
        if (componentType == 'Custom Setting') {
            return 'GLOBAL.CUSTOMSETTING.' + apiName;
        }
        if (componentType == 'Platform Event') {
            return 'GLOBAL.PEVENT.' + apiName;
        }
        return 'GLOBAL.METADATA.' + sanitizeKey(apiName);
    }

    private static Boolean isBetterFlowRow(Map<String, Object> candidate, Map<String, Object> current) {
        String candidateStatus = ToolingApiService.getString(candidate, 'Status');
        String currentStatus = ToolingApiService.getString(current, 'Status');
        if (candidateStatus == 'Active' && currentStatus != 'Active') {
            return true;
        }
        if (candidateStatus != 'Active' && currentStatus == 'Active') {
            return false;
        }

        Decimal candidateVersion = ToolingApiService.getDecimal(candidate, 'VersionNumber');
        Decimal currentVersion = ToolingApiService.getDecimal(current, 'VersionNumber');
        Decimal safeCandidate = candidateVersion == null ? 0 : candidateVersion;
        Decimal safeCurrent = currentVersion == null ? 0 : currentVersion;
        return safeCandidate > safeCurrent;
    }

    private static Boolean isBetterFlowRowFallback(SObject candidate, SObject current) {
        String candidateStatus = String.valueOf(candidate.get('Status'));
        String currentStatus = String.valueOf(current.get('Status'));
        if (candidateStatus == 'Active' && currentStatus != 'Active') {
            return true;
        }
        if (candidateStatus != 'Active' && currentStatus == 'Active') {
            return false;
        }

        Decimal candidateVersion = parseDecimal(candidate.get('VersionNumber'));
        Decimal currentVersion = parseDecimal(current.get('VersionNumber'));
        Decimal safeCandidate = candidateVersion == null ? 0 : candidateVersion;
        Decimal safeCurrent = currentVersion == null ? 0 : currentVersion;
        return safeCandidate > safeCurrent;
    }

    private static String sanitizeKey(String keyPart) {
        return String.isBlank(keyPart) ? 'UNKNOWN' : keyPart.replaceAll('[^A-Za-z0-9_]', '_');
    }

    private static Decimal parseDecimal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }

    private static void removeStaleGlobalRecommendations(List<Recommendation__c> generatedGlobalRecommendations) {
        Set<String> generatedKeys = new Set<String>();
        for (Recommendation__c recommendation : generatedGlobalRecommendations) {
            generatedKeys.add(recommendation.FieldKey__c);
        }

        List<Recommendation__c> staleGlobalRecommendations = [
            SELECT Id, FieldKey__c
            FROM Recommendation__c
            WHERE FieldKey__c LIKE 'GLOBAL.%'
        ];

        List<Recommendation__c> deletes = new List<Recommendation__c>();
        for (Recommendation__c existing : staleGlobalRecommendations) {
            if (!generatedKeys.contains(existing.FieldKey__c)) {
                deletes.add(existing);
            }
        }
        if (!deletes.isEmpty()) {
            delete deletes;
        }
    }

    private static void removeMetadataFieldRecommendations() {
        List<Recommendation__c> existingFieldRecommendations = [
            SELECT Id, FieldKey__c
            FROM Recommendation__c
            WHERE FieldKey__c != null
        ];

        List<Recommendation__c> deletes = new List<Recommendation__c>();
        for (Recommendation__c row : existingFieldRecommendations) {
            if (row.FieldKey__c != null && row.FieldKey__c.startsWith('GLOBAL.')) {
                continue;
            }
            String objectApiName = extractObjectFromFieldKey(row.FieldKey__c);
            if (!InventoryService.isObjectInRecommendationScope(objectApiName)) {
                deletes.add(new Recommendation__c(Id = row.Id));
            }
        }

        if (!deletes.isEmpty()) {
            delete deletes;
        }
    }

    private static Map<Id, Decimal> queryApexCoveragePct(Set<Id> apexClassIds) {
        Map<Id, Decimal> coverageByClassId = new Map<Id, Decimal>();
        if (apexClassIds == null || apexClassIds.isEmpty()) {
            return coverageByClassId;
        }

        try {
            List<AggregateResult> rows = Database.query(
                'SELECT ApexClassOrTriggerId classId, SUM(NumLinesCovered) covered, SUM(NumLinesUncovered) uncovered ' +
                'FROM ApexCodeCoverageAggregate ' +
                'WHERE ApexClassOrTriggerId IN :apexClassIds ' +
                'GROUP BY ApexClassOrTriggerId'
            );
            for (AggregateResult row : rows) {
                Decimal covered = (Decimal) row.get('covered');
                Decimal uncovered = (Decimal) row.get('uncovered');
                Decimal total = covered + uncovered;
                if (total > 0) {
                    coverageByClassId.put((Id) row.get('classId'), (covered * 100.0) / total);
                }
            }
        } catch (Exception ex) {
            // If coverage table is unavailable in Apex SOQL context, fallback below.
        }

        if (!coverageByClassId.isEmpty()) {
            return coverageByClassId;
        }

        try {
            mergeCoverageFromTooling(coverageByClassId, apexClassIds, 'ApexCodeCoverageAggregate', false);
            // Developer Console often surfaces per-test coverage rows from ApexCodeCoverage.
            // Merge that signal and keep the higher percentage to avoid stale aggregate under-reporting.
            mergeCoverageFromTooling(coverageByClassId, apexClassIds, 'ApexCodeCoverage', true);
        } catch (Exception ex) {
            // Keep empty map if tooling coverage is unavailable.
        }

        return coverageByClassId;
    }

    private static void mergeCoverageFromTooling(
        Map<Id, Decimal> targetCoverage,
        Set<Id> apexClassIds,
        String toolingObjectApi,
        Boolean preferHigher
    ) {
        for (List<Id> chunk : chunkIds(apexClassIds, 100)) {
            if (chunk.isEmpty()) {
                continue;
            }
            String idsCsv = buildIdCsv(chunk);
            ToolingApiService.ToolingQueryResult toolingResult = ToolingApiService.query(
                'SELECT ApexClassOrTriggerId, NumLinesCovered, NumLinesUncovered ' +
                'FROM ' + toolingObjectApi + ' ' +
                'WHERE ApexClassOrTriggerId IN (' + idsCsv + ')',
                10000
            );
            if (toolingResult == null || !toolingResult.success || toolingResult.records.isEmpty()) {
                continue;
            }

            Map<Id, Decimal> coveredByClassId = new Map<Id, Decimal>();
            Map<Id, Decimal> uncoveredByClassId = new Map<Id, Decimal>();
            for (Map<String, Object> row : toolingResult.records) {
                String classIdText = ToolingApiService.getString(row, 'ApexClassOrTriggerId');
                if (String.isBlank(classIdText)) {
                    continue;
                }
                Id classId;
                try {
                    classId = (Id) classIdText;
                } catch (Exception castEx) {
                    continue;
                }
                Decimal covered = ToolingApiService.getDecimal(row, 'NumLinesCovered');
                Decimal uncovered = ToolingApiService.getDecimal(row, 'NumLinesUncovered');
                coveredByClassId.put(
                    classId,
                    (coveredByClassId.containsKey(classId) ? coveredByClassId.get(classId) : 0) +
                    (covered == null ? 0 : covered)
                );
                uncoveredByClassId.put(
                    classId,
                    (uncoveredByClassId.containsKey(classId) ? uncoveredByClassId.get(classId) : 0) +
                    (uncovered == null ? 0 : uncovered)
                );
            }

            for (Id classId : coveredByClassId.keySet()) {
                Decimal covered = coveredByClassId.get(classId);
                Decimal uncovered = uncoveredByClassId.containsKey(classId) ? uncoveredByClassId.get(classId) : 0;
                Decimal total = covered + uncovered;
                if (total <= 0) {
                    continue;
                }
                Decimal pct = (covered * 100.0) / total;
                if (!targetCoverage.containsKey(classId)) {
                    targetCoverage.put(classId, pct);
                    continue;
                }
                if (preferHigher == true) {
                    targetCoverage.put(classId, Math.max(targetCoverage.get(classId), pct));
                }
            }
        }
    }

    private static List<List<Id>> chunkIds(Set<Id> ids, Integer chunkSize) {
        List<List<Id>> chunks = new List<List<Id>>();
        Integer safeChunkSize = (chunkSize == null || chunkSize <= 0) ? 100 : chunkSize;
        List<Id> current = new List<Id>();
        for (Id idValue : ids) {
            current.add(idValue);
            if (current.size() >= safeChunkSize) {
                chunks.add(current);
                current = new List<Id>();
            }
        }
        if (!current.isEmpty()) {
            chunks.add(current);
        }
        return chunks;
    }

    private static String buildIdCsv(List<Id> ids) {
        List<String> quoted = new List<String>();
        for (Id idValue : ids) {
            quoted.add('\'' + String.escapeSingleQuotes(String.valueOf(idValue)) + '\'');
        }
        return String.join(quoted, ',');
    }

    private static Integer extractInteger(String evidence, String key) {
        return extractInteger(EvidenceParser.get().parse(evidence), key);
    }

    private static Integer extractInteger(Map<String, String> parsedEvidence, String key) {
        String value = EvidenceParser.get().getString(parsedEvidence, key);
        if (String.isBlank(value)) {
            return 0;
        }

        try {
            return Integer.valueOf(value.trim());
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Decimal extractDecimal(String evidence, String key) {
        return extractDecimal(EvidenceParser.get().parse(evidence), key);
    }

    private static Decimal extractDecimal(Map<String, String> parsedEvidence, String key) {
        String value = EvidenceParser.get().getString(parsedEvidence, key);
        if (String.isBlank(value) || value.trim() == 'Unknown') {
            return null;
        }

        try {
            return Decimal.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean extractBoolean(String evidence, String key, Boolean defaultValue) {
        return extractBoolean(EvidenceParser.get().parse(evidence), key, defaultValue);
    }

    private static Boolean extractBoolean(Map<String, String> parsedEvidence, String key, Boolean defaultValue) {
        String value = EvidenceParser.get().getString(parsedEvidence, key);
        if (String.isBlank(value)) {
            return defaultValue;
        }

        value = value.trim().toLowerCase();
        if (value == 'true') {
            return true;
        }
        if (value == 'false') {
            return false;
        }
        return defaultValue;
    }

    private static String extractTokenValue(String evidence, String key) {
        if (String.isBlank(evidence) || String.isBlank(key)) {
            return null;
        }

        String prefix = key + '=';
        for (String token : evidence.split(';')) {
            String trimmedToken = token == null ? null : token.trim();
            if (trimmedToken != null && trimmedToken.startsWith(prefix)) {
                return trimmedToken.substring(prefix.length());
            }
        }

        return null;
    }

    private static String extractObjectFromFieldKey(String fieldKey) {
        if (String.isBlank(fieldKey)) {
            return null;
        }
        Integer splitIndex = fieldKey.indexOf('.');
        if (splitIndex <= 0) {
            return fieldKey;
        }
        return fieldKey.substring(0, splitIndex);
    }

    private static Boolean isCustomFieldApi(String fieldApiName) {
        return !String.isBlank(fieldApiName) && fieldApiName.endsWith('__c');
    }

    private static Boolean isManagedPackageFieldApi(String fieldApiName) {
        return !String.isBlank(fieldApiName) && Pattern.matches('^[A-Za-z0-9]+__.+__c$', fieldApiName);
    }
}
