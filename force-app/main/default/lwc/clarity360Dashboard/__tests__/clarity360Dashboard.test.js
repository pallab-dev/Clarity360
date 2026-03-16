import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import Clarity360Dashboard from 'c/clarity360Dashboard';

import getDashboardSummary from '@salesforce/apex/Clarity360DashboardController.getDashboardSummary';
import getRecommendations from '@salesforce/apex/Clarity360DashboardController.getRecommendations';
import getGlobalComponentSections from '@salesforce/apex/Clarity360DashboardController.getGlobalComponentSections';
import getMetadataComponents from '@salesforce/apex/Clarity360DashboardController.getMetadataComponents';
import getMonitoringSnapshot from '@salesforce/apex/Clarity360DashboardController.getMonitoringSnapshot';
import getRecentJobs from '@salesforce/apex/Clarity360DashboardController.getRecentJobs';
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
    '@salesforce/apex/Clarity360DashboardController.getRecentJobs',
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

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

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
            queueableActiveCount: 0,
            batchActiveCount: 0,
            scheduledJobCount: 0,
            platformEventCount: 0,
            activePlatformSubscriberCount: 0,
            limitMetrics: [],
            platformEvents: []
        });
        getRecentJobs.mockResolvedValue({ jobs: [], totalCount: 0, pageNumber: 1 });
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
        jest.clearAllMocks();
    });

    it('renders summary and recommendation content from wire data', async () => {
        createDashboard();
        await seedDashboardData();

        expect(document.body.textContent).toContain('Cleanliness Score');
        expect(document.body.textContent).toContain('92%');
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

        expect(runFullScan).toHaveBeenCalled();
        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.variant).toBe('success');
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

        expect(document.body.textContent).toContain('Recommended Next Steps');
        expect(document.body.textContent).toContain('Eligible for deletion');

        const modalButtons = element.shadowRoot.querySelectorAll('lightning-button');
        const deleteButton = Array.from(modalButtons).find((button) => button.label === 'Delete Field');
        deleteButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        expect(deleteCustomField).toHaveBeenCalledWith({ fieldKey: 'Account.Legacy_Flag__c' });
    });
});
