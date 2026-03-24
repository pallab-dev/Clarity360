public with sharing class ScanOrchestratorSchedulable implements Schedulable {
    @TestVisible
    static Boolean skipFullScanInTests = false;

    @TestVisible
    static SetupConfigLoader setupConfigLoader = new SetupConfigLoader();

    @TestVisible
    static FullScanRunner fullScanRunner = new FullScanRunner();

    public virtual class SetupConfigLoader {
        public virtual Clarity360SetupConfigService.SetupConfigDTO load() {
            return Clarity360SetupConfigService.load();
        }
    }

    public virtual class FullScanRunner {
        public virtual void run() {
            ScanOrchestrator.runScheduledFullScan();
        }
    }

    public void execute(SchedulableContext context) {
        try {
            if (Test.isRunningTest() && skipFullScanInTests) {
                return;
            }
            Clarity360SetupConfigService.SetupConfigDTO config = setupConfigLoader.load();
            if (config != null && config.enableScheduledScan == true && config.isSetupComplete == true) {
                fullScanRunner.run();
            }
        } catch (Exception ignored) {
            // If setup config can't be loaded, skip the scheduled run safely.
        }
    }
}
