@IsTest
private class Clarity360AccessControlServiceTest {
    private class DenyAllAccessEvaluator extends Clarity360AccessControlService.AccessEvaluator {
        public override Boolean canRead(Schema.SObjectType objectType) {
            return objectType == null;
        }

        public override Boolean canCreate(Schema.SObjectType objectType) {
            return objectType == null;
        }

        public override Boolean canUpdate(Schema.SObjectType objectType) {
            return objectType == null;
        }

        public override Boolean canDelete(Schema.SObjectType objectType) {
            return objectType == null;
        }
    }

    @TestSetup
    static void resetAccessControlDefaults() {
        Clarity360AccessControlService.accessEvaluator = new Clarity360AccessControlService.AccessEvaluator();
        Clarity360AccessControlService.useSecurityStripInTests = false;
    }

    @IsTest
    static void assertMethodsAllowAccessibleAndNullObjectTypes() {
        Clarity360AccessControlService service = new Clarity360AccessControlService();

        Test.startTest();
        service.assertReadable(Account.SObjectType, 'read-op');
        service.assertCreateable(Account.SObjectType, 'create-op');
        service.assertUpdateable(Account.SObjectType, 'update-op');
        service.assertDeleteable(Account.SObjectType, 'delete-op');
        service.assertReadable(null, 'null-read-op');
        service.assertCreateable(null, 'null-create-op');
        service.assertUpdateable(null, 'null-update-op');
        service.assertDeleteable(null, 'null-delete-op');
        Test.stopTest();

        System.assertNotEquals(null, service, 'Service instance should remain available after access checks.');
    }

    @IsTest
    static void assertMethodsThrowWhenAccessEvaluatorDeniesOperation() {
        Clarity360AccessControlService service = new Clarity360AccessControlService();
        Clarity360AccessControlService.accessEvaluator = new DenyAllAccessEvaluator();

        try {
            service.assertReadable(Account.SObjectType, 'read-op');
            System.assert(false, 'Read access should be denied.');
        } catch (SecurityException ex) {
            System.assert(ex.getMessage().contains('Insufficient read access'), 'Read failure should mention the denied operation.');
        }

        try {
            service.assertCreateable(Account.SObjectType, 'create-op');
            System.assert(false, 'Create access should be denied.');
        } catch (SecurityException ex) {
            System.assert(ex.getMessage().contains('Insufficient create access'), 'Create failure should mention the denied operation.');
        }

        try {
            service.assertUpdateable(Account.SObjectType, 'update-op');
            System.assert(false, 'Update access should be denied.');
        } catch (SecurityException ex) {
            System.assert(ex.getMessage().contains('Insufficient update access'), 'Update failure should mention the denied operation.');
        }

        try {
            service.assertDeleteable(Account.SObjectType, 'delete-op');
            System.assert(false, 'Delete access should be denied.');
        } catch (SecurityException ex) {
            System.assert(ex.getMessage().contains('Insufficient delete access'), 'Delete failure should mention the denied operation.');
        }
    }

    @IsTest
    static void stripReadableReturnsClonedRecordsInTests() {
        Clarity360AccessControlService service = new Clarity360AccessControlService();
        Account original = new Account(Name = 'Readable');

        List<SObject> stripped = service.stripReadable(new List<SObject>{ original, null });
        Account clonedRecord = (Account) stripped[0];

        System.assertEquals(2, stripped.size(), 'Readable strip should preserve list shape.');
        System.assertEquals(null, stripped[1], 'Null rows should remain null.');
        System.assertEquals('Readable', clonedRecord.Name, 'Cloned readable record should preserve field values.');

        clonedRecord.Name = 'Changed in clone';
        System.assertEquals(
            'Readable',
            original.Name,
            'Test-mode readable sanitization should return an independent clone, not the original instance.'
        );
    }

    @IsTest
    static void stripMethodsHandleNullAndEmptyInputs() {
        Clarity360AccessControlService service = new Clarity360AccessControlService();

        List<SObject> strippedReadableNull = service.stripReadable(null);
        List<SObject> strippedReadableEmpty = service.stripReadable(new List<SObject>());
        List<SObject> strippedUpsertNull = service.stripForUpsert(null);
        List<SObject> strippedUpsertEmpty = service.stripForUpsert(new List<SObject>());

        System.assertEquals(0, strippedReadableNull.size(), 'Null readable input should return an empty list.');
        System.assertEquals(0, strippedReadableEmpty.size(), 'Empty readable input should return an empty list.');
        System.assertEquals(0, strippedUpsertNull.size(), 'Null upsert input should return an empty list.');
        System.assertEquals(0, strippedUpsertEmpty.size(), 'Empty upsert input should return an empty list.');
    }

    @IsTest
    static void stripReadableCanExerciseSecuritySanitizationPathInTests() {
        Clarity360AccessControlService service = new Clarity360AccessControlService();
        Clarity360AccessControlService.useSecurityStripInTests = true;
        Account original = new Account(Name = 'Readable');

        List<SObject> stripped = service.stripReadable(new List<SObject>{ original });

        System.assertEquals(1, stripped.size(), 'Readable sanitization should return one row.');
        System.assertEquals('Readable', ((Account) stripped[0]).Name, 'Readable sanitization should preserve accessible field values.');
    }

    @IsTest
    static void stripForUpsertReturnsClonesForInsertAndUpdateRecords() {
        Clarity360AccessControlService service = new Clarity360AccessControlService();

        Account existing = new Account(Name = 'Existing');
        insert existing;
        Account updated = existing.clone(false, true, false, false);
        updated.Id = existing.Id;
        updated.Name = 'Updated';
        Account toInsert = new Account(Name = 'Inserted');

        List<SObject> stripped = service.stripForUpsert(new List<SObject>{ updated, toInsert, null });

        System.assertEquals(3, stripped.size(), 'Upsert strip should preserve all rows including nulls.');
        System.assertEquals(null, stripped[2], 'Null upsert row should remain null.');
        System.assertEquals(existing.Id, ((Account) stripped[0]).Id, 'Updated row should preserve the record id.');
        System.assertEquals('Updated', ((Account) stripped[0]).Name, 'Updated row should preserve changed values.');
        System.assertEquals(null, ((Account) stripped[1]).Id, 'Insert row should remain an insert candidate.');
        System.assertEquals('Inserted', ((Account) stripped[1]).Name, 'Insert row should preserve field values.');
    }

    @IsTest
    static void stripForUpsertCanExerciseSecuritySanitizationPathInTests() {
        Clarity360AccessControlService service = new Clarity360AccessControlService();
        Clarity360AccessControlService.useSecurityStripInTests = true;

        Account existing = new Account(Name = 'Existing');
        insert existing;
        Account updated = existing.clone(false, true, false, false);
        updated.Id = existing.Id;
        updated.Name = 'Updated';
        Account toInsert = new Account(Name = 'Inserted');

        List<SObject> stripped = service.stripForUpsert(new List<SObject>{ updated, toInsert });
        Account firstRow = (Account) stripped[0];
        Account secondRow = (Account) stripped[1];

        System.assertEquals(2, stripped.size(), 'Upsert sanitization should return both insert and update rows.');
        System.assertEquals(null, firstRow.Id, 'Insert rows should remain insert candidates after sanitization.');
        System.assertEquals('Inserted', firstRow.Name, 'Insert rows should preserve field values.');
        System.assertEquals(existing.Id, secondRow.Id, 'Update rows should preserve the record id.');
        System.assertEquals('Updated', secondRow.Name, 'Update rows should preserve changed values.');
    }

    @IsTest
    static void getReturnsServiceInstance() {
        Clarity360AccessControlService service = Clarity360AccessControlService.get();

        System.assertNotEquals(null, service, 'Factory method should return a service instance.');
    }
}
