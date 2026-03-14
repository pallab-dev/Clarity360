/**
 * Centralizes CRUD and field-level access enforcement for application services.
 */
public with sharing class Clarity360AccessControlService {
    /**
     * Ensures the running user can read the specified object before use.
     */
    public void assertReadable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isAccessible()) {
            return;
        }
        throw new SecurityException('Insufficient read access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * Ensures the running user can create records of the specified object.
     */
    public void assertCreateable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isCreateable()) {
            return;
        }
        throw new SecurityException('Insufficient create access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * Ensures the running user can update records of the specified object.
     */
    public void assertUpdateable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isUpdateable()) {
            return;
        }
        throw new SecurityException('Insufficient update access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * Ensures the running user can delete records of the specified object.
     */
    public void assertDeleteable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isDeletable()) {
            return;
        }
        throw new SecurityException('Insufficient delete access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    /**
     * Removes unreadable fields from queried records before they are used.
     */
    public List<SObject> stripReadable(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return new List<SObject>();
        }
        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }

    /**
     * Removes inaccessible fields for insert and update operations in a mixed record list.
     */
    public List<SObject> stripForUpsert(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return new List<SObject>();
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
     * Returns a shared access-control service instance.
     */
    public static Clarity360AccessControlService get() {
        return new Clarity360AccessControlService();
    }
}
