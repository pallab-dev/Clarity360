@IsTest
private class Clarity360PostInstallHandlerTest {
    @IsTest
    static void ensureSetupConfigExists_createsDefaultRow() {
        delete [SELECT Id FROM Clarity360SetupConfig__c];

        Test.startTest();
        Clarity360PostInstallHandler.ensureSetupConfigExists();
        Test.stopTest();

        Integer rowCount = [SELECT COUNT() FROM Clarity360SetupConfig__c];
        System.assertEquals(1, rowCount, 'Post install helper should create one default config row.');
    }
}
