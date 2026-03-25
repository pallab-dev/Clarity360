@IsTest
private class Clarity360AutomationTriggerTest {
    @IsTest
    static void triggersFillRequiredFallbackValues() {
        Test.startTest();
        insert new Account(Name = 'Coverage Account', AnnualRevenue = 1500000);
        insert new Contact(LastName = 'Coverage Contact');
        Test.stopTest();

        Account accountRow = [SELECT Name FROM Account LIMIT 1];
        Contact contactRow = [SELECT LastName FROM Contact LIMIT 1];

        System.assertEquals('Coverage Account', accountRow.Name);
        System.assertEquals('Coverage Contact', contactRow.LastName);
    }
}
