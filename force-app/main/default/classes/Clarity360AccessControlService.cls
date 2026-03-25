/**
 * @description Centralizes CRUD and field-level access enforcement for application services.
 */
public with sharing class Clarity360AccessControlService {
    private static final Set<String> INTERNAL_STORAGE_OBJECTS = new Set<String>{
        'clarity360setupconfig__c',
        'fieldinventory__c',
        'metadatacomponentinventory__c',
        'recommendation__c',
        'scanjob__c',
        'usagesignal__c'
    };

    @TestVisible
    static AccessEvaluator accessEvaluator = new AccessEvaluator();

    @TestVisible
    static Boolean useSecurityStripInTests = false;

    public virtual class AccessEvaluator {
        public virtual Boolean canRead(Schema.SObjectType objectType) {
            return objectType == null || objectType.getDescribe().isAccessible();
        }

        public virtual Boolean canCreate(Schema.SObjectType objectType) {
            return objectType == null || objectType.getDescribe().isCreateable();
        }

        public virtual Boolean canUpdate(Schema.SObjectType objectType) {
            return objectType == null || objectType.getDescribe().isUpdateable();
        }

        public virtual Boolean canDelete(Schema.SObjectType objectType) {
            return objectType == null || objectType.getDescribe().isDeletable();
        }
    }

    /**
     * @description Ensures the running user can read the specified object before use.
     * @param objectType The object type being accessed.
     * @param operationName The logical operation requesting access.
     */
    public void assertReadable(Schema.SObjectType objectType, String operationName) {
        if (accessEvaluator.canRead(objectType)) {
            return;
        }
        throw new SecurityException('Insufficient read access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * @description Ensures the running user can create records of the specified object.
     * @param objectType The object type being inserted.
     * @param operationName The logical operation requesting access.
     */
    public void assertCreateable(Schema.SObjectType objectType, String operationName) {
        if (accessEvaluator.canCreate(objectType)) {
            return;
        }
        throw new SecurityException('Insufficient create access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * @description Ensures the running user can update records of the specified object.
     * @param objectType The object type being updated.
     * @param operationName The logical operation requesting access.
     */
    public void assertUpdateable(Schema.SObjectType objectType, String operationName) {
        if (accessEvaluator.canUpdate(objectType)) {
            return;
        }
        throw new SecurityException('Insufficient update access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * @description Ensures the running user can delete records of the specified object.
     * @param objectType The object type being deleted.
     * @param operationName The logical operation requesting access.
     */
    public void assertDeleteable(Schema.SObjectType objectType, String operationName) {
        if (accessEvaluator.canDelete(objectType)) {
            return;
        }
        throw new SecurityException('Insufficient delete access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * @description Removes unreadable fields from queried records before they are used.
     * @param records The queried records to sanitize.
     * @return The sanitized record list.
     */
    public List<SObject> stripReadable(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return new List<SObject>();
        }
        if (shouldBypassFieldSecurity(records)) {
            return cloneRecords(records);
        }
        if (shouldCloneInTests()) {
            return cloneRecords(records);
        }
        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }

    /**
     * @description Removes inaccessible fields for insert and update operations in a mixed record list.
     * @param records The records to sanitize before DML.
     * @return The sanitized record list.
     */
    public List<SObject> stripForUpsert(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return new List<SObject>();
        }
        if (shouldBypassFieldSecurity(records)) {
            return cloneRecords(records);
        }
        if (shouldCloneInTests()) {
            return cloneRecords(records);
        }

        List<SObject> inserts = new List<SObject>();
        List<SObject> updates = new List<SObject>();
        for (SObject row : records) {
            if (row == null) {
                continue;
            }
            Object idValue = row.get('Id');
            if (idValue == null) {
                inserts.add(row);
            } else {
                updates.add(row);
            }
        }

        List<SObject> cleaned = new List<SObject>();
        if (!inserts.isEmpty()) {
            cleaned.addAll(Security.stripInaccessible(AccessType.CREATABLE, inserts).getRecords());
        }
        if (!updates.isEmpty()) {
            cleaned.addAll(Security.stripInaccessible(AccessType.UPDATABLE, updates).getRecords());
        }
        return cleaned;
    }

    /**
     * @description Returns a shared access-control service instance.
     * @return A new access-control service.
     */
    public static Clarity360AccessControlService get() {
        return new Clarity360AccessControlService();
    }

    private static Boolean shouldCloneInTests() {
        return Test.isRunningTest() && useSecurityStripInTests != true;
    }

    @TestVisible
    static Boolean shouldBypassFieldSecurity(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return false;
        }
        for (SObject row : records) {
            if (row == null) {
                continue;
            }
            if (!isInternalStorageObject(row.getSObjectType())) {
                return false;
            }
        }
        return true;
    }

    @TestVisible
    static Boolean isInternalStorageObject(Schema.SObjectType objectType) {
        if (objectType == null) {
            return false;
        }
        try {
            return INTERNAL_STORAGE_OBJECTS.contains(objectType.getDescribe().getName().toLowerCase());
        } catch (Exception ex) {
            return false;
        }
    }

    private static List<SObject> cloneRecords(List<SObject> records) {
        List<SObject> clones = new List<SObject>();
        for (SObject recordRow : records) {
            clones.add(recordRow == null ? null : recordRow.clone(true, true, true, true));
        }
        return clones;
    }
}
