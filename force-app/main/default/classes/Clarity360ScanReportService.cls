public with sharing class Clarity360ScanReportService {
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{ 'Completed', 'Partial', 'Failed' };

    @TestVisible
    static EmailSender emailSender = new EmailSender();

    public virtual class EmailSender {
        public virtual List<Messaging.SendEmailResult> send(List<Messaging.SingleEmailMessage> messages) {
            if (messages == null || messages.isEmpty()) {
                return new List<Messaging.SendEmailResult>();
            }
            return Messaging.sendEmail(messages);
        }
    }

    public static void notifyIfNeeded(Id scanJobId) {
        if (scanJobId == null) {
            return;
        }

        try {
            ScanJob__c job = [
                SELECT Id, Name, CreatedBy.Email, JobType__c, Status__c, StartedOn__c, FinishedOn__c, ScopeSummary__c,
                    ErrorMessage__c, ReportMode__c, ReportSentOn__c
                FROM ScanJob__c
                WHERE Id = :scanJobId
                LIMIT 1
            ];

            if (
                job.JobType__c != 'Full Scan' ||
                job.ReportSentOn__c != null ||
                !TERMINAL_STATUSES.contains(job.Status__c) ||
                !isReportRequested(job.ScopeSummary__c)
            ) {
                return;
            }

            String recipient = resolveRecipient(job);
            if (String.isBlank(recipient)) {
                return;
            }

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setToAddresses(new List<String>{ recipient });
            message.setSaveAsActivity(false);
            String orgWideEmailAddressId = resolveOrgWideEmailAddressId();
            if (!String.isBlank(orgWideEmailAddressId)) {
                message.setOrgWideEmailAddressId(orgWideEmailAddressId);
            }
            message.setSubject(buildSubject(job));
            message.setPlainTextBody(buildPlainTextBody(job));
            List<Messaging.SendEmailResult> results =
                emailSender.send(new List<Messaging.SingleEmailMessage>{ message });
            if (!wasEmailSendSuccessful(results)) {
                String errorMessage = firstEmailError(results);
                if (!String.isBlank(errorMessage)) {
                    ScanJobRepository.safeAppendError(job.Id, 'Report email failed: ' + errorMessage, false);
                }
                return;
            }

            ScanJobRepository.safeUpdate(new ScanJob__c(
                Id = job.Id,
                ReportSentOn__c = System.now(),
                ScopeSummary__c = markReportDelivered(job.ScopeSummary__c)
            ));
        } catch (Exception ex) {
            Clarity360SecureLog.warn('Clarity360ScanReportService.notifyIfNeeded', ex);
        }
    }

    @TestVisible
    static String resolveRecipient(ScanJob__c job) {
        if (job == null) {
            return null;
        }
        String explicitRecipient = extractSummaryToken(job.ScopeSummary__c, 'reportRecipient');
        if (!String.isBlank(explicitRecipient)) {
            return explicitRecipient;
        }
        if (job.ReportMode__c == 'Requester' && !String.isBlank(job.CreatedBy.Email)) {
            return job.CreatedBy.Email;
        }

        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        if (job.ReportMode__c == 'Scheduled') {
            if (config != null && config.enableScheduledReports == true && !String.isBlank(config.scheduledReportRecipient)) {
                return config.scheduledReportRecipient;
            }
            if (!String.isBlank(job.CreatedBy.Email)) {
                return job.CreatedBy.Email;
            }
        }
        return null;
    }

    @TestVisible
    static String buildSubject(ScanJob__c job) {
        return 'Clarity360 scan summary | ' + safeValue(job.Status__c) + ' | ' + safeValue(job.Name);
    }

    @TestVisible
    static String buildPlainTextBody(ScanJob__c job) {
        Integer activeInventory = [SELECT COUNT() FROM FieldInventory__c WHERE IsActive__c = true];
        Integer usageSignals = [SELECT COUNT() FROM UsageSignal__c];
        Integer openRecommendations = [SELECT COUNT() FROM Recommendation__c WHERE Status__c = 'Open'];
        Integer highRiskRecommendations = [
            SELECT COUNT()
            FROM Recommendation__c
            WHERE Status__c = 'Open'
            AND RiskScore__c >= 75
        ];

        List<String> lines = new List<String>{
            'Clarity360 finished reviewing your org and prepared a simple summary for you.',
            '',
            'Organization: ' + UserInfo.getOrganizationName(),
            'Scan result: ' + safeValue(job.Status__c),
            'Scan job: ' + safeValue(job.Name),
            'Started: ' + formatDatetime(job.StartedOn__c),
            'Finished: ' + formatDatetime(job.FinishedOn__c),
            '',
            'At a glance:',
            '- Active inventory currently tracked: ' + String.valueOf(activeInventory),
            '- Usage signals collected so far: ' + String.valueOf(usageSignals),
            '- Open recommendations waiting for review: ' + String.valueOf(openRecommendations),
            '- Higher-risk recommendations to review first: ' + String.valueOf(highRiskRecommendations)
        };

        if (!String.isBlank(job.ScopeSummary__c)) {
            lines.add('');
            lines.add('Scan details: ' + humanizeScopeSummary(job.ScopeSummary__c));
        }

        if (!String.isBlank(job.ErrorMessage__c)) {
            lines.add('');
            lines.add('Items that may still need attention: ' + trimForEmail(job.ErrorMessage__c, 700));
        }

        lines.add('');
        lines.add('Open Clarity360 to review recommendations, job history, and the areas worth checking next.');
        return String.join(lines, '\n');
    }

    private static String humanizeScopeSummary(String summary) {
        List<String> parts = new List<String>();
        for (String token : summary.split(';')) {
            String trimmed = token == null ? null : token.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            if (
                trimmed == 'reportRequested=true' ||
                trimmed == 'reportDelivered=true' ||
                trimmed.startsWith('reportMode=') ||
                trimmed.startsWith('reportRecipient=')
            ) {
                continue;
            }
            List<String> keyValue = trimmed.split('=');
            if (keyValue.size() == 2) {
                parts.add(keyValue[0] + ': ' + keyValue[1]);
            } else {
                parts.add(trimmed);
            }
        }
        return String.join(parts, ', ');
    }

    private static String trimForEmail(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength) + '...';
    }

    private static String safeValue(String value) {
        return String.isBlank(value) ? '-' : value;
    }

    @TestVisible
    static Boolean wasEmailSendSuccessful(List<Messaging.SendEmailResult> results) {
        return results != null && !results.isEmpty() && results[0] != null && results[0].isSuccess();
    }

    @TestVisible
    static String firstEmailError(List<Messaging.SendEmailResult> results) {
        if (results == null || results.isEmpty() || results[0] == null || results[0].isSuccess()) {
            return null;
        }
        List<Messaging.SendEmailError> errors = results[0].getErrors();
        if (errors == null || errors.isEmpty() || errors[0] == null) {
            return 'Unknown email failure';
        }
        return errors[0].getMessage();
    }

    @TestVisible
    static String extractSummaryToken(String summary, String tokenName) {
        if (String.isBlank(summary) || String.isBlank(tokenName)) {
            return null;
        }
        String prefix = tokenName + '=';
        for (String token : summary.split(';')) {
            String trimmed = token == null ? null : token.trim();
            if (!String.isBlank(trimmed) && trimmed.startsWith(prefix)) {
                return trimmed.substring(prefix.length());
            }
        }
        return null;
    }

    @TestVisible
    static String resolveOrgWideEmailAddressId() {
        try {
            List<OrgWideEmailAddress> rows = [
                SELECT Id
                FROM OrgWideEmailAddress
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].Id;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean isReportRequested(String summary) {
        return !String.isBlank(summary) && summary.contains('reportRequested=true') && !summary.contains('reportDelivered=true');
    }

    private static String markReportDelivered(String summary) {
        String existing = String.isBlank(summary) ? '' : summary;
        if (existing.contains('reportDelivered=true')) {
            return existing;
        }
        return existing + '; reportDelivered=true';
    }

    private static String formatDatetime(Datetime value) {
        return value == null ? '-' : value.format('yyyy-MM-dd HH:mm');
    }
}
