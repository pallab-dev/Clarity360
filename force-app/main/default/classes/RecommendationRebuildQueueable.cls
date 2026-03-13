public with sharing class RecommendationRebuildQueueable implements Queueable, Database.AllowsCallouts {
    private final Integer maxRows;
    private final Id scanJobId;

    public RecommendationRebuildQueueable(Integer maxRows, Id scanJobId) {
        this.maxRows = maxRows;
        this.scanJobId = scanJobId;
    }

    public void execute(QueueableContext context) {
        try {
            MetadataComponentInventoryService.refreshAll(maxRows);
            RecommendationEngine.rebuildAllRecommendations(maxRows);
        } catch (Exception ex) {
            markRecommendationFailure(ex);
        }
    }

    private void markRecommendationFailure(Exception ex) {
        if (scanJobId == null) {
            return;
        }
        ScanJobRepository.safeAppendError(scanJobId, 'Recommendation rebuild failed: ' + ex.getMessage(), true);
    }
}
