public with sharing class Clarity360AccessControlService {
    public void assertReadable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isAccessible()) {
            return;
        }
        throw new SecurityException('Insufficient read access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    public void assertCreateable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isCreateable()) {
            return;
        }
        throw new SecurityException('Insufficient create access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    public void assertUpdateable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isUpdateable()) {
            return;
        }
        throw new SecurityException('Insufficient update access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    public void assertDeleteable(Schema.SObjectType objectType, String operationName) {
        if (objectType == null || objectType.getDescribe().isDeletable()) {
            return;
        }
        throw new SecurityException('Insufficient delete access for ' + String.valueOf(objectType) + ' in ' + operationName + '.');
    }

    public List<SObject> stripReadable(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return new List<SObject>();
        }
        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }

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

    public static Clarity360AccessControlService get() {
        return new Clarity360AccessControlService();
    }
}
