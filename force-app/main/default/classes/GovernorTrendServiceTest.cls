@IsTest
private class GovernorTrendServiceTest {
    @IsTest
    static void captureCurrentTransactionAccumulatesGovernorSummary() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Usage Scan',
            Status__c = 'Running',
            StartedOn__c = System.now(),
            ScopeSummary__c = 'sampleLimit=5000'
        );
        insert job;

        GovernorTrendService.setTestMetric(120, 40960, 14, 3, 18.5, 22.5);
        GovernorTrendService.captureCurrentTransaction(job.Id, 'UsageScan');
        GovernorTrendService.setTestMetric(180, 61440, 20, 4, 20, 25);
        GovernorTrendService.captureCurrentTransaction(job.Id, 'UsageScan');
        GovernorTrendService.clearTestOverrides();

        ScanJob__c refreshed = [
            SELECT GovernorSummary__c
            FROM ScanJob__c
            WHERE Id = :job.Id
            LIMIT 1
        ];
        Map<String, String> parsed = EvidenceParser.get().parse(refreshed.GovernorSummary__c);
        System.assertEquals(2, Integer.valueOf(parsed.get('TxnCount')));
        System.assertEquals(300, Integer.valueOf(parsed.get('CpuTotalMs')));
        System.assertEquals(34, Integer.valueOf(parsed.get('SoqlTotal')));
        System.assertEquals('150.00', parsed.get('AvgCpuMs'));
        System.assertEquals('50.00', parsed.get('AvgHeapKb'));
        System.assertEquals('4', parsed.get('AsyncActiveJobs'));
        System.assertEquals('25.00', parsed.get('DailyAsyncApexPct'));
        System.assertEquals('UsageScan', parsed.get('LastPhase'));
    }
}
