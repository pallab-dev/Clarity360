@IsTest
private class Clarity360ScheduleServiceTest {
    @IsTest
    static void syncSchedule_createsAndRemovesScheduledJob() {
        Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
        input.isSetupComplete = true;
        input.enableScheduledScan = true;
        input.scheduleEnabled = true;
        input.scheduleFrequency = 'Weekly';
        Clarity360SetupConfigService.save(input);

        Test.startTest();
        Clarity360ScheduleService.syncSchedule();
        List<CronTrigger> scheduled = [
            SELECT Id, CronJobDetail.Name, CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = :Clarity360ScheduleService.JOB_NAME
        ];
        System.assertEquals(1, scheduled.size());
        System.assertEquals('0 0 2 ? * SUN', scheduled[0].CronExpression);
        Test.stopTest();

        input.enableScheduledScan = false;
        input.scheduleEnabled = false;
        Clarity360SetupConfigService.save(input);

        Test.startTest();
        Clarity360ScheduleService.syncSchedule();
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :Clarity360ScheduleService.JOB_NAME]
        );
        Test.stopTest();
    }
}
