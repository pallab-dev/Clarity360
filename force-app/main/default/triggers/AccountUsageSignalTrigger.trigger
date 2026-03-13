trigger AccountUsageSignalTrigger on Account (before insert, before update) {
    // Keep deterministic SLA assignments so usage scans can observe field references and data changes.
    Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
    Schema.DescribeFieldResult slaDescribe = accountFields.containsKey('SLA__c')
        ? accountFields.get('SLA__c').getDescribe()
        : null;
    Schema.DisplayType slaType = slaDescribe == null ? null : slaDescribe.getType();

    Map<String, String> picklistMapByKey = new Map<String, String>();
    String firstActivePicklist = null;
    if (slaType == Schema.DisplayType.PICKLIST) {
        for (Schema.PicklistEntry entry : slaDescribe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            if (firstActivePicklist == null) {
                firstActivePicklist = entry.getValue();
            }
            picklistMapByKey.put(entry.getValue().toLowerCase(), entry.getValue());
            picklistMapByKey.put(entry.getLabel().toLowerCase(), entry.getValue());
        }
    }

    for (Account acc : Trigger.new) {
        if (String.isBlank(acc.Name)) {
            acc.Name = 'Auto-Name Placeholder';
        }

        if (slaType == null) {
            continue;
        }

        Decimal revenue = acc.AnnualRevenue == null ? 0 : acc.AnnualRevenue;
        String tierLabel;
        Decimal tierNumber;
        if (revenue >= 1000000) {
            tierLabel = 'Platinum';
            tierNumber = 3;
        } else if (revenue >= 250000) {
            tierLabel = 'Gold';
            tierNumber = 2;
        } else {
            tierLabel = 'Silver';
            tierNumber = 1;
        }

        if (slaType == Schema.DisplayType.PICKLIST) {
            String mapped = picklistMapByKey.get(tierLabel.toLowerCase());
            acc.put('SLA__c', mapped == null ? firstActivePicklist : mapped);
        } else if (
            slaType == Schema.DisplayType.CURRENCY ||
            slaType == Schema.DisplayType.DOUBLE ||
            slaType == Schema.DisplayType.INTEGER ||
            slaType == Schema.DisplayType.LONG ||
            slaType == Schema.DisplayType.PERCENT
        ) {
            acc.put('SLA__c', tierNumber);
        } else if (slaType == Schema.DisplayType.BOOLEAN) {
            acc.put('SLA__c', tierNumber == 3);
        } else if (slaType == Schema.DisplayType.DATE) {
            acc.put('SLA__c', Date.today().addDays((Integer) tierNumber));
        } else if (slaType == Schema.DisplayType.DATETIME) {
            acc.put('SLA__c', System.now().addDays((Integer) tierNumber));
        } else {
            acc.put('SLA__c', tierLabel);
        }
    }
}
