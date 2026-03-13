public with sharing class InventoryRefreshQueueable implements Queueable {
    private static final Integer OBJECTS_PER_CHUNK = 10;

    private final Id scanJobId;
    private final Boolean customObjectsOnly;
    private final Integer maxObjects;
    private final List<String> scopedObjectNames;
    private final Integer startIndex;
    private final Integer totalScanned;
    private final Integer totalUpserted;
    private final Integer totalInactivated;
    private final Boolean launchUsageScanAfterInventory;
    private final Integer usageSampleLimit;
    private final Integer usageMaxObjects;
    private final Boolean skipUsageBatchInTests;

    public InventoryRefreshQueueable(
        Id scanJobId,
        Boolean customObjectsOnly,
        Integer maxObjects,
        List<String> scopedObjectNames,
        Integer startIndex,
        Integer totalScanned,
        Integer totalUpserted,
        Integer totalInactivated
    ) {
        this(
            scanJobId,
            customObjectsOnly,
            maxObjects,
            scopedObjectNames,
            startIndex,
            totalScanned,
            totalUpserted,
            totalInactivated,
            false,
            null,
            null,
            false
        );
    }

    public InventoryRefreshQueueable(
        Id scanJobId,
        Boolean customObjectsOnly,
        Integer maxObjects,
        List<String> scopedObjectNames,
        Integer startIndex,
        Integer totalScanned,
        Integer totalUpserted,
        Integer totalInactivated,
        Boolean launchUsageScanAfterInventory,
        Integer usageSampleLimit,
        Integer usageMaxObjects,
        Boolean skipUsageBatchInTests
    ) {
        this.scanJobId = scanJobId;
        this.customObjectsOnly = customObjectsOnly;
        this.maxObjects = maxObjects;
        this.scopedObjectNames = scopedObjectNames == null ? null : new List<String>(scopedObjectNames);
        this.startIndex = startIndex == null ? 0 : Math.max(0, startIndex);
        this.totalScanned = totalScanned == null ? 0 : Math.max(0, totalScanned);
        this.totalUpserted = totalUpserted == null ? 0 : Math.max(0, totalUpserted);
        this.totalInactivated = totalInactivated == null ? 0 : Math.max(0, totalInactivated);
        this.launchUsageScanAfterInventory = launchUsageScanAfterInventory == true;
        this.usageSampleLimit = usageSampleLimit;
        this.usageMaxObjects = usageMaxObjects;
        this.skipUsageBatchInTests = skipUsageBatchInTests == true;
    }

    public void execute(QueueableContext context) {
        try {
            List<String> safeScopedObjects = scopedObjectNames;
            if (safeScopedObjects == null) {
                safeScopedObjects = InventoryService.getScopedObjectNames(customObjectsOnly, maxObjects);
                InventoryService.cleanupExcludedInventory(safeScopedObjects);
            }

            Integer scannedSoFar = totalScanned;
            Integer upsertedSoFar = totalUpserted;
            Integer inactivatedSoFar = totalInactivated;
            Integer nextIndex = startIndex;
            InventoryService.RefreshChunkResult chunk;

            do {
                chunk = InventoryService.refreshInventoryChunkForScopedObjects(
                    safeScopedObjects,
                    customObjectsOnly,
                    nextIndex,
                    OBJECTS_PER_CHUNK
                );
                scannedSoFar += chunk.scannedObjectCount;
                upsertedSoFar += chunk.upsertedFieldCount;
                inactivatedSoFar += chunk.inactivatedFieldCount;
                nextIndex = chunk.nextIndex;
            } while (Test.isRunningTest() && chunk.hasMore == true);

            updateProgress(chunk.totalObjects, scannedSoFar, upsertedSoFar, inactivatedSoFar);

            if (chunk.hasMore == true) {
                System.enqueueJob(new InventoryRefreshQueueable(
                    scanJobId,
                    customObjectsOnly,
                    maxObjects,
                    safeScopedObjects,
                    nextIndex,
                    scannedSoFar,
                    upsertedSoFar,
                    inactivatedSoFar,
                    launchUsageScanAfterInventory,
                    usageSampleLimit,
                    usageMaxObjects,
                    skipUsageBatchInTests
                ));
                return;
            }

            if (launchUsageScanAfterInventory == true) {
                launchUsageBatchOrComplete(scannedSoFar, upsertedSoFar, inactivatedSoFar);
                return;
            }

            markCompleted(scannedSoFar, upsertedSoFar, inactivatedSoFar);
        } catch (Exception ex) {
            markFailed(ex);
        }
    }

    private void updateProgress(Integer totalObjects, Integer scanned, Integer upserted, Integer inactivated) {
        if (scanJobId == null) {
            return;
        }

        Decimal progress = 0;
        if (totalObjects != null && totalObjects > 0) {
            progress = Math.min(100, (scanned * 100.0) / totalObjects);
        }

        ScanJobRepository.safeUpdate(new ScanJob__c(
            Id = scanJobId,
            Status__c = 'Running',
            ProgressPct__c = progress,
            ScopeSummary__c =
                'InventoryObjects=' + scanned +
                '; InventoryFields=' + upserted +
                '; Inactivated=' + inactivated
        ));
    }

    private void markCompleted(Integer scanned, Integer upserted, Integer inactivated) {
        if (scanJobId == null) {
            return;
        }

        ScanJobRepository.safeUpdate(new ScanJob__c(
            Id = scanJobId,
            Status__c = 'Completed',
            ProgressPct__c = 100,
            FinishedOn__c = System.now(),
            ScopeSummary__c =
                'InventoryObjects=' + scanned +
                '; InventoryFields=' + upserted +
                '; Inactivated=' + inactivated
        ));
    }

    private void launchUsageBatchOrComplete(Integer scanned, Integer upserted, Integer inactivated) {
        if (scanJobId == null) {
            return;
        }

        if (Test.isRunningTest() && skipUsageBatchInTests) {
            markCompleted(scanned, upserted, inactivated);
            return;
        }

        ScanJobRepository.safeUpdate(new ScanJob__c(
            Id = scanJobId,
            Status__c = 'Running',
            ScopeSummary__c =
                'InventoryObjects=' + scanned +
                '; InventoryFields=' + upserted +
                '; Inactivated=' + inactivated
        ));
        Database.executeBatch(new UsageScanBatch(usageSampleLimit, usageMaxObjects, scanJobId), 1);
    }

    private void markFailed(Exception ex) {
        if (scanJobId == null) {
            return;
        }

        ScanJobRepository.safeUpdate(new ScanJob__c(
            Id = scanJobId,
            Status__c = 'Failed',
            FinishedOn__c = System.now(),
            ErrorMessage__c = ex == null ? 'Unknown inventory refresh failure' : ex.getMessage()
        ));
    }
}
