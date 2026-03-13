public with sharing class DependencySignalService {
    public class FieldDependencySummary {
        public Integer activeTriggerRefs = 0;
        public Integer inactiveTriggerRefs = 0;
        public Integer activeValidationRuleRefs = 0;
        public Integer inactiveValidationRuleRefs = 0;
        public Integer activeFlowRefs = 0;
        public Integer inactiveFlowRefs = 0;
        public Integer apexClassRefs = 0;
        public Decimal avgApexCoveragePct;
        public Set<String> activeTriggerNames = new Set<String>();
        public Set<String> inactiveTriggerNames = new Set<String>();
        public Set<String> apexClassNames = new Set<String>();
    }

    public static Map<String, FieldDependencySummary> scan(String objectApiName, Set<String> fieldApiNames) {
        Map<String, FieldDependencySummary> result = new Map<String, FieldDependencySummary>();
        if (String.isBlank(objectApiName) || fieldApiNames == null || fieldApiNames.isEmpty()) {
            return result;
        }

        for (String fieldApiName : fieldApiNames) {
            result.put(fieldApiName, new FieldDependencySummary());
        }

        Clarity360Settings.RuntimeConfig settings = Clarity360Settings.getRequiredRuntime();
        Integer maxRows = settings.maxToolingRows;

        if (settings.enableTriggerScan == true) {
            scanTriggers(objectApiName, fieldApiNames, result, maxRows);
        }
        if (settings.enableValidationRuleScan == true) {
            scanValidationRules(objectApiName, fieldApiNames, result, Math.min(maxRows, 5000));
        }
        if (settings.enableFlowAndProcessScan == true) {
            scanFlowsAndProcessBuilder(result, Math.min(maxRows, 5000));
        }
        if (settings.enableApexCoverageScan == true) {
            scanApexClassCoverage(objectApiName, fieldApiNames, result, maxRows);
        }

        return result;
    }

    private static void scanTriggers(
        String objectApiName,
        Set<String> fieldApiNames,
        Map<String, FieldDependencySummary> result,
        Integer maxRows
    ) {
        try {
            List<ApexTrigger> triggers = [
                SELECT Id, Name, Status, Body, TableEnumOrId
                FROM ApexTrigger
                WHERE TableEnumOrId = :objectApiName
                LIMIT :maxRows
            ];

            for (ApexTrigger triggerRow : triggers) {
                String body = safeLower(triggerRow.Body);
                Boolean isActive = String.valueOf(triggerRow.Status) == 'Active';
                for (String fieldApiName : fieldApiNames) {
                    if (containsToken(body, fieldApiName)) {
                        FieldDependencySummary summary = result.get(fieldApiName);
                        if (isActive) {
                            summary.activeTriggerRefs++;
                            summary.activeTriggerNames.add(triggerRow.Name);
                        } else {
                            summary.inactiveTriggerRefs++;
                            summary.inactiveTriggerNames.add(triggerRow.Name);
                        }
                    }
                }
            }
        } catch (Exception ex) {
            // Fallback when TableEnumOrId filtering fails in a runtime context.
            try {
                List<ApexTrigger> triggers = [
                    SELECT Id, Name, Status, Body, TableEnumOrId
                    FROM ApexTrigger
                    LIMIT :maxRows
                ];
                for (ApexTrigger triggerRow : triggers) {
                    if (String.valueOf(triggerRow.TableEnumOrId) != objectApiName) {
                        continue;
                    }
                    String body = safeLower(triggerRow.Body);
                    Boolean isActive = String.valueOf(triggerRow.Status) == 'Active';
                    for (String fieldApiName : fieldApiNames) {
                        if (containsToken(body, fieldApiName)) {
                            FieldDependencySummary summary = result.get(fieldApiName);
                            if (isActive) {
                                summary.activeTriggerRefs++;
                                summary.activeTriggerNames.add(triggerRow.Name);
                            } else {
                                summary.inactiveTriggerRefs++;
                                summary.inactiveTriggerNames.add(triggerRow.Name);
                            }
                        }
                    }
                }
            } catch (Exception ignored) {
                // Ignore scanner gaps. Recommendation engine handles unknown/partial evidence.
            }
        }
    }

    private static void scanValidationRules(
        String objectApiName,
        Set<String> fieldApiNames,
        Map<String, FieldDependencySummary> result,
        Integer maxRows
    ) {
        List<SObject> rules = new List<SObject>();
        try {
            rules = Database.query(
                'SELECT Id, Active, ErrorConditionFormula, EntityDefinition.QualifiedApiName ' +
                'FROM ValidationRule ' +
                'WHERE EntityDefinition.QualifiedApiName = \'' + String.escapeSingleQuotes(objectApiName) + '\' ' +
                'LIMIT ' + maxRows
            );
        } catch (Exception primaryEx) {
            try {
                rules = Database.query(
                    'SELECT Id, Active, ErrorConditionFormula, EntityDefinition.QualifiedApiName ' +
                    'FROM ValidationRule LIMIT ' + maxRows
                );
            } catch (Exception fallbackEx) {
                return;
            }
        }

        for (SObject rule : rules) {
            String ruleObjectName = null;
            try {
                SObject entityDefinition = rule.getSObject('EntityDefinition');
                if (entityDefinition != null) {
                    ruleObjectName = (String) entityDefinition.get('QualifiedApiName');
                }
            } catch (Exception ex) {
                ruleObjectName = null;
            }
            if (!String.isBlank(ruleObjectName) && ruleObjectName != objectApiName) {
                continue;
            }

            String formula = safeLower((String) rule.get('ErrorConditionFormula'));
            Boolean isActive = false;
            try {
                isActive = (Boolean) rule.get('Active');
            } catch (Exception ex) {
                isActive = false;
            }

            for (String fieldApiName : fieldApiNames) {
                if (containsToken(formula, fieldApiName)) {
                    FieldDependencySummary summary = result.get(fieldApiName);
                    if (isActive) {
                        summary.activeValidationRuleRefs++;
                    } else {
                        summary.inactiveValidationRuleRefs++;
                    }
                }
            }
        }
    }

    private static void scanFlowsAndProcessBuilder(Map<String, FieldDependencySummary> result, Integer maxRows) {
        // Do not assign org-wide flow counts to every field. Without field-level flow
        // parsing this creates false dependencies and noisy recommendations.
        if (result == null || result.isEmpty() || maxRows == null || maxRows <= 0) {
            return;
        }
    }

    private static void scanApexClassCoverage(
        String objectApiName,
        Set<String> fieldApiNames,
        Map<String, FieldDependencySummary> result,
        Integer maxRows
    ) {
        List<ApexClass> classes = new List<ApexClass>();
        try {
            classes = [SELECT Id, Name, Body FROM ApexClass LIMIT :maxRows];
        } catch (Exception ex) {
            return;
        }

        Map<Id, Decimal> coverageByClassId = queryApexCoveragePct(new Map<Id, ApexClass>(classes).keySet());

        for (ApexClass classRow : classes) {
            if (classRow.Body == null) {
                continue;
            }
            String body = safeLower(classRow.Body);
            Decimal classCoverage = coverageByClassId.get(classRow.Id);

            for (String fieldApiName : fieldApiNames) {
                String qualifiedFieldToken = objectApiName + '.' + fieldApiName;
                if (!containsToken(body, qualifiedFieldToken)) {
                    continue;
                }

                FieldDependencySummary summary = result.get(fieldApiName);
                summary.apexClassRefs++;
                summary.apexClassNames.add(classRow.Name);

                if (classCoverage == null) {
                    continue;
                }

                if (summary.avgApexCoveragePct == null) {
                    summary.avgApexCoveragePct = classCoverage;
                } else {
                    summary.avgApexCoveragePct =
                        ((summary.avgApexCoveragePct * (summary.apexClassRefs - 1)) + classCoverage) / summary.apexClassRefs;
                }
            }
        }
    }

    private static Map<Id, Decimal> queryApexCoveragePct(Set<Id> apexClassIds) {
        Map<Id, Decimal> coverageByClassId = new Map<Id, Decimal>();
        if (apexClassIds == null || apexClassIds.isEmpty()) {
            return coverageByClassId;
        }

        try {
            String idsCsv = buildIdCsv(apexClassIds);
            if (String.isBlank(idsCsv)) {
                return coverageByClassId;
            }

            List<AggregateResult> rows = Database.query(
                'SELECT ApexClassOrTriggerId classId, SUM(NumLinesCovered) covered, SUM(NumLinesUncovered) uncovered ' +
                'FROM ApexCodeCoverageAggregate ' +
                'WHERE ApexClassOrTriggerId IN (' + idsCsv + ') ' +
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
            // Coverage table isn't always available in all contexts.
        }

        return coverageByClassId;
    }

    private static String buildIdCsv(Set<Id> ids) {
        List<String> quoted = new List<String>();
        for (Id idValue : ids) {
            quoted.add('\'' + String.escapeSingleQuotes(String.valueOf(idValue)) + '\'');
        }
        return String.join(quoted, ',');
    }

    private static String safeLower(String value) {
        return value == null ? '' : value.toLowerCase();
    }

    public static String joinNames(Set<String> names, Integer maxItems) {
        if (names == null || names.isEmpty()) {
            return '';
        }

        List<String> sorted = new List<String>();
        sorted.addAll(names);
        sorted.sort();
        Integer maxCount = Math.min(maxItems == null ? 5 : maxItems, sorted.size());

        List<String> selected = new List<String>();
        for (Integer i = 0; i < maxCount; i++) {
            selected.add(sorted[i]);
        }
        return String.join(selected, ',');
    }

    private static Boolean containsToken(String sourceText, String token) {
        if (String.isBlank(sourceText) || String.isBlank(token)) {
            return false;
        }

        return sourceText.contains(token.toLowerCase());
    }
}
