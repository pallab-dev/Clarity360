import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';

import getDashboardSummary from '@salesforce/apex/Clarity360DashboardController.getDashboardSummary';
import getRecommendations from '@salesforce/apex/Clarity360DashboardController.getRecommendations';
import getGlobalComponentSections from '@salesforce/apex/Clarity360DashboardController.getGlobalComponentSections';
import getMetadataComponents from '@salesforce/apex/Clarity360DashboardController.getMetadataComponents';
import getMonitoringSnapshot from '@salesforce/apex/Clarity360DashboardController.getMonitoringSnapshot';
import getMonitoringDetail from '@salesforce/apex/Clarity360DashboardController.getMonitoringDetail';
import getRecentJobs from '@salesforce/apex/Clarity360DashboardController.getRecentJobs';
import getAdminHygieneSnapshot from '@salesforce/apex/Clarity360DashboardController.getAdminHygieneSnapshot';
import getFieldDetailEvidence from '@salesforce/apex/Clarity360DashboardController.getFieldDetailEvidence';
import runFullScan from '@salesforce/apex/Clarity360DashboardController.runFullScanV2';
import deleteCustomField from '@salesforce/apex/Clarity360DashboardController.deleteCustomField';
import getAgentAssistantAvailability from '@salesforce/apex/Clarity360DashboardController.getAgentAssistantAvailability';
import askAgentAssistant from '@salesforce/apex/Clarity360DashboardController.askAgentAssistant';
import isSetupComplete from '@salesforce/apex/Clarity360SetupWizardController.isSetupComplete';
import getSetupState from '@salesforce/apex/Clarity360SetupWizardController.getSetupState';

const TOUR_STORAGE_KEY_PREFIX = 'clarity360.dashboard.tour.dismissed';
const SETUP_STEP_STORAGE_KEY_PREFIX = 'clarity360.setup.overrideStep';
const SETUP_NAV_ITEM_API_NAME = 'Clarity360_Setup';
const SETUP_STEP_WELCOME = 1;
const SETUP_STEP_READINESS = 2;
const SETUP_STEP_CONFIGURATION = 3;
const TOUR_SETS = {
    usage: [
        {
            title: 'Usage Summary',
            body: 'Start here. These tiles summarize the current Clarity360 inventory health, evidence volume, and open recommendations.',
            targetId: 'usage-summary'
        },
        {
            title: 'Usage Actions',
            body: 'Use these top actions to run a full scan, refresh the workspace, or switch between Standard and AI mode.',
            targetId: 'dashboard-actions'
        },
        {
            title: 'Inventory Workspace',
            body: 'Use search and filters here to focus on the highest-priority object and metadata items.',
            targetId: 'usage-filters'
        },
        {
            title: 'Object Recommendations',
            body: 'Open a recommendation to see the evidence, next steps, and whether the field is safe to deprecate or delete.',
            targetId: 'usage-object-recommendations'
        },
        {
            title: 'Global Components',
            body: 'This section brings flows, triggers, validation rules, and other global components into the same review workspace so you can inspect non-field cleanup decisions.',
            targetId: 'usage-global-components'
        },
        {
            title: 'Admin And Access',
            body: 'Review inactive users and clearly actionable access artifacts here. These are cleanup findings, not runtime consumption metrics.',
            targetId: 'usage-hygiene'
        },
        {
            title: 'Job Issues',
            body: 'This section only shows Clarity360 scan jobs that logged an error. Review it when a scan result looks incomplete.',
            targetId: 'usage-job-issues'
        }
    ],
    monitoring: [
        {
            title: 'Monitoring Overview',
            targetId: 'monitoring-overview'
        },
        {
            title: 'Salesforce Reported',
            body: 'This view shows live runtime activity such as async jobs, queueable load, batch load, and scheduled jobs. Inspect any row for details.',
            targetId: 'monitoring-signals',
            view: 'signals'
        },
        {
            title: 'Governor Limits',
            body: 'These rows come from Salesforce org limits. Use them to understand actual platform-reported capacity usage.',
            targetId: 'monitoring-limits',
            view: 'limits'
        },
        {
            title: 'Latest Scan',
            body: 'These rows show what Clarity360 captured during recent scan transactions, such as CPU, heap, SOQL, and async snapshots.',
            targetId: 'monitoring-latest',
            view: 'latest'
        },
        {
            title: 'Platform Event Monitoring',
            body: 'This section shows discovered platform events, even if they currently have no publishers or subscribers, and lets you drill into why each row is visible.',
            targetId: 'monitoring-events',
            view: 'events'
        }
    ]
};

const JOB_COLUMNS = [
    { label: 'Job', fieldName: 'Name', type: 'text' },
    { label: 'Type', fieldName: 'JobType__c', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Progress %', fieldName: 'ProgressPct__c', type: 'number', typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } },
    { label: 'Started', fieldName: 'StartedOn__c', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } },
    { label: 'Finished', fieldName: 'FinishedOn__c', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } }
];

const JOB_ISSUE_COLUMNS = [
    { label: 'Job', fieldName: 'Name', type: 'text' },
    { label: 'Type', fieldName: 'JobType__c', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Finished', fieldName: 'FinishedOn__c', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } },
    { label: 'Error', fieldName: 'ErrorMessage__c', type: 'text', wrapText: true }
];

const METADATA_COLUMNS = [
    { label: 'Type', fieldName: 'componentType', type: 'text' },
    { label: 'API Name', fieldName: 'apiName', type: 'text' },
    { label: 'References', fieldName: 'referenceCount', type: 'number' },
    { label: 'Active Subscribers', fieldName: 'activeSubscriberCount', type: 'number' },
    { label: 'Active Publishers', fieldName: 'activePublisherCount', type: 'number' },
    { label: 'Monitoring', fieldName: 'monitoringEligibleLabel', type: 'text' },
    { label: 'Last Scanned', fieldName: 'lastScannedOn', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } }
];

const MONITORING_OVERVIEW_COLUMNS = [
    { label: 'Metric', fieldName: 'label', type: 'text' },
    { label: 'Current Value', fieldName: 'valueLabel', type: 'text' },
    { label: 'What It Means', fieldName: 'meaning', type: 'text', wrapText: true },
    { label: 'Source', fieldName: 'sourceLabel', type: 'text' }
];

const SALESFORCE_SIGNAL_COLUMNS = [
    { label: 'Signal', fieldName: 'label', type: 'text' },
    { label: 'Current Value', fieldName: 'valueLabel', type: 'text' },
    { label: 'Meaning', fieldName: 'meaning', type: 'text', wrapText: true },
    { label: 'Source', fieldName: 'sourceLabel', type: 'text' },
    {
        type: 'button',
        fixedWidth: 110,
        typeAttributes: { label: 'Inspect', name: 'details', variant: 'base' }
    }
];

const GOVERNOR_LIMIT_COLUMNS = [
    { label: 'Metric', fieldName: 'label', type: 'text' },
    { label: 'Used', fieldName: 'usedLabel', type: 'text' },
    { label: 'Limit', fieldName: 'limitLabel', type: 'text' },
    { label: 'Remaining', fieldName: 'remainingLabel', type: 'text' },
    { label: '% Used', fieldName: 'pctLabel', type: 'text' },
    {
        type: 'button',
        fixedWidth: 110,
        typeAttributes: { label: 'Explain', name: 'details', variant: 'base' }
    }
];

const SCAN_TREND_COLUMNS = [
    { label: 'Scan', fieldName: 'jobType', type: 'text' },
    { label: 'Finished', fieldName: 'finishedLabel', type: 'text' },
    { label: 'Avg CPU (ms)', fieldName: 'avgCpuLabel', type: 'text' },
    { label: 'Avg Heap (KB)', fieldName: 'avgHeapLabel', type: 'text' },
    { label: 'Total SOQL', fieldName: 'soqlLabel', type: 'text' },
    { label: 'Async Jobs', fieldName: 'asyncJobsLabel', type: 'text' },
    { label: 'API %', fieldName: 'apiPctLabel', type: 'text' },
    { label: 'Async %', fieldName: 'asyncPctLabel', type: 'text' },
    {
        type: 'button',
        fixedWidth: 110,
        typeAttributes: { label: 'Details', name: 'details', variant: 'base' }
    }
];

const PLATFORM_EVENT_COLUMNS = [
    { label: 'Event', fieldName: 'displayName', type: 'text' },
    { label: 'State', fieldName: 'activityState', type: 'text' },
    { label: 'Publishers', fieldName: 'publisherLabel', type: 'text' },
    { label: 'Subscribers', fieldName: 'subscriberLabel', type: 'text' },
    { label: 'References', fieldName: 'referenceLabel', type: 'text' },
    { label: 'Last Scanned', fieldName: 'lastScannedLabel', type: 'text' },
    {
        type: 'button',
        fixedWidth: 110,
        typeAttributes: { label: 'Details', name: 'details', variant: 'base' }
    }
];

const HYGIENE_COLUMNS = [
    { label: 'Name', fieldName: 'name', type: 'text' },
    { label: 'Detail', fieldName: 'detail', type: 'text', wrapText: true },
    { label: 'Context', fieldName: 'context', type: 'text', wrapText: true }
];

const USER_FIELDS = ['User.Name'];

export default class Clarity360Dashboard extends NavigationMixin(LightningElement) {
    JOBS_PAGE_SIZE = 5;
    GOVERNOR_WARNING_PCT = 75;

    @track summary = {
        cleanlinessScore: 0,
        activeInventoryCount: 0,
        usageSignalCount: 0,
        openRecommendationCount: 0,
        metadataComponentCount: 0,
        referencedMetadataComponentCount: 0,
        platformEventComponentCount: 0,
        latestJobStatus: '-'
    };
    @track allRecommendations = [];
    @track recommendations = [];
    @track globalComponentSections = [];
    @track metadataComponents = [];
    @track jobs = [];
    @track jobsTotalCount = 0;
    @track jobsPageNumber = 1;
    @track expandedRecommendationGroups = [];
    @track expandedMetadataGroups = [];
    @track expandedGlobalGroups = [];

    @track actionFilter = '';
    @track statusFilter = '';
    @track searchFilter = '';
    @track inventoryHealthFilter = 'priority';
    @track isBusy = false;
    @track pendingOperationLabel = '';
    @track pendingOperationDetail = '';
    @track isRefreshingDashboard = false;
    @track isLaunchingFullScan = false;
    @track isSummaryLoading = false;
    @track isInventoryLoading = false;
    @track isJobsLoading = false;
    @track isMonitoringLoading = false;
    @track activeMonitoringView = 'signals';
    @track hasLoadedSummary = false;
    @track hasLoadedJobs = false;
    @track dataWarning = '';
    @track isUsageModalOpen = false;
    @track selectedUsage = null;
    @track isUsageDetailLoading = false;
    @track isSearchModalOpen = false;
    @track searchResults = [];
    @track searchSuggestions = [];
    @track isFullScanModalOpen = false;
    @track generateReportOnFullScan = true;
    @track fullScanReportRecipient = '';
    @track setupComplete = true;
    @track readinessOverallStatus = 'Unknown';
    @track setupGuidanceItems = [];
    @track setupChecksTotal = 0;
    @track setupChecksReady = 0;
    @track isSetupGuidanceBusy = false;
    @track assistantAvailable = false;
    @track assistantStatusMessage = '';
    @track currentMode = 'Standard';
    @track activeDashboardTab = 'usage';
    @track isChatOpen = false;
    @track chatInput = '';
    @track chatMessages = [];
    @track isChatBusy = false;
    @track chatPendingContext = '';
    @track isTourOpen = false;
    @track tourMode = 'usage';
    @track currentTourStepIndex = 0;
    @track tourCoachmarkStyle = '';
    @track tourCoachmarkDock = 'tour-coachmark-bottom';
    @track isMonitoringDetailOpen = false;
    @track isMonitoringDetailLoading = false;
    @track monitoringDetail = null;
    @track monitoringSnapshot = {
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
    };
    @track adminHygieneSnapshot = {
        inactiveUserCount: 0,
        unusedProfileCount: 0,
        unassignedPermissionSetCount: 0,
        unassignedPermissionSetGroupCount: 0,
        emptyRoleCount: 0,
        emptyGroupOrQueueCount: 0,
        sections: []
    };

    summaryWireResult;
    recommendationsWireResult;
    metadataWireResult;
    recommendationGroupsCache;
    recommendationGroupsCacheKey;
    globalGroupsInitialized = false;
    loadingCounters = {
        summary: 0,
        inventory: 0,
        jobs: 0,
        monitoring: 0
    };
    metadataColumns = METADATA_COLUMNS;
    jobColumns = JOB_COLUMNS;
    jobIssueColumns = JOB_ISSUE_COLUMNS;
    hygieneColumns = HYGIENE_COLUMNS;
    monitoringOverviewColumns = MONITORING_OVERVIEW_COLUMNS;
    salesforceSignalColumns = SALESFORCE_SIGNAL_COLUMNS;
    governorLimitColumns = GOVERNOR_LIMIT_COLUMNS;
    scanTrendColumns = SCAN_TREND_COLUMNS;
    platformEventColumns = PLATFORM_EVENT_COLUMNS;
    monitoringDetailCache = new Map();
    activeTourTargetElement;
    userDisplayName = '';
    viewportTourSyncHandler;
    pendingTourSync = false;

    actionOptions = [
        { label: 'All Actions', value: '' },
        { label: 'Deprecate', value: 'Deprecate' },
        { label: 'Investigate Dependencies', value: 'Investigate Dependencies' }
    ];

    statusOptions = [
        { label: 'All Statuses', value: '' },
        { label: 'Open', value: 'Open' },
        { label: 'Accepted', value: 'Accepted' },
        { label: 'Dismissed', value: 'Dismissed' }
    ];

    inventoryHealthOptions = [
        { label: 'Priority View', value: 'priority' },
        { label: 'All Inventory States', value: '' },
        { label: 'Needs Attention', value: 'attention' },
        { label: 'Inactive Only', value: 'inactive' },
        { label: 'Coverage Pending', value: 'coverage_pending' },
        { label: 'Healthy Only', value: 'healthy' }
    ];

    modeOptions = [
        { label: 'Standard Mode', value: 'Standard' },
        { label: 'AI Mode', value: 'AI' }
    ];

    connectedCallback() {
        this.viewportTourSyncHandler = () => {
            if (this.isTourOpen && this.activeTourTargetElement) {
                this.positionTourCoachmark(this.activeTourTargetElement);
            }
        };
        window.addEventListener('resize', this.viewportTourSyncHandler);
        window.addEventListener('scroll', this.viewportTourSyncHandler, true);
        this.loadSetupState();
        this.loadAgentAssistantAvailability();
        this.refreshJobs(1);
        this.loadMonitoringSnapshot();
        this.loadAdminHygieneSnapshot();
        this.refreshGlobalComponents();
        this.openTourIfNeeded();
    }

    disconnectedCallback() {
        if (this.viewportTourSyncHandler) {
            window.removeEventListener('resize', this.viewportTourSyncHandler);
            window.removeEventListener('scroll', this.viewportTourSyncHandler, true);
        }
    }

    async loadSetupState() {
        try {
            this.isSetupGuidanceBusy = true;
            const completeFlag = await isSetupComplete();
            const state = await getSetupState();
            this.setupComplete = completeFlag === true || state?.isSetupComplete === true;
            this.applySetupGuidance(state);
            if (this.setupComplete === false) {
                this.jobs = [];
                this.jobsTotalCount = 0;
            }
        } catch {
            this.setupComplete = true;
            this.readinessOverallStatus = 'Unknown';
            this.setupGuidanceItems = [];
            this.setupChecksTotal = 0;
            this.setupChecksReady = 0;
        } finally {
            this.isSetupGuidanceBusy = false;
        }
    }

    @wire(getDashboardSummary)
    wiredSummary(result) {
        this.summaryWireResult = result;
        if (result.data) {
            this.hasLoadedSummary = true;
            this.summary = {
                ...result.data,
                cleanlinessScore: this.toFixedNumber(result.data.cleanlinessScore)
            };
            this.dataWarning = this.summary.latestJobStatus === 'Partial' ? 'Latest run completed with partial results.' : '';
        } else if (result.error) {
            this.hasLoadedSummary = true;
            this.summary = {
                cleanlinessScore: 0,
                activeInventoryCount: 0,
                usageSignalCount: 0,
                openRecommendationCount: 0,
                metadataComponentCount: 0,
                referencedMetadataComponentCount: 0,
                platformEventComponentCount: 0,
                latestJobStatus: '-'
            };
            this.dataWarning = '';
            this.showError(result.error, 'Failed to load summary');
        }
    }

    @wire(getRecord, { recordId: USER_ID, fields: USER_FIELDS })
    wiredUserRecord({ data }) {
        const fullName = data?.fields?.Name?.value;
        this.userDisplayName = fullName ? String(fullName).trim() : '';
    }

    @wire(getRecommendations, {
        actionFilter: '$actionFilter',
        statusFilter: '$statusFilter',
        rowLimit: 500
    })
    wiredRecommendations(result) {
        this.recommendationsWireResult = result;
        if (result.data) {
            this.allRecommendations = Array.isArray(result.data) ? result.data : [];
            this.recommendations = this.allRecommendations.filter(
                (row) =>
                    !String(row?.fieldKey || '').startsWith('GLOBAL.') &&
                    String(row?.action || '').toLowerCase() !== 'keep'
            );
            this.invalidateRecommendationGroupsCache();
        } else if (result.error) {
            this.allRecommendations = [];
            this.recommendations = [];
            this.invalidateRecommendationGroupsCache();
            this.showError(result.error, 'Failed to load recommendations');
        }
    }

    @wire(getMetadataComponents, {
        typeFilter: '',
        rowLimit: 25
    })
    wiredMetadataComponents(result) {
        this.metadataWireResult = result;
        if (result.data) {
            this.metadataComponents = (Array.isArray(result.data) ? result.data : []).map((row) => ({
                ...row,
                monitoringEligibleLabel: row?.monitoringEligible ? 'Eligible' : 'Inventory Only',
                lastScannedDisplay: this.formatDate(row?.lastScannedOn),
                activePublisherCount: this.toInteger(row?.activePublisherCount),
                whyVisible: row?.whyVisible || 'Shown because it was included in metadata inventory.',
                nextStep: row?.nextStep || 'Refresh after the next scan if you need more evidence.'
            }));
        } else if (result.error) {
            this.metadataComponents = [];
            this.showError(result.error, 'Failed to load metadata inventory');
        }
    }

    get hasRecommendations() {
        return this.filteredRecommendations.length > 0;
    }

    get hasMetadataComponents() {
        return this.filteredMetadataComponents.length > 0;
    }

    get hasMetadataSection() {
        return true;
    }

    get hygieneSections() {
        return (this.adminHygieneSnapshot?.sections || []).map((section) => ({
            ...section,
            hasRows: Array.isArray(section?.rows) && section.rows.length > 0,
            countLabel: `${this.toInteger(section?.totalCount)}`
        })).filter((section) => this.toInteger(section?.totalCount) > 0);
    }

    get hasHygieneFindings() {
        return this.hygieneSections.some((section) => this.toInteger(section?.totalCount) > 0);
    }

    get hygieneSummaryCards() {
        return [
            { key: 'inactiveUsers', label: 'Inactive Users', value: `${this.toInteger(this.adminHygieneSnapshot?.inactiveUserCount)}` },
            { key: 'unassignedPermissionSets', label: 'Unassigned Permission Sets', value: `${this.toInteger(this.adminHygieneSnapshot?.unassignedPermissionSetCount)}` },
            { key: 'unassignedPermissionSetGroups', label: 'Unassigned Permission Set Groups', value: `${this.toInteger(this.adminHygieneSnapshot?.unassignedPermissionSetGroupCount)}` }
        ];
    }

    get hasGlobalComponents() {
        return this.filteredGlobalSections.length > 0;
    }

    get currentTourStep() {
        const steps = this.currentTourSteps;
        return steps[this.currentTourStepIndex] || steps[0];
    }

    get currentTourStepNumber() {
        return this.currentTourStepIndex + 1;
    }

    get tourStepCount() {
        return this.currentTourSteps.length;
    }

    get disablePreviousTourStep() {
        return this.currentTourStepIndex <= 0;
    }

    get tourNextLabel() {
        return this.currentTourStepIndex >= this.currentTourSteps.length - 1 ? 'Finish Tour' : 'Next';
    }

    get currentTourSteps() {
        return TOUR_SETS[this.tourMode] || TOUR_SETS.usage;
    }

    get globalRecommendationMap() {
        const map = new Map();
        (this.allRecommendations || []).forEach((row) => {
            const fieldKey = String(row?.fieldKey || '');
            if (fieldKey.startsWith('GLOBAL.') && String(row?.action || '').toLowerCase() !== 'keep') {
                map.set(fieldKey, row);
            }
        });
        return map;
    }

    get filteredRecommendations() {
        return (this.recommendations || [])
            .map((row) => this.enrichRecommendationRow(row))
            .filter((row) => {
                if (this.inventoryHealthFilter === 'priority') {
                    return row?.priorityRank > 0;
                }
                if (this.inventoryHealthFilter === 'coverage_pending') {
                    return row?.showCoverageHint === true;
                }
                if (this.inventoryHealthFilter === 'attention') {
                    return row?.showCoverageHint === true || row?.status === 'Open' || Number(row?.riskScore || 0) >= 60;
                }
                if (this.inventoryHealthFilter === 'healthy') {
                    return row?.showCoverageHint !== true && row?.status !== 'Open' && Number(row?.riskScore || 0) < 60;
                }
                return this.inventoryHealthFilter !== 'inactive';
            });
    }

    get filteredMetadataComponents() {
        return (this.metadataComponents || [])
            .map((row) => this.enrichMetadataRow(row))
            .filter((row) => {
                if (this.inventoryHealthFilter === 'priority') {
                    return row?.priorityRank > 0;
                }
                if (this.inventoryHealthFilter === 'attention') {
                    return row?.priorityRank >= 1;
                }
                if (this.inventoryHealthFilter === 'healthy') {
                    return row?.priorityRank === 0;
                }
                return this.inventoryHealthFilter !== 'inactive';
            });
    }

    get filteredGlobalSections() {
        return (this.globalComponentSections || [])
            .map((section) => {
                const rows = (section?.rows || [])
                    .map((row) => this.enrichGlobalComponentRow(row, this.globalRecommendationMap.get(row?.fieldKey)))
                    .filter((row) => {
                        if (this.inventoryHealthFilter === 'priority') {
                            return row?.priorityRank > 0;
                        }
                        if (this.inventoryHealthFilter === 'inactive') {
                            return this.isInactiveGlobalComponent(row);
                        }
                        if (this.inventoryHealthFilter === 'coverage_pending') {
                            return row?.showCoverageHint === true;
                        }
                        if (this.inventoryHealthFilter === 'attention') {
                            return Number(row?.priorityRank || 0) > 0;
                        }
                        if (this.inventoryHealthFilter === 'healthy') {
                            return Number(row?.priorityRank || 0) === 0;
                        }
                        return true;
                    });
                return rows.length > 0
                    ? {
                          ...section,
                          label: `${section?.name || 'Unknown'} (${rows.length})`,
                          rows
                      }
                    : null;
            })
            .filter(Boolean);
    }

    get globalSectionViewModels() {
        return this.filteredGlobalSections.map((section) => ({
            ...section,
            isOpen: (this.expandedGlobalGroups || []).includes(section.name),
            toggleIcon: (this.expandedGlobalGroups || []).includes(section.name) ? 'utility:chevrondown' : 'utility:chevronright'
        }));
    }

    get globalSectionSummaryChips() {
        return (this.filteredGlobalSections || []).map((section) => ({
            key: section?.name,
            label: `${section?.name || 'Unknown'} ${section?.count || 0}`
        }));
    }

    get normalizedSearchFilter() {
        return String(this.searchFilter || '').trim().toLowerCase();
    }

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    get hasSearchSuggestions() {
        return this.searchSuggestions.length > 0;
    }

    get searchResultsTitle() {
        const term = String(this.searchFilter || '').trim();
        return term ? `Search Results for "${term}"` : 'Search Results';
    }

    get isPriorityView() {
        return this.inventoryHealthFilter === 'priority';
    }

    get showFocusGuidance() {
        return this.isPriorityView;
    }

    get focusGuidanceMessage() {
        return 'Showing only Critical, Warning, and Needs Action items by default. Healthy or low-signal items stay hidden until you search or switch the view.';
    }

    get monitoringLimitMetrics() {
        return Array.isArray(this.monitoringSnapshot?.limitMetrics) ? this.monitoringSnapshot.limitMetrics : [];
    }

    get monitoringOverviewRows() {
        return [
            {
                id: 'async-jobs-today',
                label: 'Async Jobs Today',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.asyncJobsToday)}`,
                meaning: 'How many async Apex job records were created today in the org.',
                sourceLabel: 'AsyncApexJob'
            },
            {
                id: 'async-limit-used',
                label: 'Async Limit Used',
                valueLabel: `${Number(this.monitoringSnapshot?.asyncApexUsedPct || 0).toFixed(2)}%`,
                meaning: 'Salesforce-reported daily async Apex capacity usage from org limits.',
                sourceLabel: 'System.OrgLimits'
            },
            {
                id: 'queueable-active',
                label: 'Queueable Active',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.queueableActiveCount)}`,
                meaning: 'Queueable jobs currently active or waiting in the async job queue.',
                sourceLabel: 'AsyncApexJob'
            },
            {
                id: 'batch-active',
                label: 'Batch Active',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.batchActiveCount)}`,
                meaning: 'Batch Apex jobs currently active or queued.',
                sourceLabel: 'AsyncApexJob'
            },
            {
                id: 'scheduled-jobs',
                label: 'Scheduled Jobs',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.scheduledJobCount)}`,
                meaning: 'Current org-wide scheduled Apex job count.',
                sourceLabel: 'CronTrigger'
            },
            {
                id: 'platform-events',
                label: 'Platform Events',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.platformEventCount)}`,
                meaning: 'Discovered active platform event metadata rows currently visible to monitoring.',
                sourceLabel: 'Metadata inventory'
            },
            {
                id: 'event-subscribers',
                label: 'Event Subscribers',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.activePlatformSubscriberCount)}`,
                meaning: 'Total active subscriber signals found across discovered platform events.',
                sourceLabel: 'Metadata inventory'
            },
            {
                id: 'event-publishers',
                label: 'Event Publishers',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.activePlatformPublisherCount)}`,
                meaning: 'Total active publisher signals found across discovered platform events.',
                sourceLabel: 'Metadata inventory'
            }
        ];
    }

    get salesforceSignalRows() {
        return [
            {
                key: 'async-jobs-today',
                label: 'Async Jobs Today',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.asyncJobsToday)}`,
                meaning: 'Async Apex job records created today in the org.',
                sourceLabel: 'AsyncApexJob',
                detailType: 'salesforceSignal',
                recordKey: 'async-jobs-today'
            },
            {
                key: 'queueable-active',
                label: 'Queueable Active',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.queueableActiveCount)}`,
                meaning: 'Queueable jobs currently active or waiting in the async queue.',
                sourceLabel: 'AsyncApexJob',
                detailType: 'salesforceSignal',
                recordKey: 'queueable-active'
            },
            {
                key: 'batch-active',
                label: 'Batch Active',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.batchActiveCount)}`,
                meaning: 'Batch Apex jobs currently active or queued.',
                sourceLabel: 'AsyncApexJob',
                detailType: 'salesforceSignal',
                recordKey: 'batch-active'
            },
            {
                key: 'scheduled-jobs',
                label: 'Scheduled Jobs',
                valueLabel: `${this.toInteger(this.monitoringSnapshot?.scheduledJobCount)}`,
                meaning: 'Current org-wide scheduled Apex job count.',
                sourceLabel: 'CronTrigger',
                detailType: 'salesforceSignal',
                recordKey: 'scheduled-jobs'
            }
        ];
    }

    get dailyAsyncApexMetric() {
        return (this.monitoringLimitMetrics || []).find((metric) => String(metric?.label || '').toLowerCase() === 'daily async apex') || null;
    }

    get dailyAsyncApexUsedValue() {
        return this.toInteger(this.dailyAsyncApexMetric?.usedValue);
    }

    get dailyAsyncApexUsedLabel() {
        return this.formatMonitoringNumber(this.dailyAsyncApexMetric?.usedValue);
    }

    get monitoringOverviewCards() {
        return [
            {
                key: 'salesforce-signals',
                label: 'Salesforce Reported',
                value: 'Runtime Signals',
                note: 'Async activity, queue load, batch load, and scheduled jobs.',
                tone: 'sage'
            },
            {
                key: 'governor-limits',
                label: 'Governor Limits',
                value: this.topGovernorLimitValue,
                note: this.topGovernorLimitNote,
                tone: 'amber'
            },
            {
                key: 'latest-scan',
                label: 'Latest Scan',
                value: this.latestScanOverviewValue,
                note: this.latestScanOverviewNote,
                tone: 'iris'
            },
            {
                key: 'platform-events',
                label: 'Platform Events',
                value: `${this.toInteger(this.monitoringSnapshot?.platformEventCount)} tracked`,
                note: `${this.toInteger(this.monitoringSnapshot?.activePlatformPublisherCount)} publishers, ${this.toInteger(this.monitoringSnapshot?.activePlatformSubscriberCount)} subscribers.`,
                tone: 'rose'
            }
        ];
    }

    get monitoringSignalRows() {
        return [
            {
                key: 'async-jobs-today',
                label: 'Async Jobs Today',
                value: `${this.toInteger(this.monitoringSnapshot?.asyncJobsToday)}`,
                note: 'Async Apex jobs created today.',
                strengthPct: this.normalizeSignalStrength(this.monitoringSnapshot?.asyncJobsToday, 50)
            },
            {
                key: 'queueable-active',
                label: 'Queueable Active',
                value: `${this.toInteger(this.monitoringSnapshot?.queueableActiveCount)}`,
                note: 'Queueable jobs active or waiting now.',
                strengthPct: this.normalizeSignalStrength(this.monitoringSnapshot?.queueableActiveCount, 25)
            },
            {
                key: 'batch-active',
                label: 'Batch Active',
                value: `${this.toInteger(this.monitoringSnapshot?.batchActiveCount)}`,
                note: 'Batch Apex jobs active or queued now.',
                strengthPct: this.normalizeSignalStrength(this.monitoringSnapshot?.batchActiveCount, 25)
            },
            {
                key: 'scheduled-jobs',
                label: 'Scheduled Jobs',
                value: `${this.toInteger(this.monitoringSnapshot?.scheduledJobCount)}`,
                note: 'Current org-wide scheduled Apex jobs.',
                strengthPct: this.normalizeSignalStrength(this.monitoringSnapshot?.scheduledJobCount, 25)
            }
        ].map((row) => ({
            ...row,
            barStyle: `width:${row.strengthPct}%`
        }));
    }

    get monitoringKpiCards() {
        return this.monitoringOverviewCards.map((card) => ({
            ...card,
            className: `monitoring-stat-card monitoring-stat-card-${card.tone || 'default'}`
        }));
    }

    get latestScanTitle() {
        const latest = this.latestMonitoringTrend;
        if (!latest) {
            return 'No recent scan';
        }
        return `${this.formatMonitoringNumber(latest.avgCpuMs)} ms CPU`;
    }

    get latestScanSupportLabel() {
        const latest = this.latestMonitoringTrend;
        if (!latest) {
            return 'A scan snapshot will appear here after the next completed scan.';
        }
        return `Finished ${this.formatDateTime(latest?.finishedOn)}`;
    }

    get latestScanOverviewValue() {
        const latest = this.latestMonitoringTrend;
        if (!latest) {
            return 'No data';
        }
        const asyncPct = Number(latest?.dailyAsyncApexPct);
        if (Number.isFinite(asyncPct) && asyncPct > 0) {
            return `${asyncPct.toFixed(2)}% async`;
        }
        return `${this.formatMonitoringNumber(latest?.avgCpuMs)} ms CPU`;
    }

    get latestScanOverviewNote() {
        const latest = this.latestMonitoringTrend;
        if (!latest) {
            return 'Clarity360 scan consumption appears here after the next completed scan.';
        }
        return `SOQL ${this.formatMonitoringNumber(latest?.totalSoqlQueries)} | Heap ${this.formatMonitoringNumber(latest?.avgHeapKb)} KB`;
    }

    get topGovernorLimitMetric() {
        return this.governorLimitRows
            .slice()
            .sort((left, right) => Number(right?.pctUsed || 0) - Number(left?.pctUsed || 0))[0] || null;
    }

    get topGovernorLimitValue() {
        return this.topGovernorLimitMetric?.pctLabel || '0.00%';
    }

    get topGovernorLimitNote() {
        if (!this.topGovernorLimitMetric) {
            return 'No governor limit snapshot available yet.';
        }
        return `${this.topGovernorLimitMetric.label} is currently the highest monitored org limit.`;
    }

    get monitoringViewOptions() {
        return [
            { key: 'signals', label: 'Salesforce Reported' },
            { key: 'limits', label: 'Governor Limits' },
            { key: 'latest', label: 'Latest Scan' },
            { key: 'events', label: 'Platform Events' }
        ];
    }

    get monitoringViewButtons() {
        return this.monitoringViewOptions.map((option) => ({
            ...option,
            variant: this.activeMonitoringView === option.key ? 'brand' : 'neutral'
        }));
    }

    get greetingLabel() {
        const hour = new Date().getHours();
        if (hour < 12) {
            return 'Good Morning';
        }
        if (hour < 18) {
            return 'Good Afternoon';
        }
        return 'Good Evening';
    }

    get greetingName() {
        if (!this.userDisplayName) {
            return 'there';
        }
        return this.userDisplayName.split(' ')[0];
    }

    get usageHeaderDateLabel() {
        try {
            return new Intl.DateTimeFormat('en-US', {
                weekday: 'long',
                month: 'short',
                day: 'numeric'
            }).format(new Date());
        } catch {
            return '';
        }
    }

    get dashboardContextLabel() {
        return this.activeDashboardTab === 'monitoring' ? 'Monitoring Workspace' : 'Usage Workspace';
    }

    get dashboardShellSubtitle() {
        return this.activeDashboardTab === 'monitoring'
            ? 'Track live operational signals, platform limits, and latest scan health from one clear operations view.'
            : 'Review inventory health, usage evidence, and recommendation decisions from one clean dashboard.';
    }

    get platformEventRows() {
        return Array.isArray(this.monitoringSnapshot?.platformEvents) ? this.monitoringSnapshot.platformEvents : [];
    }

    get scanTrendRows() {
        return Array.isArray(this.monitoringSnapshot?.scanTrends) ? this.monitoringSnapshot.scanTrends : [];
    }

    get governorLimitRows() {
        return this.monitoringLimitMetrics.map((metric) => ({
            ...metric,
            usedLabel: this.formatMonitoringNumber(metric?.usedValue),
            limitLabel: this.formatMonitoringNumber(metric?.limitValue),
            remainingLabel: this.formatMonitoringNumber(metric?.remainingValue),
            pctLabel: `${Number(metric?.pctUsed || 0).toFixed(2)}%`,
            detailType: 'governorLimit'
        }));
    }

    get scanTrendTableRows() {
        return this.scanTrendRows.map((row) => ({
            ...row,
            finishedLabel: this.formatDateTime(row?.finishedOn),
            avgCpuLabel: this.formatMonitoringNumber(row?.avgCpuMs),
            avgHeapLabel: this.formatMonitoringNumber(row?.avgHeapKb),
            soqlLabel: this.formatMonitoringNumber(row?.totalSoqlQueries),
            asyncJobsLabel: this.formatMonitoringNumber(row?.asyncActiveJobs),
            apiPctLabel: `${Number(row?.dailyApiRequestsPct || 0).toFixed(2)}%`,
            asyncPctLabel: `${Number(row?.dailyAsyncApexPct || 0).toFixed(2)}%`,
            detailType: 'scanTrend',
            recordKey: row?.scanJobId
        }));
    }

    get platformEventTableRows() {
        return this.platformEventRows.map((row) => {
            const publishers = this.toInteger(row?.activePublisherCount);
            const subscribers = this.toInteger(row?.activeSubscriberCount);
            const references = this.toInteger(row?.referenceCount);
            return {
                ...row,
                publisherLabel: `${publishers}`,
                subscriberLabel: `${subscribers}`,
                referenceLabel: `${references}`,
                lastScannedLabel: this.formatDateTime(row?.lastScannedOn),
                activityState: publishers === 0 && subscribers === 0 && references === 0 ? 'No usage detected' : 'In use or referenced',
                detailType: 'platformEvent',
                recordKey: row?.id
            };
        });
    }

    get hasPlatformEvents() {
        return this.platformEventRows.length > 0;
    }

    get hasScanTrends() {
        return this.scanTrendRows.length > 0;
    }

    get latestMonitoringTrend() {
        return this.hasScanTrends ? this.scanTrendRows[0] : null;
    }

    get monitoringTrendSummary() {
        const latest = this.latestMonitoringTrend;
        if (!latest) {
            return 'Per-scan CPU, heap, SOQL, and async trend data will appear after the next completed scan.';
        }
        const parts = [];
        if (latest.avgCpuMs !== null && latest.avgCpuMs !== undefined) {
            parts.push(`Avg CPU ${this.toFixedNumber(latest.avgCpuMs)} ms`);
        }
        if (latest.totalSoqlQueries !== null && latest.totalSoqlQueries !== undefined) {
            parts.push(`Total SOQL ${latest.totalSoqlQueries}`);
        }
        if (latest.asyncActiveJobs !== null && latest.asyncActiveJobs !== undefined) {
            parts.push(`Async jobs ${latest.asyncActiveJobs}`);
        }
        return parts.join(' | ');
    }

    get latestTrendCards() {
        const latest = this.latestMonitoringTrend;
        if (!latest) {
            return [];
        }
        return [
            { key: 'cpu', label: 'Latest Avg CPU', value: `${this.formatMonitoringNumber(latest.avgCpuMs)} ms` },
            { key: 'heap', label: 'Latest Avg Heap', value: `${this.formatMonitoringNumber(latest.avgHeapKb)} KB` },
            { key: 'soql', label: 'Latest SOQL', value: `${this.formatMonitoringNumber(latest.totalSoqlQueries)}` },
            { key: 'async', label: 'Latest Async %', value: `${Number(latest.dailyAsyncApexPct || 0).toFixed(2)}%` }
        ];
    }

    get latestScanTrendRow() {
        return this.scanTrendTableRows.length > 0 ? [this.scanTrendTableRows[0]] : [];
    }

    get governorChartRows() {
        return this.governorLimitRows
            .slice()
            .sort((left, right) => Number(right?.pctUsed || 0) - Number(left?.pctUsed || 0))
            .slice(0, 4)
            .map((row) => ({
                ...row,
                barStyle: `width:${Math.max(6, Math.min(100, Number(row?.pctUsed || 0)))}%`
            }));
    }

    get platformEventInsightCards() {
        const unusedEvents = this.platformEventTableRows.filter((row) => row.activityState === 'No usage detected').length;
        return [
            { key: 'events', label: 'Tracked Events', value: `${this.toInteger(this.monitoringSnapshot?.platformEventCount)}` },
            { key: 'unused', label: 'No Usage Detected', value: `${unusedEvents}` },
            { key: 'publishers', label: 'Publishers', value: `${this.toInteger(this.monitoringSnapshot?.activePlatformPublisherCount)}` },
            { key: 'subscribers', label: 'Subscribers', value: `${this.toInteger(this.monitoringSnapshot?.activePlatformSubscriberCount)}` }
        ];
    }

    get governorAttentionItems() {
        const items = [];
        const threshold = this.GOVERNOR_WARNING_PCT;
        (this.monitoringLimitMetrics || []).forEach((metric) => {
            const pctUsed = Number(metric?.pctUsed);
            if (Number.isFinite(pctUsed) && pctUsed >= threshold) {
                items.push(`${metric.label} is at ${pctUsed.toFixed(2)}%`);
            }
        });
        const latest = this.latestMonitoringTrend;
        if (latest) {
            const apiPct = Number(latest.dailyApiRequestsPct);
            const asyncPct = Number(latest.dailyAsyncApexPct);
            if (Number.isFinite(apiPct) && apiPct >= threshold) {
                items.push(`Latest scan API usage is at ${apiPct.toFixed(2)}%`);
            }
            if (Number.isFinite(asyncPct) && asyncPct >= threshold) {
                items.push(`Latest scan async usage is at ${asyncPct.toFixed(2)}%`);
            }
        }
        return items;
    }

    get showGovernorAttention() {
        return this.governorAttentionItems.length > 0;
    }

    get governorAttentionMessage() {
        if (!this.showGovernorAttention) {
            return '';
        }
        return `Governor review suggested because any single monitored limit can trigger attention. ${this.governorAttentionItems.join(' | ')}`;
    }

    get automationSignalDisclaimer() {
        return 'Automation rows are status-based governance signals. Active or inactive status does not prove recent runtime usage.';
    }

    get asyncUsageStyle() {
        const pct = Math.max(0, Math.min(100, Number(this.monitoringSnapshot?.asyncApexUsedPct || 0)));
        return `background: conic-gradient(#0b5cab 0 ${pct}%, #dfe7f3 ${pct}% 100%);`;
    }

    get asyncUsageLabel() {
        return `${this.toInteger(this.monitoringSnapshot?.asyncJobsToday)}`;
    }

    get asyncUsageSubLabel() {
        if (this.showAsyncLimitNotReported) {
            return 'Salesforce did not report async limit usage for this org snapshot.';
        }
        const pct = Number(this.monitoringSnapshot?.asyncApexUsedPct || 0).toFixed(2);
        return `${pct}% of daily async limit used`;
    }

    get monitoringTabGuide() {
        return 'Operational metrics are current org counts, governor limits are Salesforce-reported capacity values, and scan trends are Clarity360 snapshots captured during scans.';
    }

    get asyncLimitHeroValue() {
        return this.showAsyncLimitNotReported
            ? 'Not reported'
            : `${Number(this.monitoringSnapshot?.asyncApexUsedPct || 0).toFixed(2)}%`;
    }

    get showAsyncLimitNotReported() {
        return this.toInteger(this.monitoringSnapshot?.asyncJobsToday) > 0 &&
            Number(this.monitoringSnapshot?.asyncApexUsedPct || 0) === 0;
    }

    get showMonitoringLimitsView() {
        return this.activeMonitoringView === 'limits';
    }

    get showMonitoringSignalsView() {
        return this.activeMonitoringView === 'signals';
    }

    get showMonitoringLatestView() {
        return this.activeMonitoringView === 'latest';
    }

    get showMonitoringEventsView() {
        return this.activeMonitoringView === 'events';
    }

    get totalJobPages() {
        return Math.max(1, Math.ceil((this.jobsTotalCount || 0) / this.JOBS_PAGE_SIZE));
    }

    get hasPreviousJobsPage() {
        return this.jobsPageNumber > 1;
    }

    get hasNextJobsPage() {
        return this.jobsPageNumber < this.totalJobPages;
    }

    get jobsPageLabel() {
        return `Page ${this.jobsPageNumber} of ${this.totalJobPages}`;
    }

    get previousJobsDisabled() {
        return this.isBusy || !this.hasPreviousJobsPage;
    }

    get nextJobsDisabled() {
        return this.isBusy || !this.hasNextJobsPage;
    }

    get hasDataWarning() {
        return Boolean(this.dataWarning);
    }

    get showSetupBanner() {
        return this.setupComplete === false;
    }

    get dashboardLocked() {
        return this.setupComplete === false;
    }

    get latestJob() {
        return Array.isArray(this.jobs) && this.jobs.length > 0 ? this.jobs[0] : null;
    }

    get latestJobStatus() {
        const latestStatus = this.latestJob?.Status__c;
        if (latestStatus) {
            return String(latestStatus).trim();
        }
        return String(this.summary?.latestJobStatus || '').trim();
    }

    get latestJobHasError() {
        return Boolean(String(this.latestJob?.ErrorMessage__c || '').trim());
    }

    get failedJobs() {
        return (this.jobs || []).filter((row) => Boolean(String(row?.ErrorMessage__c || '').trim()));
    }

    get hasFailedJobs() {
        return this.failedJobs.length > 0;
    }

    get fullScanDisabled() {
        return !this.hasLoadedSummary || !this.hasLoadedJobs || this.isBusy || this.isRefreshingDashboard || this.isLaunchingFullScan || this.dashboardLocked || this.isLatestJobBlockingFullScan;
    }

    get isLatestJobBlockingFullScan() {
        const status = this.latestJobStatus.toLowerCase();
        if (!status) {
            return false;
        }
        if (this.latestJobHasError) {
            return false;
        }
        return status === 'queued' || status === 'running';
    }

    get fullScanDisabledReason() {
        if (this.dashboardLocked) {
            return 'Complete setup wizard before running dashboard operations.';
        }
        if (!this.hasLoadedSummary || !this.hasLoadedJobs) {
            return 'Loading latest scan state before enabling Full Scan.';
        }
        if (this.isLaunchingFullScan) {
            return 'Clarity360 is starting a full scan. Wait for the latest job to update.';
        }
        if (this.isBusy) {
            return 'Clarity360 is refreshing the dashboard.';
        }
        if (this.isLatestJobBlockingFullScan) {
            return `Latest scan job is ${this.latestJobStatus}. Wait for it to finish before starting another full scan.`;
        }
        return '';
    }

    get hasSetupGuidanceItems() {
        return Array.isArray(this.setupGuidanceItems) && this.setupGuidanceItems.length > 0;
    }

    get warningGuidanceItems() {
        if (!this.hasSetupGuidanceItems) {
            return [];
        }
        return this.setupGuidanceItems.filter((item) => item?.status === 'Warning');
    }

    get runtimeWarningGuidanceItems() {
        return this.warningGuidanceItems.filter((item) => item?.key === 'runtimeChoices');
    }

    get readinessWarningGuidanceItems() {
        return this.warningGuidanceItems.filter((item) => item?.key !== 'runtimeChoices');
    }

    get hasRuntimeWarningGuidance() {
        return this.runtimeWarningGuidanceItems.length > 0;
    }

    get hasReadinessWarningGuidance() {
        return this.readinessWarningGuidanceItems.length > 0;
    }

    get runtimeWarningSummary() {
        if (!this.hasRuntimeWarningGuidance) {
            return '';
        }
        return this.runtimeWarningGuidanceItems[0]?.whatToDo || 'Some setup choices are currently using org defaults.';
    }

    get readinessWarningSummary() {
        if (!this.hasReadinessWarningGuidance) {
            return '';
        }
        const count = this.readinessWarningGuidanceItems.length;
        return count === 1
            ? 'There is 1 readiness warning that you may want to review.'
            : `There are ${count} readiness warnings that you may want to review.`;
    }

    get showCompactWarningGuidance() {
        return this.dashboardLocked === false && this.warningGuidanceItems.length > 0;
    }

    get setupProgressPct() {
        if (!this.setupChecksTotal) {
            return 0;
        }
        return Math.round((this.setupChecksReady * 100) / this.setupChecksTotal);
    }

    get setupRemainingCount() {
        return Math.max(0, this.setupChecksTotal - this.setupChecksReady);
    }

    get deleteFieldDisabled() {
        return this.isBusy || !this.selectedUsage || !this.selectedUsage.deleteAllowed;
    }

    get showUsageProgressBanner() {
        return this.isSummaryLoading || this.isInventoryLoading || this.isJobsLoading || this.isLaunchingFullScan;
    }

    get usageProgressMessage() {
        if (this.isLaunchingFullScan) {
            return 'Full scan started. Active Inventory, Usage Signals, recommendations, and jobs will refresh as the new scan advances.';
        }
        if (this.isRefreshingDashboard) {
            return this.pendingOperationDetail || 'Refreshing dashboard data. Wait a moment while Clarity360 syncs the latest scan results.';
        }
        return this.pendingOperationDetail || 'Refreshing dashboard data.';
    }

    get showSummaryRefreshState() {
        return this.isSummaryLoading;
    }

    get showInventoryRefreshState() {
        return this.isInventoryLoading;
    }

    get showJobsRefreshState() {
        return this.isJobsLoading;
    }

    get showMonitoringRefreshState() {
        return this.isMonitoringLoading;
    }

    get summaryGridClass() {
        return this.isSummaryLoading ? 'summary-grid summary-grid-loading' : 'summary-grid';
    }

    get inventoryStackClass() {
        return this.isInventoryLoading ? 'inventory-stack inventory-stack-loading' : 'inventory-stack';
    }

    get monitoringShellClass() {
        return this.isMonitoringLoading ? 'monitoring-shell monitoring-shell-loading slds-p-top_small' : 'monitoring-shell slds-p-top_small';
    }

    beginSectionLoad(sectionName) {
        this.loadingCounters[sectionName] = (this.loadingCounters[sectionName] || 0) + 1;
        this.applyLoadingState(sectionName, true);
    }

    endSectionLoad(sectionName) {
        const nextValue = Math.max(0, (this.loadingCounters[sectionName] || 0) - 1);
        this.loadingCounters[sectionName] = nextValue;
        this.applyLoadingState(sectionName, nextValue > 0);
    }

    applyLoadingState(sectionName, isLoading) {
        if (sectionName === 'summary') {
            this.isSummaryLoading = isLoading;
        } else if (sectionName === 'inventory') {
            this.isInventoryLoading = isLoading;
        } else if (sectionName === 'jobs') {
            this.isJobsLoading = isLoading;
        } else if (sectionName === 'monitoring') {
            this.isMonitoringLoading = isLoading;
        }
    }

    get effectiveModeLabel() {
        return this.currentMode === 'AI' ? 'AI Mode' : 'Standard Mode';
    }

    get modeBannerClass() {
        return this.isAiModeActive ? 'mode-banner mode-banner-ai' : 'mode-banner';
    }

    get modeToggleLabel() {
        return this.isAiModeActive ? 'Switch to Standard Mode' : 'Switch to AI Mode';
    }

    get modeDescription() {
        if (this.currentMode === 'AI' && this.assistantAvailable) {
            return 'Dashboard + chatbot';
        }
        return 'Dashboard + recommendations';
    }

    get isAiModeActive() {
        return this.currentMode === 'AI' && this.assistantAvailable;
    }

    get modeSelectorDisabled() {
        return !this.assistantAvailable;
    }

    get modeToggleVariant() {
        return this.isAiModeActive ? 'brand' : 'neutral';
    }

    get showAssistantWarning() {
        return !this.assistantAvailable && Boolean(this.assistantStatusMessage);
    }

    get monitoringDetailTitle() {
        return this.monitoringDetail?.title || 'Loading details';
    }

    get monitoringDetailSubtitle() {
        return this.monitoringDetail?.subtitle || '';
    }

    get monitoringDetailHighlights() {
        return Array.isArray(this.monitoringDetail?.highlights) ? this.monitoringDetail.highlights : [];
    }

    get monitoringDetailItems() {
        return Array.isArray(this.monitoringDetail?.items) ? this.monitoringDetail.items : [];
    }

    get tourCoachmarkClass() {
        return `tour-coachmark ${this.tourCoachmarkDock}`;
    }

    get showChatLauncher() {
        return this.isAiModeActive;
    }

    get sendDisabled() {
        return this.isChatBusy || String(this.chatInput || '').trim().length === 0;
    }

    get recommendationGroups() {
        if (!this.hasRecommendations) {
            return [];
        }

        const key = this.filteredRecommendations
            .map((row) => `${row.id || ''}|${row.fieldKey || ''}|${row.status || ''}`)
            .join('~');
        if (this.recommendationGroupsCache && this.recommendationGroupsCacheKey === key) {
            return this.recommendationGroupsCache;
        }

        const groupsByName = new Map();
        this.filteredRecommendations.forEach((row) => {
            const name = this.getRecommendationGroupName(row?.fieldKey);
            if (!groupsByName.has(name)) {
                groupsByName.set(name, []);
            }
            groupsByName.get(name).push(row);
        });

        this.recommendationGroupsCache = Array.from(groupsByName.keys()).map((name) => ({
            name,
            label: `${name} (${groupsByName.get(name).length})`,
            rows: groupsByName.get(name)
        }));
        this.recommendationGroupsCacheKey = key;
        return this.recommendationGroupsCache;
    }

    get metadataGroups() {
        if (!this.hasMetadataComponents) {
            return [];
        }

        const groupsByType = new Map();
        this.filteredMetadataComponents.forEach((row) => {
            const type = row?.componentType || 'Unknown';
            if (!groupsByType.has(type)) {
                groupsByType.set(type, []);
            }
            groupsByType.get(type).push({
                ...row,
                displayTitle: row?.displayName || row?.apiName || 'Unknown',
                publisherLabel: `Publishers ${this.toInteger(row?.activePublisherCount)}`,
                summaryText: this.buildMetadataSummary(row)
            });
        });

        return Array.from(groupsByType.keys())
            .sort()
            .map((type) => ({
                name: type,
                label: `${type} (${groupsByType.get(type).length})`,
                rows: groupsByType.get(type)
            }));
    }

    async refreshAll() {
        if (this.dashboardLocked) {
            return;
        }
        this.isBusy = true;
        this.isRefreshingDashboard = true;
        this.pendingOperationLabel = 'Refreshing dashboard';
        this.pendingOperationDetail = 'Refreshing Active Inventory, Usage Signals, recommendations, global components, metadata, and recent jobs.';
        try {
            await Promise.all([
                this.refreshSummary(),
                this.refreshRecommendations(),
                this.refreshGlobalComponents(),
                this.refreshMetadataComponents(),
                this.loadAdminHygieneSnapshot(),
                this.refreshJobs(1),
                this.loadMonitoringSnapshot()
            ]);
        } catch (error) {
            this.showError(error, 'Failed to load dashboard');
        } finally {
            this.isBusy = false;
            this.isRefreshingDashboard = false;
            this.pendingOperationLabel = '';
            this.pendingOperationDetail = '';
        }
    }

    async refreshSummary() {
        this.beginSectionLoad('summary');
        try {
            if (this.summaryWireResult) {
                await refreshApex(this.summaryWireResult);
            }
        } finally {
            this.endSectionLoad('summary');
        }
    }

    async refreshRecommendations() {
        this.beginSectionLoad('inventory');
        try {
            if (this.recommendationsWireResult) {
                await refreshApex(this.recommendationsWireResult);
            }
        } finally {
            this.endSectionLoad('inventory');
        }
    }

    async refreshGlobalComponents() {
        this.beginSectionLoad('inventory');
        try {
            const sections = await getGlobalComponentSections({ rowLimit: 1000 });
            this.globalComponentSections = Array.isArray(sections) ? sections : [];
            if (!this.globalGroupsInitialized) {
                this.expandedGlobalGroups = [];
                this.globalGroupsInitialized = true;
            }
        } catch (error) {
            this.showError(error, 'Failed to load global components');
        } finally {
            this.endSectionLoad('inventory');
        }
    }

    async refreshMetadataComponents() {
        this.beginSectionLoad('inventory');
        try {
            if (this.metadataWireResult) {
                await refreshApex(this.metadataWireResult);
            }
        } finally {
            this.endSectionLoad('inventory');
        }
    }

    async loadMonitoringSnapshot() {
        this.beginSectionLoad('monitoring');
        try {
            const snapshot = await getMonitoringSnapshot();
            this.monitoringSnapshot = {
                ...this.monitoringSnapshot,
                ...(snapshot || {})
            };
        } catch {
            this.resetMonitoringSnapshot();
        } finally {
            this.endSectionLoad('monitoring');
        }
    }

    async loadAdminHygieneSnapshot() {
        this.beginSectionLoad('inventory');
        try {
            const snapshot = await getAdminHygieneSnapshot();
            this.adminHygieneSnapshot = {
                inactiveUserCount: 0,
                unusedProfileCount: 0,
                unassignedPermissionSetCount: 0,
                unassignedPermissionSetGroupCount: 0,
                emptyRoleCount: 0,
                emptyGroupOrQueueCount: 0,
                sections: [],
                ...(snapshot || {})
            };
        } catch (error) {
            this.adminHygieneSnapshot = {
                inactiveUserCount: 0,
                unusedProfileCount: 0,
                unassignedPermissionSetCount: 0,
                unassignedPermissionSetGroupCount: 0,
                emptyRoleCount: 0,
                emptyGroupOrQueueCount: 0,
                sections: []
            };
            this.showError(error, 'Failed to load admin and access findings');
        } finally {
            this.endSectionLoad('inventory');
        }
    }

    async refreshJobs(pageNumber) {
        this.beginSectionLoad('jobs');
        try {
            const page = await getRecentJobs({
                pageNumber,
                pageSize: this.JOBS_PAGE_SIZE
            });
            this.jobs = page?.jobs || [];
            this.jobsTotalCount = page?.totalCount || 0;
            this.jobsPageNumber = page?.pageNumber || 1;
            this.hasLoadedJobs = true;
        } catch (error) {
            this.hasLoadedJobs = true;
            throw error;
        } finally {
            this.endSectionLoad('jobs');
        }
    }

    async handleRunFullScan() {
        if (this.dashboardLocked) {
            this.showToast('Error', 'Complete setup wizard before running dashboard operations.', 'error');
            return;
        }
        this.fullScanReportRecipient = '';
        this.isFullScanModalOpen = true;
    }

    handleCloseFullScanModal() {
        this.isFullScanModalOpen = false;
        this.fullScanReportRecipient = '';
    }

    handleGenerateReportChange(event) {
        this.generateReportOnFullScan = event.target.checked === true;
        if (!this.generateReportOnFullScan) {
            this.fullScanReportRecipient = '';
        }
    }

    handleFullScanReportRecipientChange(event) {
        this.fullScanReportRecipient = event.detail?.value || '';
    }

    async handleConfirmFullScan() {
        this.isFullScanModalOpen = false;
        this.closeTransientUiState();
        await this.runJob(
            runFullScan,
            'Full scan queued',
            {
                sendReport: this.generateReportOnFullScan,
                reportRecipient: this.generateReportOnFullScan ? this.fullScanReportRecipient : ''
            }
        );
        this.fullScanReportRecipient = '';
    }

    get isFullScanRecipientDisabled() {
        return this.generateReportOnFullScan !== true;
    }

    handleOpenTour() {
        this.tourMode = this.activeDashboardTab === 'monitoring' ? 'monitoring' : 'usage';
        this.currentTourStepIndex = 0;
        this.isTourOpen = true;
        this.syncMonitoringTourView();
        this.scheduleTourSync();
    }

    handleCloseTour() {
        this.isTourOpen = false;
        this.tourCoachmarkStyle = '';
        this.clearTourTarget();
        this.persistTourDismissed();
    }

    handlePreviousTourStep() {
        this.currentTourStepIndex = Math.max(0, this.currentTourStepIndex - 1);
        this.syncMonitoringTourView();
        this.scheduleTourSync();
    }

    handleNextTourStep() {
        if (this.currentTourStepIndex >= this.currentTourSteps.length - 1) {
            this.handleCloseTour();
            return;
        }
        this.currentTourStepIndex += 1;
        this.syncMonitoringTourView();
        this.scheduleTourSync();
    }

    async runJob(apexMethod, successMessage, extraParams = {}) {
        this.isBusy = true;
        this.isLaunchingFullScan = true;
        this.pendingOperationLabel = 'Running full scan';
        this.pendingOperationDetail = 'Full scan requested. Clarity360 is preparing new inventory, usage signals, and recommendations.';
        try {
            this.closeTransientUiState();
            const requestId = `${Date.now()}`;
            const response = await apexMethod({ requestId, ...extraParams });
            const jobId = response?.jobId;
            const suffix = jobId
                ? ` Job Id: ${jobId}.${extraParams.sendReport === false ? '' : ` A plain-language report will be emailed when the scan finishes${extraParams.reportRecipient ? ` to ${extraParams.reportRecipient}` : ' to the scan requester'}.`}`
                : ' Running in reduced-storage mode (no ScanJob record).';
            this.showToast('Success', `${successMessage}.${suffix}`, 'success');
            await Promise.all([
                this.refreshSummary(),
                this.refreshRecommendations(),
                this.refreshGlobalComponents(),
                this.refreshMetadataComponents(),
                this.loadAdminHygieneSnapshot(),
                this.refreshJobs(1),
                this.loadMonitoringSnapshot()
            ]);
        } catch (error) {
            this.showError(error, 'Failed to queue job');
        } finally {
            this.isBusy = false;
            this.isLaunchingFullScan = false;
            this.pendingOperationLabel = '';
            this.pendingOperationDetail = '';
        }
    }

    closeTransientUiState() {
        this.isUsageModalOpen = false;
        this.selectedUsage = null;
        this.isUsageDetailLoading = false;
        this.isSearchModalOpen = false;
        this.searchResults = [];
        this.searchSuggestions = [];
    }

    resetMonitoringSnapshot() {
        this.monitoringSnapshot = {
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
        };
    }

    async handleActionFilterChange(event) {
        this.actionFilter = event.detail.value;
    }

    async handleStatusFilterChange(event) {
        this.statusFilter = event.detail.value;
    }

    handleSearchInputChange(event) {
        this.searchFilter = event.detail.value;
        this.searchSuggestions = this.buildSearchSuggestions(this.normalizedSearchFilter);
        this.isSearchModalOpen = false;
        this.searchResults = [];
    }

    handleSearchInputKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.openSearchResults();
        }
    }

    handleSearchFilterChange(event) {
        this.searchFilter = event.detail.value;
        this.searchSuggestions = this.buildSearchSuggestions(this.normalizedSearchFilter);
    }

    handleInventoryHealthFilterChange(event) {
        this.inventoryHealthFilter = event.detail.value;
    }

    handleToggleMode() {
        const requestedMode = this.isAiModeActive ? 'Standard' : 'AI';
        if (requestedMode === 'AI' && !this.assistantAvailable) {
            this.currentMode = 'Standard';
            return;
        }
        this.currentMode = requestedMode;
        if (this.currentMode !== 'AI') {
            this.isChatOpen = false;
        }
    }

    handleModeToggleChange(event) {
        const checked = event?.detail?.checked === true || event?.target?.checked === true;
        if (checked && !this.assistantAvailable) {
            this.currentMode = 'Standard';
            return;
        }
        this.currentMode = checked ? 'AI' : 'Standard';
        if (this.currentMode !== 'AI') {
            this.isChatOpen = false;
        }
    }

    handleTabChange(event) {
        this.activeDashboardTab =
            event?.target?.dataset?.tab ||
            event?.currentTarget?.dataset?.tab ||
            event?.target?.value ||
            event?.detail?.value ||
            'usage';
        this.syncMonitoringTourView();
        if (this.isTourOpen) {
            this.scheduleTourSync();
        }
    }

    handleMonitoringViewChange(event) {
        const nextView = event?.currentTarget?.dataset?.view;
        if (nextView) {
            this.activeMonitoringView = nextView;
        }
    }

    renderedCallback() {
        if (this.pendingTourSync) {
            this.pendingTourSync = false;
            this.syncTourTarget();
        }
    }

    async loadAgentAssistantAvailability() {
        try {
            const state = await getAgentAssistantAvailability();
            this.assistantAvailable = state?.available === true;
            this.assistantStatusMessage = state?.message || '';
            this.currentMode = this.assistantAvailable ? 'AI' : 'Standard';
        } catch {
            this.assistantAvailable = false;
            this.currentMode = 'Standard';
            this.assistantStatusMessage = 'Agentforce status could not be determined.';
        }
    }

    toggleChatWindow() {
        if (!this.showChatLauncher) {
            return;
        }
        this.isChatOpen = !this.isChatOpen;
        if (this.isChatOpen) {
            if (this.chatMessages.length === 0) {
                this.chatPendingContext = '';
                this.chatMessages = [
                    this.createChatMessage(
                        'assistant',
                        'Hi, ask anything about Clarity360. I will answer in simple English using your dashboard data.'
                    )
                ];
            }
        }
    }

    handleChatInputChange(event) {
        this.chatInput = event.detail.value;
    }

    handleChatInputKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleSendChat();
        }
    }

    async handleSendChat() {
        const prompt = String(this.chatInput || '').trim();
        if (!prompt || this.isChatBusy) {
            return;
        }

        this.chatMessages = [...this.chatMessages, this.createChatMessage('user', prompt)];
        this.chatInput = '';
        this.isChatBusy = true;
        try {
            const reply = await askAgentAssistant({
                userMessage: prompt,
                pendingContext: this.chatPendingContext || null
            });
            this.chatPendingContext = reply?.nextContext || '';
            const message = reply?.responseText || 'No response available.';
            this.chatMessages = [...this.chatMessages, this.createChatMessage('assistant', message)];
        } catch (error) {
            this.chatPendingContext = '';
            this.chatMessages = [
                ...this.chatMessages,
                this.createChatMessage(
                    'assistant',
                    error?.body?.message || error?.message || 'Unable to process your request right now.'
                )
            ];
        } finally {
            this.isChatBusy = false;
        }
    }

    createChatMessage(role, text) {
        return {
            id: `${role}-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            role,
            text,
            bubbleClass: role === 'assistant' ? 'chat-bubble assistant' : 'chat-bubble user'
        };
    }

    async handlePreviousJobsPage() {
        if (!this.hasPreviousJobsPage || this.isBusy) {
            return;
        }
        this.isBusy = true;
        try {
            await this.refreshJobs(this.jobsPageNumber - 1);
        } catch (error) {
            this.showError(error, 'Failed to load recent jobs');
        } finally {
            this.isBusy = false;
        }
    }

    async handleNextJobsPage() {
        if (!this.hasNextJobsPage || this.isBusy) {
            return;
        }
        this.isBusy = true;
        try {
            await this.refreshJobs(this.jobsPageNumber + 1);
        } catch (error) {
            this.showError(error, 'Failed to load recent jobs');
        } finally {
            this.isBusy = false;
        }
    }

    async handleRecommendationRowAction(event) {
        const rowId = event?.currentTarget?.dataset?.rowId;
        const row = this.recommendations.find((item) => item?.id === rowId);
        if (!row) {
            return;
        }
        await this.openUsageDetails(this.enrichRecommendationRow(row));
    }

    async handleGlobalRowAction(event) {
        const rowKey = event?.currentTarget?.dataset?.rowKey;
        let matchedRow;
        this.filteredGlobalSections.some((section) => {
            matchedRow = (section?.rows || []).find((row) => row?.key === rowKey);
            return Boolean(matchedRow);
        });
        if (!matchedRow) {
            return;
        }
        await this.openUsageDetails(matchedRow);
    }

    handleCloseUsageModal() {
        this.isUsageModalOpen = false;
        this.selectedUsage = null;
    }

    handleCloseSearchModal() {
        this.isSearchModalOpen = false;
        this.searchResults = [];
    }

    async handleSearchSuggestionClick(event) {
        const resultKey = event?.currentTarget?.dataset?.resultKey;
        const matched = (this.searchSuggestions || []).find((item) => item?.key === resultKey);
        if (!matched) {
            return;
        }
        this.searchFilter = matched.title;
        this.searchSuggestions = [];
        await this.openUsageDetails(matched.sourceRow);
    }

    async handleSearchResultClick(event) {
        const resultKey = event?.currentTarget?.dataset?.resultKey;
        const matched = (this.searchResults || []).find((item) => item?.key === resultKey);
        if (!matched) {
            return;
        }
        this.handleCloseSearchModal();
        this.searchSuggestions = [];
        await this.openUsageDetails(matched.sourceRow);
    }

    async openUsageDetails(row) {
        this.selectedUsage = this.buildNextStepDetails(row);
        this.isUsageModalOpen = true;
        this.isUsageDetailLoading = true;
        try {
            const fieldKey = String(row?.fieldKey || '');
            if (!fieldKey || fieldKey.startsWith('GLOBAL.')) {
                return;
            }
            const detail = await getFieldDetailEvidence({ fieldKey });
            this.selectedUsage = this.buildNextStepDetails(row, detail);
        } catch (error) {
            this.showError(error, 'Failed to load field detail evidence');
        } finally {
            this.isUsageDetailLoading = false;
        }
    }

    async handleDeleteField() {
        if (!this.selectedUsage?.deleteAllowed || this.isBusy) {
            return;
        }
        this.isBusy = true;
        try {
            const response = await deleteCustomField({ fieldKey: this.selectedUsage.fieldKey });
            if (response?.success && response?.deleted) {
                this.showToast('Success', response.message || 'Field deleted successfully.', 'success');
                this.handleCloseUsageModal();
                await Promise.all([this.refreshSummary(), this.refreshRecommendations(), this.refreshJobs(this.jobsPageNumber)]);
            } else {
                this.showToast('Error', response?.message || 'Field deletion failed.', 'error');
            }
        } catch (error) {
            this.showError(error, 'Field deletion failed');
        } finally {
            this.isBusy = false;
        }
    }

    handleRecommendationGroupToggle(event) {
        this.expandedRecommendationGroups = event.detail.openSections || [];
    }

    async handleMonitoringRowAction(event) {
        const actionName = event?.detail?.action?.name;
        const row = event?.detail?.row;
        if (actionName !== 'details' || !row) {
            return;
        }
        await this.openMonitoringDetail(row.detailType, row);
    }

    async handleOpenAsyncJobsDetail() {
        await this.openMonitoringDetail('asyncToday', { recordKey: 'today' });
    }

    async openMonitoringDetail(detailType, row) {
        const key = `${detailType}:${row?.recordKey || row?.key || row?.id || row?.label}`;
        this.isMonitoringDetailOpen = true;
        this.isMonitoringDetailLoading = true;
        this.monitoringDetail = null;
        try {
            if (detailType === 'governorLimit') {
                this.monitoringDetail = this.buildGovernorLimitDetail(row);
                return;
            }
            if (this.monitoringDetailCache.has(key)) {
                this.monitoringDetail = this.monitoringDetailCache.get(key);
                return;
            }
            const detail = await getMonitoringDetail({
                detailType,
                recordKey: row?.recordKey
            });
            this.monitoringDetail = detail || {
                title: row?.label || 'Monitoring detail',
                subtitle: '',
                summary: 'No detail payload was returned for this monitoring item.',
                highlights: [],
                items: []
            };
            if (detail) {
                this.monitoringDetailCache.set(key, detail);
            }
        } catch (error) {
            this.showError(error, 'Failed to load monitoring detail');
        } finally {
            this.isMonitoringDetailLoading = false;
        }
    }

    handleCloseMonitoringDetail() {
        this.isMonitoringDetailOpen = false;
        this.isMonitoringDetailLoading = false;
        this.monitoringDetail = null;
    }

    buildGovernorLimitDetail(row) {
        return {
            detailType: 'governorLimit',
            title: row?.label,
            subtitle: 'Salesforce org limit',
            summary: 'This row comes directly from Salesforce org limits and shows platform-reported capacity usage.',
            highlights: [
                'Use this as a limit signal, not as a replacement for job counts or scan-trend snapshots.',
                'If Salesforce reports zero here while async jobs exist, the org-limit counter itself is what is returning zero.'
            ],
            items: [
                { label: 'Used', value: row?.usedLabel || '-' },
                { label: 'Limit', value: row?.limitLabel || '-' },
                { label: 'Remaining', value: row?.remainingLabel || '-' },
                { label: '% Used', value: row?.pctLabel || '-' }
            ]
        };
    }

    openTourIfNeeded() {
        try {
            const dismissed = window.localStorage.getItem(this.getTourStorageKey('usage'));
            if (!dismissed) {
                this.tourMode = 'usage';
                this.isTourOpen = true;
                this.scheduleTourSync();
            }
        } catch {
            this.tourMode = 'usage';
            this.isTourOpen = true;
            this.scheduleTourSync();
        }
    }

    persistTourDismissed() {
        try {
            window.localStorage.setItem(this.getTourStorageKey(this.tourMode), 'true');
        } catch {
            // Ignore storage access failures in restricted browsing contexts.
        }
    }

    getTourStorageKey(mode) {
        return `${TOUR_STORAGE_KEY_PREFIX}.${mode}.${window.location.hostname}`;
    }

    clearTourTarget() {
        if (this.activeTourTargetElement) {
            this.activeTourTargetElement.classList.remove('tour-target-active');
            this.activeTourTargetElement = null;
        }
    }

    scheduleTourSync() {
        if (!this.isTourOpen) {
            return;
        }
        this.pendingTourSync = true;
    }

    syncTourTarget() {
        this.clearTourTarget();
        if (!this.isTourOpen) {
            return;
        }
        const targetId = this.currentTourStep?.targetId;
        if (!targetId || !this.template) {
            return;
        }
        const target = this.template.querySelector(`[data-tour-id="${targetId}"]`);
        if (!target) {
            return;
        }
        target.classList.add('tour-target-active');
        this.activeTourTargetElement = target;
        if (typeof target.scrollIntoView === 'function') {
            try {
                target.scrollIntoView({ behavior: 'smooth', block: 'center' });
            } catch {
                target.scrollIntoView();
            }
        }
        this.positionTourCoachmark(target);
    }

    syncMonitoringTourView() {
        if (this.tourMode !== 'monitoring') {
            return;
        }
        const nextView = this.currentTourStep?.view;
        if (nextView) {
            this.activeMonitoringView = nextView;
            this.scheduleTourSync();
        }
    }

    positionTourCoachmark(target) {
        if (!target || typeof window === 'undefined') {
            this.tourCoachmarkStyle = '';
            this.tourCoachmarkDock = 'tour-coachmark-bottom';
            return;
        }
        const rect = target.getBoundingClientRect();
        const viewportWidth = window.innerWidth || 1280;
        const viewportHeight = window.innerHeight || 720;
        const coachmarkWidth = Math.min(360, Math.max(280, viewportWidth - 24));
        const estimatedHeight = 220;
        let dock = 'tour-coachmark-right';
        let left = rect.right + 18;
        let top = Math.max(12, rect.top);

        if (viewportWidth - rect.right < coachmarkWidth + 32) {
            dock = 'tour-coachmark-left';
            left = rect.left - coachmarkWidth - 18;
        }
        if (left < 12) {
            dock = 'tour-coachmark-bottom';
            left = Math.max(12, Math.min(viewportWidth - coachmarkWidth - 12, rect.left));
            top = rect.bottom + 18;
        }
        if (top + estimatedHeight > viewportHeight - 12) {
            top = Math.max(12, viewportHeight - estimatedHeight - 12);
        }

        this.tourCoachmarkDock = dock;
        this.tourCoachmarkStyle = `top:${Math.round(top)}px;left:${Math.round(left)}px;width:${Math.round(coachmarkWidth)}px;`;
    }

    normalizeSignalStrength(value, maxExpected) {
        const numeric = this.toInteger(value);
        if (numeric <= 0) {
            return 8;
        }
        return Math.max(8, Math.min(100, Math.round((numeric * 100) / Math.max(1, maxExpected))));
    }

    handleMetadataGroupToggle(event) {
        this.expandedMetadataGroups = event.detail.openSections || [];
    }

    handleToggleGlobalSection(event) {
        const sectionName = event?.currentTarget?.dataset?.sectionName;
        if (!sectionName) {
            return;
        }
        const openSections = new Set(this.expandedGlobalGroups || []);
        if (openSections.has(sectionName)) {
            openSections.delete(sectionName);
        } else {
            openSections.add(sectionName);
        }
        this.expandedGlobalGroups = Array.from(openSections);
    }

    handleOpenSetup() {
        this.navigateToSetupStep(SETUP_STEP_WELCOME);
    }

    handleOpenConfiguration() {
        this.navigateToSetupStep(SETUP_STEP_CONFIGURATION);
    }

    handleOpenReadiness() {
        this.navigateToSetupStep(SETUP_STEP_READINESS);
    }

    navigateToSetupStep(step) {
        this.persistSetupWizardOverride(step);
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: SETUP_NAV_ITEM_API_NAME
            }
        });
    }

    async handleRefreshSetupGuidance() {
        await this.loadSetupState();
    }

    getRecommendationGroupName(fieldKey) {
        if (!fieldKey) {
            return 'Unknown';
        }
        if (fieldKey.startsWith('GLOBAL.')) {
            return 'Global Components';
        }
        const tokens = fieldKey.split('.');
        if (!Array.isArray(tokens) || tokens.length === 0 || !tokens[0]) {
            return 'Unknown';
        }
        return tokens[0];
    }

    buildMetadataSummary(row) {
        const parts = [];
        if (row?.usageFlagLabel) {
            parts.push(row.usageFlagLabel);
        }
        parts.push(row?.whyVisible || 'Shown because it was included in metadata inventory.');
        if (row?.componentType === 'Platform Event') {
            parts.push(`Publishers ${this.toInteger(row?.activePublisherCount)} | Subscribers ${this.toInteger(row?.activeSubscriberCount)}`);
        }
        parts.push(`Next: ${row?.nextStep || 'Refresh after the next scan if you need more evidence.'}`);
        return parts.join(' | ');
    }

    enrichMetadataRow(row) {
        const priority = this.evaluateMetadataPriority(row);
        const refs = this.toInteger(row?.referenceCount);
        const subscribers = this.toInteger(row?.activeSubscriberCount);
        const publishers = this.toInteger(row?.activePublisherCount);
        const isNoUsageSignal = refs === 0 && subscribers === 0 && publishers === 0;
        const isLowUsageSignal = !isNoUsageSignal && refs <= 1 && subscribers <= 1 && publishers <= 1;
        return {
            ...row,
            priorityLabel: priority.label,
            priorityRank: priority.rank,
            priorityClass: this.priorityClassFor(priority.tone),
            usageFlagLabel: isNoUsageSignal
                ? 'No usage found in the latest scan.'
                : (isLowUsageSignal ? 'Very low usage found in the latest scan.' : ''),
            usageFlagClass: isNoUsageSignal
                ? 'metadata-usage-flag metadata-usage-flag-unused'
                : (isLowUsageSignal ? 'metadata-usage-flag metadata-usage-flag-low' : ''),
            showUsageFlag: isNoUsageSignal || isLowUsageSignal
        };
    }

    enrichRecommendationRow(row) {
        const evidence = this.parseEvidence(row?.evidenceSummary);
        const usageMetrics = this.extractUsageMetrics(evidence);
        const isOnLayout = String(evidence.IsOnLayout || '').toLowerCase() === 'true';
        const hasCoverageData = usageMetrics.hasCoverageData;
        const isApexCoverageRow = usageMetrics.isApexCoverageRow || String(row?.fieldKey || '').startsWith('GLOBAL.APEXCLASS.');
        const showCoverageHint = isApexCoverageRow && !hasCoverageData;
        const missingEvidence = !row?.reason || row?.riskScore === null || row?.riskScore === undefined || row?.confidenceScore === null || row?.confidenceScore === undefined;
        const priority = this.evaluateRecommendationPriority(row, evidence, usageMetrics, showCoverageHint, missingEvidence);
        return {
            ...row,
            confidenceDisplay: this.formatNullablePercent(row?.confidenceScore),
            riskDisplay: this.formatNullablePercent(row?.riskScore),
            lastEvaluatedDisplay: this.formatDate(row?.lastEvaluatedOn),
            usageDisplay: this.buildUsageSummary(usageMetrics),
            onLayoutDisplay: isOnLayout ? 'Yes' : 'No',
            reasonDisplay: row?.reason || 'Reason will appear after usage evidence is rebuilt.',
            showCoverageHint,
            priorityLabel: priority.label,
            priorityRank: priority.rank,
            priorityClass: this.priorityClassFor(priority.tone),
            coverageHint: showCoverageHint
                ? 'Coverage data is not available yet. Rerun Full Scan or Usage Scan and refresh this dashboard.'
                : '',
            showEvidenceHint: missingEvidence,
            evidenceHint: missingEvidence
                ? 'Reason, risk, and confidence will fill in after Inventory Refresh, Usage Scan, and Refresh.'
                : '',
            rowClass: `recommendation-row ${showCoverageHint || missingEvidence ? 'recommendation-row-warning' : ''}`
        };
    }

    enrichGlobalComponentRow(row, recommendation) {
        const mergedRecommendation = recommendation ? this.enrichRecommendationRow(recommendation) : null;
        const evidence = this.parseEvidence(mergedRecommendation?.evidenceSummary);
        const usageMetrics = this.extractUsageMetrics(evidence, row?.componentType);
        const liveCoverageLabel = this.extractCoverageLabel(row?.status);
        const liveCoverageValue = this.extractCoverageValue(row?.status);
        const hasLiveCoverageData = String(row?.fieldKey || '').startsWith('GLOBAL.APEXCLASS.') && Boolean(liveCoverageLabel);
        const showCoverageHint = String(row?.fieldKey || '').startsWith('GLOBAL.APEXCLASS.') && !usageMetrics.hasCoverageData && !hasLiveCoverageData;
        const shouldOverrideWithLiveCoverage =
            hasLiveCoverageData &&
            liveCoverageValue !== null &&
            liveCoverageValue >= 80 &&
            (
                !mergedRecommendation ||
                mergedRecommendation?.showCoverageHint === true ||
                String(mergedRecommendation?.action || '') === 'Investigate Dependencies'
            );
        const hasRecommendation = Boolean(mergedRecommendation);
        const recommendationAction = String(mergedRecommendation?.action || '');
        const statusTone = this.getStatusTone(row?.status, hasRecommendation, recommendationAction, showCoverageHint, liveCoverageValue);
        const fallbackReason = hasLiveCoverageData && liveCoverageValue < 80
            ? `Apex class has low coverage (${liveCoverageLabel}) and needs review.`
            : (hasLiveCoverageData ? `Apex class coverage is healthy (${liveCoverageLabel}).` : 'Usage evidence has not been calculated yet.');
        const fallbackAction = hasLiveCoverageData && liveCoverageValue < 80
            ? 'Investigate Dependencies'
            : 'Pending analysis';
        let reason = mergedRecommendation?.reasonDisplay || fallbackReason;
        let usageDisplay = mergedRecommendation?.usageDisplay || this.buildUsageSummary(usageMetrics);
        if (hasLiveCoverageData && mergedRecommendation?.showCoverageHint === true) {
            reason = `Apex Class (Coverage=${liveCoverageLabel})`;
            usageDisplay = `Coverage ${liveCoverageLabel}`;
        }
        if (shouldOverrideWithLiveCoverage) {
            reason = `Apex Class (Coverage=${liveCoverageLabel})`;
            usageDisplay = `Coverage ${liveCoverageLabel}`;
        }
        const action = shouldOverrideWithLiveCoverage
            ? 'Keep'
            : (mergedRecommendation?.action || fallbackAction);
        const riskDisplay = shouldOverrideWithLiveCoverage
            ? '15.00%'
            : (mergedRecommendation?.riskDisplay || 'Pending');
        const confidenceDisplay = shouldOverrideWithLiveCoverage
            ? '92.00%'
            : (mergedRecommendation?.confidenceDisplay || 'Pending');
        const priority = this.evaluateGlobalPriority(row, mergedRecommendation, usageMetrics, showCoverageHint, liveCoverageValue);
        const effectivePriority = shouldOverrideWithLiveCoverage
            ? { label: 'Healthy', rank: 0, tone: 'healthy' }
            : priority;
        return {
            ...row,
            hasRecommendation,
            displayName: row?.objectName ? `${row.objectName} / ${row.componentName}` : row?.componentName,
            typeCaption: row?.componentType || 'Global Component',
            action,
            reason,
            usageDisplay,
            priorityLabel: effectivePriority.label,
            priorityRank: effectivePriority.rank,
            priorityClass: this.priorityClassFor(effectivePriority.tone),
            riskDisplay,
            confidenceDisplay,
            showCoverageHint,
            showEvidenceHint: showCoverageHint ? false : (!hasRecommendation || mergedRecommendation?.showEvidenceHint === true),
            evidenceHint: showCoverageHint
                ? 'Coverage is pending. Run Full Scan or Usage Scan again, then refresh this dashboard.'
                : (shouldOverrideWithLiveCoverage
                    ? 'Live coverage is above the current review threshold. No follow-up is needed unless the class changes.'
                    : this.buildEvidenceGuidance(row?.componentType, hasRecommendation)),
            detailDisplay: row?.detail || (row?.objectName ? `Scoped to ${row.objectName}` : 'Metadata inventory row'),
            itemClass: `global-component-item global-component-item-${shouldOverrideWithLiveCoverage ? 'good' : statusTone}`,
            statusClass: `global-component-status global-component-status-${shouldOverrideWithLiveCoverage ? 'good' : statusTone}`
        };
    }

    invalidateRecommendationGroupsCache() {
        this.recommendationGroupsCache = null;
        this.recommendationGroupsCacheKey = null;
    }

    applySetupGuidance(state) {
        const checks = state?.readiness?.checks || [];
        this.readinessOverallStatus = state?.readiness?.overallStatus || 'Unknown';
        this.setupChecksTotal = checks.length;
        this.setupChecksReady = checks.filter((item) => item?.status === 'Ready').length;

        this.setupGuidanceItems = checks
            .filter((item) => item?.status !== 'Ready')
            .map((item, index) => ({
                key: item?.key || `guidance-${index}`,
                title: item?.label || 'Setup Check',
                status: item?.status || 'Warning',
                statusClass: this.statusClassFor(item?.status),
                why: this.whyTextForCheck(item?.key),
                details: item?.message || 'No additional details.',
                whatToDo: item?.remediation || 'Open Setup Wizard and resolve this item.'
            }));
    }

    statusClassFor(status) {
        const value = String(status || '').toLowerCase();
        if (value === 'blocked') {
            return 'guidance-status blocked';
        }
        if (value === 'warning') {
            return 'guidance-status warning';
        }
        return 'guidance-status ready';
    }

    whyTextForCheck(key) {
        const map = {
            runtimeChoices: 'Optional setup choices can use org defaults, then be optimized later without blocking access.',
            adminPrivileges: 'Required to save org configuration and orchestrate scans safely.',
            configAccess: 'Required to store your setup choices for this org.',
            configFieldAccess: 'Required so admins can update critical setup values in-app.',
            operationalAccess: 'Required for inventory, usage evidence, jobs, and recommendations.',
            asyncCapacity: 'Required for background scan execution without blocking users.',
            storageHealth: 'Low free storage can cause partial scan output and noisy recommendations.',
            coreComponents: 'Required to ensure package components are installed and available.',
            namedCredential: 'Improves callout reliability and security for metadata operations.',
            toolingApi: 'Enables deeper metadata insights and advanced recommendation evidence.',
            uiComponents: 'Ensures app and tabs are visible and usable for admins.',
            agentAssistant: 'Confirms Agentforce action runtime is available for AI mode and chatbot experiences.'
        };
        return map[key] || 'Required to ensure reliable onboarding and dashboard operations.';
    }

    persistSetupWizardOverride(step) {
        try {
            window.sessionStorage.setItem(
                `${SETUP_STEP_STORAGE_KEY_PREFIX}.${window.location.hostname}`,
                String(step)
            );
        } catch {
            // Ignore storage access failures in restricted browsing contexts.
        }
    }

    extractUsageMetrics(evidence, componentType) {
        const activeTriggerRefs = this.toInteger(evidence.ActiveTriggerRefs);
        const inactiveTriggerRefs = this.toInteger(evidence.InactiveTriggerRefs);
        const activeValidationRuleRefs = this.toInteger(evidence.ActiveValidationRuleRefs);
        const inactiveValidationRuleRefs = this.toInteger(evidence.InactiveValidationRuleRefs);
        const activeFlowRefs = this.toInteger(evidence.ActiveFlowRefs);
        const inactiveFlowRefs = this.toInteger(evidence.InactiveFlowRefs);
        const apexClassRefs = this.toInteger(evidence.ApexClassRefs);
        return {
            activeRefs: activeTriggerRefs + activeValidationRuleRefs + activeFlowRefs + apexClassRefs,
            inactiveRefs: inactiveTriggerRefs + inactiveValidationRuleRefs + inactiveFlowRefs,
            sampled: this.toInteger(evidence.Sampled),
            nonNull: this.toInteger(evidence.NonNull),
            hasData: String(evidence.HasData || '').toLowerCase() === 'true',
            hasDataKnown: ['true', 'false'].includes(String(evidence.HasData || '').toLowerCase()),
            hasCoverageData: String(evidence.HasCoverageData || '').toLowerCase() === 'true',
            isApexCoverageRow:
                String(evidence.ComponentType || '').toLowerCase() === 'apexclass' ||
                String(componentType || '').toLowerCase() === 'apex class'
        };
    }

    buildUsageSummary(metrics) {
        const parts = [];
        if ((metrics?.sampled || 0) > 0) {
            parts.push(`Sample ${metrics.sampled}`);
            parts.push(`Non-null ${metrics.nonNull}`);
        }
        if ((metrics?.activeRefs || 0) > 0) {
            parts.push(`Active deps ${metrics.activeRefs}`);
        }
        if ((metrics?.inactiveRefs || 0) > 0) {
            parts.push(`Inactive deps ${metrics.inactiveRefs}`);
        }
        if (metrics?.hasDataKnown) {
            parts.push(metrics.hasData ? 'Data present' : 'No sampled data');
        }
        return parts.length > 0 ? parts.join(' | ') : 'Usage evidence pending';
    }

    buildEvidenceGuidance(componentType, hasRecommendation) {
        if (hasRecommendation) {
            return 'Refresh after the next Inventory Refresh or Usage Scan if the evidence still looks incomplete.';
        }
        const noun = componentType || 'component';
        return `${noun} analysis is still pending. Run Inventory Refresh, then Usage Scan, then Refresh to calculate reason, risk, and usage.`;
    }

    getStatusTone(status, hasRecommendation, recommendationAction, showCoverageHint, liveCoverageValue) {
        if (this.isInactiveStatusValue(status)) {
            return 'warning';
        }
        if (liveCoverageValue !== null && liveCoverageValue < 80) {
            return 'attention';
        }
        if (showCoverageHint || (hasRecommendation && recommendationAction !== 'Keep')) {
            return 'attention';
        }
        if (this.isActiveStatusValue(status)) {
            return 'good';
        }
        return 'neutral';
    }

    matchesSearch(values, term) {
        if (!term) {
            return true;
        }
        return (values || []).some((value) => String(value || '').toLowerCase().includes(term));
    }

    openSearchResults() {
        const term = this.normalizedSearchFilter;
        if (!term) {
            this.handleCloseSearchModal();
            return;
        }
        this.searchResults = this.buildSearchResults(term);
        this.searchSuggestions = [];
        this.isSearchModalOpen = true;
    }

    buildSearchResults(term) {
        const results = [];
        const addResult = (key, section, title, summary, sourceRow) => {
            results.push({
                key,
                section,
                title,
                summary,
                priorityLabel: sourceRow?.priorityLabel || 'Healthy',
                priorityClass: sourceRow?.priorityClass || this.priorityClassFor('healthy'),
                hiddenReason: this.hiddenReasonForPriority(sourceRow?.priorityLabel),
                sourceRow
            });
        };

        (this.recommendations || [])
            .map((row) => this.enrichRecommendationRow(row))
            .forEach((row) => {
                if (!this.matchesSearch([row?.componentName, row?.reasonDisplay, row?.action, row?.status, row?.fieldKey, row?.usageDisplay], term)) {
                    return;
                }
                addResult(`rec-${row.id || row.fieldKey}`, 'Object Usage', row?.componentName || row?.fieldKey, row?.reasonDisplay || row?.usageDisplay, row);
            });

        (this.globalComponentSections || []).forEach((section) => {
            (section?.rows || [])
                .map((row) => this.enrichGlobalComponentRow(row, this.globalRecommendationMap.get(row?.fieldKey)))
                .forEach((row) => {
                    if (!this.matchesSearch([row?.componentType, row?.componentName, row?.status, row?.objectName, row?.detail, row?.reason, row?.usageDisplay], term)) {
                        return;
                    }
                    addResult(`global-${row.key}`, 'Global Components', row?.displayName || row?.componentName, row?.reason || row?.detailDisplay, row);
                });
        });

        (this.metadataComponents || [])
            .map((row) => this.enrichMetadataRow(row))
            .forEach((row) => {
                if (!this.matchesSearch([row?.componentType, row?.displayName, row?.apiName, row?.whyVisible, row?.nextStep], term)) {
                    return;
                }
                addResult(
                    `meta-${row.id || row.apiName}`,
                    'Metadata Usage',
                    row?.displayName || row?.apiName,
                    row?.whyVisible,
                    {
                        ...row,
                        componentName: row?.displayName || row?.apiName,
                        componentType: row?.componentType,
                        reasonDisplay: row?.whyVisible,
                        usageDisplay: row?.nextStep,
                        action: 'Review',
                        fieldKey: row?.componentKey || row?.apiName
                    }
                );
            });

        return results.slice(0, 25);
    }

    buildSearchSuggestions(term) {
        if (!term || term.length < 2) {
            return [];
        }
        return this.buildSearchResults(term).slice(0, 6);
    }

    hiddenReasonForPriority(priorityLabel) {
        const normalized = String(priorityLabel || '').toLowerCase();
        if (normalized === 'healthy') {
            return 'This item is hidden in the default view because it is currently healthy and does not need immediate action.';
        }
        return 'This item is shown here because you searched for it directly.';
    }

    evaluateRecommendationPriority(row, evidence, usageMetrics, showCoverageHint, missingEvidence) {
        const nullRate = this.toDecimal(evidence.NullRatePct);
        const riskScore = this.toDecimal(row?.riskScore);
        const status = String(row?.status || '').toLowerCase();

        if (nullRate >= 70 || riskScore >= 85) {
            return { label: 'Needs Action', rank: 3, tone: 'needs-action' };
        }
        if (nullRate >= 50 || riskScore >= 70) {
            return { label: 'Critical', rank: 2, tone: 'critical' };
        }
        if (nullRate >= 30 || showCoverageHint || missingEvidence || status === 'open' || riskScore >= 50) {
            return { label: 'Warning', rank: 1, tone: 'warning' };
        }
        if (usageMetrics?.activeRefs > 0 || usageMetrics?.inactiveRefs > 0) {
            return { label: 'Warning', rank: 1, tone: 'warning' };
        }
        return { label: 'Healthy', rank: 0, tone: 'healthy' };
    }

    evaluateGlobalPriority(row, recommendation, usageMetrics, showCoverageHint, liveCoverageValue) {
        const riskScore = this.toDecimal(recommendation?.riskScore);
        const recommendationAction = String(recommendation?.action || '');
        const isInactive = this.isInactiveGlobalComponent(row);

        if (showCoverageHint || riskScore >= 85) {
            return { label: 'Needs Action', rank: 3, tone: 'needs-action' };
        }
        if (liveCoverageValue !== null && liveCoverageValue < 50) {
            return { label: 'Needs Action', rank: 3, tone: 'needs-action' };
        }
        if (isInactive || riskScore >= 70) {
            return { label: 'Critical', rank: 2, tone: 'critical' };
        }
        if (liveCoverageValue !== null && liveCoverageValue < 80) {
            return { label: 'Warning', rank: 1, tone: 'warning' };
        }
        if ((recommendation && recommendationAction !== 'Keep') || usageMetrics?.activeRefs > 0 || usageMetrics?.inactiveRefs > 0) {
            return { label: 'Warning', rank: 1, tone: 'warning' };
        }
        return { label: 'Healthy', rank: 0, tone: 'healthy' };
    }

    isInactiveGlobalComponent(row) {
        if (!row) {
            return false;
        }
        if (this.isInactiveStatusValue(row?.status)) {
            return true;
        }
        if (this.isFlowLikeComponent(row)) {
            return !this.isActiveStatusValue(row?.status);
        }
        return false;
    }

    isFlowLikeComponent(row) {
        const componentType = String(row?.componentType || '').toLowerCase();
        return componentType === 'flow' || componentType === 'process builder';
    }

    isActiveStatusValue(status) {
        return this.extractPrimaryStatusToken(status) === 'active';
    }

    isInactiveStatusValue(status) {
        const normalized = this.extractPrimaryStatusToken(status);
        return normalized === 'inactive' || normalized === 'obsolete';
    }

    extractPrimaryStatusToken(status) {
        const normalized = String(status || '').toLowerCase().trim();
        if (!normalized) {
            return '';
        }
        return normalized.split('|')[0].trim();
    }

    evaluateMetadataPriority(row) {
        const refs = this.toInteger(row?.referenceCount);
        const subscribers = this.toInteger(row?.activeSubscriberCount);
        const type = String(row?.componentType || '').toLowerCase();

        if (type === 'platform event') {
            if (subscribers === 0 && refs === 0) {
                return { label: 'Needs Action', rank: 3, tone: 'needs-action' };
            }
            if (subscribers === 0) {
                return { label: 'Critical', rank: 2, tone: 'critical' };
            }
            if (subscribers <= 1 || refs <= 1) {
                return { label: 'Warning', rank: 1, tone: 'warning' };
            }
            return { label: 'Healthy', rank: 0, tone: 'healthy' };
        }

        if (refs === 0) {
            return { label: 'Critical', rank: 2, tone: 'critical' };
        }
        if (refs <= 1) {
            return { label: 'Warning', rank: 1, tone: 'warning' };
        }
        return { label: 'Healthy', rank: 0, tone: 'healthy' };
    }

    priorityClassFor(tone) {
        return `priority-pill priority-pill-${tone || 'healthy'}`;
    }

    toFixedNumber(value) {
        if (value === null || value === undefined) {
            return 0;
        }
        return Number.parseFloat(value).toFixed(2);
    }

    formatNullablePercent(value) {
        if (value === null || value === undefined || value === '') {
            return 'Pending';
        }
        const parsed = Number.parseFloat(value);
        return Number.isFinite(parsed) ? `${parsed.toFixed(2)}%` : 'Pending';
    }

    buildNextStepDetails(row, detailEvidence) {
        const evidence = this.parseEvidence(row?.evidenceSummary);
        const activeTriggerRefs = this.toInteger(evidence.ActiveTriggerRefs);
        const inactiveTriggerRefs = this.toInteger(evidence.InactiveTriggerRefs);
        const activeValidationRuleRefs = this.toInteger(evidence.ActiveValidationRuleRefs);
        const inactiveValidationRuleRefs = this.toInteger(evidence.InactiveValidationRuleRefs);
        const activeFlowRefs = this.toInteger(evidence.ActiveFlowRefs);
        const inactiveFlowRefs = this.toInteger(evidence.InactiveFlowRefs);
        const apexClassRefs = this.toInteger(evidence.ApexClassRefs);
        const usedInRefs =
            activeTriggerRefs +
            inactiveTriggerRefs +
            activeValidationRuleRefs +
            inactiveValidationRuleRefs +
            activeFlowRefs +
            inactiveFlowRefs +
            apexClassRefs;
        const hasConcreteUsage = usedInRefs > 0;
        const hasData = String(evidence.HasData || '').toLowerCase() === 'true';
        const hasDataKnown = String(evidence.HasData || '').toLowerCase() === 'true' || String(evidence.HasData || '').toLowerCase() === 'false';
        const isCustomField = Boolean(row?.fieldKey) && !row.fieldKey.startsWith('GLOBAL.') && row.fieldKey.endsWith('__c');
        const isManagedPackageField = this.isManagedPackageFieldKey(row?.fieldKey);
        const isGlobalComponent = String(row?.fieldKey || '').startsWith('GLOBAL.');
        const componentType = row?.typeCaption || row?.componentType || this.inferComponentType(row?.fieldKey);
        const isApexClass = String(componentType || '').toLowerCase() === 'apex class';
        const isInactiveGlobal = isGlobalComponent && String(row?.status || '').toLowerCase() === 'inactive';
        const showCoverageHint = row?.showCoverageHint === true;
        const layoutNames = Array.isArray(detailEvidence?.layoutNames) ? detailEvidence.layoutNames : [];
        const isOnLayout = detailEvidence?.isOnLayout === true || String(evidence.IsOnLayout || '').toLowerCase() === 'true';
        const signalHistoryCount = this.toInteger(detailEvidence?.signalHistoryCount);

        let deleteGuidance = 'Deletion requires manual review.';
        let deleteAllowed = false;
        if (!isCustomField) {
            deleteGuidance = 'Only custom fields are considered for deletion.';
        } else if (isManagedPackageField) {
            deleteGuidance = 'Managed-package fields should not be deleted from this dashboard. Review the package impact first.';
        } else if (hasConcreteUsage) {
            deleteGuidance = 'Field is referenced by triggers, validation rules, flows, or Apex classes.';
        } else if (isOnLayout) {
            deleteGuidance = 'Field is still present on one or more layouts.';
        } else if (hasData) {
            deleteGuidance = 'Field still contains sampled data.';
        } else if (!hasDataKnown) {
            deleteGuidance = 'Data usage could not be determined from current evidence.';
        } else {
            deleteAllowed = true;
            deleteGuidance = 'No usage references and no sampled data detected. Eligible for deletion.';
        }

        const nextSteps = this.buildNextSteps({
            componentType,
            isCustomField,
            isManagedPackageField,
            isApexClass,
            isInactiveGlobal,
            showCoverageHint,
            hasConcreteUsage,
            hasData,
            hasDataKnown,
            deleteAllowed,
            activeTriggerRefs,
            activeValidationRuleRefs,
            activeFlowRefs,
            apexClassRefs,
            isOnLayout
        });

        return {
            title: row?.displayName || row?.componentName || 'Next Steps',
            sectionLabel: componentType,
            fieldKey: row?.fieldKey || 'Unknown',
            componentName: row?.componentName || 'Unknown',
            summary: row?.reasonDisplay || row?.reason || row?.detailDisplay || 'Review this item and take the next recommended action.',
            actionLabel: row?.action || 'Review',
            riskDisplay: row?.riskDisplay || 'Pending',
            confidenceDisplay: row?.confidenceDisplay || 'Pending',
            usageDisplay: row?.usageDisplay || 'Usage evidence pending',
            activeTriggerRefs,
            inactiveTriggerRefs,
            activeValidationRuleRefs,
            inactiveValidationRuleRefs,
            activeFlowRefs,
            inactiveFlowRefs,
            apexClassRefs,
            sampleSize: this.toInteger(evidence.Sampled),
            nonNullCount: this.toInteger(evidence.NonNull),
            hasData: hasData ? 'Yes' : hasDataKnown ? 'No' : 'Unknown',
            isOnLayout: isOnLayout ? 'Yes' : 'No',
            layoutNames: layoutNames.length > 0 ? layoutNames.join(', ') : 'Not detected',
            signalHistoryCount,
            activeTriggerNames: this.toDisplayList(evidence.ActiveTriggerNames),
            inactiveTriggerNames: this.toDisplayList(evidence.InactiveTriggerNames),
            apexClassNames: this.toDisplayList(evidence.ApexClassNames),
            deleteAllowed,
            canDelete: deleteAllowed ? 'Yes' : 'No',
            deleteGuidance,
            nextSteps,
            showDeleteAction: deleteAllowed
        };
    }

    buildNextSteps(context) {
        const steps = [];
        if (context.showCoverageHint) {
            steps.push('Run Full Scan or Usage Scan again after deploying your latest classes and tests.');
            steps.push('Refresh the dashboard to pull updated Apex coverage evidence.');
        }
        if (context.isApexClass && !context.showCoverageHint) {
            steps.push('Review the class test coverage and add or strengthen tests before the next release.');
            steps.push('Deploy the updated tests or class changes, then rerun Full Scan to refresh coverage.');
        }
        if (context.isCustomField) {
            steps.push('Review where this field is used across triggers, validation rules, flows, and Apex before changing it.');
            if (context.isManagedPackageField) {
                steps.push('This looks like a managed-package field. Coordinate with the package owner before making any change.');
            } else if (context.isOnLayout) {
                steps.push('Remove the field from active page layouts and rerun Usage Scan before considering deprecation.');
            } else if (context.hasConcreteUsage) {
                steps.push('Deprecate the field gradually: remove layouts, help text, and automation references before deletion.');
            } else if (context.deleteAllowed) {
                steps.push('Field looks removable. Confirm with the business owner, then delete it and rerun Inventory Refresh.');
            } else if (!context.hasDataKnown) {
                steps.push('Run Usage Scan again to improve data sampling before making a delete decision.');
            }
        }
        if (context.isInactiveGlobal) {
            steps.push('Confirm with the owner that this status-based inactive automation may no longer be needed.');
            steps.push('If confirmed, remove it from the org and rerun Inventory Refresh to clear it from the dashboard.');
        }
        if (String(context.componentType || '').toLowerCase() === 'flow') {
            steps.push('Open the flow, review latest version status and dependencies, then decide whether to activate, retire, or delete it.');
        }
        if (String(context.componentType || '').toLowerCase() === 'validation rule') {
            steps.push('Check whether the rule was intentionally disabled for business reasons before removing it.');
        }
        if (String(context.componentType || '').toLowerCase() === 'trigger') {
            steps.push('Review trigger handlers and deployment history before removing or consolidating trigger logic.');
        }
        if (steps.length === 0) {
            steps.push('Review this item in Setup or source control, then rerun the relevant scan to refresh evidence.');
        }
        return steps.map((step, index) => ({
            key: `step-${index}`,
            text: step
        }));
    }

    inferComponentType(fieldKey) {
        const value = String(fieldKey || '');
        if (value.startsWith('GLOBAL.APEXCLASS.')) {
            return 'Apex Class';
        }
        if (value.startsWith('GLOBAL.VALRULE.')) {
            return 'Validation Rule';
        }
        if (value.startsWith('GLOBAL.FLOW.')) {
            return 'Flow';
        }
        if (value.startsWith('GLOBAL.TRIGGER.')) {
            return 'Trigger';
        }
        return 'Object Usage';
    }

    isManagedPackageFieldKey(fieldKey) {
        const value = String(fieldKey || '');
        const splitIndex = value.indexOf('.');
        if (splitIndex <= 0 || splitIndex >= value.length - 1) {
            return false;
        }
        const fieldApiName = value.substring(splitIndex + 1);
        return /^[A-Za-z0-9]+__.+__c$/.test(fieldApiName);
    }

    parseEvidence(evidenceSummary) {
        const result = {};
        if (!evidenceSummary) {
            return result;
        }
        evidenceSummary.split(';').forEach((entry) => {
            const token = String(entry || '').trim();
            if (!token) {
                return;
            }
            const splitIndex = token.indexOf('=');
            if (splitIndex <= 0) {
                return;
            }
            const key = token.substring(0, splitIndex).trim();
            const value = token.substring(splitIndex + 1).trim();
            if (key) {
                result[key] = value;
            }
        });
        return result;
    }

    toInteger(value) {
        const parsed = Number.parseInt(value, 10);
        return Number.isFinite(parsed) ? parsed : 0;
    }

    toDecimal(value) {
        const parsed = Number.parseFloat(value);
        return Number.isFinite(parsed) ? parsed : 0;
    }

    extractCoverageLabel(status) {
        const value = String(status || '').trim();
        return /^\d+(\.\d+)?%$/.test(value) ? value : '';
    }

    extractCoverageValue(status) {
        const value = this.extractCoverageLabel(status);
        return value ? Number.parseFloat(value.replace('%', '')) : null;
    }

    toDisplayList(value) {
        if (!value) {
            return 'None';
        }
        const cleaned = String(value)
            .split(',')
            .map((item) => item.trim())
            .filter((item) => item);
        return cleaned.length > 0 ? cleaned.join(', ') : 'None';
    }

    formatDate(value) {
        if (!value) {
            return 'Unknown';
        }
        try {
            return new Intl.DateTimeFormat('en-US', {
                year: 'numeric',
                month: 'short',
                day: '2-digit'
            }).format(new Date(value));
        } catch {
            return String(value);
        }
    }

    formatDateTime(value) {
        if (!value) {
            return 'Unknown';
        }
        try {
            return new Intl.DateTimeFormat('en-US', {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }).format(new Date(value));
        } catch {
            return String(value);
        }
    }

    formatMonitoringNumber(value) {
        const parsed = Number(value);
        if (!Number.isFinite(parsed)) {
            return '-';
        }
        return Number.isInteger(parsed) ? `${parsed}` : parsed.toFixed(2);
    }

    showError(error, fallbackMessage) {
        const message =
            error?.body?.message ||
            error?.body?.output?.errors?.[0]?.message ||
            error?.body?.pageErrors?.[0]?.message ||
            error?.message ||
            fallbackMessage;
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
