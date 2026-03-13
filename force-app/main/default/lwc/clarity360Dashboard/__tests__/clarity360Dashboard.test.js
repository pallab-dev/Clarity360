import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import Clarity360Dashboard from 'c/clarity360Dashboard';

import getDashboardSummary from '@salesforce/apex/Clarity360DashboardController.getDashboardSummary';
import getRecommendations from '@salesforce/apex/Clarity360DashboardController.getRecommendations';
import getMonitoringSnapshot from '@salesforce/apex/Clarity360DashboardController.getMonitoringSnapshot';
import getRecentJobs from '@salesforce/apex/Clarity360DashboardController.getRecentJobs';
import runFullScan from '@salesforce/apex/Clarity360DashboardController.runFullScanV2';
import deleteCustomField from '@salesforce/apex/Clarity360DashboardController.deleteCustomField';
import getAgentAssistantAvailability from '@salesforce/apex/Clarity360DashboardController.getAgentAssistantAvailability';

jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getMonitoringSnapshot',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getRecentJobs',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/Clarity360DashboardController.runFullScanV2',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/Clarity360DashboardController.deleteCustomField',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getAgentAssistantAvailability',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

const summaryAdapter = registerApexTestWireAdapter(getDashboardSummary);
const recommendationsAdapter = registerApexTestWireAdapter(getRecommendations);

const flushPromises = () => new Promise(setImmediate);

describe('c-clarity360-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    beforeEach(() => {
        getAgentAssistantAvailability.mockResolvedValue({ available: true, mode: 'AI Mode', message: 'Available' });
        getMonitoringSnapshot.mockResolvedValue({
            asyncApexUsedPct: 0,
            queueableActiveCount: 0,
            batchActiveCount: 0,
            scheduledJobCount: 0,
            platformEventCount: 0,
            activePlatformSubscriberCount: 0,
            limitMetrics: [],
            platformEvents: []
        });
    });

    it('renders grouped recommendations from wire data', async () => {
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });

        const element = createElement('c-clarity360-dashboard', {
            is: Clarity360Dashboard
        });
        document.body.appendChild(element);

        summaryAdapter.emit({ cleanlinessScore: 92, latestJobStatus: 'Completed' });
        recommendationsAdapter.emit([
            { id: '1', fieldKey: 'Account.A__c', status: 'Open' },
            { id: '2', fieldKey: 'Account.B__c', status: 'Open' },
            { id: '3', fieldKey: 'GLOBAL.TRIGGER.X', status: 'Open' }
        ]);
        await flushPromises();

        expect(element.recommendationGroups.length).toBe(2);
    });

    it('defaults to priority view and search opens matching items in a popup', async () => {
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });

        const element = createElement('c-clarity360-dashboard', {
            is: Clarity360Dashboard
        });
        document.body.appendChild(element);

        summaryAdapter.emit({ cleanlinessScore: 92, latestJobStatus: 'Completed' });
        recommendationsAdapter.emit([
            {
                id: '1',
                fieldKey: 'Account.Healthy__c',
                componentName: 'Healthy__c',
                status: 'Accepted',
                riskScore: 10,
                confidenceScore: 85,
                reason: 'Looks healthy',
                evidenceSummary: 'NullRatePct=10; Sampled=100; NonNull=90; HasData=true'
            },
            {
                id: '2',
                fieldKey: 'Account.Critical__c',
                componentName: 'Critical__c',
                status: 'Open',
                riskScore: 80,
                confidenceScore: 85,
                reason: 'High null rate',
                evidenceSummary: 'NullRatePct=60; Sampled=100; NonNull=40; HasData=true'
            }
        ]);
        await flushPromises();

        expect(element.inventoryHealthFilter).toBe('priority');
        expect(element.filteredRecommendations).toHaveLength(1);
        expect(element.filteredRecommendations[0].fieldKey).toBe('Account.Critical__c');

        element.handleSearchFilterChange({ detail: { value: 'Healthy__c' } });
        await flushPromises();

        expect(element.isSearchModalOpen).toBe(true);
        expect(element.searchResults).toHaveLength(1);
        expect(element.searchResults[0].title).toBe('Healthy__c');
    });

    it('supports job pagination boundaries', async () => {
        getRecentJobs
            .mockResolvedValueOnce({ jobs: [{ Id: 'a' }], totalCount: 11, pageNumber: 2 })
            .mockResolvedValueOnce({ jobs: [{ Id: 'b' }], totalCount: 11, pageNumber: 3 });

        const element = createElement('c-clarity360-dashboard', {
            is: Clarity360Dashboard
        });
        document.body.appendChild(element);
        await flushPromises();

        element.jobsPageNumber = 2;
        element.jobsTotalCount = 11;
        await element.handleNextJobsPage();

        expect(getRecentJobs).toHaveBeenCalled();
        expect(element.jobsPageNumber).toBe(3);
    });

    it('shows success toast on full scan action', async () => {
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });
        runFullScan.mockResolvedValue({ success: true, jobId: '707xx0000001234', status: 'Queued' });

        const element = createElement('c-clarity360-dashboard', {
            is: Clarity360Dashboard
        });
        document.body.appendChild(element);

        summaryAdapter.emit({ cleanlinessScore: 92, latestJobStatus: 'Completed' });
        recommendationsAdapter.emit([]);
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);
        await element.handleRunFullScan();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.variant).toBe('success');
    });

    it('normalizes nested error message to toast', async () => {
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });
        runFullScan.mockRejectedValue({
            body: {
                output: {
                    errors: [{ message: 'Queue unavailable' }]
                }
            }
        });

        const element = createElement('c-clarity360-dashboard', {
            is: Clarity360Dashboard
        });
        document.body.appendChild(element);

        summaryAdapter.emit({ cleanlinessScore: 92, latestJobStatus: 'Completed' });
        recommendationsAdapter.emit([]);
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);
        await element.handleRunFullScan();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.message).toBe('Queue unavailable');
        expect(handler.mock.calls[0][0].detail.variant).toBe('error');
    });

    it('opens usage modal and marks custom field deletable when no usage or dependencies', async () => {
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });

        const element = createElement('c-clarity360-dashboard', {
            is: Clarity360Dashboard
        });
        document.body.appendChild(element);
        await flushPromises();

        element.handleRecommendationRowAction({
            detail: {
                action: { name: 'view_usage' },
                row: {
                    fieldKey: 'Account.Legacy_Flag__c',
                    componentName: 'Legacy_Flag__c',
                    evidenceSummary:
                        'HasData=false; Sampled=500; NonNull=0; ActiveTriggerRefs=0; InactiveTriggerRefs=0; ' +
                        'ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ActiveFlowRefs=0; InactiveFlowRefs=0; ApexClassRefs=0'
                }
            }
        });

        expect(element.isUsageModalOpen).toBe(true);
        expect(element.selectedUsage.fieldKey).toBe('Account.Legacy_Flag__c');
        expect(element.selectedUsage.canDelete).toBe('Yes');
    });

    it('calls delete api for eligible field', async () => {
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });
        deleteCustomField.mockResolvedValue({ success: true, deleted: true, message: 'Field deleted successfully.' });

        const element = createElement('c-clarity360-dashboard', {
            is: Clarity360Dashboard
        });
        document.body.appendChild(element);
        await flushPromises();

        element.selectedUsage = { fieldKey: 'Account.Legacy_Flag__c', deleteAllowed: true };
        await element.handleDeleteField();

        expect(deleteCustomField).toHaveBeenCalledWith({ fieldKey: 'Account.Legacy_Flag__c' });
    });

});
