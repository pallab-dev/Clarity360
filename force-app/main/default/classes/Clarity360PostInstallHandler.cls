public with sharing class Clarity360PostInstallHandler implements InstallHandler {
    public void onInstall(InstallContext context) {
        ensureSetupConfigExists();
    }

    @TestVisible
    static void ensureSetupConfigExists() {
        try {
            Integer existing = [SELECT COUNT() FROM Clarity360SetupConfig__c];
            if (existing > 0) {
                return;
            }

            Clarity360SetupConfigService.SetupConfigDTO defaults = Clarity360SetupConfigService.load();
            if (defaults != null) {
                Clarity360SetupConfigService.save(defaults);
            }
        } catch (Exception ex) {
            Clarity360SecureLog.error('PostInstall.ensureSetupConfigExists', ex);
        }
    }
}
