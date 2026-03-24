@IsTest
private class Clarity360SetupConnectionServiceTest {
    @IsTest
    static void testConnectionReturnsPassedEnvelope() {
        ToolingApiService.ToolingQueryResult successResult = new ToolingApiService.ToolingQueryResult();
        successResult.success = true;
        successResult.records.add(new Map<String, Object>{ 'Id' => '01p000000000001AAA' });
        ToolingApiService.setTestQueryResult(successResult);

        Test.startTest();
        Clarity360SetupConnectionService.ConnectionTestResult result =
            Clarity360SetupConnectionService.testConnection(false);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Passed', result.status);
        System.assertEquals('SessionPreferred', result.mode);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void testConnectionReturnsFailedEnvelope() {
        ToolingApiService.ToolingQueryResult failureResult = new ToolingApiService.ToolingQueryResult();
        failureResult.success = false;
        failureResult.errorMessage = 'Unable to connect.';
        ToolingApiService.setTestQueryResult(failureResult);

        Test.startTest();
        Clarity360SetupConnectionService.ConnectionTestResult result =
            Clarity360SetupConnectionService.testConnection(true);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Failed', result.status);
        System.assertEquals('NamedCredentialPreferred', result.mode);
        System.assertEquals('Unable to connect.', result.message);

        ToolingApiService.clearTestOverrides();
    }
}
