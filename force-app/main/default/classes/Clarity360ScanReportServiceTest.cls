@IsTest
private class Clarity360ScanReportServiceTest {
    private class CapturingEmailSender extends Clarity360ScanReportService.EmailSender {
        public Integer sentCount = 0;
        public List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        public Boolean succeed = true;
        public String failureMessage = 'Simulated email failure';

        public override List<Messaging.SendEmailResult> send(List<Messaging.SingleEmailMessage> outbound) {
            sentCount += outbound == null ? 0 : outbound.size();
            if (outbound != null) {
                messages.addAll(outbound);
            }
            if (succeed) {
                return new List<Messaging.SendEmailResult>{
                    (Messaging.SendEmailResult) JSON.deserialize('{"success":true}', Messaging.SendEmailResult.class)
                };
            }
            return new List<Messaging.SendEmailResult>{
                (Messaging.SendEmailResult) JSON.deserialize(
                    '{"success":false,"errors":[{"message":"' + failureMessage + '"}]}',
                    Messaging.SendEmailResult.class
                )
            };
        }
    }

    @IsTest
    static void notifyIfNeededSendsRequesterReportOnce() {
        User currentUser = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId()];
        insert new FieldInventory__c(FieldKey__c = 'Account.Legacy__c', ObjectApiName__c = 'Account', FieldApiName__c = 'Legacy__c', DataType__c = 'Text', IsActive__c = true);
        insert new UsageSignal__c(FieldKey__c = 'Account.Legacy__c', SampleSize__c = 100, NonNullCount__c = 0, NullRatePct__c = 100, IsOnLayout__c = false);
        insert new Recommendation__c(FieldKey__c = 'Account.Legacy__c', Action__c = 'Deprecate', Status__c = 'Open', RiskScore__c = 80, ConfidenceScore__c = 90);

        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-10),
            FinishedOn__c = System.now(),
            ReportMode__c = 'Requester',
            ScopeSummary__c = 'reportRequested=true; reportMode=Requester'
        );
        insert job;

        CapturingEmailSender sender = new CapturingEmailSender();
        Clarity360ScanReportService.emailSender = sender;

        Test.startTest();
        Clarity360ScanReportService.notifyIfNeeded(job.Id);
        Clarity360ScanReportService.notifyIfNeeded(job.Id);
        Test.stopTest();

        ScanJob__c updated = [SELECT ReportSentOn__c, ScopeSummary__c FROM ScanJob__c WHERE Id = :job.Id];
        System.assertEquals(1, sender.sentCount);
        System.assertNotEquals(null, updated.ReportSentOn__c);
        System.assert(updated.ScopeSummary__c.contains('reportDelivered=true'));
        System.assertNotEquals(null, currentUser.Email);
        System.assertEquals(currentUser.Email, sender.messages[0].getToAddresses()[0]);
    }

    @IsTest
    static void notifyIfNeededDoesNotMarkSentWhenEmailFails() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-10),
            FinishedOn__c = System.now(),
            ReportMode__c = 'Requester',
            ScopeSummary__c = 'reportRequested=true; reportMode=Requester'
        );
        insert job;

        CapturingEmailSender sender = new CapturingEmailSender();
        sender.succeed = false;
        sender.failureMessage = 'Mailbox unavailable';
        Clarity360ScanReportService.emailSender = sender;

        Test.startTest();
        Clarity360ScanReportService.notifyIfNeeded(job.Id);
        Test.stopTest();

        ScanJob__c updated = [SELECT ReportSentOn__c, ScopeSummary__c, ErrorMessage__c FROM ScanJob__c WHERE Id = :job.Id];
        System.assertEquals(1, sender.sentCount);
        System.assertEquals(null, updated.ReportSentOn__c);
        System.assert(!updated.ScopeSummary__c.contains('reportDelivered=true'));
        System.assertEquals(false, updated.ScopeSummary__c.contains('reportDelivered=true'));
    }

    @IsTest
    static void notifyIfNeededFallsBackToConfiguredScheduledRecipient() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        config.enableScheduledScan = true;
        config.scheduleEnabled = true;
        config.scheduleFrequency = 'Daily';
        config.enableScheduledReports = true;
        config.scheduledReportRecipient = 'admin@example.com';
        Clarity360SetupConfigService.save(config);

        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Partial',
            StartedOn__c = System.now().addMinutes(-5),
            FinishedOn__c = System.now(),
            ReportMode__c = 'Scheduled',
            ScopeSummary__c = 'reportRequested=true; reportMode=Scheduled'
        );
        insert job;

        CapturingEmailSender sender = new CapturingEmailSender();
        Clarity360ScanReportService.emailSender = sender;

        Test.startTest();
        Clarity360ScanReportService.notifyIfNeeded(job.Id);
        Test.stopTest();

        ScanJob__c updated = [SELECT ScopeSummary__c, ReportSentOn__c FROM ScanJob__c WHERE Id = :job.Id];
        System.assertEquals(1, sender.sentCount);
        System.assertNotEquals(null, updated.ReportSentOn__c);
        System.assert(updated.ScopeSummary__c.contains('reportDelivered=true'));
        System.assertEquals('admin@example.com', sender.messages[0].getToAddresses()[0]);
    }

    @IsTest
    static void notifyIfNeededUsesExplicitRecipientFromSummary() {
        ScanJob__c job = new ScanJob__c(
            JobType__c = 'Full Scan',
            Status__c = 'Completed',
            StartedOn__c = System.now().addMinutes(-10),
            FinishedOn__c = System.now(),
            ReportMode__c = 'Requester',
            ScopeSummary__c = 'reportRequested=true; reportMode=Requester; reportRecipient=ops@example.com'
        );
        insert job;

        CapturingEmailSender sender = new CapturingEmailSender();
        Clarity360ScanReportService.emailSender = sender;

        Test.startTest();
        Clarity360ScanReportService.notifyIfNeeded(job.Id);
        Test.stopTest();

        ScanJob__c updated = [SELECT ScopeSummary__c, ReportSentOn__c FROM ScanJob__c WHERE Id = :job.Id];
        System.assertEquals(1, sender.sentCount);
        System.assertNotEquals(null, updated.ReportSentOn__c);
        System.assert(updated.ScopeSummary__c.contains('reportDelivered=true'));
        System.assertEquals('ops@example.com', sender.messages[0].getToAddresses()[0]);
    }
}
