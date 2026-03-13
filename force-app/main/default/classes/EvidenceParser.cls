public with sharing class EvidenceParser {
    public Map<String, String> parse(String evidence) {
        Map<String, String> parsed = new Map<String, String>();
        if (String.isBlank(evidence)) {
            return parsed;
        }

        for (String token : evidence.split(';')) {
            if (token == null) {
                continue;
            }
            String trimmed = token.trim();
            Integer splitIndex = trimmed.indexOf('=');
            if (splitIndex <= 0 || splitIndex >= trimmed.length() - 1) {
                continue;
            }
            parsed.put(trimmed.substring(0, splitIndex), trimmed.substring(splitIndex + 1));
        }
        return parsed;
    }

    public String getString(Map<String, String> parsed, String key) {
        if (parsed == null || String.isBlank(key) || !parsed.containsKey(key)) {
            return null;
        }
        return parsed.get(key);
    }

    public Integer getInteger(Map<String, String> parsed, String key, Integer defaultValue) {
        String value = getString(parsed, key);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        try {
            return Integer.valueOf(value.trim());
        } catch (Exception ex) {
            return defaultValue;
        }
    }

    public Decimal getDecimal(Map<String, String> parsed, String key, Decimal defaultValue) {
        String value = getString(parsed, key);
        if (String.isBlank(value) || value == 'Unknown') {
            return defaultValue;
        }
        try {
            return Decimal.valueOf(value.trim());
        } catch (Exception ex) {
            return defaultValue;
        }
    }

    public Boolean getBoolean(Map<String, String> parsed, String key, Boolean defaultValue) {
        String value = getString(parsed, key);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        String normalized = value.trim().toLowerCase();
        if (normalized == 'true') {
            return true;
        }
        if (normalized == 'false') {
            return false;
        }
        return defaultValue;
    }

    public static EvidenceParser get() {
        return new EvidenceParser();
    }
}
