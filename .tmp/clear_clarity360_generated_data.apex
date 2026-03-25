Integer chunkSize = 10000;

void deleteAllForObject(String objectApiName) {
    while (true) {
        List<SObject> rows = Database.query('SELECT Id FROM ' + objectApiName + ' LIMIT ' + chunkSize);
        if (rows.isEmpty()) {
            break;
        }
        delete rows;
    }
}

deleteAllForObject('Recommendation__c');
deleteAllForObject('UsageSignal__c');
deleteAllForObject('MetadataComponentInventory__c');
deleteAllForObject('FieldInventory__c');
deleteAllForObject('ScanJob__c');

System.debug('Clarity360 generated data cleanup complete.');
