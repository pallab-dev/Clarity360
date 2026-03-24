@IsTest
private class ToolingApiServiceTest {
    private class SequencedToolingMock implements HttpCalloutMock {
        private Integer queryAttempts = 0;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            if (endpoint != null && endpoint.contains('/tooling/query')) {
                queryAttempts++;
                if (queryAttempts == 1) {
                    res.setStatusCode(503);
                    res.setBody('retry');
                    return res;
                }
                if (endpoint.contains('nextRecordsUrl')) {
                    res.setStatusCode(200);
                    res.setBody('{"done":true,"records":[{"Name":"SecondPage"}]}');
                    return res;
                }
                res.setStatusCode(200);
                res.setBody('{"done":false,"nextRecordsUrl":"/services/data/v66.0/tooling/query/nextRecordsUrl","records":[{"Name":"FirstPage"}]}');
                return res;
            }

            if (endpoint != null && endpoint.contains('/tooling/sobjects/')) {
                res.setStatusCode(204);
                res.setBody('');
                return res;
            }

            res.setStatusCode(500);
            res.setBody('unexpected');
            return res;
        }
    }

    private class AlwaysFailToolingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('server-error');
            return res;
        }
    }

    @IsTest
    static void queryAndDeleteConsumeQueuedTestOverrides() {
        ToolingApiService.ToolingQueryResult firstQuery = new ToolingApiService.ToolingQueryResult();
        firstQuery.records.add(new Map<String, Object>{ 'Name' => 'First' });
        ToolingApiService.ToolingQueryResult secondQuery = new ToolingApiService.ToolingQueryResult();
        secondQuery.records.add(new Map<String, Object>{ 'Name' => 'Second' });
        ToolingApiService.setTestQueryResults(new List<ToolingApiService.ToolingQueryResult>{
            firstQuery,
            secondQuery
        });

        ToolingApiService.ToolingMutationResult firstDelete = new ToolingApiService.ToolingMutationResult();
        firstDelete.success = false;
        firstDelete.errorMessage = 'Blocked';
        ToolingApiService.ToolingMutationResult secondDelete = new ToolingApiService.ToolingMutationResult();
        secondDelete.success = true;
        secondDelete.statusCode = 204;
        ToolingApiService.setTestDeleteResults(new List<ToolingApiService.ToolingMutationResult>{
            firstDelete,
            secondDelete
        });

        Test.startTest();
        ToolingApiService.ToolingQueryResult firstResult = ToolingApiService.query('SELECT Id FROM ApexClass', 10);
        ToolingApiService.ToolingQueryResult secondResult = ToolingApiService.queryWithMode('SELECT Id FROM ApexClass', 10, true, true);
        ToolingApiService.ToolingMutationResult firstDeleteResult = ToolingApiService.deleteRecord('CustomField', '00N000000000001');
        ToolingApiService.ToolingMutationResult secondDeleteResult =
            ToolingApiService.deleteRecordWithMode('CustomField', '00N000000000001', false, true);
        Test.stopTest();

        System.assertEquals('First', ToolingApiService.getString(firstResult.records[0], 'Name'));
        System.assertEquals('Second', ToolingApiService.getString(secondResult.records[0], 'Name'));
        System.assertEquals(false, firstDeleteResult.success);
        System.assertEquals(true, secondDeleteResult.success);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void liveNamedCredentialPathsSupportRetryPaginationAndDelete() {
        ToolingApiService.allowLiveCalloutsInTests = true;
        Test.setMock(HttpCalloutMock.class, new SequencedToolingMock());

        Test.startTest();
        ToolingApiService.ToolingQueryResult queryResult =
            ToolingApiService.queryWithMode('SELECT Id FROM ApexClass', 5, true, false);
        ToolingApiService.ToolingMutationResult deleteResult =
            ToolingApiService.deleteRecordWithMode('CustomField', '00N000000000001', true, false);
        Test.stopTest();

        System.assertEquals(true, queryResult.success);
        System.assertEquals(2, queryResult.records.size());
        System.assertEquals('FirstPage', ToolingApiService.getString(queryResult.records[0], 'Name'));
        System.assertEquals('SecondPage', ToolingApiService.getString(queryResult.records[1], 'Name'));
        System.assertEquals(true, deleteResult.success);
        System.assertEquals(204, deleteResult.statusCode);

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void liveFallbackReportsCombinedFailuresWhenBothModesFail() {
        ToolingApiService.allowLiveCalloutsInTests = true;
        Test.setMock(HttpCalloutMock.class, new AlwaysFailToolingMock());

        Test.startTest();
        ToolingApiService.ToolingQueryResult queryResult =
            ToolingApiService.queryWithMode('SELECT Id FROM ApexClass', 5, false, true);
        ToolingApiService.ToolingMutationResult deleteResult =
            ToolingApiService.deleteRecordWithMode('CustomField', '00N000000000001', false, true);
        Test.stopTest();

        System.assertEquals(false, queryResult.success);
        System.assert(queryResult.errorMessage.contains('Named Credential and session fallback'));
        System.assertEquals(false, deleteResult.success);
        System.assert(deleteResult.errorMessage.contains('Named Credential and session fallback'));

        ToolingApiService.clearTestOverrides();
    }

    @IsTest
    static void helperReadersAreNullSafe() {
        Map<String, Object> row = new Map<String, Object>{
            'flagTrue' => 'true',
            'flagFalse' => 'false',
            'numberValue' => '18.50',
            'nested' => new Map<String, Object>{ 'child' => 'value' }
        };

        System.assertEquals(null, ToolingApiService.getString(null, 'Name'));
        System.assertEquals(true, ToolingApiService.getBoolean(row, 'flagTrue'));
        System.assertEquals(false, ToolingApiService.getBoolean(row, 'flagFalse'));
        System.assertEquals(null, ToolingApiService.getBoolean(row, 'missing'));
        System.assertEquals(18.50, ToolingApiService.getDecimal(row, 'numberValue'));
        System.assertEquals(null, ToolingApiService.getDecimal(new Map<String, Object>{ 'numberValue' => 'bad' }, 'numberValue'));
        System.assertEquals('value', ToolingApiService.getNestedString(row, 'nested', 'child'));
        System.assertEquals(null, ToolingApiService.getNestedString(row, 'nested', 'missing'));
    }
}
