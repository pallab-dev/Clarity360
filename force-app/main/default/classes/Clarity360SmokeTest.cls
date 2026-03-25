@IsTest
private class Clarity360SmokeTest {
    @IsTest
    static void installCreatesSetupConfigAndExposesState() {
        delete [SELECT Id FROM Clarity360SetupConfig__c];

        Test.startTest();
        Clarity360PostInstallHandler.ensureSetupConfigExists();
        Clarity360SetupWizardController.SetupState state = Clarity360SetupWizardController.getSetupState();
        Test.stopTest();

        Integer rowCount = [SELECT COUNT() FROM Clarity360SetupConfig__c];
        System.assertEquals(1, rowCount, 'Package install should create a single setup config row.');
        System.assertNotEquals(null, state, 'Setup state should be returned.');
        System.assertNotEquals(null, state.config, 'Runtime config should be available.');
        System.assertNotEquals(null, state.readiness, 'Readiness result should be available.');
    }

    @IsTest
    static void upgradeLeavesExistingSetupConfigUntouched() {
        Clarity360SetupConfig__c existing = new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            ScopeMode__c = 'CustomOnly',
            CoverageThreshold__c = 81
        );
        insert existing;

        Test.startTest();
        Clarity360PostInstallHandler.ensureSetupConfigExists();
        Test.stopTest();

        List<Clarity360SetupConfig__c> configs = [
            SELECT Id, IsSetupComplete__c, ScopeMode__c, CoverageThreshold__c
            FROM Clarity360SetupConfig__c
        ];
        System.assertEquals(1, configs.size(), 'Package upgrade should not create duplicate setup config rows.');
        System.assertEquals(existing.Id, configs[0].Id, 'Existing setup config should be preserved during upgrade.');
        System.assertEquals(true, configs[0].IsSetupComplete__c, 'Existing completion state should remain intact.');
        System.assertEquals('CustomOnly', configs[0].ScopeMode__c, 'Existing scope should remain intact.');
        System.assertEquals(81, configs[0].CoverageThreshold__c, 'Existing coverage threshold should remain intact.');
    }
}
