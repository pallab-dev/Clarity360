public with sharing class Clarity360DashboardController {
    private static final Set<String> ALLOWED_ACTIONS = new Set<String>{
        'Keep',
        'Deprecate',
        'Investigate Dependencies'
    };
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Open',
        'Accepted',
        'Dismissed'
    };
    private static final Set<String> ALLOWED_AGENT_TEST_ACTIONS = new Set<String>{
        'ExplainRecommendation',
        'GetHighRiskRecommendations',
        'GetRecentScanSummary'
    };

    public class RecommendationRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String componentName;
        @AuraEnabled public String action;
        @AuraEnabled public String reason;
        @AuraEnabled public Decimal confidenceScore;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime lastEvaluatedOn;
        @AuraEnabled public String evidenceSummary;
    }

    public class DashboardSummary {
        @AuraEnabled public Integer activeInventoryCount;
        @AuraEnabled public Integer usageSignalCount;
        @AuraEnabled public Integer openRecommendationCount;
        @AuraEnabled public Integer metadataComponentCount;
        @AuraEnabled public Integer referencedMetadataComponentCount;
        @AuraEnabled public Integer platformEventComponentCount;
        @AuraEnabled public Decimal avgNullRatePct;
        @AuraEnabled public Decimal cleanlinessScore;
        @AuraEnabled public String latestJobStatus;
        @AuraEnabled public Datetime latestJobStartedOn;
    }

    public class MetadataComponentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String componentKey;
        @AuraEnabled public String componentType;
        @AuraEnabled public String apiName;
        @AuraEnabled public String displayName;
        @AuraEnabled public Integer referenceCount;
        @AuraEnabled public Integer activeSubscriberCount;
        @AuraEnabled public Boolean monitoringEligible;
        @AuraEnabled public Datetime lastScannedOn;
        @AuraEnabled public String sourceSummary;
        @AuraEnabled public String whyVisible;
        @AuraEnabled public String nextStep;
    }

    public class GlobalComponentRow {
        @AuraEnabled public String key;
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String componentType;
        @AuraEnabled public String componentName;
        @AuraEnabled public String status;
        @AuraEnabled public String objectName;
        @AuraEnabled public String detail;
    }

    public class GlobalComponentSection {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        @AuraEnabled public List<GlobalComponentRow> rows;
    }

    public class RecentJobsPage {
        @AuraEnabled public List<ScanJob__c> jobs;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
    }

    public class LimitMetricRow {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal usedValue;
        @AuraEnabled public Decimal limitValue;
        @AuraEnabled public Decimal remainingValue;
        @AuraEnabled public Decimal pctUsed;
    }

    public class EventMonitorRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String apiName;
        @AuraEnabled public String displayName;
        @AuraEnabled public Integer activeSubscriberCount;
        @AuraEnabled public Integer referenceCount;
        @AuraEnabled public Datetime lastScannedOn;
    }

    public class MonitoringSnapshot {
        @AuraEnabled public Decimal asyncApexUsedPct;
        @AuraEnabled public Integer queueableActiveCount;
        @AuraEnabled public Integer batchActiveCount;
        @AuraEnabled public Integer scheduledJobCount;
        @AuraEnabled public Integer platformEventCount;
        @AuraEnabled public Integer activePlatformSubscriberCount;
        @AuraEnabled public List<LimitMetricRow> limitMetrics;
        @AuraEnabled public List<EventMonitorRow> platformEvents;
    }

    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id jobId;
        @AuraEnabled public String status;
        @AuraEnabled public String messageCode;
    }

    public class FieldDeleteResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean deleted;
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String message;
    }

    public class AgentActionTestResult {
        @AuraEnabled public String action;
        @AuraEnabled public Decimal confidenceScore;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public String explanation;
        @AuraEnabled public String status;
        @AuraEnabled public String summary;
        @AuraEnabled public Id recommendationId;
        @AuraEnabled public String fieldKey;
    }

    public class AgentAssistantAvailability {
        @AuraEnabled public Boolean available;
        @AuraEnabled public String mode;
        @AuraEnabled public String message;
    }

    public class AgentAssistantChatResponse {
        @AuraEnabled public String status;
        @AuraEnabled public String actionUsed;
        @AuraEnabled public String responseText;
        @AuraEnabled public String nextContext;
    }

    private class ChatIntentResolution {
        public String intent;
        public String entityHint;
        public String recommendationIdToken;
        public String fieldKeyToken;
    }

    @TestVisible private static List<GlobalComponentRow> testGlobalComponents;

    @AuraEnabled(cacheable=true)
    public static DashboardSummary getDashboardSummary() {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(FieldInventory__c.SObjectType, 'DashboardSummary');
        access.assertReadable(UsageSignal__c.SObjectType, 'DashboardSummary');
        access.assertReadable(Recommendation__c.SObjectType, 'DashboardSummary');
        access.assertReadable(MetadataComponentInventory__c.SObjectType, 'DashboardSummary');

        DashboardSummary summary = new DashboardSummary();

        summary.activeInventoryCount = [
            SELECT COUNT()
            FROM FieldInventory__c
            WHERE IsActive__c = true
        ];
        summary.usageSignalCount = [SELECT COUNT() FROM UsageSignal__c];
        summary.openRecommendationCount = [SELECT COUNT() FROM Recommendation__c WHERE Status__c = 'Open'];
        summary.metadataComponentCount = [SELECT COUNT() FROM MetadataComponentInventory__c WHERE IsActive__c = true];
        summary.referencedMetadataComponentCount = [
            SELECT COUNT()
            FROM MetadataComponentInventory__c
            WHERE IsActive__c = true
            AND
            ReferenceCount__c > 0
        ];
        summary.platformEventComponentCount = [
            SELECT COUNT()
            FROM MetadataComponentInventory__c
            WHERE IsActive__c = true
            AND ComponentType__c = 'Platform Event'
        ];

        AggregateResult avgResult = [SELECT AVG(NullRatePct__c) avgNullRate FROM UsageSignal__c];
        summary.avgNullRatePct = (Decimal) avgResult.get('avgNullRate');
        if (summary.avgNullRatePct == null) {
            summary.avgNullRatePct = 0;
        }

        Decimal baseScore = 100 - (summary.avgNullRatePct * 0.7);
        Decimal recommendationPenalty = (summary.openRecommendationCount > 0)
            ? Math.min(35, summary.openRecommendationCount * 0.2)
            : 0;
        Decimal calculatedScore = baseScore - recommendationPenalty;
        summary.cleanlinessScore = Math.max(0, Math.min(100, calculatedScore));

        List<ScanJob__c> latest = [
            SELECT Status__c, StartedOn__c
            FROM ScanJob__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!latest.isEmpty()) {
            ScanJob__c readable = latest[0];
            if (readable != null) {
                summary.latestJobStatus = safeGetString(readable, 'Status__c');
                summary.latestJobStartedOn = safeGetDatetime(readable, 'StartedOn__c');
            }
        }

        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<MetadataComponentRow> getMetadataComponents(String typeFilter, Integer rowLimit) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(MetadataComponentInventory__c.SObjectType, 'MetadataComponents');

        Integer safeLimit = (rowLimit == null || rowLimit <= 0) ? 20 : Math.min(rowLimit, 100);
        String safeType = sanitizeMetadataType(typeFilter);
        List<MetadataComponentInventory__c> queried;
        if (String.isBlank(safeType)) {
            queried = [
                SELECT Id, ComponentKey__c, ComponentType__c, ApiName__c, DisplayName__c, ReferenceCount__c,
                    ActiveSubscriberCount__c, MonitoringEligible__c, LastScannedOn__c, SourceSummary__c
                FROM MetadataComponentInventory__c
                WHERE IsActive__c = true
                    AND (
                    MonitoringEligible__c = true
                    OR ReferenceCount__c > 0
                    OR ActiveSubscriberCount__c > 0
                )
                ORDER BY ReferenceCount__c DESC, LastScannedOn__c DESC, ApiName__c ASC
                LIMIT :safeLimit
            ];
        } else {
            queried = [
                SELECT Id, ComponentKey__c, ComponentType__c, ApiName__c, DisplayName__c, ReferenceCount__c,
                    ActiveSubscriberCount__c, MonitoringEligible__c, LastScannedOn__c, SourceSummary__c
                FROM MetadataComponentInventory__c
                WHERE IsActive__c = true
                AND ComponentType__c = :safeType
                AND (
                    MonitoringEligible__c = true
                    OR ReferenceCount__c > 0
                    OR ActiveSubscriberCount__c > 0
                )
                ORDER BY ReferenceCount__c DESC, LastScannedOn__c DESC, ApiName__c ASC
                LIMIT :safeLimit
            ];
        }

        List<MetadataComponentRow> rows = new List<MetadataComponentRow>();
        for (MetadataComponentInventory__c raw : queried) {
            MetadataComponentRow row = new MetadataComponentRow();
            row.id = raw.Id;
            row.componentKey = raw.ComponentKey__c;
            row.componentType = raw.ComponentType__c;
            row.apiName = raw.ApiName__c;
            row.displayName = raw.DisplayName__c;
            row.referenceCount = raw.ReferenceCount__c == null ? 0 : raw.ReferenceCount__c.intValue();
            row.activeSubscriberCount = raw.ActiveSubscriberCount__c == null ? 0 : raw.ActiveSubscriberCount__c.intValue();
            row.monitoringEligible = raw.MonitoringEligible__c;
            row.lastScannedOn = raw.LastScannedOn__c;
            row.sourceSummary = raw.SourceSummary__c;
            row.whyVisible = buildMetadataWhyVisible(row);
            row.nextStep = buildMetadataNextStep(row);
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<RecommendationRow> getRecommendations(
        String actionFilter,
        String statusFilter,
        String objectFilter,
        Integer rowLimit
    ) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(Recommendation__c.SObjectType, 'Recommendations');

        Integer safeLimit = (rowLimit == null || rowLimit <= 0) ? 100 : Math.min(rowLimit, 500);
        String safeAction = sanitizeAction(actionFilter);
        String safeStatus = sanitizeStatus(statusFilter);
        String fieldPattern = buildObjectPattern(objectFilter);

        List<Recommendation__c> queried = queryRecommendations(safeAction, safeStatus, fieldPattern, safeLimit);

        List<RecommendationRow> rows = new List<RecommendationRow>();
        for (Recommendation__c raw : queried) {
            String safeFieldKey = safeGetString(raw, 'FieldKey__c');
            String safeEvidenceSummary = safeGetString(raw, 'EvidenceSummary__c');
            String derivedName = deriveComponentName(safeFieldKey, safeEvidenceSummary);
            if (String.isBlank(safeFieldKey) && String.isBlank(derivedName)) {
                continue;
            }
            RecommendationRow row = new RecommendationRow();
            row.id = (Id) safeGet(raw, 'Id');
            row.fieldKey = safeFieldKey;
            row.componentName = derivedName;
            row.action = safeGetString(raw, 'Action__c');
            row.reason = deriveReason(safeEvidenceSummary);
            row.confidenceScore = safeGetDecimal(raw, 'ConfidenceScore__c');
            row.riskScore = safeGetDecimal(raw, 'RiskScore__c');
            row.status = safeGetString(raw, 'Status__c');
            row.lastEvaluatedOn = safeGetDatetime(raw, 'LastEvaluatedOn__c');
            row.evidenceSummary = safeEvidenceSummary;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<GlobalComponentRow> getGlobalComponents(Integer rowLimit) {
        if (Test.isRunningTest() && testGlobalComponents != null) {
            return testGlobalComponents;
        }

        return buildGlobalComponentRows(rowLimit);
    }

    @AuraEnabled
    public static List<GlobalComponentSection> getGlobalComponentSections(Integer rowLimit) {
        return buildGlobalComponentSections(buildGlobalComponentRows(rowLimit));
    }

    private static List<GlobalComponentRow> buildGlobalComponentRows(Integer rowLimit) {
        Integer safeLimit = (rowLimit == null || rowLimit <= 0) ? 200 : Math.min(rowLimit, 1000);
        List<GlobalComponentRow> rows = new List<GlobalComponentRow>();
        Clarity360Settings.RuntimeConfig runtime = Clarity360Settings.getRequiredRuntime();

        if (runtime.enableTriggerScan == true) {
            rows.addAll(loadGlobalTriggers(safeLimit));
        }
        if (runtime.enableValidationRuleScan == true) {
            rows.addAll(loadGlobalValidationRules(safeLimit));
        }
        if (runtime.enableFlowAndProcessScan == true) {
            rows.addAll(loadGlobalFlows(safeLimit));
        }
        if (runtime.enableWorkflowRuleScan == true) {
            rows.addAll(loadGlobalWorkflowRules(safeLimit));
        }
        if (runtime.enableApexCoverageScan == true) {
            rows.addAll(loadGlobalApexClasses(safeLimit));
        }

        rows.sort(new GlobalComponentRowSorter());
        return rows;
    }

    private static List<GlobalComponentSection> buildGlobalComponentSections(List<GlobalComponentRow> rows) {
        List<GlobalComponentSection> sections = new List<GlobalComponentSection>();
        if (rows == null || rows.isEmpty()) {
            return sections;
        }

        Map<String, Integer> typeOrder = new Map<String, Integer>{
            'Validation Rule' => 1,
            'Trigger' => 2,
            'Flow' => 3,
            'Process Builder' => 4,
            'Workflow Rule' => 5,
            'Apex Class' => 6
        };
        Map<String, List<GlobalComponentRow>> grouped = new Map<String, List<GlobalComponentRow>>();
        for (GlobalComponentRow row : rows) {
            String typeName = String.isBlank(row == null ? null : row.componentType) ? 'Unknown' : row.componentType;
            if (!grouped.containsKey(typeName)) {
                grouped.put(typeName, new List<GlobalComponentRow>());
            }
            grouped.get(typeName).add(row);
        }

        List<String> typeNames = new List<String>(grouped.keySet());
        typeNames.sort();
        typeNames.sort(new GlobalTypeSorter(typeOrder));

        for (String typeName : typeNames) {
            List<GlobalComponentRow> sectionRows = grouped.get(typeName);
            GlobalComponentSection section = new GlobalComponentSection();
            section.name = typeName;
            section.count = sectionRows == null ? 0 : sectionRows.size();
            section.label = typeName + ' (' + section.count + ')';
            section.rows = sectionRows;
            sections.add(section);
        }
        return sections;
    }

    @AuraEnabled(cacheable=true)
    public static List<UsageSignal__c> getSignalsForField(String fieldKey) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(UsageSignal__c.SObjectType, 'SignalsForField');
        if (String.isBlank(fieldKey) || !isSafeFieldKey(fieldKey)) {
            return new List<UsageSignal__c>();
        }

        List<UsageSignal__c> rows = [
            SELECT Id, FieldKey__c, SampleSize__c, NonNullCount__c, NullRatePct__c, IsOnLayout__c, LastObservedOn__c, EvidenceSummary__c
            FROM UsageSignal__c
            WHERE FieldKey__c = :fieldKey
            ORDER BY LastObservedOn__c DESC
            LIMIT 50
        ];
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static RecentJobsPage getRecentJobs(Integer pageNumber, Integer pageSize) {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(ScanJob__c.SObjectType, 'RecentJobs');

        Integer safePageSize = (pageSize == null || pageSize <= 0) ? 5 : Math.min(pageSize, 50);
        Integer totalCount = [SELECT COUNT() FROM ScanJob__c];
        Integer maxPageNumber = Math.max(1, (totalCount + safePageSize - 1) / safePageSize);
        Integer safePageNumber = (pageNumber == null || pageNumber <= 0) ? 1 : Math.min(pageNumber, maxPageNumber);
        Integer rowOffset = (safePageNumber - 1) * safePageSize;

        List<ScanJob__c> queried = [
            SELECT Id, Name, JobType__c, Status__c, StartedOn__c, FinishedOn__c, ProgressPct__c, ErrorMessage__c
            FROM ScanJob__c
            ORDER BY CreatedDate DESC
            LIMIT :safePageSize
            OFFSET :rowOffset
        ];

        RecentJobsPage page = new RecentJobsPage();
        page.jobs = queried;
        page.totalCount = totalCount;
        page.pageNumber = safePageNumber;
        page.pageSize = safePageSize;
        return page;
    }

    @AuraEnabled(cacheable=true)
    public static MonitoringSnapshot getMonitoringSnapshot() {
        Clarity360AccessControlService access = Clarity360AccessControlService.get();
        access.assertReadable(MetadataComponentInventory__c.SObjectType, 'MonitoringSnapshot');

        MonitoringSnapshot snapshot = new MonitoringSnapshot();
        snapshot.limitMetrics = new List<LimitMetricRow>();
        snapshot.platformEvents = new List<EventMonitorRow>();

        try {
            Map<String, System.OrgLimit> limitsByName = System.OrgLimits.getMap();
            addOrgLimitMetric(snapshot, limitsByName, 'DailyAsyncApexExecutions', 'Daily Async Apex');
            addOrgLimitMetric(snapshot, limitsByName, 'DailyApiRequests', 'Daily API Requests');
            addOrgLimitMetric(snapshot, limitsByName, 'DataStorageMB', 'Data Storage (MB)');
            addOrgLimitMetric(snapshot, limitsByName, 'FileStorageMB', 'File Storage (MB)');
        } catch (Exception ex) {
            Clarity360SecureLog.warn('Dashboard.getMonitoringSnapshot.limits', ex);
        }

        LimitMetricRow asyncMetric = findMetric(snapshot.limitMetrics, 'DailyAsyncApexExecutions');
        snapshot.asyncApexUsedPct = asyncMetric == null ? 0 : asyncMetric.pctUsed;

        try {
            snapshot.queueableActiveCount = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'Queueable'
                AND Status IN ('Processing', 'Preparing', 'Holding', 'Queued')
            ];
        } catch (Exception ex) {
            Clarity360SecureLog.warn('Dashboard.getMonitoringSnapshot.queueable', ex);
        }
        try {
            snapshot.batchActiveCount = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType IN ('BatchApex', 'BatchApexWorker')
                AND Status IN ('Processing', 'Preparing', 'Holding', 'Queued')
            ];
        } catch (Exception ex) {
            Clarity360SecureLog.warn('Dashboard.getMonitoringSnapshot.batch', ex);
        }
        try {
            snapshot.scheduledJobCount = [SELECT COUNT() FROM CronTrigger];
        } catch (Exception ex) {
            Clarity360SecureLog.warn('Dashboard.getMonitoringSnapshot.scheduled', ex);
        }

        try {
            for (MetadataComponentInventory__c row : [
                SELECT Id, ApiName__c, DisplayName__c, ActiveSubscriberCount__c, ReferenceCount__c, LastScannedOn__c
                FROM MetadataComponentInventory__c
                WHERE ComponentType__c = 'Platform Event'
                AND IsActive__c = true
                AND (ActiveSubscriberCount__c > 0 OR ReferenceCount__c > 0)
                ORDER BY ActiveSubscriberCount__c DESC, ReferenceCount__c DESC, ApiName__c ASC
                LIMIT 100
            ]) {
                EventMonitorRow eventRow = new EventMonitorRow();
                eventRow.id = row.Id;
                eventRow.apiName = row.ApiName__c;
                eventRow.displayName = row.DisplayName__c;
                eventRow.activeSubscriberCount =
                    row.ActiveSubscriberCount__c == null ? 0 : row.ActiveSubscriberCount__c.intValue();
                eventRow.referenceCount = row.ReferenceCount__c == null ? 0 : row.ReferenceCount__c.intValue();
                eventRow.lastScannedOn = row.LastScannedOn__c;
                snapshot.platformEvents.add(eventRow);
                snapshot.activePlatformSubscriberCount += eventRow.activeSubscriberCount;
            }
        } catch (Exception ex) {
            Clarity360SecureLog.warn('Dashboard.getMonitoringSnapshot.platformEvents', ex);
        }
        snapshot.platformEventCount = snapshot.platformEvents.size();
        return snapshot;
    }

    private static String buildMetadataWhyVisible(MetadataComponentRow row) {
        List<String> reasons = new List<String>();
        if ((row == null ? 0 : row.activeSubscriberCount) > 0) {
            reasons.add('has active subscribers');
        }
        if ((row == null ? 0 : row.referenceCount) > 0) {
            reasons.add('is referenced by metadata or code');
        }
        if (row != null && row.monitoringEligible == true) {
            reasons.add('is eligible for monitoring');
        }
        if (reasons.isEmpty()) {
            return 'Shown because it was included in metadata inventory.';
        }
        return 'Shown because it ' + String.join(reasons, ', ') + '.';
    }

    private static String buildMetadataNextStep(MetadataComponentRow row) {
        if (row == null) {
            return 'Refresh metadata inventory after the next scan.';
        }
        if (row.componentType == 'Platform Event') {
            if (row.activeSubscriberCount > 0) {
                return 'Review subscribers and confirm each event is still required before cleanup.';
            }
            return 'Confirm whether this event should remain monitored or be retired.';
        }
        if (row.referenceCount > 0) {
            return 'Review dependencies before changing or removing this metadata.';
        }
        return 'No action is needed yet. Keep it visible for monitoring and refresh after the next scan.';
    }

    @AuraEnabled
    public static Id runInventoryRefresh() {
        return runInventoryRefreshV2(null).jobId;
    }

    @AuraEnabled
    public static OperationResult runInventoryRefreshV2(String requestId) {
        try {
            assertSetupComplete();
            ScanOrchestrator.StartResult result = ScanOrchestrator.runInventoryOnlyV2(null, null, requestId);
            return toOperationResult(result, 'INVENTORY_SCAN_QUEUED');
        } catch (Exception ex) {
            Clarity360SecureLog.error('Dashboard.runInventoryRefreshV2', ex);
            throw new AuraHandledException(Clarity360SecureLog.sanitizeForUi(ex, 'Inventory refresh failed.'));
        }
    }

    @AuraEnabled
    public static Id runUsageScan() {
        return runUsageScanV2(null).jobId;
    }

    @AuraEnabled
    public static OperationResult runUsageScanV2(String requestId) {
        try {
            assertSetupComplete();
            ScanOrchestrator.StartResult result = ScanOrchestrator.runUsageScanOnlyV2(null, null, requestId);
            return toOperationResult(result, 'USAGE_SCAN_QUEUED');
        } catch (Exception ex) {
            Clarity360SecureLog.error('Dashboard.runUsageScanV2', ex);
            throw new AuraHandledException(Clarity360SecureLog.sanitizeForUi(ex, 'Usage scan failed.'));
        }
    }

    @AuraEnabled
    public static Id runFullScan() {
        return runFullScanV2(null).jobId;
    }

    @AuraEnabled
    public static OperationResult runFullScanV2(String requestId) {
        try {
            assertSetupComplete();
            ScanOrchestrator.StartResult result = ScanOrchestrator.runFullScanV2(requestId);
            return toOperationResult(result, 'FULL_SCAN_QUEUED');
        } catch (Exception ex) {
            Clarity360SecureLog.error('Dashboard.runFullScanV2', ex);
            throw new AuraHandledException(Clarity360SecureLog.sanitizeForUi(ex, 'Full scan failed.'));
        }
    }

    @AuraEnabled
    public static FieldDeleteResult deleteCustomField(String fieldKey) {
        FieldDeleteResult result = new FieldDeleteResult();
        result.success = false;
        result.deleted = false;
        result.fieldKey = fieldKey;

        try {
            assertSetupComplete();
            if (String.isBlank(fieldKey) || !isSafeFieldKey(fieldKey) || fieldKey.startsWith('GLOBAL.')) {
                result.message = 'Invalid field key.';
                return result;
            }

            Integer splitIndex = fieldKey.indexOf('.');
            if (splitIndex <= 0 || splitIndex >= fieldKey.length() - 1) {
                result.message = 'Invalid field key format.';
                return result;
            }

            String objectApiName = fieldKey.substring(0, splitIndex);
            String fieldApiName = fieldKey.substring(splitIndex + 1);
            if (!fieldApiName.endsWith('__c')) {
                result.message = 'Only custom fields can be deleted.';
                return result;
            }

            UsageSignal__c latestSignal;
            List<UsageSignal__c> signalRows = [
                SELECT Id, EvidenceSummary__c, NonNullCount__c
                FROM UsageSignal__c
                WHERE FieldKey__c = :fieldKey
                ORDER BY LastObservedOn__c DESC
                LIMIT 1
            ];
            if (!signalRows.isEmpty()) {
                latestSignal = signalRows[0];
            }
            if (latestSignal == null) {
                result.message = 'No usage scan evidence found. Run Usage Scan before deletion.';
                return result;
            }

            if (!isEligibleForDeletion(latestSignal)) {
                result.message = 'Field is in use or has sampled data. Deletion is blocked.';
                return result;
            }

            String customFieldId = resolveCustomFieldToolingId(objectApiName, fieldApiName);
            if (String.isBlank(customFieldId)) {
                result.message = 'Unable to resolve custom field metadata id. Deletion skipped.';
                return result;
            }

            ToolingApiService.ToolingMutationResult deleteResult =
                ToolingApiService.deleteRecord('CustomField', customFieldId);
            if (deleteResult == null || deleteResult.success != true) {
                result.message = deleteResult == null ? 'Tooling API delete failed.' : deleteResult.errorMessage;
                return result;
            }

            cleanupFieldArtifacts(fieldKey);
            result.success = true;
            result.deleted = true;
            result.message = 'Field deleted successfully.';
            return result;
        } catch (Exception ex) {
            Clarity360SecureLog.error('Dashboard.deleteCustomField', ex);
            throw new AuraHandledException(Clarity360SecureLog.sanitizeForUi(ex, 'Field deletion failed.'));
        }
    }

    @AuraEnabled
    public static List<AgentActionTestResult> runAgentActionTest(
        String testAction,
        Id recommendationId,
        String fieldKey,
        Decimal minRiskScore,
        Integer maxResults,
        String statusFilter,
        Integer lookbackDays
    ) {
        try {
            assertSetupComplete();
            String safeAction = sanitizeAgentTestAction(testAction);

            if (safeAction == 'ExplainRecommendation') {
                Clarity360AgentActions.ExplainRecommendationRequest request =
                    new Clarity360AgentActions.ExplainRecommendationRequest();
                request.recommendationId = recommendationId;
                request.fieldKey = fieldKey;
                return mapAgentActionResults(
                    Clarity360AgentActions.explainRecommendation(
                        new List<Clarity360AgentActions.ExplainRecommendationRequest>{ request }
                    )
                );
            }

            if (safeAction == 'GetHighRiskRecommendations') {
                Clarity360AgentActions.GetHighRiskRecommendationsRequest request =
                    new Clarity360AgentActions.GetHighRiskRecommendationsRequest();
                request.minRiskScore = minRiskScore;
                request.maxResults = maxResults;
                request.statusFilter = statusFilter;
                return mapAgentActionResults(
                    Clarity360AgentActions.getHighRiskRecommendations(
                        new List<Clarity360AgentActions.GetHighRiskRecommendationsRequest>{ request }
                    )
                );
            }

            Clarity360AgentActions.GetRecentScanSummaryRequest request =
                new Clarity360AgentActions.GetRecentScanSummaryRequest();
            request.lookbackDays = lookbackDays;
            return mapAgentActionResults(
                Clarity360AgentActions.getRecentScanSummary(
                    new List<Clarity360AgentActions.GetRecentScanSummaryRequest>{ request }
                )
            );
        } catch (Exception ex) {
            Clarity360SecureLog.error('Dashboard.runAgentActionTest', ex);
            throw new AuraHandledException(Clarity360SecureLog.sanitizeForUi(ex, 'Agent action test failed.'));
        }
    }

    @AuraEnabled(cacheable=true)
    public static AgentAssistantAvailability getAgentAssistantAvailability() {
        AgentAssistantAvailability state = new AgentAssistantAvailability();
        state.available = false;
        state.mode = 'Standard Mode';
        state.message = 'Agentforce is not available for this user/session.';

        try {
            if (!Recommendation__c.SObjectType.getDescribe().isAccessible()) {
                state.message = 'Read access to Recommendation__c is required for AI mode.';
                return state;
            }

            // Probe core Agent action path without mutating data.
            Clarity360AgentActions.getRecentScanSummary(new List<Clarity360AgentActions.GetRecentScanSummaryRequest>{
                new Clarity360AgentActions.GetRecentScanSummaryRequest()
            });

            state.available = true;
            state.mode = 'AI Mode';
            state.message = 'Agentforce is available. AI mode can be enabled.';
            return state;
        } catch (Exception ex) {
            state.available = false;
            state.mode = 'Standard Mode';
            state.message = 'Agentforce unavailable: ' + Clarity360SecureLog.sanitizeForUi(ex, 'Check class access and permissions.');
            return state;
        }
    }

    @AuraEnabled
    public static AgentAssistantChatResponse askAgentAssistant(String userMessage, String pendingContext) {
        AgentAssistantChatResponse response = new AgentAssistantChatResponse();
        response.status = 'Success';
        response.actionUsed = 'None';
        response.responseText = 'Please ask a question.';
        response.nextContext = null;

        try {
            assertSetupComplete();
            AgentAssistantAvailability availability = getAgentAssistantAvailability();
            if (availability == null || availability.available != true) {
                response.status = 'Unavailable';
                response.responseText = availability == null
                    ? 'Agentforce is not available right now.'
                    : availability.message;
                return response;
            }

            if (String.isBlank(userMessage)) {
                response.status = 'Invalid Input';
                response.responseText = 'Ask anything about your Clarity360 data, for example: "top high-risk items" or "explain Account.Legacy_Flag__c".';
                return response;
            }

            String normalized = userMessage.toLowerCase();
            String safeContext = String.isBlank(pendingContext) ? null : pendingContext.trim().toLowerCase();
            ChatIntentResolution intent = resolveChatIntent(normalized, safeContext, userMessage);

            if (intent.intent == 'clarifyDeleteInactive') {
                response.status = 'Needs Clarification';
                response.nextContext = 'deleteInactive';
                response.responseText = 'I can help with that. Do you mean inactive triggers, flows, or fields?';
                return response;
            }

            if (intent.intent == 'deleteInactive') {
                response.actionUsed = 'GeneralRecommendations';
                response.responseText = formatEntityDeletionGuidance(intent.entityHint);
                return response;
            }

            if (intent.intent == 'scanSummary') {
                response.actionUsed = 'GetRecentScanSummary';
                Integer lookbackDays = extractInteger(userMessage, '(\\d+)\\s*day');
                Clarity360AgentActions.GetRecentScanSummaryRequest request = new Clarity360AgentActions.GetRecentScanSummaryRequest();
                request.lookbackDays = lookbackDays == null ? 30 : lookbackDays;
                List<Clarity360AgentActions.AgentActionResult> rows =
                    Clarity360AgentActions.getRecentScanSummary(
                        new List<Clarity360AgentActions.GetRecentScanSummaryRequest>{ request }
                    );
                response.responseText = formatRecentScanSummary(rows);
                return response;
            }

            if (intent.intent == 'highRisk') {
                response.actionUsed = 'GetHighRiskRecommendations';
                Integer maxResults = extractInteger(userMessage, 'top\\s*(\\d+)');
                Decimal riskThreshold = extractDecimal(userMessage, '(?:above|over|>=?)\\s*(\\d+(?:\\.\\d+)?)');
                String statusFilter = normalized.contains('accepted')
                    ? 'Accepted'
                    : (normalized.contains('dismissed') ? 'Dismissed' : 'Open');

                Clarity360AgentActions.GetHighRiskRecommendationsRequest request =
                    new Clarity360AgentActions.GetHighRiskRecommendationsRequest();
                request.maxResults = maxResults == null ? 5 : maxResults;
                request.minRiskScore = riskThreshold == null ? 70 : riskThreshold;
                request.statusFilter = statusFilter;
                List<Clarity360AgentActions.AgentActionResult> rows =
                    Clarity360AgentActions.getHighRiskRecommendations(
                        new List<Clarity360AgentActions.GetHighRiskRecommendationsRequest>{ request }
                    );
                response.responseText = formatHighRiskSummary(rows);
                return response;
            }

            if (intent.intent == 'explain') {
                response.actionUsed = 'ExplainRecommendation';
                Clarity360AgentActions.ExplainRecommendationRequest request =
                    new Clarity360AgentActions.ExplainRecommendationRequest();
                request.recommendationId = parseIdOrNull(intent.recommendationIdToken);
                request.fieldKey = intent.fieldKeyToken;
                List<Clarity360AgentActions.AgentActionResult> rows =
                    Clarity360AgentActions.explainRecommendation(
                        new List<Clarity360AgentActions.ExplainRecommendationRequest>{ request }
                    );
                response.responseText = formatExplainSummary(rows);
                if (rows != null && !rows.isEmpty() && rows[0] != null && rows[0].status == 'Not Found') {
                    response.status = 'Needs Clarification';
                }
                return response;
            }

            response.actionUsed = 'AskClarity360Data';
            response.responseText = formatDataDrivenAnswer(userMessage, intent.entityHint);
            return response;
        } catch (Exception ex) {
            Clarity360SecureLog.error('Dashboard.askAgentAssistant', ex);
            response.status = 'Error';
            response.responseText = Clarity360SecureLog.sanitizeForUi(ex, 'Unable to process your request right now.');
            return response;
        }
    }

    private static ChatIntentResolution resolveChatIntent(String normalizedMessage, String pendingContext, String originalMessage) {
        ChatIntentResolution resolution = new ChatIntentResolution();
        resolution.intent = 'data';
        resolution.entityHint = resolveEntityHint(normalizedMessage, pendingContext);
        resolution.recommendationIdToken = extractString(originalMessage, '\\b[a-zA-Z0-9]{15,18}\\b');
        resolution.fieldKeyToken = extractString(originalMessage, '\\b[A-Za-z][A-Za-z0-9_]*\\.[A-Za-z][A-Za-z0-9_]*\\b');

        Boolean askedDeleteInactive =
            (normalizedMessage.contains('delete') && normalizedMessage.contains('inactive')) ||
            pendingContext == 'deleteinactive';
        if (askedDeleteInactive) {
            if (String.isBlank(resolution.entityHint)) {
                resolution.intent = 'clarifyDeleteInactive';
            } else {
                resolution.intent = 'deleteInactive';
            }
            return resolution;
        }

        Integer scanScore = keywordScore(normalizedMessage, new List<String>{ 'scan', 'summary', 'recent', 'job' });
        Integer highRiskScore = keywordScore(normalizedMessage, new List<String>{ 'high risk', 'priority', 'risky', 'top', 'danger' });
        Integer explainScore = keywordScore(normalizedMessage, new List<String>{ 'explain', 'why', 'reason', 'details' });

        if (!String.isBlank(resolution.recommendationIdToken) || !String.isBlank(resolution.fieldKeyToken)) {
            resolution.intent = 'explain';
            return resolution;
        }
        if (highRiskScore >= 1 && highRiskScore >= scanScore) {
            resolution.intent = 'highRisk';
            return resolution;
        }
        if (scanScore >= 1) {
            resolution.intent = 'scanSummary';
            return resolution;
        }
        if (explainScore >= 1 && !String.isBlank(resolution.entityHint)) {
            resolution.intent = 'data';
            return resolution;
        }
        return resolution;
    }

    private static Integer keywordScore(String normalizedMessage, List<String> keywords) {
        if (String.isBlank(normalizedMessage) || keywords == null || keywords.isEmpty()) {
            return 0;
        }
        Integer score = 0;
        for (String keyword : keywords) {
            if (!String.isBlank(keyword) && normalizedMessage.contains(keyword)) {
                score++;
            }
        }
        return score;
    }

    private static String resolveEntityHint(String normalizedMessage, String pendingContext) {
        String source = safeString(normalizedMessage, '') + ' ' + safeString(pendingContext, '');
        if (source.contains('trigger')) {
            return 'trigger';
        }
        if (source.contains('flow')) {
            return 'flow';
        }
        if (source.contains('field')) {
            return 'field';
        }
        return null;
    }

    private static String formatDataDrivenAnswer(String userMessage, String entityHint) {
        List<String> tokens = extractSearchTokens(userMessage);
        List<Recommendation__c> candidates = queryDataDrivenCandidates(entityHint);
        List<Recommendation__c> ranked = rankRecommendationsByTokens(candidates, tokens);

        Integer openRecommendationCount = [SELECT COUNT() FROM Recommendation__c WHERE Status__c = 'Open'];
        Integer usageSignalCount = [SELECT COUNT() FROM UsageSignal__c WHERE LastObservedOn__c != null];
        List<ScanJob__c> latestJobs = [
            SELECT JobType__c, Status__c, StartedOn__c
            FROM ScanJob__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        String latestStatus = latestJobs.isEmpty()
            ? 'No recent scan job found'
            : safeString(latestJobs[0].JobType__c, 'Unknown job') + ' is ' + safeString(latestJobs[0].Status__c, 'Unknown');

        List<String> lines = new List<String>{
            'Here is what I found in your Clarity360 data:',
            '- Open recommendations: ' + String.valueOf(openRecommendationCount),
            '- Usage signals collected: ' + String.valueOf(usageSignalCount),
            '- Latest scan: ' + latestStatus
        };

        if (!ranked.isEmpty()) {
            lines.add('Most relevant recommendations:');
            Integer maxRows = Math.min(3, ranked.size());
            for (Integer i = 0; i < maxRows; i++) {
                Recommendation__c row = ranked[i];
                String risk = row.RiskScore__c == null ? 'n/a' : String.valueOf(row.RiskScore__c.setScale(2));
                lines.add(
                    String.valueOf(i + 1) + '. ' +
                    safeString(row.FieldKey__c, 'Unknown component') +
                    ' - ' + safeString(row.Action__c, 'Review') +
                    ' (risk ' + risk + ', status ' + safeString(row.Status__c, 'Unknown') + ')'
                );
            }
            lines.add('If you want a detailed reason, ask: "explain <fieldKey or recommendationId>".');
        } else {
            lines.add('I could not find a direct match for that wording.');
            lines.add('Try including an object/field or component type like triggers, flows, or fields.');
        }
        return String.join(lines, '\n');
    }

    private static List<Recommendation__c> queryDataDrivenCandidates(String entityHint) {
        if (entityHint == 'trigger') {
            return [
                SELECT Id, FieldKey__c, Action__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE Status__c = 'Open' AND FieldKey__c LIKE 'GLOBAL.TRIGGER.%'
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT 25
            ];
        }
        if (entityHint == 'flow') {
            return [
                SELECT Id, FieldKey__c, Action__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE Status__c = 'Open' AND FieldKey__c LIKE 'GLOBAL.FLOW.%'
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT 25
            ];
        }
        List<Recommendation__c> rows = [
            SELECT Id, FieldKey__c, Action__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
            FROM Recommendation__c
            WHERE Status__c = 'Open'
            ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
            LIMIT 50
        ];
        if (entityHint != 'field') {
            return rows;
        }
        List<Recommendation__c> fieldRows = new List<Recommendation__c>();
        for (Recommendation__c row : rows) {
            if (row == null || String.isBlank(row.FieldKey__c)) {
                continue;
            }
            if (row.FieldKey__c.toUpperCase().startsWith('GLOBAL.')) {
                continue;
            }
            fieldRows.add(row);
            if (fieldRows.size() == 25) {
                break;
            }
        }
        return fieldRows;
    }

    private static List<String> extractSearchTokens(String source) {
        List<String> tokens = new List<String>();
        if (String.isBlank(source)) {
            return tokens;
        }
        Set<String> ignored = new Set<String>{
            'what', 'when', 'where', 'which', 'about', 'this', 'that', 'from', 'with', 'have',
            'show', 'tell', 'give', 'need', 'please', 'clarity360', 'could', 'should', 'would',
            'can', 'you', 'for', 'the', 'and', 'any', 'all', 'are', 'how', 'why'
        };
        String normalized = source.toLowerCase().replaceAll('[^a-z0-9_\\. ]', ' ');
        for (String token : normalized.split('\\s+')) {
            if (String.isBlank(token) || token.length() < 4 || ignored.contains(token)) {
                continue;
            }
            tokens.add(token);
            if (tokens.size() == 8) {
                break;
            }
        }
        return tokens;
    }

    private static List<Recommendation__c> rankRecommendationsByTokens(List<Recommendation__c> candidates, List<String> tokens) {
        if (candidates == null || candidates.isEmpty()) {
            return new List<Recommendation__c>();
        }
        List<Recommendation__c> ranked = new List<Recommendation__c>();
        Set<Id> usedIds = new Set<Id>();
        Map<Id, Integer> scores = new Map<Id, Integer>();
        for (Recommendation__c row : candidates) {
            if (row == null || row.Id == null) {
                continue;
            }
            String haystack = (
                safeString(row.FieldKey__c, '') + ' ' +
                safeString(row.Action__c, '') + ' ' +
                safeString(row.EvidenceSummary__c, '')
            ).toLowerCase();
            Integer score = 0;
            for (String token : tokens) {
                if (!String.isBlank(token) && haystack.contains(token)) {
                    score++;
                }
            }
            scores.put(row.Id, score);
        }

        // Prefer records with the highest lexical score, then keep natural query order.
        for (Integer targetScore = 8; targetScore >= 1; targetScore--) {
            for (Recommendation__c row : candidates) {
                if (row == null || row.Id == null || usedIds.contains(row.Id)) {
                    continue;
                }
                if (scores.get(row.Id) == targetScore) {
                    ranked.add(row);
                    usedIds.add(row.Id);
                    if (ranked.size() == 5) {
                        return ranked;
                    }
                }
            }
        }
        for (Recommendation__c row : candidates) {
            if (row == null || row.Id == null || usedIds.contains(row.Id)) {
                continue;
            }
            ranked.add(row);
            if (ranked.size() == 5) {
                break;
            }
        }
        return ranked;
    }

    private static void assertSetupComplete() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        if (config == null || config.isSetupComplete != true) {
            throw new AuraHandledException('Complete Clarity360 Setup Wizard before using dashboard operations.');
        }
    }

    private static OperationResult toOperationResult(ScanOrchestrator.StartResult startResult, String messageCode) {
        OperationResult result = new OperationResult();
        result.success = true;
        result.jobId = startResult == null ? null : startResult.jobId;
        result.status = startResult == null ? null : startResult.status;
        result.messageCode = messageCode;
        return result;
    }

    private static Boolean isEligibleForDeletion(UsageSignal__c latestSignal) {
        if (latestSignal == null) {
            return false;
        }
        EvidenceParser parser = EvidenceParser.get();
        Map<String, String> parsed = parser.parse((String) safeGet(latestSignal, 'EvidenceSummary__c'));

        Integer triggerRefs = parser.getInteger(parsed, 'ActiveTriggerRefs', 0) + parser.getInteger(parsed, 'InactiveTriggerRefs', 0);
        Integer validationRuleRefs =
            parser.getInteger(parsed, 'ActiveValidationRuleRefs', 0) + parser.getInteger(parsed, 'InactiveValidationRuleRefs', 0);
        Integer flowRefs = parser.getInteger(parsed, 'ActiveFlowRefs', 0) + parser.getInteger(parsed, 'InactiveFlowRefs', 0);
        Integer apexClassRefs = parser.getInteger(parsed, 'ApexClassRefs', 0);
        Integer concreteRefs = triggerRefs + validationRuleRefs + flowRefs + apexClassRefs;
        if (concreteRefs > 0) {
            return false;
        }

        Boolean hasData = parser.getBoolean(parsed, 'HasData', null);
        Integer nonNull = 0;
        try {
            nonNull = Integer.valueOf(String.valueOf(safeGet(latestSignal, 'NonNullCount__c')));
        } catch (Exception ignored) {
            nonNull = 0;
        }

        if (hasData == true || nonNull > 0) {
            return false;
        }
        if (hasData == null) {
            return false;
        }
        return true;
    }

    private static String resolveCustomFieldToolingId(String objectApiName, String fieldApiName) {
        String escapedObject = String.escapeSingleQuotes(objectApiName);
        String escapedField = String.escapeSingleQuotes(fieldApiName);
        String soql =
            'SELECT MetadataComponentId, NamespacePrefix, DurableId, EntityDefinition.QualifiedApiName ' +
            'FROM FieldDefinition ' +
            'WHERE EntityDefinition.QualifiedApiName = \'' + escapedObject + '\' ' +
            'AND QualifiedApiName = \'' + escapedField + '\' ' +
            'LIMIT 5';
        ToolingApiService.ToolingQueryResult toolingResult = ToolingApiService.query(soql, 5);
        if (toolingResult == null || toolingResult.success != true || toolingResult.records == null || toolingResult.records.isEmpty()) {
            return null;
        }

        for (Map<String, Object> row : toolingResult.records) {
            if (row == null) {
                continue;
            }
            String namespacePrefix = ToolingApiService.getString(row, 'NamespacePrefix');
            if (!String.isBlank(namespacePrefix)) {
                continue;
            }
            String metadataComponentId = ToolingApiService.getString(row, 'MetadataComponentId');
            if (!String.isBlank(metadataComponentId)) {
                return metadataComponentId;
            }
        }
        return null;
    }

    private static void cleanupFieldArtifacts(String fieldKey) {
        List<Recommendation__c> recommendations = [
            SELECT Id
            FROM Recommendation__c
            WHERE FieldKey__c = :fieldKey
            LIMIT 10000
        ];
        if (!recommendations.isEmpty()) {
            delete recommendations;
        }

        List<UsageSignal__c> signals = [
            SELECT Id
            FROM UsageSignal__c
            WHERE FieldKey__c = :fieldKey
            LIMIT 10000
        ];
        if (!signals.isEmpty()) {
            delete signals;
        }

        List<FieldInventory__c> inventory = [
            SELECT Id
            FROM FieldInventory__c
            WHERE FieldKey__c = :fieldKey
            LIMIT 1000
        ];
        if (!inventory.isEmpty()) {
            delete inventory;
        }
    }

    private static List<Recommendation__c> queryRecommendations(String action, String status, String objectPattern, Integer safeLimit) {
        if (action == null && status == null && objectPattern == null) {
            return [
                SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT :safeLimit
            ];
        }
        if (action != null && status == null && objectPattern == null) {
            return [
                SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE Action__c = :action
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT :safeLimit
            ];
        }
        if (action == null && status != null && objectPattern == null) {
            return [
                SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE Status__c = :status
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT :safeLimit
            ];
        }
        if (action == null && status == null && objectPattern != null) {
            return [
                SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE FieldKey__c LIKE :objectPattern
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT :safeLimit
            ];
        }
        if (action != null && status != null && objectPattern == null) {
            return [
                SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE Action__c = :action AND Status__c = :status
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT :safeLimit
            ];
        }
        if (action != null && status == null && objectPattern != null) {
            return [
                SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE Action__c = :action AND FieldKey__c LIKE :objectPattern
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT :safeLimit
            ];
        }
        if (action == null && status != null && objectPattern != null) {
            return [
                SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
                FROM Recommendation__c
                WHERE Status__c = :status AND FieldKey__c LIKE :objectPattern
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT :safeLimit
            ];
        }

        return [
            SELECT Id, FieldKey__c, FieldInventory__c, Action__c, ConfidenceScore__c, RiskScore__c, Status__c, EvidenceSummary__c, LastEvaluatedOn__c
            FROM Recommendation__c
            WHERE Action__c = :action AND Status__c = :status AND FieldKey__c LIKE :objectPattern
            ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
            LIMIT :safeLimit
        ];
    }

    private static void addOrgLimitMetric(
        MonitoringSnapshot snapshot,
        Map<String, System.OrgLimit> limitsByName,
        String limitKey,
        String label
    ) {
        if (snapshot == null || limitsByName == null || !limitsByName.containsKey(limitKey)) {
            return;
        }
        System.OrgLimit orgLimit = limitsByName.get(limitKey);
        if (orgLimit == null) {
            return;
        }

        Decimal usedValue = Decimal.valueOf(String.valueOf(orgLimit.getValue()));
        Decimal limitValue = Decimal.valueOf(String.valueOf(orgLimit.getLimit()));
        if (limitValue <= 0) {
            return;
        }

        LimitMetricRow metric = new LimitMetricRow();
        metric.key = limitKey;
        metric.label = label;
        metric.usedValue = usedValue.setScale(2);
        metric.limitValue = limitValue.setScale(2);
        metric.remainingValue = (limitValue - usedValue).setScale(2);
        metric.pctUsed = ((usedValue * 100) / limitValue).setScale(2);
        snapshot.limitMetrics.add(metric);
    }

    private static LimitMetricRow findMetric(List<LimitMetricRow> metrics, String key) {
        if (metrics == null || String.isBlank(key)) {
            return null;
        }
        for (LimitMetricRow metric : metrics) {
            if (metric != null && metric.key == key) {
                return metric;
            }
        }
        return null;
    }

    private static String sanitizeMetadataType(String typeFilter) {
        if (String.isBlank(typeFilter)) {
            return null;
        }
        String normalized = typeFilter.trim();
        Set<String> allowed = new Set<String>{
            'Custom Metadata Type',
            'Custom Setting',
            'Platform Event'
        };
        return allowed.contains(normalized) ? normalized : null;
    }

    private static String deriveComponentName(String fieldKey, String evidence) {
        if (!String.isBlank(fieldKey) && !fieldKey.startsWith('GLOBAL.')) {
            Integer splitIndex = fieldKey.indexOf('.');
            if (splitIndex > -1 && splitIndex < fieldKey.length() - 1) {
                return fieldKey.substring(splitIndex + 1);
            }
            return fieldKey;
        }

        if (!String.isBlank(fieldKey) && fieldKey.startsWith('GLOBAL.APEXCLASS.')) {
            String prefix = 'GLOBAL.APEXCLASS.';
            if (fieldKey.length() > prefix.length()) {
                return fieldKey.substring(prefix.length());
            }
        }

        Map<String, String> parsed = EvidenceParser.get().parse(evidence);
        String componentName = EvidenceParser.get().getString(parsed, 'ComponentName');
        if (!String.isBlank(componentName)) {
            return componentName;
        }

        String activeTriggers = EvidenceParser.get().getString(parsed, 'ActiveTriggerNames');
        if (!String.isBlank(activeTriggers)) {
            return activeTriggers;
        }

        String inactiveTriggers = EvidenceParser.get().getString(parsed, 'InactiveTriggerNames');
        if (!String.isBlank(inactiveTriggers)) {
            return inactiveTriggers;
        }

        String apexClassNames = EvidenceParser.get().getString(parsed, 'ApexClassNames');
        if (!String.isBlank(apexClassNames)) {
            return apexClassNames;
        }

        return fieldKey;
    }

    private static String deriveReason(String evidence) {
        EvidenceParser parser = EvidenceParser.get();
        Map<String, String> parsed = parser.parse(evidence);

        String componentType = parser.getString(parsed, 'ComponentType');
        String componentStatus = parser.getString(parsed, 'ComponentStatus');
        String coveragePct = parser.getString(parsed, 'CoveragePct');
        if (String.isBlank(coveragePct)) {
            coveragePct = parser.getString(parsed, 'AvgApexCoveragePct');
        }
        if (String.isBlank(componentType) && !String.isBlank(coveragePct) && !String.isBlank(parser.getString(parsed, 'HasCoverageData'))) {
            componentType = 'ApexClass';
        }
        if (!String.isBlank(componentType)) {
            List<String> details = new List<String>();
            if (!String.isBlank(componentStatus)) {
                details.add(componentStatus);
            }
            if (!String.isBlank(coveragePct)) {
                if (coveragePct.equalsIgnoreCase('Unavailable') || coveragePct.equalsIgnoreCase('Unknown')) {
                    details.add('Coverage pending');
                } else {
                    details.add('Coverage=' + coveragePct + '%');
                }
            }
            return componentType + (details.isEmpty() ? '' : ' (' + String.join(details, ', ') + ')');
        }

        String hasData = parser.getString(parsed, 'HasData');
        String nullRatePct = parser.getString(parsed, 'NullRatePct');
        String activeDependencyCount = parser.getString(parsed, 'ActiveDependencyCount');
        String inactiveDependencyCount = parser.getString(parsed, 'InactiveDependencyCount');
        String objectRecordCount = parser.getString(parsed, 'ObjectRecordCount');

        List<String> parts = new List<String>();
        if (!String.isBlank(hasData)) {
            parts.add('HasData=' + hasData);
        }
        if (!String.isBlank(nullRatePct)) {
            parts.add('NullRate=' + nullRatePct + '%');
        }
        if (!String.isBlank(objectRecordCount)) {
            parts.add('Records=' + objectRecordCount);
        }
        if (!String.isBlank(activeDependencyCount)) {
            parts.add('ActiveDeps=' + activeDependencyCount);
        }
        if (!String.isBlank(inactiveDependencyCount)) {
            parts.add('InactiveDeps=' + inactiveDependencyCount);
        }

        if (!parts.isEmpty()) {
            return String.join(parts, ', ');
        }
        return 'Derived from usage and dependency signals';
    }

    private static List<GlobalComponentRow> loadGlobalTriggers(Integer maxRows) {
        List<GlobalComponentRow> rows = new List<GlobalComponentRow>();
        Map<Id, Decimal> coverageByTriggerId = new Map<Id, Decimal>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.queryWithMode(
            'SELECT Id, Name, Status FROM ApexTrigger ORDER BY Name',
            maxRows,
            true,
            true
        );
        if (queryResult.success && !queryResult.records.isEmpty()) {
            Set<Id> triggerIds = new Set<Id>();
            for (Map<String, Object> row : queryResult.records) {
                String triggerIdText = ToolingApiService.getString(row, 'Id');
                if (String.isBlank(triggerIdText)) {
                    continue;
                }
                try {
                    triggerIds.add((Id) triggerIdText);
                } catch (Exception ignored) {
                    // Ignore malformed ids from tooling fallback payloads.
                }
            }
            coverageByTriggerId = loadApexCoveragePct(triggerIds);
            for (Map<String, Object> row : queryResult.records) {
                String triggerIdText = ToolingApiService.getString(row, 'Id');
                Decimal coveragePct = null;
                if (!String.isBlank(triggerIdText)) {
                    try {
                        coveragePct = coverageByTriggerId.get((Id) triggerIdText);
                    } catch (Exception ignored) {
                        coveragePct = null;
                    }
                }
                addGlobalComponentRow(
                    rows,
                    'GLOBAL.TRIGGER.' + ToolingApiService.getString(row, 'Name'),
                    'Trigger',
                    ToolingApiService.getString(row, 'Name'),
                    formatTriggerStatus(ToolingApiService.getString(row, 'Status'), coveragePct),
                    null,
                    formatTriggerDetail(coveragePct)
                );
            }
            return rows;
        }

        List<ApexTrigger> triggers = [SELECT Id, Name, Status FROM ApexTrigger LIMIT :maxRows];
        coverageByTriggerId = loadApexCoveragePct(new Map<Id, ApexTrigger>(triggers).keySet());
        for (ApexTrigger row : triggers) {
            addGlobalComponentRow(
                rows,
                'GLOBAL.TRIGGER.' + row.Name,
                'Trigger',
                row.Name,
                formatTriggerStatus(String.valueOf(row.Status), coverageByTriggerId.get(row.Id)),
                null,
                formatTriggerDetail(coverageByTriggerId.get(row.Id))
            );
        }
        return rows;
    }

    private static List<GlobalComponentRow> loadGlobalValidationRules(Integer maxRows) {
        List<GlobalComponentRow> rows = new List<GlobalComponentRow>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.queryWithMode(
            'SELECT Id, ValidationName, Active, EntityDefinition.QualifiedApiName FROM ValidationRule ORDER BY ValidationName',
            maxRows,
            true,
            true
        );
        if (queryResult.success && !queryResult.records.isEmpty()) {
            for (Map<String, Object> row : queryResult.records) {
                addGlobalComponentRow(
                    rows,
                    'GLOBAL.VALRULE.' + sanitizeKey(ToolingApiService.getString(row, 'Id')),
                    'Validation Rule',
                    fallbackComponentName(
                        ToolingApiService.getString(row, 'ValidationName'),
                        'Validation Rule',
                        ToolingApiService.getString(row, 'Id')
                    ),
                    ToolingApiService.getBoolean(row, 'Active') == true ? 'Active' : 'Inactive',
                    ToolingApiService.getNestedString(row, 'EntityDefinition', 'QualifiedApiName'),
                    'Validation rule metadata'
                );
            }
            return rows;
        }

        try {
            for (SObject row : Database.query(
                'SELECT Id, ValidationName, Active, EntityDefinition.QualifiedApiName FROM ValidationRule LIMIT ' + maxRows
            )) {
                String objectName = null;
                try {
                    SObject entity = row.getSObject('EntityDefinition');
                    objectName = entity == null ? null : String.valueOf(entity.get('QualifiedApiName'));
                } catch (Exception ignored) {
                    objectName = null;
                }
                addGlobalComponentRow(
                    rows,
                    'GLOBAL.VALRULE.' + sanitizeKey(String.valueOf(row.get('Id'))),
                    'Validation Rule',
                    fallbackComponentName(
                        String.valueOf(row.get('ValidationName')),
                        'Validation Rule',
                        String.valueOf(row.get('Id'))
                    ),
                    ((Boolean) row.get('Active')) == true ? 'Active' : 'Inactive',
                    objectName,
                    'Validation rule metadata'
                );
            }
        } catch (Exception ex) {
            return rows;
        }
        return rows;
    }

    private static List<GlobalComponentRow> loadGlobalFlows(Integer maxRows) {
        List<GlobalComponentRow> rows = new List<GlobalComponentRow>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.queryWithMode(
            'SELECT Id, MasterLabel, Status, ProcessType, VersionNumber FROM Flow ORDER BY MasterLabel, VersionNumber DESC',
            maxRows,
            true,
            true
        );
        if (queryResult.success && !queryResult.records.isEmpty()) {
            Map<String, Map<String, Object>> bestByDefinition = new Map<String, Map<String, Object>>();
            for (Map<String, Object> row : queryResult.records) {
                String masterLabel = ToolingApiService.getString(row, 'MasterLabel');
                String processType = ToolingApiService.getString(row, 'ProcessType');
                String key = fallbackComponentName(masterLabel, 'Flow', ToolingApiService.getString(row, 'Id')) +
                    '|' + String.valueOf(processType);
                if (!bestByDefinition.containsKey(key) || isBetterFlowToolingRow(row, bestByDefinition.get(key))) {
                    bestByDefinition.put(key, row);
                }
            }
            for (Map<String, Object> row : bestByDefinition.values()) {
                String processType = ToolingApiService.getString(row, 'ProcessType');
                addGlobalComponentRow(
                    rows,
                    'GLOBAL.FLOW.' + sanitizeKey(ToolingApiService.getString(row, 'Id')),
                    processType == 'Workflow' ? 'Process Builder' : 'Flow',
                    fallbackComponentName(
                        ToolingApiService.getString(row, 'MasterLabel'),
                        processType == 'Workflow' ? 'Process Builder' : 'Flow',
                        ToolingApiService.getString(row, 'Id')
                    ),
                    ToolingApiService.getString(row, 'Status'),
                    null,
                    'ProcessType=' + processType
                );
            }
            return rows;
        }
        return rows;
    }

    private static List<GlobalComponentRow> loadGlobalWorkflowRules(Integer maxRows) {
        List<GlobalComponentRow> rows = new List<GlobalComponentRow>();
        ToolingApiService.ToolingQueryResult queryResult = ToolingApiService.queryWithMode(
            'SELECT Id, Name, TableEnumOrId, Metadata FROM WorkflowRule ORDER BY Name',
            maxRows,
            true,
            true
        );
        if (queryResult.success && !queryResult.records.isEmpty()) {
            for (Map<String, Object> row : queryResult.records) {
                addGlobalComponentRow(
                    rows,
                    'GLOBAL.WORKFLOW.' + sanitizeKey(ToolingApiService.getString(row, 'Id')),
                    'Workflow Rule',
                    ToolingApiService.getString(row, 'Name'),
                    deriveWorkflowRuleStatus(row),
                    ToolingApiService.getString(row, 'TableEnumOrId'),
                    'Workflow rule metadata'
                );
            }
            return rows;
        }

        try {
            for (SObject row : Database.query(
                'SELECT Id, Name, TableEnumOrId FROM WorkflowRule LIMIT ' + maxRows
            )) {
                addGlobalComponentRow(
                    rows,
                    'GLOBAL.WORKFLOW.' + sanitizeKey(String.valueOf(row.get('Id'))),
                    'Workflow Rule',
                    String.valueOf(row.get('Name')),
                    'Configured',
                    String.valueOf(row.get('TableEnumOrId')),
                    'Workflow rule metadata'
                );
            }
        } catch (Exception ex) {
            return rows;
        }
        return rows;
    }

    private static String deriveWorkflowRuleStatus(Map<String, Object> row) {
        if (row == null) {
            return 'Configured';
        }
        Object metadataValue = row.get('Metadata');
        if (metadataValue instanceof Map<String, Object>) {
            Map<String, Object> metadata = (Map<String, Object>) metadataValue;
            Boolean activeFlag = ToolingApiService.getBoolean(metadata, 'active');
            if (activeFlag == null) {
                activeFlag = ToolingApiService.getBoolean(metadata, 'Active');
            }
            if (activeFlag != null) {
                return activeFlag == true ? 'Active' : 'Inactive';
            }
        }
        return 'Configured';
    }

    private static List<GlobalComponentRow> loadGlobalApexClasses(Integer maxRows) {
        List<GlobalComponentRow> rows = new List<GlobalComponentRow>();
        List<ApexClass> classes = [SELECT Id, Name, Body FROM ApexClass LIMIT :maxRows];
        Map<Id, Decimal> coverageByClassId = loadApexCoveragePct(new Map<Id, ApexClass>(classes).keySet());
        for (ApexClass classRow : classes) {
            if (!isActionableApexClassForInventory(classRow)) {
                continue;
            }
            Decimal coveragePct = coverageByClassId.get(classRow.Id);
            String status = coveragePct == null ? 'Coverage Pending' : String.valueOf(coveragePct.setScale(2)) + '%';
            String detail = coveragePct == null
                ? 'Run Usage Scan or Full Scan again to refresh Apex coverage.'
                : 'Apex coverage available';
            addGlobalComponentRow(rows, 'GLOBAL.APEXCLASS.' + classRow.Name, 'Apex Class', classRow.Name, status, null, detail);
        }
        return rows;
    }

    private static void addGlobalComponentRow(
        List<GlobalComponentRow> rows,
        String fieldKey,
        String componentType,
        String componentName,
        String status,
        String objectName,
        String detail
    ) {
        if (rows == null || String.isBlank(componentName)) {
            return;
        }
        GlobalComponentRow row = new GlobalComponentRow();
        row.key = componentType + '|' + componentName + '|' + String.valueOf(objectName) + '|' + String.valueOf(fieldKey);
        row.fieldKey = fieldKey;
        row.componentType = componentType;
        row.componentName = componentName;
        row.status = String.isBlank(status) ? 'Unknown' : status;
        row.objectName = objectName;
        row.detail = detail;
        rows.add(row);
    }

    private static String formatTriggerStatus(String triggerStatus, Decimal coveragePct) {
        String baseStatus = String.isBlank(triggerStatus) ? 'Unknown' : triggerStatus;
        if (coveragePct == null) {
            return baseStatus + ' | Coverage Pending';
        }
        return baseStatus + ' | ' + String.valueOf(coveragePct.setScale(2)) + '%';
    }

    private static String formatTriggerDetail(Decimal coveragePct) {
        if (coveragePct == null) {
            return 'Trigger metadata | Coverage pending';
        }
        return 'Trigger metadata | Coverage=' + String.valueOf(coveragePct.setScale(2)) + '%';
    }

    private static Boolean isBetterFlowToolingRow(Map<String, Object> candidate, Map<String, Object> current) {
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
        return (candidateVersion == null ? 0 : candidateVersion) > (currentVersion == null ? 0 : currentVersion);
    }

    private static Boolean isBetterFlowFallbackRow(SObject candidate, SObject current) {
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
        return (candidateVersion == null ? 0 : candidateVersion) > (currentVersion == null ? 0 : currentVersion);
    }

    private static Map<Id, Decimal> loadApexCoveragePct(Set<Id> apexClassIds) {
        Map<Id, Decimal> coverageByClassId = new Map<Id, Decimal>();
        if (apexClassIds == null || apexClassIds.isEmpty()) {
            return coverageByClassId;
        }
        try {
            for (AggregateResult row : Database.query(
                'SELECT ApexClassOrTriggerId classId, SUM(NumLinesCovered) covered, SUM(NumLinesUncovered) uncovered ' +
                'FROM ApexCodeCoverageAggregate ' +
                'WHERE ApexClassOrTriggerId IN :apexClassIds ' +
                'GROUP BY ApexClassOrTriggerId'
            )) {
                Decimal covered = (Decimal) row.get('covered');
                Decimal uncovered = (Decimal) row.get('uncovered');
                Decimal total = covered + uncovered;
                if (total > 0) {
                    coverageByClassId.put((Id) row.get('classId'), (covered * 100.0) / total);
                }
            }
        } catch (Exception ex) {
            // Fall through to Tooling API fallback below.
        }

        try {
            mergeApexCoverageFromTooling(coverageByClassId, apexClassIds, 'ApexCodeCoverageAggregate', true);
            mergeApexCoverageFromTooling(coverageByClassId, apexClassIds, 'ApexCodeCoverage', true);
        } catch (Exception ex) {
            // Keep whatever coverage was already resolved if tooling coverage is unavailable.
        }

        return coverageByClassId;
    }

    private static void mergeApexCoverageFromTooling(
        Map<Id, Decimal> targetCoverage,
        Set<Id> apexClassIds,
        String toolingObjectApi,
        Boolean preferHigher
    ) {
        for (List<Id> chunk : chunkIds(apexClassIds, 100)) {
            if (chunk.isEmpty()) {
                continue;
            }

            ToolingApiService.ToolingQueryResult toolingResult = ToolingApiService.queryWithMode(
                'SELECT ApexClassOrTriggerId, NumLinesCovered, NumLinesUncovered ' +
                'FROM ' + toolingObjectApi + ' ' +
                'WHERE ApexClassOrTriggerId IN (' + buildIdCsv(chunk) + ')',
                10000,
                true,
                true
            );
            if (toolingResult == null || toolingResult.success != true || toolingResult.records.isEmpty()) {
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

    private static Boolean isActionableApexClassForInventory(ApexClass classRow) {
        if (classRow == null || String.isBlank(classRow.Name)) {
            return false;
        }
        if (classRow.Name.endsWith('Test')) {
            return false;
        }
        if (classRow.Body != null && classRow.Body.toLowerCase().contains('@istest')) {
            return false;
        }
        return true;
    }

    private static String fallbackString(String primaryValue, String fallbackValue) {
        return String.isBlank(primaryValue) ? fallbackValue : primaryValue;
    }

    private static String fallbackComponentName(String primaryValue, String prefix, String seed) {
        if (!String.isBlank(primaryValue)) {
            return primaryValue;
        }
        String safeSeed = sanitizeKey(seed);
        if (String.isBlank(safeSeed)) {
            return prefix;
        }
        Integer tokenLength = Math.min(6, safeSeed.length());
        return prefix + ' ' + safeSeed.substring(safeSeed.length() - tokenLength);
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

    private static String sanitizeKey(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.replaceAll('[^A-Za-z0-9_]', '_');
    }

    private class GlobalComponentRowSorter implements Comparator<GlobalComponentRow> {
        public Integer compare(GlobalComponentRow left, GlobalComponentRow right) {
            String leftType = left == null ? '' : String.valueOf(left.componentType);
            String rightType = right == null ? '' : String.valueOf(right.componentType);
            if (leftType != rightType) {
                return leftType < rightType ? -1 : 1;
            }

            String leftName = left == null ? '' : String.valueOf(left.componentName);
            String rightName = right == null ? '' : String.valueOf(right.componentName);
            if (leftName == rightName) {
                return 0;
            }
            return leftName < rightName ? -1 : 1;
        }
    }

    private class GlobalTypeSorter implements Comparator<String> {
        private Map<String, Integer> orderByType;

        GlobalTypeSorter(Map<String, Integer> orderByType) {
            this.orderByType = orderByType == null ? new Map<String, Integer>() : orderByType;
        }

        public Integer compare(String left, String right) {
            Integer leftOrder = orderByType.containsKey(left) ? orderByType.get(left) : 999;
            Integer rightOrder = orderByType.containsKey(right) ? orderByType.get(right) : 999;
            if (leftOrder != rightOrder) {
                return leftOrder < rightOrder ? -1 : 1;
            }
            if (left == right) {
                return 0;
            }
            return String.valueOf(left) < String.valueOf(right) ? -1 : 1;
        }
    }

    private static String sanitizeAction(String actionFilter) {
        if (String.isBlank(actionFilter)) {
            return null;
        }
        String trimmed = actionFilter.trim();
        if (!ALLOWED_ACTIONS.contains(trimmed)) {
            throw new AuraHandledException('Invalid action filter value.');
        }
        return trimmed;
    }

    private static String sanitizeAgentTestAction(String testAction) {
        if (String.isBlank(testAction)) {
            return 'ExplainRecommendation';
        }
        String trimmed = testAction.trim();
        if (!ALLOWED_AGENT_TEST_ACTIONS.contains(trimmed)) {
            throw new AuraHandledException('Invalid agent test action.');
        }
        return trimmed;
    }

    private static Integer extractInteger(String source, String regexPattern) {
        String token = extractString(source, regexPattern);
        if (String.isBlank(token)) {
            return null;
        }
        try {
            return Integer.valueOf(token);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Decimal extractDecimal(String source, String regexPattern) {
        String token = extractString(source, regexPattern);
        if (String.isBlank(token)) {
            return null;
        }
        try {
            return Decimal.valueOf(token);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String extractString(String source, String regexPattern) {
        if (String.isBlank(source) || String.isBlank(regexPattern)) {
            return null;
        }
        Matcher matcher = Pattern.compile('(?i)' + regexPattern).matcher(source);
        if (!matcher.find()) {
            return null;
        }
        if (matcher.groupCount() >= 1) {
            return matcher.group(1);
        }
        return matcher.group(0);
    }

    private static Id parseIdOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static String formatHighRiskSummary(List<Clarity360AgentActions.AgentActionResult> rows) {
        if (rows == null || rows.isEmpty()) {
            return 'No high-risk recommendations found.';
        }
        if (rows.size() == 1 && rows[0] != null && rows[0].status == 'No Data') {
            return safeString(rows[0].summary, 'No high-risk recommendations matched your request.');
        }
        List<String> lines = new List<String>();
        Integer maxRows = Math.min(rows.size(), 5);
        for (Integer i = 0; i < maxRows; i++) {
            Clarity360AgentActions.AgentActionResult row = rows[i];
            String risk = row == null || row.riskScore == null ? 'n/a' : String.valueOf(row.riskScore.setScale(2));
            lines.add(
                String.valueOf(i + 1) + '. ' +
                safeString(row == null ? null : row.fieldKey, 'Unknown field') +
                ' - ' + safeString(row == null ? null : row.action, 'Unknown action') +
                ' (risk ' + risk + ', status ' + safeString(row == null ? null : row.status, 'Unknown') + ')'
            );
        }
        return 'Top high-risk recommendations:\n' + String.join(lines, '\n');
    }

    private static String formatRecentScanSummary(List<Clarity360AgentActions.AgentActionResult> rows) {
        if (rows == null || rows.isEmpty()) {
            return 'No recent scan summary available.';
        }
        Clarity360AgentActions.AgentActionResult row = rows[0];
        return safeString(row == null ? null : row.summary, 'No summary available.') +
            '\nDetails: ' + safeString(row == null ? null : row.explanation, 'No details available.');
    }

    private static String formatExplainSummary(List<Clarity360AgentActions.AgentActionResult> rows) {
        if (rows == null || rows.isEmpty()) {
            return 'No matching recommendation found.';
        }
        Clarity360AgentActions.AgentActionResult row = rows[0];
        if (row != null && row.status == 'Not Found') {
            return 'I could not find that recommendation. Please share a valid Recommendation Id or Field Key like Account.Legacy_Flag__c.';
        }
        return safeString(row == null ? null : row.summary, 'No summary available.') +
            '\nReason: ' + safeString(row == null ? null : row.explanation, 'No explanation available.');
    }

    private static String formatEntityDeletionGuidance(String entityType) {
        String likePattern;
        String label;
        if (entityType == 'trigger') {
            likePattern = 'GLOBAL.TRIGGER.%';
            label = 'triggers';
        } else if (entityType == 'flow') {
            likePattern = 'GLOBAL.FLOW.%';
            label = 'flows';
        } else {
            likePattern = null;
            label = 'fields';
        }

        List<Recommendation__c> rows;
        if (likePattern == null) {
            List<Recommendation__c> candidateRows = [
                SELECT FieldKey__c, Action__c, RiskScore__c, Status__c
                FROM Recommendation__c
                WHERE Status__c = 'Open'
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT 25
            ];
            rows = new List<Recommendation__c>();
            for (Recommendation__c candidate : candidateRows) {
                if (candidate == null || String.isBlank(candidate.FieldKey__c)) {
                    continue;
                }
                if (candidate.FieldKey__c.toUpperCase().startsWith('GLOBAL.')) {
                    continue;
                }
                rows.add(candidate);
                if (rows.size() == 5) {
                    break;
                }
            }
        } else {
            rows = [
                SELECT FieldKey__c, Action__c, RiskScore__c, Status__c
                FROM Recommendation__c
                WHERE Status__c = 'Open' AND FieldKey__c LIKE :likePattern
                ORDER BY RiskScore__c DESC, LastEvaluatedOn__c DESC
                LIMIT 5
            ];
        }

        if (rows.isEmpty()) {
            return 'I did not find open inactive ' + label + ' recommendations right now. Run a fresh scan and try again.';
        }

        List<String> lines = new List<String>();
        for (Integer i = 0; i < rows.size(); i++) {
            Recommendation__c row = rows[i];
            String risk = row.RiskScore__c == null ? 'n/a' : String.valueOf(row.RiskScore__c.setScale(2));
            lines.add(
                String.valueOf(i + 1) + '. ' +
                safeString(row.FieldKey__c, 'Unknown component') +
                ' - ' + safeString(row.Action__c, 'Review') +
                ' (risk ' + risk + ')'
            );
        }
        return 'Here are current recommendations for ' + label + ':\n' + String.join(lines, '\n') +
            '\nPlease review dependencies before deletion.';
    }

    private static String formatGeneralDataAnswer() {
        Integer openRecommendationCount = [
            SELECT COUNT()
            FROM Recommendation__c
            WHERE Status__c = 'Open'
        ];
        Integer highRiskOpenCount = [
            SELECT COUNT()
            FROM Recommendation__c
            WHERE Status__c = 'Open' AND RiskScore__c >= 70
        ];
        Integer usageSignalCount = [
            SELECT COUNT()
            FROM UsageSignal__c
            WHERE LastObservedOn__c != null
        ];
        List<ScanJob__c> latestJobs = [
            SELECT JobType__c, Status__c, StartedOn__c
            FROM ScanJob__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        String latestStatus = latestJobs.isEmpty()
            ? 'No recent scan job found'
            : safeString(latestJobs[0].JobType__c, 'Unknown job') + ' is ' + safeString(latestJobs[0].Status__c, 'Unknown');

        return
            'Here is a quick Clarity360 snapshot:\n' +
            '- Open recommendations: ' + String.valueOf(openRecommendationCount) + '\n' +
            '- High-risk open recommendations (70+): ' + String.valueOf(highRiskOpenCount) + '\n' +
            '- Usage signals collected: ' + String.valueOf(usageSignalCount) + '\n' +
            '- Latest scan: ' + latestStatus + '\n' +
            'If you want, ask me one of these next: "show top high-risk items", "summarize recent scans", or "explain Account.Legacy_Flag__c".';
    }

    private static String sanitizeStatus(String statusFilter) {
        if (String.isBlank(statusFilter)) {
            return null;
        }
        String trimmed = statusFilter.trim();
        if (!ALLOWED_STATUSES.contains(trimmed)) {
            throw new AuraHandledException('Invalid status filter value.');
        }
        return trimmed;
    }

    private static String buildObjectPattern(String objectFilter) {
        if (String.isBlank(objectFilter)) {
            return null;
        }
        String trimmed = objectFilter.trim();
        if (trimmed == 'GLOBAL') {
            return 'GLOBAL.%';
        }
        if (!Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', trimmed)) {
            throw new AuraHandledException('Invalid object filter value.');
        }
        return trimmed + '.%';
    }

    private static Boolean isSafeFieldKey(String fieldKey) {
        return Pattern.matches('^[A-Za-z0-9_.]+$', fieldKey);
    }

    private static String safeGetString(SObject row, String fieldApiName) {
        Object value = safeGet(row, fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static String safeString(String value, String fallbackValue) {
        return String.isBlank(value) ? fallbackValue : value;
    }

    private static Decimal safeGetDecimal(SObject row, String fieldApiName) {
        Object value = safeGet(row, fieldApiName);
        if (value == null) {
            return null;
        }
        try {
            return (Decimal) value;
        } catch (Exception ex) {
            try {
                return Decimal.valueOf(String.valueOf(value));
            } catch (Exception ignored) {
                return null;
            }
        }
    }

    private static Datetime safeGetDatetime(SObject row, String fieldApiName) {
        Object value = safeGet(row, fieldApiName);
        if (value == null) {
            return null;
        }
        try {
            return (Datetime) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Object safeGet(SObject row, String fieldApiName) {
        if (row == null || String.isBlank(fieldApiName)) {
            return null;
        }
        try {
            return row.get(fieldApiName);
        } catch (Exception ex) {
            return null;
        }
    }

    private static List<AgentActionTestResult> mapAgentActionResults(List<Clarity360AgentActions.AgentActionResult> source) {
        List<AgentActionTestResult> results = new List<AgentActionTestResult>();
        if (source == null) {
            return results;
        }

        for (Clarity360AgentActions.AgentActionResult row : source) {
            AgentActionTestResult mapped = new AgentActionTestResult();
            mapped.action = row == null ? null : row.action;
            mapped.confidenceScore = row == null ? null : row.confidenceScore;
            mapped.riskScore = row == null ? null : row.riskScore;
            mapped.explanation = row == null ? null : row.explanation;
            mapped.status = row == null ? null : row.status;
            mapped.summary = row == null ? null : row.summary;
            mapped.recommendationId = row == null ? null : row.recommendationId;
            mapped.fieldKey = row == null ? null : row.fieldKey;
            results.add(mapped);
        }

        return results;
    }
}
