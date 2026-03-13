public with sharing class ToolingApiService {
    private static final String API_VERSION = 'v66.0';
    private static final String NAMED_CREDENTIAL = 'Clarity360Tooling';
    private static final Integer MAX_CALL_RETRIES = 2;

    public class ToolingQueryResult {
        public List<Map<String, Object>> records = new List<Map<String, Object>>();
        public Boolean success = true;
        public String errorMessage;
    }

    public class ToolingMutationResult {
        public Boolean success = true;
        public Integer statusCode;
        public String errorMessage;
    }

    @TestVisible private static ToolingQueryResult testQueryResult;
    @TestVisible private static ToolingMutationResult testDeleteResult;

    public static ToolingQueryResult query(String soql, Integer maxRows) {
        return queryInternal(soql, maxRows, null, true);
    }

    public static ToolingQueryResult queryWithMode(String soql, Integer maxRows, Boolean preferNamedCredential, Boolean allowFallback) {
        return queryInternal(soql, maxRows, preferNamedCredential, allowFallback);
    }

    public static ToolingMutationResult deleteRecord(String toolingObjectName, String recordId) {
        return deleteInternal(toolingObjectName, recordId, null, true);
    }

    public static ToolingMutationResult deleteRecordWithMode(
        String toolingObjectName,
        String recordId,
        Boolean preferNamedCredential,
        Boolean allowFallback
    ) {
        return deleteInternal(toolingObjectName, recordId, preferNamedCredential, allowFallback);
    }

    public static Boolean hasNamedCredentialConfigured() {
        try {
            List<NamedCredential> rows = [
                SELECT Id
                FROM NamedCredential
                WHERE DeveloperName = :NAMED_CREDENTIAL
                LIMIT 1
            ];
            return !rows.isEmpty();
        } catch (Exception ex) {
            return false;
        }
    }

    private static ToolingQueryResult queryInternal(
        String soql,
        Integer maxRows,
        Boolean preferNamedCredentialOverride,
        Boolean allowFallback
    ) {
        ToolingQueryResult result = new ToolingQueryResult();
        if (String.isBlank(soql)) {
            return result;
        }

        Integer rowLimit = (maxRows == null || maxRows <= 0) ? 1000 : maxRows;
        if (Test.isRunningTest()) {
            if (testQueryResult != null) {
                return testQueryResult;
            }
            return result;
        }

        Boolean preferNamedCredential =
            preferNamedCredentialOverride == null ? shouldUseNamedCredential() : preferNamedCredentialOverride;
        ToolingQueryResult namedCredentialResult = new ToolingQueryResult();
        ToolingQueryResult sessionResult = new ToolingQueryResult();
        if (preferNamedCredential) {
            namedCredentialResult = queryWithNamedCredential(soql, rowLimit);
            if (namedCredentialResult.success) {
                return namedCredentialResult;
            }
            if (allowFallback != true) {
                return namedCredentialResult;
            }
            sessionResult = queryWithSession(soql, rowLimit);
        } else {
            sessionResult = queryWithSession(soql, rowLimit);
            if (sessionResult.success) {
                return sessionResult;
            }
            if (allowFallback != true) {
                return sessionResult;
            }
            namedCredentialResult = queryWithNamedCredential(soql, rowLimit);
        }
        if (sessionResult.success) {
            return sessionResult;
        }

        result.success = false;
        result.errorMessage =
            'Tooling API query failed with Named Credential and session fallback. ' +
            'NC error=' + namedCredentialResult.errorMessage +
            '; Session error=' + sessionResult.errorMessage;
        return result;
    }

    private static ToolingMutationResult deleteInternal(
        String toolingObjectName,
        String recordId,
        Boolean preferNamedCredentialOverride,
        Boolean allowFallback
    ) {
        ToolingMutationResult result = new ToolingMutationResult();
        if (String.isBlank(toolingObjectName) || String.isBlank(recordId)) {
            result.success = false;
            result.errorMessage = 'Tooling delete requires object name and record id.';
            return result;
        }

        if (Test.isRunningTest()) {
            if (testDeleteResult != null) {
                return testDeleteResult;
            }
            return result;
        }

        Boolean preferNamedCredential =
            preferNamedCredentialOverride == null ? shouldUseNamedCredential() : preferNamedCredentialOverride;
        ToolingMutationResult namedCredentialResult = new ToolingMutationResult();
        ToolingMutationResult sessionResult = new ToolingMutationResult();
        if (preferNamedCredential) {
            namedCredentialResult = deleteWithNamedCredential(toolingObjectName, recordId);
            if (namedCredentialResult.success) {
                return namedCredentialResult;
            }
            if (allowFallback != true) {
                return namedCredentialResult;
            }
            sessionResult = deleteWithSession(toolingObjectName, recordId);
        } else {
            sessionResult = deleteWithSession(toolingObjectName, recordId);
            if (sessionResult.success) {
                return sessionResult;
            }
            if (allowFallback != true) {
                return sessionResult;
            }
            namedCredentialResult = deleteWithNamedCredential(toolingObjectName, recordId);
        }
        if (sessionResult.success) {
            return sessionResult;
        }

        result.success = false;
        result.errorMessage =
            'Tooling API delete failed with Named Credential and session fallback. ' +
            'NC error=' + namedCredentialResult.errorMessage +
            '; Session error=' + sessionResult.errorMessage;
        return result;
    }

    private static ToolingQueryResult queryWithNamedCredential(String soql, Integer rowLimit) {
        ToolingQueryResult result = new ToolingQueryResult();
        try {
            String endpoint = 'callout:' + NAMED_CREDENTIAL +
                '/services/data/' + API_VERSION + '/tooling/query?q=' +
                EncodingUtil.urlEncode(soql, 'UTF-8');
            while (!String.isBlank(endpoint) && result.records.size() < rowLimit) {
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');
                req.setEndpoint(endpoint);
                req.setHeader('Content-Type', 'application/json');
                req.setTimeout(120000);

                HttpResponse res = sendWithRetry(req);
                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                    result.success = false;
                    result.errorMessage =
                        'Tooling API query failed (' + res.getStatusCode() + '): ' + res.getBody();
                    return result;
                }

                Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> rawRecords = (List<Object>) payload.get('records');
                if (rawRecords != null) {
                    for (Object row : rawRecords) {
                        if (result.records.size() >= rowLimit) {
                            break;
                        }
                        result.records.add((Map<String, Object>) row);
                    }
                }

                Boolean done = (Boolean) payload.get('done');
                String nextRecordsUrl = (String) payload.get('nextRecordsUrl');
                if (done == true || String.isBlank(nextRecordsUrl)) {
                    endpoint = null;
                } else {
                    endpoint = 'callout:' + NAMED_CREDENTIAL + nextRecordsUrl;
                }
            }
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = ex.getMessage();
        }

        return result;
    }

    private static ToolingQueryResult queryWithSession(String soql, Integer rowLimit) {
        ToolingQueryResult result = new ToolingQueryResult();
        String sessionId = UserInfo.getSessionId();
        if (String.isBlank(sessionId)) {
            result.success = false;
            result.errorMessage = 'Session unavailable for Tooling API callout.';
            return result;
        }

        try {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() +
                '/services/data/' + API_VERSION + '/tooling/query?q=' +
                EncodingUtil.urlEncode(soql, 'UTF-8');
            while (!String.isBlank(endpoint) && result.records.size() < rowLimit) {
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');
                req.setEndpoint(endpoint);
                req.setHeader('Authorization', 'Bearer ' + sessionId);
                req.setHeader('Content-Type', 'application/json');
                req.setTimeout(120000);

                HttpResponse res = sendWithRetry(req);
                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                    result.success = false;
                    result.errorMessage =
                        'Tooling API query failed (' + res.getStatusCode() + '): ' + res.getBody();
                    return result;
                }

                Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> rawRecords = (List<Object>) payload.get('records');
                if (rawRecords != null) {
                    for (Object row : rawRecords) {
                        if (result.records.size() >= rowLimit) {
                            break;
                        }
                        result.records.add((Map<String, Object>) row);
                    }
                }

                Boolean done = (Boolean) payload.get('done');
                String nextRecordsUrl = (String) payload.get('nextRecordsUrl');
                if (done == true || String.isBlank(nextRecordsUrl)) {
                    endpoint = null;
                } else {
                    endpoint = URL.getOrgDomainUrl().toExternalForm() + nextRecordsUrl;
                }
            }
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = ex.getMessage();
        }

        return result;
    }

    private static ToolingMutationResult deleteWithNamedCredential(String toolingObjectName, String recordId) {
        ToolingMutationResult result = new ToolingMutationResult();
        try {
            String endpoint = 'callout:' + NAMED_CREDENTIAL +
                '/services/data/' + API_VERSION + '/tooling/sobjects/' +
                toolingObjectName + '/' + EncodingUtil.urlEncode(recordId, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setMethod('DELETE');
            req.setEndpoint(endpoint);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(120000);

            HttpResponse res = sendWithRetry(req);
            result.statusCode = res.getStatusCode();
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                result.success = false;
                result.errorMessage =
                    'Tooling API delete failed (' + res.getStatusCode() + '): ' + res.getBody();
            }
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = ex.getMessage();
        }
        return result;
    }

    private static ToolingMutationResult deleteWithSession(String toolingObjectName, String recordId) {
        ToolingMutationResult result = new ToolingMutationResult();
        String sessionId = UserInfo.getSessionId();
        if (String.isBlank(sessionId)) {
            result.success = false;
            result.errorMessage = 'Session unavailable for Tooling API delete callout.';
            return result;
        }

        try {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() +
                '/services/data/' + API_VERSION + '/tooling/sobjects/' +
                toolingObjectName + '/' + EncodingUtil.urlEncode(recordId, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setMethod('DELETE');
            req.setEndpoint(endpoint);
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(120000);

            HttpResponse res = sendWithRetry(req);
            result.statusCode = res.getStatusCode();
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                result.success = false;
                result.errorMessage =
                    'Tooling API delete failed (' + res.getStatusCode() + '): ' + res.getBody();
            }
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = ex.getMessage();
        }
        return result;
    }

    public static String getString(Map<String, Object> row, String key) {
        if (row == null || String.isBlank(key) || !row.containsKey(key) || row.get(key) == null) {
            return null;
        }
        return String.valueOf(row.get(key));
    }

    public static Boolean getBoolean(Map<String, Object> row, String key) {
        String value = getString(row, key);
        if (String.isBlank(value)) {
            return null;
        }

        value = value.toLowerCase();
        if (value == 'true') {
            return true;
        }
        if (value == 'false') {
            return false;
        }
        return null;
    }

    public static Decimal getDecimal(Map<String, Object> row, String key) {
        String value = getString(row, key);
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Decimal.valueOf(value);
        } catch (Exception ex) {
            return null;
        }
    }

    public static String getNestedString(Map<String, Object> row, String parentKey, String childKey) {
        if (row == null || !row.containsKey(parentKey) || row.get(parentKey) == null) {
            return null;
        }

        try {
            Map<String, Object> nestedMap = (Map<String, Object>) row.get(parentKey);
            return getString(nestedMap, childKey);
        } catch (Exception ex) {
            return null;
        }
    }

    @TestVisible
    static void setTestQueryResult(ToolingQueryResult value) {
        testQueryResult = value;
    }

    @TestVisible
    static void setTestDeleteResult(ToolingMutationResult value) {
        testDeleteResult = value;
    }

    @TestVisible
    static void clearTestOverrides() {
        testQueryResult = null;
        testDeleteResult = null;
    }

    private static Boolean shouldUseNamedCredential() {
        try {
            return Clarity360Settings.getRuntime().useNamedCredential == true;
        } catch (Exception ex) {
            return false;
        }
    }

    private static HttpResponse sendWithRetry(HttpRequest req) {
        Integer attempt = 0;
        Exception lastEx;
        while (attempt <= MAX_CALL_RETRIES) {
            try {
                HttpResponse res = new Http().send(req);
                if (isRetryableStatusCode(res.getStatusCode()) && attempt < MAX_CALL_RETRIES) {
                    attempt++;
                    continue;
                }
                return res;
            } catch (Exception ex) {
                lastEx = ex;
                if (attempt >= MAX_CALL_RETRIES) {
                    throw ex;
                }
                attempt++;
            }
        }
        if (lastEx != null) {
            throw lastEx;
        }
        throw new CalloutException('Tooling API callout failed after retries.');
    }

    private static Boolean isRetryableStatusCode(Integer statusCode) {
        return statusCode == 429 || statusCode == 503 || statusCode == 504;
    }
}
