public with sharing class SignalRepository {
    public static void upsertSignals(List<UsageSignal__c> signals) {
        if (signals == null || signals.isEmpty()) {
            return;
        }
        List<SObject> rawRows = new List<SObject>();
        rawRows.addAll(signals);
        List<SObject> cleanedRows = Clarity360AccessControlService.get().stripForUpsert(rawRows);
        if (cleanedRows.isEmpty()) {
            return;
        }
        List<UsageSignal__c> cleanedSignals = new List<UsageSignal__c>();
        for (SObject row : cleanedRows) {
            cleanedSignals.add((UsageSignal__c) row);
        }
        upsert cleanedSignals FieldKey__c;
    }
}
