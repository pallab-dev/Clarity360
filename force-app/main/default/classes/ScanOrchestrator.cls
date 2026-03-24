public with sharing class ScanOrchestrator {
    @TestVisible
    static Boolean skipUsageBatchInTests = false;

    private class RuntimeOptions {
        public Boolean customObjectsOnly = false;
        public Integer maxInventoryObjects;
        public Integer maxScanObjects;
        public Integer samplingLimit;
    }

    public class StartResult {
        @AuraEnabled public Id jobId;
        @AuraEnabled public Boolean reusedJob;
        @AuraEnabled public String status;
    }

    public static Id runFullScan() {
        return runFullScanV2(null, true, null).jobId;
    }

    public static StartResult runFullScanV2(String requestId, Boolean sendReport) {
        return runFullScanV2(requestId, sendReport, null);
    }

    public static StartResult runFullScanV2(String requestId, Boolean sendReport, String reportRecipient) {
        return startFullScan(requestId, sendReport == true ? 'Requester' : null, reportRecipient);
    }

    public static StartResult runScheduledFullScan() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        Boolean sendReport = config != null && config.enableScheduledReports == true;
        return startFullScan(
            null,
            sendReport ? 'Scheduled' : null,
            config == null ? null : config.scheduledReportRecipient
        );
    }

    private static StartResult startFullScan(String requestId, String reportMode, String reportRecipient) {
        RuntimeOptions options = getRuntimeOptions();
        String scopeSummary =
            'customObjectsOnly=' + options.customObjectsOnly +
            '; maxInventoryObjects=' + options.maxInventoryObjects +
            '; maxScanObjects=' + options.maxScanObjects +
            '; sampleLimit=' + options.samplingLimit +
            requestToken(requestId) +
            reportToken(reportMode, reportRecipient);
        ScanJob__c existing = ScanJobRepository.findRecentRunningJob('Full Scan', requestId, 10);
        if (existing != null) {
            StartResult reusedResult = new StartResult();
            reusedResult.jobId = existing.Id;
            reusedResult.reusedJob = true;
            reusedResult.status = existing.Status__c;
            return reusedResult;
        }

        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Queued',
            StartedOn__c = System.now(),
            ScopeSummary__c = scopeSummary,
            ReportMode__c = reportMode
        );
        insertScanJobWithStorageRecovery(job);
        try {
            System.enqueueJob(new InventoryRefreshQueueable(
                job.Id,
                options.customObjectsOnly,
                options.maxInventoryObjects,
                null,
                0,
                0,
                0,
                0,
                true,
                options.samplingLimit,
                options.maxScanObjects,
                Test.isRunningTest() && skipUsageBatchInTests
            ));
            StartResult queuedResult = new StartResult();
            queuedResult.jobId = job.Id;
            queuedResult.reusedJob = false;
            queuedResult.status = 'Queued';
            return queuedResult;
        } catch (Exception ex) {
            ScanJobRepository.safeUpdate(new ScanJob__c(
                Id = job.Id,
                Status__c = 'Failed',
                FinishedOn__c = System.now(),
                ErrorMessage__c = ex.getMessage()
            ));
            Clarity360SecureLog.error('ScanOrchestrator.runFullScanV2', ex);
            throw ex;
        }
    }

    private static String reportToken(String reportMode, String reportRecipient) {
        if (String.isBlank(reportMode)) {
            return '';
        }

        String token = '; reportRequested=true; reportMode=' + reportMode;
        String safeRecipient = sanitizeReportRecipient(reportRecipient);
        if (!String.isBlank(safeRecipient)) {
            token += '; reportRecipient=' + safeRecipient;
        }
        return token;
    }

    @TestVisible
    static String sanitizeReportRecipient(String reportRecipient) {
        if (String.isBlank(reportRecipient)) {
            return null;
        }
        String sanitized = reportRecipient.trim().replace(';', '').replace('\n', '').replace('\r', '');
        if (String.isBlank(sanitized)) {
            return null;
        }
        return sanitized.length() > 80 ? sanitized.substring(0, 80) : sanitized;
    }

    public static Id runInventoryOnly(Boolean customObjectsOnly, Integer maxObjects) {
        return runInventoryOnlyV2(customObjectsOnly, maxObjects, null).jobId;
    }

    public static StartResult runInventoryOnlyV2(Boolean customObjectsOnly, Integer maxObjects, String requestId) {
        RuntimeOptions options = getRuntimeOptions();
        Boolean safeCustomOnly = (customObjectsOnly == null) ? options.customObjectsOnly : customObjectsOnly;
        Integer safeMaxObjects = (maxObjects == null || maxObjects <= 0) ? options.maxInventoryObjects : maxObjects;
        String scopeSummary = 'customObjectsOnly=' + safeCustomOnly + '; maxObjects=' + safeMaxObjects + requestToken(requestId);
        ScanJob__c existing = ScanJobRepository.findRecentRunningJob('Inventory Refresh', requestId, 10);
        if (existing != null) {
            StartResult reusedResult = new StartResult();
            reusedResult.jobId = existing.Id;
            reusedResult.reusedJob = true;
            reusedResult.status = existing.Status__c;
            return reusedResult;
        }

        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Inventory Refresh',
            Status__c = 'Queued',
            StartedOn__c = System.now(),
            ScopeSummary__c = scopeSummary
        );
        Id jobId = null;
        try {
            insertScanJobWithStorageRecovery(job);
            jobId = job.Id;
        } catch (DmlException dmlex) {
            if (!isStorageLimitError(dmlex)) {
                throw dmlex;
            }
        }

        try {
            System.enqueueJob(new InventoryRefreshQueueable(
                jobId,
                safeCustomOnly,
                safeMaxObjects,
                null,
                0,
                0,
                0,
                0
            ));
            StartResult queuedResult = new StartResult();
            queuedResult.jobId = jobId;
            queuedResult.reusedJob = false;
            queuedResult.status = 'Queued';
            return queuedResult;
        } catch (Exception ex) {
            if (jobId != null) {
                ScanJobRepository.safeUpdate(new ScanJob__c(
                    Id = jobId,
                    Status__c = 'Failed',
                    FinishedOn__c = System.now(),
                    ErrorMessage__c = ex.getMessage()
                ));
            }
            Clarity360SecureLog.error('ScanOrchestrator.runInventoryOnlyV2', ex);
            throw ex;
        }
    }

    public static Id runUsageScanOnly(Integer sampleLimit, Integer maxObjects) {
        return runUsageScanOnlyV2(sampleLimit, maxObjects, null).jobId;
    }

    public static StartResult runUsageScanOnlyV2(Integer sampleLimit, Integer maxObjects, String requestId) {
        RuntimeOptions options = getRuntimeOptions();
        Integer safeSampleLimit = (sampleLimit == null || sampleLimit <= 0) ? options.samplingLimit : sampleLimit;
        Integer safeMaxObjects = (maxObjects == null || maxObjects <= 0) ? options.maxScanObjects : maxObjects;
        String scopeSummary = 'sampleLimit=' + safeSampleLimit + '; maxObjects=' + safeMaxObjects + requestToken(requestId);
        ScanJob__c existing = ScanJobRepository.findRecentRunningJob('Usage Scan', requestId, 10);
        if (existing != null) {
            StartResult reusedResult = new StartResult();
            reusedResult.jobId = existing.Id;
            reusedResult.reusedJob = true;
            reusedResult.status = existing.Status__c;
            return reusedResult;
        }

        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Running',
            StartedOn__c = System.now(),
            ScopeSummary__c = scopeSummary
        );
        Id jobId = null;
        try {
            insertScanJobWithStorageRecovery(job);
            jobId = job.Id;
        } catch (DmlException dmlex) {
            // If org is out of storage, run scan without job logging instead of failing immediately.
            if (!isStorageLimitError(dmlex)) {
                throw dmlex;
            }
        }

        try {
            Database.executeBatch(new UsageScanBatch(safeSampleLimit, safeMaxObjects, jobId), 1);
            StartResult runningResult = new StartResult();
            runningResult.jobId = jobId;
            runningResult.reusedJob = false;
            runningResult.status = 'Running';
            return runningResult;
        } catch (Exception ex) {
            if (jobId != null) {
                ScanJobRepository.safeUpdate(new ScanJob__c(
                    Id = jobId,
                    Status__c = 'Failed',
                    FinishedOn__c = System.now(),
                    ErrorMessage__c = ex.getMessage()
                ));
            }
            Clarity360SecureLog.error('ScanOrchestrator.runUsageScanOnlyV2', ex);
            throw ex;
        }
    }

    private static void insertScanJobWithStorageRecovery(ScanJob__c job) {
        try {
            insert job;
        } catch (DmlException dmlex) {
            if (!isStorageLimitError(dmlex)) {
                throw dmlex;
            }

            purgeGeneratedData();
            insert job;
        }
    }

    private static Boolean isStorageLimitError(Exception ex) {
        return ex != null && ex.getMessage() != null && ex.getMessage().contains('STORAGE_LIMIT_EXCEEDED');
    }

    private static void purgeGeneratedData() {
        // These datasets are fully derived and can be rebuilt by rerunning scans.
        deleteChunk('UsageSignal__c', 10000);
        deleteChunk('Recommendation__c', 10000);
        deleteOldScanJobs(1000);
    }

    private static void deleteChunk(String objectApiName, Integer sizeLimit) {
        if (!Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', objectApiName)) {
            return;
        }
        List<SObject> rows = Database.query('SELECT Id FROM ' + objectApiName + ' LIMIT ' + sizeLimit);
        if (!rows.isEmpty()) {
            delete rows;
        }
    }

    private static void deleteOldScanJobs(Integer sizeLimit) {
        List<ScanJob__c> jobs = [
            SELECT Id
            FROM ScanJob__c
            ORDER BY CreatedDate ASC
            LIMIT :sizeLimit
        ];
        if (!jobs.isEmpty()) {
            delete jobs;
        }
    }

    private static String requestToken(String requestId) {
        return String.isBlank(requestId) ? '' : '; requestId=' + requestId;
    }

    private static RuntimeOptions getRuntimeOptions() {
        RuntimeOptions options = new RuntimeOptions();
        Clarity360Settings.RuntimeConfig config = Clarity360Settings.getRequiredRuntime();
        options.customObjectsOnly = config.includeStandardObjects != true;
        options.maxInventoryObjects = config.maxInventoryObjects;
        options.maxScanObjects = config.maxScanObjects;
        options.samplingLimit = config.samplingLimit;
        return options;
    }
}
