public with sharing class Clarity360SecureLog {
    public static void warn(String area, Exception ex) {
        System.debug(LoggingLevel.WARN, format(area, ex));
    }

    public static void error(String area, Exception ex) {
        System.debug(LoggingLevel.ERROR, format(area, ex));
    }

    public static String sanitizeForUi(Exception ex, String fallback) {
        if (String.isBlank(fallback)) {
            fallback = 'Operation failed. Please contact your Salesforce admin.';
        }
        if (ex != null && ex instanceOf AuraHandledException) {
            String handledMessage = ex.getMessage();
            if (!String.isBlank(handledMessage)) {
                return handledMessage;
            }
        }
        return fallback;
    }

    private static String format(String area, Exception ex) {
        String safeArea = String.isBlank(area) ? 'UnknownArea' : area;
        if (ex == null) {
            return '[' + safeArea + '] Unknown exception';
        }
        return '[' + safeArea + '] ' + ex.getTypeName() + ': ' + ex.getMessage() + ' | ' + ex.getStackTraceString();
    }
}
