public with sharing class Clarity360ScheduleService {
    @TestVisible
    static final String JOB_NAME = 'Clarity360 Scheduled Full Scan';

    public static void syncSchedule() {
        Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
        if (config == null || config.isSetupComplete != true) {
            return;
        }

        Boolean scheduleEnabled = config.enableScheduledScan == true || config.scheduleEnabled == true;
        abortExistingSchedules();
        if (!scheduleEnabled) {
            return;
        }

        if (String.isBlank(config.scheduleFrequency)) {
            throw new AuraHandledException('Schedule frequency is required when scheduled scans are enabled.');
        }

        System.schedule(JOB_NAME, cronForFrequency(config.scheduleFrequency), new ScanOrchestratorSchedulable());
    }

    @TestVisible
    static void abortExistingSchedules() {
        for (CronTrigger job : [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ]) {
            System.abortJob(job.Id);
        }
    }

    @TestVisible
    static String cronForFrequency(String frequency) {
        if (String.isBlank(frequency)) {
            throw new AuraHandledException('Schedule frequency is required.');
        }
        String normalized = frequency.trim().toLowerCase();
        if (normalized == 'weekly') {
            return '0 0 2 ? * SUN';
        }
        if (normalized == 'monthly') {
            return '0 0 2 1 * ?';
        }
        if (normalized != 'daily') {
            throw new AuraHandledException('Unsupported schedule frequency: ' + frequency);
        }
        return '0 0 2 * * ?';
    }
}
