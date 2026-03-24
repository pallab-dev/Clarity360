@IsTest
private class DependencySignalServiceTest {
    private static void ensureRuntimeSetup() {
        List<Clarity360SetupConfig__c> existing = [SELECT Id FROM Clarity360SetupConfig__c LIMIT 1];
        if (existing.isEmpty()) {
            insert new Clarity360SetupConfig__c(
                IsSetupComplete__c = true,
                ScopeMode__c = 'IncludeStandard',
                IncludeStandardObjects__c = true,
                CoverageThreshold__c = 80
            );
        } else {
            existing[0].put('IsSetupComplete__c', true);
            existing[0].put('ScopeMode__c', 'IncludeStandard');
            existing[0].put('IncludeStandardObjects__c', true);
            existing[0].put('CoverageThreshold__c', 80);
            update existing[0];
        }
        Clarity360Settings.resetCache();
    }

    @IsTest
    static void scanReturnsEmptyForInvalidInput() {
        ensureRuntimeSetup();

        System.assertEquals(0, DependencySignalService.scan(null, new Set<String>{ 'SLA__c' }).size());
        System.assertEquals(0, DependencySignalService.scan('Account', new Set<String>()).size());
        System.assertEquals('', DependencySignalService.joinNames(null, 3));
    }

    @IsTest
    static void scanFindsTriggerDependenciesAndFormatsNames() {
        ensureRuntimeSetup();

        Test.startTest();
        Map<String, DependencySignalService.FieldDependencySummary> result =
            DependencySignalService.scan('Account', new Set<String>{ 'SLA__c' });
        Test.stopTest();

        System.assert(result.containsKey('SLA__c'));
        DependencySignalService.FieldDependencySummary summary = result.get('SLA__c');
        System.assertNotEquals(null, summary.activeTriggerRefs);
        System.assertNotEquals(null, summary.apexClassRefs);
        System.assertEquals(
            'Alpha,Beta',
            DependencySignalService.joinNames(new Set<String>{ 'Beta', 'Alpha' }, 5)
        );
    }
}
