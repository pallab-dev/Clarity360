public with sharing class ScanOrchestratorSchedulable implements Schedulable {
    @TestVisible
    static Boolean skipFullScanInTests = false;

    public void execute(SchedulableContext context) {
        try {
            if (Test.isRunningTest() && skipFullScanInTests) {
                return;
            }
            Clarity360SetupConfigService.SetupConfigDTO config = Clarity360SetupConfigService.load();
            if (config != null && config.enableScheduledScan == true && config.isSetupComplete == true) {
                ScanOrchestrator.runFullScan();
            }
        } catch (Exception ignored) {
            // If setup config can't be loaded, skip the scheduled run safely.
        }
    }
}
