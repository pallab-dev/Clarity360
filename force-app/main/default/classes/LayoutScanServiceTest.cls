@IsTest
private class LayoutScanServiceTest {
    @IsTest
    static void scanObjectFindsFieldsOnLayoutsWhenEnabled() {
        Clarity360SetupConfig__c config = new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            EnableLayoutScan__c = true
        );
        insert config;
        Clarity360Settings.resetCache();

        LayoutScanService.setTestMetadataByLayoutName(new Map<String, Object>{
            'Account Layout' => new Map<String, Object>{
                'layoutSections' => new List<Object>{
                    new Map<String, Object>{
                        'layoutColumns' => new List<Object>{
                            new Map<String, Object>{
                                'layoutItems' => new List<Object>{
                                    new Map<String, Object>{ 'field' => 'Legacy_Flag__c' },
                                    new Map<String, Object>{ 'field' => 'Another_Field__c' }
                                }
                            }
                        }
                    }
                }
            }
        });

        Map<String, LayoutScanService.FieldLayoutSummary> result = LayoutScanService.scanObject(
            'Account',
            new Set<String>{ 'Legacy_Flag__c', 'Unused_Field__c' },
            true
        );

        System.assertEquals(true, result.get('Legacy_Flag__c').isOnLayout);
        System.assertEquals(false, result.get('Unused_Field__c').isOnLayout);
        System.assertEquals(true, result.get('Legacy_Flag__c').layoutNames.contains('Account Layout'));

        LayoutScanService.clearTestOverrides();
    }
}
