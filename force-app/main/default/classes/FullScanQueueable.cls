public with sharing class FullScanQueueable implements Queueable {
    @TestVisible
    static Boolean skipUsageBatchInTests = false;

    private final Id scanJobId;
    private final Boolean customObjectsOnly;
    private final Integer maxInventoryObjects;
    private final Integer sampleLimit;
    private final Integer maxScanObjects;

    public FullScanQueueable(Id scanJobId) {
        Clarity360Settings.RuntimeConfig runtime = Clarity360Settings.getRequiredRuntime();
        this.scanJobId = scanJobId;
        this.customObjectsOnly = runtime.includeStandardObjects != true;
        this.maxInventoryObjects = runtime.maxInventoryObjects;
        this.sampleLimit = runtime.samplingLimit;
        this.maxScanObjects = runtime.maxScanObjects;
    }

    public FullScanQueueable(
        Id scanJobId,
        Boolean customObjectsOnly,
        Integer maxInventoryObjects,
        Integer sampleLimit,
        Integer maxScanObjects
    ) {
        this.scanJobId = scanJobId;
        this.customObjectsOnly = customObjectsOnly == null ? false : customObjectsOnly;
        this.maxInventoryObjects = maxInventoryObjects;
        this.sampleLimit = sampleLimit;
        this.maxScanObjects = maxScanObjects;
    }

    public void execute(QueueableContext context) {
        if (scanJobId == null) {
            return;
        }

        try {
            ScanJob__c job = [
                SELECT Id, Status__c, ScopeSummary__c, ErrorMessage__c
                FROM ScanJob__c
                WHERE Id = :scanJobId
                LIMIT 1
            ];
            job.Status__c = 'Running';
            ScanJobRepository.safeUpdate(job);
            InventoryRefreshQueueable inventoryPhase = new InventoryRefreshQueueable(
                scanJobId,
                customObjectsOnly,
                maxInventoryObjects,
                null,
                0,
                0,
                0,
                0,
                true,
                sampleLimit,
                maxScanObjects,
                skipUsageBatchInTests
            );
            if (Test.isRunningTest()) {
                inventoryPhase.execute(null);
            } else {
                System.enqueueJob(inventoryPhase);
            }
        } catch (Exception ex) {
            markJobFailed(ex);
        }
    }

    private void markJobFailed(Exception ex) {
        if (scanJobId == null) {
            return;
        }

        try {
            ScanJob__c job = [
                SELECT Id, Status__c, ErrorMessage__c
                FROM ScanJob__c
                WHERE Id = :scanJobId
                LIMIT 1
            ];
            job.Status__c = 'Failed';
            job.FinishedOn__c = System.now();
            job.ErrorMessage__c = ScanJobRepository.appendError(
                job.ErrorMessage__c,
                ex == null ? 'Unknown full scan failure' : ex.getMessage()
            );
            ScanJobRepository.safeUpdate(job);
        } catch (Exception ignored) {
            // Best-effort logging only.
        }
    }
}
