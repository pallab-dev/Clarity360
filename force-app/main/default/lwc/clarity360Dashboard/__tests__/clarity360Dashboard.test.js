import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import Clarity360Dashboard from 'c/clarity360Dashboard';

import getDashboardSummary from '@salesforce/apex/Clarity360DashboardController.getDashboardSummary';
import getRecommendations from '@salesforce/apex/Clarity360DashboardController.getRecommendations';
import getGlobalComponentSections from '@salesforce/apex/Clarity360DashboardController.getGlobalComponentSections';
import getMetadataComponents from '@salesforce/apex/Clarity360DashboardController.getMetadataComponents';
import getMonitoringSnapshot from '@salesforce/apex/Clarity360DashboardController.getMonitoringSnapshot';
import getMonitoringDetail from '@salesforce/apex/Clarity360DashboardController.getMonitoringDetail';
import getRecentJobs from '@salesforce/apex/Clarity360DashboardController.getRecentJobs';
import getFieldDetailEvidence from '@salesforce/apex/Clarity360DashboardController.getFieldDetailEvidence';
import runFullScan from '@salesforce/apex/Clarity360DashboardController.runFullScanV2';
import deleteCustomField from '@salesforce/apex/Clarity360DashboardController.deleteCustomField';
import getAgentAssistantAvailability from '@salesforce/apex/Clarity360DashboardController.getAgentAssistantAvailability';
import askAgentAssistant from '@salesforce/apex/Clarity360DashboardController.askAgentAssistant';
import isSetupComplete from '@salesforce/apex/Clarity360SetupWizardController.isSetupComplete';
import getSetupState from '@salesforce/apex/Clarity360SetupWizardController.getSetupState';

jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getGlobalComponentSections',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getMetadataComponents',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getMonitoringSnapshot',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getMonitoringDetail',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getRecentJobs',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getFieldDetailEvidence',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.runFullScanV2',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.deleteCustomField',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.getAgentAssistantAvailability',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360DashboardController.askAgentAssistant',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360SetupWizardController.isSetupComplete',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Clarity360SetupWizardController.getSetupState',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const summaryAdapter = registerApexTestWireAdapter(getDashboardSummary);
const recommendationsAdapter = registerApexTestWireAdapter(getRecommendations);

const flushPromises = () => Promise.resolve();

function createDeferred() {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
}

function createDashboard() {
    const element = createElement('c-clarity360-dashboard', {
        is: Clarity360Dashboard
    });
    document.body.appendChild(element);
    return element;
}

async function seedDashboardData() {
    summaryAdapter.emit({ cleanlinessScore: 92, latestJobStatus: 'Completed' });
    recommendationsAdapter.emit([
        {
            id: 'row-1',
            fieldKey: 'Account.Legacy_Flag__c',
            componentName: 'Legacy_Flag__c',
            action: 'Deprecate',
            status: 'Open',
            riskScore: 80,
            confidenceScore: 90,
            reason: 'Unused custom field',
            evidenceSummary:
                'HasData=false; Sampled=500; NonNull=0; ActiveTriggerRefs=0; InactiveTriggerRefs=0; ' +
                'ActiveValidationRuleRefs=0; InactiveValidationRuleRefs=0; ActiveFlowRefs=0; InactiveFlowRefs=0; ApexClassRefs=0'
        }
    ]);
    await flushPromises();
}

describe('c-clarity360-dashboard', () => {
    beforeEach(() => {
        getAgentAssistantAvailability.mockResolvedValue({ available: false, mode: 'Standard', message: 'Unavailable' });
        getMonitoringSnapshot.mockResolvedValue({
            asyncApexUsedPct: 0,
            asyncJobsToday: 0,
            queueableActiveCount: 0,
            batchActiveCount: 0,
            scheduledJobCount: 0,
            platformEventCount: 0,
            activePlatformSubscriberCount: 0,
            activePlatformPublisherCount: 0,
            limitMetrics: [],
            platformEvents: [],
            scanTrends: []
        });
        getMonitoringDetail.mockResolvedValue(null);
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });
        getFieldDetailEvidence.mockResolvedValue({
            fieldKey: 'Account.Legacy_Flag__c',
            isOnLayout: false,
            layoutNames: [],
            signalHistoryCount: 1,
            latestEvidenceSummary: 'HasData=false; IsOnLayout=false'
        });
        getGlobalComponentSections.mockResolvedValue([]);
        getMetadataComponents.mockResolvedValue([]);
        askAgentAssistant.mockResolvedValue({ answer: 'ok' });
        isSetupComplete.mockResolvedValue(true);
        getSetupState.mockResolvedValue({
            isSetupComplete: true,
            readiness: { checks: [] }
        });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        window.sessionStorage.clear();
        jest.clearAllMocks();
    });

    it('renders summary and recommendation content from wire data', async () => {
        createDashboard();
        await seedDashboardData();

        expect(document.body.textContent).toContain('Cleanliness Score');
        expect(document.body.textContent).toContain('92.00%');
        expect(document.body.textContent).toContain('Legacy_Flag__c');
        expect(document.body.textContent).toContain('Deprecate');
    });

    it('queues a full scan from the toolbar and emits a success toast', async () => {
        runFullScan.mockResolvedValue({ success: true, jobId: '707xx0000001234' });

        const element = createDashboard();
        await seedDashboardData();

        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const runButton = Array.from(buttons).find((button) => button.label === 'Run Full Scan');
        runButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const modalButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const startButton = Array.from(modalButtons).find((button) => button.label === 'Start Scan');
        startButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(runFullScan).toHaveBeenCalled();
        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.variant).toBe('success');
    });

    it('disables Run Full Scan immediately while the request is still starting', async () => {
        const deferred = createDeferred();
        runFullScan.mockReturnValue(deferred.promise);

        const element = createDashboard();
        await seedDashboardData();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const runButton = Array.from(buttons).find((button) => button.label === 'Run Full Scan');
        runButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const modalButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const startButton = Array.from(modalButtons).find((button) => button.label === 'Start Scan');
        startButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const rerenderedButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const disabledRunButton = Array.from(rerenderedButtons).find((button) => button.label === 'Run Full Scan');
        expect(disabledRunButton.disabled).toBe(true);
        expect(document.body.textContent).toContain('Usage workspace update in progress');

        deferred.resolve({ success: true, jobId: '707xx0000009999' });
        await flushPromises();
        await flushPromises();
    });

    it('closes transient modals before starting a full scan refresh', async () => {
        const deferred = createDeferred();
        runFullScan.mockReturnValue(deferred.promise);
        getFieldDetailEvidence.mockResolvedValue({
            fieldKey: 'Account.Legacy_Flag__c',
            isOnLayout: false,
            layoutNames: [],
            signalHistoryCount: 1,
            latestEvidenceSummary: 'HasData=false; IsOnLayout=false'
        });

        const element = createDashboard();
        await seedDashboardData();

        const recommendationButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const nextStepButton = Array.from(recommendationButtons).find((button) => button.label === 'Check Next Step');
        nextStepButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        expect(document.body.textContent).toContain('Recommended Next Steps');

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const runButton = Array.from(buttons).find((button) => button.label === 'Run Full Scan');
        runButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const modalButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const startButton = Array.from(modalButtons).find((button) => button.label === 'Start Scan');
        startButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(document.body.textContent).not.toContain('Recommended Next Steps');

        deferred.resolve({ success: true, jobId: '707xx0000011111' });
        await flushPromises();
        await flushPromises();
    });

    it('stores only a one-time override when opening readiness from the dashboard', async () => {
        const element = createDashboard();
        await seedDashboardData();
        element.setupGuidanceItems = [
            { key: 'namedCredential', status: 'Warning', whatToDo: 'Open readiness.' }
        ];
        element.setupComplete = true;
        await flushPromises();
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const readinessButton = Array.from(buttons).find((button) => button.label === 'Open Readiness');
        readinessButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(
            window.sessionStorage.getItem(`clarity360.setup.overrideStep.${window.location.hostname}`)
        ).toBe('2');
        expect(
            window.sessionStorage.getItem(`clarity360.setup.currentStep.${window.location.hostname}`)
        ).toBeNull();
    });

    it('opens next steps and deletes an eligible field through the modal action', async () => {
        deleteCustomField.mockResolvedValue({
            success: true,
            deleted: true,
            message: 'Field deleted successfully.'
        });

        const element = createDashboard();
        await seedDashboardData();

        const recommendationButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const nextStepButton = Array.from(recommendationButtons).find((button) => button.label === 'Check Next Step');
        nextStepButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        expect(document.body.textContent).toContain('Recommended Next Steps');
        expect(document.body.textContent).toContain('Eligible for deletion');
        expect(getFieldDetailEvidence).toHaveBeenCalledWith({ fieldKey: 'Account.Legacy_Flag__c' });

        const modalButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const deleteButton = Array.from(modalButtons).find((button) => button.label === 'Delete Field');
        deleteButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(deleteCustomField).toHaveBeenCalledWith({ fieldKey: 'Account.Legacy_Flag__c' });
    });

    it('renders layout evidence returned from lazy detail fetch', async () => {
        getFieldDetailEvidence.mockResolvedValue({
            fieldKey: 'Account.Legacy_Flag__c',
            isOnLayout: true,
            layoutNames: ['Account Layout'],
            signalHistoryCount: 3,
            latestEvidenceSummary: 'HasData=false; IsOnLayout=true'
        });

        const element = createDashboard();
        await seedDashboardData();

        const recommendationButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const nextStepButton = Array.from(recommendationButtons).find((button) => button.label === 'Check Next Step');
        nextStepButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        expect(document.body.textContent).toContain('On Layout');
        expect(document.body.textContent).toContain('Yes');
        expect(document.body.textContent).toContain('Account Layout');
        expect(document.body.textContent).toContain('3');
    });

    it('renders monitoring scan trends and event publishers', async () => {
        getMonitoringSnapshot.mockResolvedValue({
            asyncApexUsedPct: 42,
            asyncJobsToday: 9,
            queueableActiveCount: 1,
            batchActiveCount: 0,
            scheduledJobCount: 2,
            platformEventCount: 1,
            activePlatformSubscriberCount: 3,
            activePlatformPublisherCount: 2,
            limitMetrics: [],
            platformEvents: [
                {
                    id: 'a01xx000000001',
                    displayName: 'CustomerSignal__e',
                    activePublisherCount: 2,
                    activeSubscriberCount: 3,
                    referenceCount: 5,
                    lastScannedOn: '2026-03-17T00:00:00.000Z'
                }
            ],
            scanTrends: [
                {
                    scanJobId: 'a02xx000000001',
                    jobType: 'Usage Scan',
                    finishedOn: '2026-03-17T00:00:00.000Z',
                    avgCpuMs: 150,
                    avgHeapKb: 60,
                    totalSoqlQueries: 35,
                    asyncActiveJobs: 4,
                    dailyApiRequestsPct: 18.5,
                    dailyAsyncApexPct: 25
                }
            ]
        });

        const element = createDashboard();
        await seedDashboardData();
        element.activeDashboardTab = 'monitoring';
        await flushPromises();

        expect(document.body.textContent).toContain('Platform Events');
        expect(document.body.textContent).toContain('Latest Scan');
        expect(document.body.textContent).toContain('Async Jobs Today');
        expect(document.body.textContent).toContain('9');
    });

    it('treats inactive trigger rows with coverage text as priority items', async () => {
        getGlobalComponentSections.mockResolvedValue([
            {
                name: 'Trigger',
                label: 'Trigger (1)',
                rows: [
                    {
                        key: 'Trigger|LegacyAccountTrigger|Account|GLOBAL.TRIGGER.LegacyAccountTrigger',
                        fieldKey: 'GLOBAL.TRIGGER.LegacyAccountTrigger',
                        componentType: 'Trigger',
                        componentName: 'LegacyAccountTrigger',
                        objectName: 'Account',
                        status: 'Inactive | Coverage Pending',
                        detail: 'Trigger metadata | Coverage pending'
                    }
                ]
            }
        ]);

        createDashboard();
        await seedDashboardData();
        await flushPromises();

        expect(getGlobalComponentSections).toHaveBeenCalled();
        expect(document.body.textContent).toContain('Trigger (1)');
    });
});
