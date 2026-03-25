@IsTest
private class DataSamplerTest {
    @IsTest
    static void scanObjectBuildsSignalsWithNullRate() {
        insert new List<Account>{
            new Account(Name = 'Acme A', NumberOfEmployees = 10),
            new Account(Name = 'Acme B'),
            new Account(Name = 'Acme C')
        };

        FieldInventory__c nameInventory = new FieldInventory__c(
            FieldKey__c = 'Account.Name',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Name'
        );
        FieldInventory__c employeeInventory = new FieldInventory__c(
            FieldKey__c = 'Account.NumberOfEmployees',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'NumberOfEmployees'
        );
        insert new List<FieldInventory__c>{ nameInventory, employeeInventory };

        List<UsageSignal__c> signals = DataSampler.scanObject(
            'Account',
            new List<FieldInventory__c>{ nameInventory, employeeInventory },
            10
        );

        System.assertEquals(2, signals.size(), 'One signal per field expected.');

        Map<String, UsageSignal__c> signalByKey = new Map<String, UsageSignal__c>();
        for (UsageSignal__c signal : signals) {
            signalByKey.put(signal.FieldKey__c, signal);
        }

        System.assertEquals(3, signalByKey.get('Account.Name').SampleSize__c);
        System.assertEquals(0, signalByKey.get('Account.Name').NullRatePct__c);
        System.assertEquals(false, signalByKey.get('Account.Name').IsOnLayout__c);
        System.assert(signalByKey.get('Account.Name').EvidenceSummary__c.contains('HasData=true'));

        System.assertEquals(3, signalByKey.get('Account.NumberOfEmployees').SampleSize__c);
        Decimal employeeNullRate = signalByKey.get('Account.NumberOfEmployees').NullRatePct__c;
        System.assert(employeeNullRate > 66 && employeeNullRate < 67, 'Null rate should be about 66.67%.');
        System.assertEquals(false, signalByKey.get('Account.NumberOfEmployees').IsOnLayout__c);
        System.assert(signalByKey.get('Account.NumberOfEmployees').EvidenceSummary__c.contains('HasData=true'));
    }

    @IsTest
    static void scanObjectSkipsDuplicateIdSelection() {
        insert new Account(Name = 'Acme D');

        FieldInventory__c idInventory = new FieldInventory__c(
            FieldKey__c = 'Account.Id',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Id'
        );
        FieldInventory__c nameInventory = new FieldInventory__c(
            FieldKey__c = 'Account.Name',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Name'
        );
        insert new List<FieldInventory__c>{ idInventory, nameInventory };

        Test.startTest();
        List<UsageSignal__c> signals = DataSampler.scanObject(
            'Account',
            new List<FieldInventory__c>{ idInventory, nameInventory },
            10
        );
        Test.stopTest();

        System.assertEquals(2, signals.size(), 'Signals should still be produced for both inventoried fields.');
        for (UsageSignal__c signal : signals) {
            System.assertEquals(1, signal.SampleSize__c, 'Duplicate Id selection should not break sampling.');
        }
    }

    @IsTest
    static void scanObjectMarksFieldsOnLayoutWhenLayoutScanEnabled() {
        insert new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            EnableLayoutScan__c = true
        );
        Clarity360Settings.resetCache();

        insert new Account(Name = 'Acme E');

        FieldInventory__c customInventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c'
        );
        insert customInventory;

        LayoutScanService.setTestMetadataByLayoutName(new Map<String, Object>{
            'Account Layout' => new Map<String, Object>{
                'layoutSections' => new List<Object>{
                    new Map<String, Object>{
                        'layoutColumns' => new List<Object>{
                            new Map<String, Object>{
                                'layoutItems' => new List<Object>{
                                    new Map<String, Object>{ 'field' => 'Legacy_Flag__c' }
                                }
                            }
                        }
                    }
                }
            }
        });

        Test.startTest();
        List<UsageSignal__c> signals = DataSampler.scanObject('Account', new List<FieldInventory__c>{ customInventory }, 10);
        Test.stopTest();

        System.assertEquals(1, signals.size());
        System.assertEquals(true, signals[0].IsOnLayout__c);
        System.assert(signals[0].EvidenceSummary__c.contains('IsOnLayout=true'));

        LayoutScanService.clearTestOverrides();
    }

    @IsTest
    static void scanObjectLeavesLayoutFalseWhenLayoutScanDisabled() {
        insert new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            EnableLayoutScan__c = false
        );
        Clarity360Settings.resetCache();

        insert new Account(Name = 'Acme F');

        FieldInventory__c customInventory = new FieldInventory__c(
            FieldKey__c = 'Account.Legacy_Flag__c',
            ObjectApiName__c = 'Account',
            FieldApiName__c = 'Legacy_Flag__c'
        );
        insert customInventory;

        LayoutScanService.setTestMetadataByLayoutName(new Map<String, Object>{
            'Account Layout' => new Map<String, Object>{
                'layoutSections' => new List<Object>{
                    new Map<String, Object>{
                        'layoutColumns' => new List<Object>{
                            new Map<String, Object>{
                                'layoutItems' => new List<Object>{
                                    new Map<String, Object>{ 'field' => 'Legacy_Flag__c' }
                                }
                            }
                        }
                    }
                }
            }
        });

        Test.startTest();
        List<UsageSignal__c> signals = DataSampler.scanObject('Account', new List<FieldInventory__c>{ customInventory }, 10);
        Test.stopTest();

        System.assertEquals(1, signals.size());
        System.assertEquals(false, signals[0].IsOnLayout__c);
        System.assert(signals[0].EvidenceSummary__c.contains('IsOnLayout=false'));

        LayoutScanService.clearTestOverrides();
    }
}
