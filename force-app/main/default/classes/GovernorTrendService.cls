public with sharing class GovernorTrendService {
    private static final String KEY_TXN_COUNT = 'TxnCount';
    private static final String KEY_CPU_TOTAL_MS = 'CpuTotalMs';
    private static final String KEY_HEAP_TOTAL_BYTES = 'HeapTotalBytes';
    private static final String KEY_SOQL_TOTAL = 'SoqlTotal';
    private static final String KEY_AVG_CPU_MS = 'AvgCpuMs';
    private static final String KEY_AVG_HEAP_KB = 'AvgHeapKb';
    private static final String KEY_ASYNC_ACTIVE_JOBS = 'AsyncActiveJobs';
    private static final String KEY_DAILY_API_PCT = 'DailyApiRequestsPct';
    private static final String KEY_DAILY_ASYNC_PCT = 'DailyAsyncApexPct';
    private static final String KEY_LAST_PHASE = 'LastPhase';
    private static final String KEY_LAST_CAPTURED_ON = 'LastCapturedOn';

    @TestVisible private static SnapshotMetric testMetricOverride;

    private class SnapshotMetric {
        public Integer cpuMs;
        public Integer heapBytes;
        public Integer soqlQueries;
        public Integer asyncActiveJobs;
        public Decimal dailyApiRequestsPct;
        public Decimal dailyAsyncApexPct;
    }

    public static void captureCurrentTransaction(Id scanJobId, String phase) {
        if (scanJobId == null) {
            return;
        }

        SnapshotMetric metric = buildCurrentMetric();
        if (metric == null) {
            return;
        }

        try {
            List<ScanJob__c> rows = [
                SELECT Id, GovernorSummary__c
                FROM ScanJob__c
                WHERE Id = :scanJobId
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return;
            }

            EvidenceParser parser = EvidenceParser.get();
            List<String> passthroughTokens = new List<String>();
            Map<String, String> parsed = parseWithPassthrough(rows[0].GovernorSummary__c, passthroughTokens);
            Integer txnCount = parser.getInteger(parsed, KEY_TXN_COUNT, 0) + 1;
            Integer cpuTotalMs = parser.getInteger(parsed, KEY_CPU_TOTAL_MS, 0) + safeInteger(metric.cpuMs);
            Integer heapTotalBytes = parser.getInteger(parsed, KEY_HEAP_TOTAL_BYTES, 0) + safeInteger(metric.heapBytes);
            Integer soqlTotal = parser.getInteger(parsed, KEY_SOQL_TOTAL, 0) + safeInteger(metric.soqlQueries);
            Decimal avgCpuMs = txnCount <= 0 ? 0 : Decimal.valueOf(cpuTotalMs) / txnCount;
            Decimal avgHeapKb = txnCount <= 0 ? 0 : (Decimal.valueOf(heapTotalBytes) / 1024) / txnCount;

            parsed.put(KEY_TXN_COUNT, String.valueOf(txnCount));
            parsed.put(KEY_CPU_TOTAL_MS, String.valueOf(cpuTotalMs));
            parsed.put(KEY_HEAP_TOTAL_BYTES, String.valueOf(heapTotalBytes));
            parsed.put(KEY_SOQL_TOTAL, String.valueOf(soqlTotal));
            parsed.put(KEY_AVG_CPU_MS, String.valueOf(avgCpuMs.setScale(2)));
            parsed.put(KEY_AVG_HEAP_KB, String.valueOf(avgHeapKb.setScale(2)));
            parsed.put(KEY_ASYNC_ACTIVE_JOBS, String.valueOf(safeInteger(metric.asyncActiveJobs)));
            parsed.put(KEY_DAILY_API_PCT, formatDecimal(metric.dailyApiRequestsPct));
            parsed.put(KEY_DAILY_ASYNC_PCT, formatDecimal(metric.dailyAsyncApexPct));
            parsed.put(KEY_LAST_PHASE, String.isBlank(phase) ? 'Unknown' : phase);
            parsed.put(KEY_LAST_CAPTURED_ON, String.valueOf(System.now()));

            update new ScanJob__c(
                Id = scanJobId,
                GovernorSummary__c = rebuildSummary(parsed, passthroughTokens)
            );
        } catch (Exception ex) {
            Clarity360SecureLog.warn('GovernorTrendService.captureCurrentTransaction', ex);
        }
    }

    private static SnapshotMetric buildCurrentMetric() {
        if (Test.isRunningTest() && testMetricOverride != null) {
            return testMetricOverride;
        }

        SnapshotMetric metric = new SnapshotMetric();
        metric.cpuMs = Limits.getCpuTime();
        metric.heapBytes = Limits.getHeapSize();
        metric.soqlQueries = Limits.getQueries();
        metric.asyncActiveJobs = queryAsyncActiveJobs();
        metric.dailyApiRequestsPct = getOrgLimitPct('DailyApiRequests');
        metric.dailyAsyncApexPct = getOrgLimitPct('DailyAsyncApexExecutions');
        return metric;
    }

    private static Integer queryAsyncActiveJobs() {
        try {
            return [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE Status IN ('Processing', 'Preparing', 'Holding', 'Queued')
            ];
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Decimal getOrgLimitPct(String key) {
        try {
            Map<String, System.OrgLimit> limitsByName = System.OrgLimits.getMap();
            if (limitsByName == null || !limitsByName.containsKey(key)) {
                return 0;
            }
            System.OrgLimit orgLimit = limitsByName.get(key);
            if (orgLimit == null || orgLimit.getLimit() == null || orgLimit.getLimit() <= 0) {
                return 0;
            }
            return (((Decimal) orgLimit.getValue()) * 100) / orgLimit.getLimit();
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Map<String, String> parseWithPassthrough(String summary, List<String> passthroughTokens) {
        Map<String, String> parsed = new Map<String, String>();
        if (String.isBlank(summary)) {
            return parsed;
        }

        for (String token : summary.split(';')) {
            if (token == null) {
                continue;
            }
            String trimmed = token.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            Integer splitIndex = trimmed.indexOf('=');
            if (splitIndex <= 0 || splitIndex >= trimmed.length() - 1) {
                passthroughTokens.add(trimmed);
                continue;
            }
            parsed.put(trimmed.substring(0, splitIndex), trimmed.substring(splitIndex + 1));
        }
        return parsed;
    }

    private static String rebuildSummary(Map<String, String> parsed, List<String> passthroughTokens) {
        List<String> tokens = new List<String>();
        if (passthroughTokens != null) {
            tokens.addAll(passthroughTokens);
        }

        List<String> orderedKeys = new List<String>{
            KEY_TXN_COUNT,
            KEY_AVG_CPU_MS,
            KEY_AVG_HEAP_KB,
            KEY_SOQL_TOTAL,
            KEY_CPU_TOTAL_MS,
            KEY_HEAP_TOTAL_BYTES,
            KEY_ASYNC_ACTIVE_JOBS,
            KEY_DAILY_API_PCT,
            KEY_DAILY_ASYNC_PCT,
            KEY_LAST_PHASE,
            KEY_LAST_CAPTURED_ON
        };
        for (String key : orderedKeys) {
            if (parsed != null && parsed.containsKey(key) && !String.isBlank(parsed.get(key))) {
                tokens.add(key + '=' + parsed.get(key));
            }
        }

        if (parsed != null) {
            List<String> remainingKeys = new List<String>();
            remainingKeys.addAll(parsed.keySet());
            remainingKeys.sort();
            for (String key : remainingKeys) {
                if (orderedKeys.contains(key)) {
                    continue;
                }
                tokens.add(key + '=' + parsed.get(key));
            }
        }
        return String.join(tokens, '; ');
    }

    private static Integer safeInteger(Integer value) {
        return value == null ? 0 : value;
    }

    private static String formatDecimal(Decimal value) {
        Decimal safeValue = value == null ? 0 : value;
        return String.valueOf(safeValue.setScale(2));
    }

    @TestVisible
    static void setTestMetric(
        Integer cpuMs,
        Integer heapBytes,
        Integer soqlQueries,
        Integer asyncActiveJobs,
        Decimal dailyApiRequestsPct,
        Decimal dailyAsyncApexPct
    ) {
        SnapshotMetric metric = new SnapshotMetric();
        metric.cpuMs = cpuMs;
        metric.heapBytes = heapBytes;
        metric.soqlQueries = soqlQueries;
        metric.asyncActiveJobs = asyncActiveJobs;
        metric.dailyApiRequestsPct = dailyApiRequestsPct;
        metric.dailyAsyncApexPct = dailyAsyncApexPct;
        testMetricOverride = metric;
    }

    @TestVisible
    static void clearTestOverrides() {
        testMetricOverride = null;
    }
}
