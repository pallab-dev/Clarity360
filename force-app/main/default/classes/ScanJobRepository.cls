public with sharing class ScanJobRepository {
    public static ScanJob__c findRecentRunningJob(String jobType, String requestId, Integer lookbackMinutes) {
        if (String.isBlank(jobType)) {
            return null;
        }
        Integer safeMinutes = (lookbackMinutes == null || lookbackMinutes <= 0) ? 10 : lookbackMinutes;
        Datetime cutoff = System.now().addMinutes(-safeMinutes);
        String requestToken = String.isBlank(requestId) ? null : 'requestId=' + requestId;

        List<ScanJob__c> jobs = [
            SELECT Id, JobType__c, Status__c, ScopeSummary__c
            FROM ScanJob__c
            WHERE JobType__c = :jobType
            AND Status__c IN ('Queued', 'Running')
            AND CreatedDate >= :cutoff
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];

        for (ScanJob__c job : jobs) {
            if (String.isBlank(requestToken)) {
                return job;
            }
            if (!String.isBlank(job.ScopeSummary__c) && job.ScopeSummary__c.contains(requestToken)) {
                return job;
            }
        }
        // Guardrail: prevent duplicate concurrent jobs of the same type even when requestIds differ.
        if (!jobs.isEmpty()) {
            return jobs[0];
        }
        return null;
    }

    public static void safeUpdate(ScanJob__c row) {
        if (row == null || row.Id == null) {
            return;
        }
        try {
            update row;
        } catch (Exception ex) {
            Clarity360SecureLog.warn('ScanJobRepository.safeUpdate', ex);
        }
    }

    public static void safeAppendError(Id jobId, String extra, Boolean markPartial) {
        if (jobId == null || String.isBlank(extra)) {
            return;
        }

        try {
            ScanJob__c current = [
                SELECT Id, Status__c, ErrorMessage__c
                FROM ScanJob__c
                WHERE Id = :jobId
                LIMIT 1
            ];
            current.ErrorMessage__c = appendError(current.ErrorMessage__c, extra);
            if (markPartial == true && (current.Status__c == 'Running' || current.Status__c == 'Queued')) {
                current.Status__c = 'Partial';
            }
            update current;
        } catch (Exception ex) {
            Clarity360SecureLog.warn('ScanJobRepository.safeAppendError', ex);
        }
    }

    public static String appendError(String existing, String extra) {
        if (String.isBlank(existing)) {
            return extra;
        }
        return existing + '\n' + extra;
    }
}
