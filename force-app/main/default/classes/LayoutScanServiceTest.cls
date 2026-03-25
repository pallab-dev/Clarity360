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

    @IsTest
    static void scanObjectReturnsEmptyWhenDisabledOrInputsAreBlank() {
        Clarity360Settings.resetCache();

        Map<String, LayoutScanService.FieldLayoutSummary> blankResult =
            LayoutScanService.scanObject(null, new Set<String>{ 'Legacy_Flag__c' }, true);
        Map<String, LayoutScanService.FieldLayoutSummary> disabledResult =
            LayoutScanService.scanObject('Account', new Set<String>{ 'Legacy_Flag__c' }, true);

        System.assertEquals(1, blankResult.size());
        System.assertEquals(false, blankResult.get('Legacy_Flag__c').isOnLayout);
        System.assertEquals(1, disabledResult.size());
        System.assertEquals(false, disabledResult.get('Legacy_Flag__c').isOnLayout);
        System.assertEquals(0, LayoutScanService.getLayoutNamesForField('Account', null).size());
    }

    @IsTest
    static void getLayoutNamesForFieldSortsNamesAcrossNestedMetadataNodes() {
        insert new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            EnableLayoutScan__c = true
        );
        Clarity360Settings.resetCache();

        LayoutScanService.setTestMetadataByLayoutName(new Map<String, Object>{
            'Zulu Layout' => new Map<String, Object>{
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
            },
            'Alpha Layout' => new Map<String, Object>{
                'detailLayoutSections' => new List<Object>{
                    new Map<String, Object>{
                        'layoutRows' => new List<Object>{
                            new Map<String, Object>{
                                'items' => new List<Object>{
                                    new Map<String, Object>{ 'field' => 'Legacy_Flag__c' }
                                }
                            }
                        }
                    }
                }
            }
        });

        List<String> layoutNames = LayoutScanService.getLayoutNamesForField('Account', 'Legacy_Flag__c');
        System.assertEquals(new List<String>{ 'Alpha Layout', 'Zulu Layout' }, layoutNames);

        LayoutScanService.clearTestOverrides();
    }

    @IsTest
    static void getLayoutNamesForFieldReturnsEmptyWhenMetadataHasNoTargetField() {
        insert new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            EnableLayoutScan__c = true
        );
        Clarity360Settings.resetCache();

        LayoutScanService.setTestMetadataByLayoutName(new Map<String, Object>{
            'Account Layout' => new Map<String, Object>{
                'layoutSections' => new List<Object>{
                    new Map<String, Object>{
                        'layoutColumns' => new List<Object>{
                            new Map<String, Object>{
                                'layoutItems' => new List<Object>{
                                    new Map<String, Object>{ 'field' => 'Different_Field__c' }
                                }
                            }
                        }
                    }
                }
            }
        });

        System.assertEquals(0, LayoutScanService.getLayoutNamesForField('Account', 'Legacy_Flag__c').size());
        LayoutScanService.clearTestOverrides();
    }

    @IsTest
    static void scanObjectLoadsMetadataThroughToolingQueryFallback() {
        insert new Clarity360SetupConfig__c(
            IsSetupComplete__c = true,
            EnableLayoutScan__c = true
        );
        Clarity360Settings.resetCache();

        ToolingApiService.ToolingQueryResult queryResult = new ToolingApiService.ToolingQueryResult();
        queryResult.success = true;
        queryResult.records.add(new Map<String, Object>{
            'Name' => 'Account Layout',
            'TableEnumOrId' => 'Account',
            'Metadata' => new Map<String, Object>{
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
        ToolingApiService.setTestQueryResult(queryResult);

        Map<String, LayoutScanService.FieldLayoutSummary> result = LayoutScanService.scanObject(
            'Account',
            new Set<String>{ 'Legacy_Flag__c' },
            true
        );

        System.assertEquals(true, result.get('Legacy_Flag__c').isOnLayout);
        System.assertEquals(true, result.get('Legacy_Flag__c').layoutNames.contains('Account Layout'));
        ToolingApiService.clearTestOverrides();
    }
}
