Clarity360SetupConfigService.SetupConfigDTO input = Clarity360SetupConfigService.load();
input.scopeMode = 'CustomOnly';
input.includeStandardObjects = false;
input.coverageThreshold = 80;
input.useNamedCredential = false;
input.enableScheduledScan = false;
input.scheduleEnabled = false;
input.scheduleFrequency = null;

try {
    Clarity360SetupWizardController.SaveResult result =
        Clarity360SetupWizardController.saveRuntimeConfig(input, true);
    System.debug('SAVE_OK ' + JSON.serialize(result));
} catch (Exception ex) {
    System.debug('SAVE_ERR_TYPE ' + ex.getTypeName());
    System.debug('SAVE_ERR_MSG ' + ex.getMessage());
    System.debug('SAVE_ERR_STACK ' + ex.getStackTraceString());
    throw ex;
}
