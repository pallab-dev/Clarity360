public with sharing class UsageScanBatch implements Database.Batchable<String>, Database.Stateful, Database.AllowsCallouts {
    private final Integer sampleLimit;
    private final Integer maxObjects;
    private final Id scanJobId;

    private Integer totalObjects = 0;
    private Integer processedObjects = 0;

    public UsageScanBatch(Integer sampleLimit, Integer maxObjects, Id scanJobId) {
        this.sampleLimit = (sampleLimit == null || sampleLimit <= 0) ? 5000 : sampleLimit;
        this.maxObjects = (maxObjects == null || maxObjects <= 0) ? 30 : maxObjects;
        this.scanJobId = scanJobId;
    }

    public Iterable<String> start(Database.BatchableContext context) {
        List<String> objectNames = new List<String>();
        for (AggregateResult row : [
            SELECT ObjectApiName__c objectName
            FROM FieldInventory__c
            WHERE IsActive__c = true
            GROUP BY ObjectApiName__c
            ORDER BY ObjectApiName__c
        ]) {
            String objectName = (String) row.get('objectName');
            if (InventoryService.isObjectExcludedByRuntimeConfig(objectName)) {
                continue;
            }
            objectNames.add(objectName);
            if (objectNames.size() >= maxObjects) {
                break;
            }
        }

        totalObjects = objectNames.size();
        if (scanJobId != null) {
            ScanJobRepository.safeUpdate(new ScanJob__c(
                Id = scanJobId,
                TotalObjects__c = totalObjects,
                Status__c = 'Running'
            ));
        }

        return objectNames;
    }

    public void execute(Database.BatchableContext context, List<String> scope) {
        for (String objectApiName : scope) {
            try {
                List<FieldInventory__c> fields = [
                    SELECT Id, FieldKey__c, FieldApiName__c, ObjectApiName__c
                    FROM FieldInventory__c
                    WHERE ObjectApiName__c = :objectApiName
                    AND IsActive__c = true
                ];

                List<UsageSignal__c> signals = DataSampler.scanObject(objectApiName, fields, sampleLimit);
                SignalRepository.upsertSignals(signals);
            } catch (Exception ex) {
                ScanJobRepository.safeAppendError(scanJobId, objectApiName + ': ' + ex.getMessage(), true);
            }

            processedObjects++;
            updateProgress();
            GovernorTrendService.captureCurrentTransaction(scanJobId, 'UsageScan');
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            System.enqueueJob(new RecommendationRebuildQueueable(20000, scanJobId));
        } catch (Exception ex) {
            ScanJobRepository.safeAppendError(scanJobId, 'Recommendation rebuild enqueue failed: ' + ex.getMessage(), true);
        }

        if (scanJobId != null) {
            try {
                ScanJob__c job = [
                    SELECT Id, Status__c
                    FROM ScanJob__c
                    WHERE Id = :scanJobId
                    LIMIT 1
                ];

                if (job.Status__c == 'Running' || job.Status__c == 'Queued') {
                    job.Status__c = 'Completed';
                }
                job.ProgressPct__c = 100;
                job.FinishedOn__c = System.now();
                ScanJobRepository.safeUpdate(job);
                Clarity360ScanReportService.notifyIfNeeded(job.Id);
            } catch (Exception ignored) {
                // Prevent scan job logging failures from marking batch as failed.
            }
        }
    }

    private void updateProgress() {
        if (scanJobId == null || totalObjects == 0) {
            return;
        }

        Decimal progress = ((Decimal) processedObjects * 100) / totalObjects;
        ScanJobRepository.safeUpdate(new ScanJob__c(
            Id = scanJobId,
            ProgressPct__c = progress
        ));
    }

}
