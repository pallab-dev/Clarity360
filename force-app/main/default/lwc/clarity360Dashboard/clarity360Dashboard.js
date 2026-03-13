import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';

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

const JOB_COLUMNS = [
    { label: 'Job', fieldName: 'Name', type: 'text' },
    { label: 'Type', fieldName: 'JobType__c', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Progress %', fieldName: 'ProgressPct__c', type: 'number', typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } },
    { label: 'Started', fieldName: 'StartedOn__c', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } },
    { label: 'Finished', fieldName: 'FinishedOn__c', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } }
];

const METADATA_COLUMNS = [
    { label: 'Type', fieldName: 'componentType', type: 'text' },
    { label: 'API Name', fieldName: 'apiName', type: 'text' },
    { label: 'References', fieldName: 'referenceCount', type: 'number' },
    { label: 'Active Subscribers', fieldName: 'activeSubscriberCount', type: 'number' },
    { label: 'Monitoring', fieldName: 'monitoringEligibleLabel', type: 'text' },
    { label: 'Last Scanned', fieldName: 'lastScannedOn', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } }
];

export default class Clarity360Dashboard extends NavigationMixin(LightningElement) {
    JOBS_PAGE_SIZE = 5;

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
    @track dataWarning = '';
    @track isUsageModalOpen = false;
    @track selectedUsage = null;
    @track isSearchModalOpen = false;
    @track searchResults = [];
    @track searchSuggestions = [];
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
    @track monitoringSnapshot = {
        asyncApexUsedPct: 0,
        queueableActiveCount: 0,
        batchActiveCount: 0,
        scheduledJobCount: 0,
        platformEventCount: 0,
        activePlatformSubscriberCount: 0,
        limitMetrics: [],
        platformEvents: []
    };

    summaryWireResult;
    recommendationsWireResult;
    metadataWireResult;
    recommendationGroupsCache;
    recommendationGroupsCacheKey;
    globalGroupsInitialized = false;
    searchSuggestionTimer;

    metadataColumns = METADATA_COLUMNS;
    jobColumns = JOB_COLUMNS;

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
        this.loadSetupState();
        this.loadAgentAssistantAvailability();
        this.refreshJobs(1);
        this.loadMonitoringSnapshot();
        this.refreshGlobalComponents();
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
                return;
            }
        } catch (error) {
            this.setupComplete = true;
        } finally {
            this.isSetupGuidanceBusy = false;
        }
    }

    @wire(getDashboardSummary)
    wiredSummary(result) {
        this.summaryWireResult = result;
        if (result.data) {
            this.summary = {
                ...result.data,
                cleanlinessScore: this.toFixedNumber(result.data.cleanlinessScore)
            };
            this.dataWarning = this.summary.latestJobStatus === 'Partial' ? 'Latest run completed with partial results.' : '';
        } else if (result.error) {
            this.showError(result.error, 'Failed to load summary');
        }
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
                whyVisible: row?.whyVisible || 'Shown because it was included in metadata inventory.',
                nextStep: row?.nextStep || 'Refresh after the next scan if you need more evidence.'
            }));
        } else if (result.error) {
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
        return this.hasMetadataComponents;
    }

    get hasGlobalComponents() {
        return this.filteredGlobalSections.length > 0;
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
                            return row?.showCoverageHint === true || row?.hasRecommendation === true || this.isInactiveGlobalComponent(row);
                        }
                        if (this.inventoryHealthFilter === 'healthy') {
                            return row?.showCoverageHint !== true && row?.hasRecommendation !== true && !this.isInactiveGlobalComponent(row);
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

    get platformEventRows() {
        return Array.isArray(this.monitoringSnapshot?.platformEvents) ? this.monitoringSnapshot.platformEvents : [];
    }

    get hasPlatformEvents() {
        return this.platformEventRows.length > 0;
    }

    get asyncUsageStyle() {
        const pct = Math.max(0, Math.min(100, Number(this.monitoringSnapshot?.asyncApexUsedPct || 0)));
        return `background: conic-gradient(#0b5cab 0 ${pct}%, #dfe7f3 ${pct}% 100%);`;
    }

    get asyncUsageLabel() {
        const pct = Number(this.monitoringSnapshot?.asyncApexUsedPct || 0).toFixed(2);
        return `${pct}% used`;
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

    get fullScanDisabled() {
        return this.isBusy || this.dashboardLocked || this.isLatestJobBlockingFullScan;
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

    get effectiveModeLabel() {
        return this.currentMode === 'AI' ? 'AI Mode' : 'Standard Mode';
    }

    get modeBannerClass() {
        return this.isAiModeActive ? 'mode-banner mode-banner-ai' : 'mode-banner';
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

    get showAssistantWarning() {
        return !this.assistantAvailable && Boolean(this.assistantStatusMessage);
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
        try {
            await Promise.all([
                this.refreshSummary(),
                this.refreshRecommendations(),
                this.refreshGlobalComponents(),
                this.refreshMetadataComponents(),
                this.refreshJobs(1),
                this.loadMonitoringSnapshot()
            ]);
        } catch (error) {
            this.showError(error, 'Failed to load dashboard');
        } finally {
            this.isBusy = false;
        }
    }

    async refreshSummary() {
        if (this.summaryWireResult) {
            await refreshApex(this.summaryWireResult);
        }
    }

    async refreshRecommendations() {
        if (this.recommendationsWireResult) {
            await refreshApex(this.recommendationsWireResult);
        }
    }

    async refreshGlobalComponents() {
        try {
            const sections = await getGlobalComponentSections({ rowLimit: 1000 });
            this.globalComponentSections = Array.isArray(sections) ? sections : [];
            if (!this.globalGroupsInitialized) {
                this.expandedGlobalGroups = [];
                this.globalGroupsInitialized = true;
            }
        } catch (error) {
            this.showError(error, 'Failed to load global components');
        }
    }

    async refreshMetadataComponents() {
        if (this.metadataWireResult) {
            await refreshApex(this.metadataWireResult);
        }
    }

    async loadMonitoringSnapshot() {
        try {
            const snapshot = await getMonitoringSnapshot();
            this.monitoringSnapshot = {
                ...this.monitoringSnapshot,
                ...(snapshot || {})
            };
        } catch (error) {
            this.monitoringSnapshot = {
                ...this.monitoringSnapshot,
                limitMetrics: [],
                platformEvents: []
            };
        }
    }

    async refreshJobs(pageNumber) {
        const page = await getRecentJobs({
            pageNumber,
            pageSize: this.JOBS_PAGE_SIZE
        });
        this.jobs = page?.jobs || [];
        this.jobsTotalCount = page?.totalCount || 0;
        this.jobsPageNumber = page?.pageNumber || 1;
    }

    async handleRunFullScan() {
        if (this.dashboardLocked) {
            this.showToast('Error', 'Complete setup wizard before running dashboard operations.', 'error');
            return;
        }
        await this.runJob(runFullScan, 'Full scan queued');
    }

    async runJob(apexMethod, successMessage) {
        this.isBusy = true;
        try {
            const requestId = `${Date.now()}`;
            const response = await apexMethod({ requestId });
            const jobId = response?.jobId;
            const suffix = jobId ? ` Job Id: ${jobId}` : ' Running in reduced-storage mode (no ScanJob record).';
            this.showToast('Success', `${successMessage}.${suffix}`, 'success');
            await Promise.all([this.refreshSummary(), this.refreshRecommendations(), this.refreshGlobalComponents(), this.refreshMetadataComponents(), this.refreshJobs(1)]);
        } catch (error) {
            this.showError(error, 'Failed to queue job');
        } finally {
            this.isBusy = false;
        }
    }

    async handleActionFilterChange(event) {
        this.actionFilter = event.detail.value;
    }

    async handleStatusFilterChange(event) {
        this.statusFilter = event.detail.value;
    }

    handleSearchInputChange(event) {
        this.searchFilter = event.detail.value;
        window.clearTimeout(this.searchSuggestionTimer);
        this.searchSuggestionTimer = window.setTimeout(() => {
            this.searchSuggestions = this.buildSearchSuggestions(this.normalizedSearchFilter);
        }, 180);
        this.isSearchModalOpen = false;
        this.searchResults = [];
    }

    handleSearchInputKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            window.clearTimeout(this.searchSuggestionTimer);
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

    handleModeChange(event) {
        const requestedMode = event.detail.value;
        if (requestedMode === 'AI' && !this.assistantAvailable) {
            this.currentMode = 'Standard';
            return;
        }
        this.currentMode = requestedMode;
        if (this.currentMode !== 'AI') {
            this.isChatOpen = false;
        }
    }

    handleTabChange(event) {
        this.activeDashboardTab = event.target.value;
    }

    async loadAgentAssistantAvailability() {
        try {
            const state = await getAgentAssistantAvailability();
            this.assistantAvailable = state?.available === true;
            this.assistantStatusMessage = state?.message || '';
            this.currentMode = this.assistantAvailable ? 'AI' : 'Standard';
        } catch (error) {
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

    handleRecommendationRowAction(event) {
        const rowId = event?.currentTarget?.dataset?.rowId;
        const row = this.recommendations.find((item) => item?.id === rowId);
        if (!row) {
            return;
        }
        this.selectedUsage = this.buildNextStepDetails(this.enrichRecommendationRow(row));
        this.isUsageModalOpen = true;
    }

    handleGlobalRowAction(event) {
        const rowKey = event?.currentTarget?.dataset?.rowKey;
        let matchedRow;
        this.filteredGlobalSections.some((section) => {
            matchedRow = (section?.rows || []).find((row) => row?.key === rowKey);
            return Boolean(matchedRow);
        });
        if (!matchedRow) {
            return;
        }
        this.selectedUsage = this.buildNextStepDetails(matchedRow);
        this.isUsageModalOpen = true;
    }

    handleCloseUsageModal() {
        this.isUsageModalOpen = false;
        this.selectedUsage = null;
    }

    handleCloseSearchModal() {
        this.isSearchModalOpen = false;
        this.searchResults = [];
    }

    handleSearchSuggestionClick(event) {
        const resultKey = event?.currentTarget?.dataset?.resultKey;
        const matched = (this.searchSuggestions || []).find((item) => item?.key === resultKey);
        if (!matched) {
            return;
        }
        this.searchFilter = matched.title;
        this.searchSuggestions = [];
        this.selectedUsage = this.buildNextStepDetails(matched.sourceRow);
        this.isUsageModalOpen = true;
    }

    handleSearchResultClick(event) {
        const resultKey = event?.currentTarget?.dataset?.resultKey;
        const matched = (this.searchResults || []).find((item) => item?.key === resultKey);
        if (!matched) {
            return;
        }
        this.handleCloseSearchModal();
        this.searchSuggestions = [];
        this.selectedUsage = this.buildNextStepDetails(matched.sourceRow);
        this.isUsageModalOpen = true;
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
        this.setSetupWizardStepStorage(1);
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Clarity360_Setup'
            }
        });
    }

    handleOpenConfiguration() {
        this.setSetupWizardStepStorage(3);
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Clarity360_Setup'
            }
        });
    }

    handleOpenReadiness() {
        this.setSetupWizardStepStorage(2);
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Clarity360_Setup'
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
        parts.push(row?.whyVisible || 'Shown because it was included in metadata inventory.');
        parts.push(`Next: ${row?.nextStep || 'Refresh after the next scan if you need more evidence.'}`);
        return parts.join(' | ');
    }

    enrichMetadataRow(row) {
        const priority = this.evaluateMetadataPriority(row);
        return {
            ...row,
            priorityLabel: priority.label,
            priorityRank: priority.rank,
            priorityClass: this.priorityClassFor(priority.tone)
        };
    }

    enrichRecommendationRow(row) {
        const evidence = this.parseEvidence(row?.evidenceSummary);
        const usageMetrics = this.extractUsageMetrics(evidence);
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
        const hasLiveCoverageData = String(row?.fieldKey || '').startsWith('GLOBAL.APEXCLASS.') && Boolean(liveCoverageLabel);
        const showCoverageHint = String(row?.fieldKey || '').startsWith('GLOBAL.APEXCLASS.') && !usageMetrics.hasCoverageData && !hasLiveCoverageData;
        const hasRecommendation = Boolean(mergedRecommendation);
        const statusTone = this.getStatusTone(row?.status, hasRecommendation, showCoverageHint);
        const reason = hasLiveCoverageData && mergedRecommendation?.showCoverageHint === true
            ? `Apex Class (Coverage=${liveCoverageLabel})`
            : (mergedRecommendation?.reasonDisplay || 'Usage evidence has not been calculated yet.');
        const usageDisplay = hasLiveCoverageData && mergedRecommendation?.showCoverageHint === true
            ? `Coverage ${liveCoverageLabel}`
            : (mergedRecommendation?.usageDisplay || this.buildUsageSummary(usageMetrics));
        const priority = this.evaluateGlobalPriority(row, mergedRecommendation, usageMetrics, showCoverageHint);
        return {
            ...row,
            hasRecommendation,
            displayName: row?.objectName ? `${row.objectName} / ${row.componentName}` : row?.componentName,
            typeCaption: row?.componentType || 'Global Component',
            action: mergedRecommendation?.action || 'Pending analysis',
            reason,
            usageDisplay,
            priorityLabel: priority.label,
            priorityRank: priority.rank,
            priorityClass: this.priorityClassFor(priority.tone),
            riskDisplay: mergedRecommendation?.riskDisplay || 'Pending',
            confidenceDisplay: mergedRecommendation?.confidenceDisplay || 'Pending',
            showCoverageHint,
            showEvidenceHint: showCoverageHint ? false : (!hasRecommendation || mergedRecommendation?.showEvidenceHint === true),
            evidenceHint: showCoverageHint
                ? 'Coverage is pending. Run Full Scan or Usage Scan again, then refresh this dashboard.'
                : this.buildEvidenceGuidance(row?.componentType, hasRecommendation),
            detailDisplay: row?.detail || (row?.objectName ? `Scoped to ${row.objectName}` : 'Metadata inventory row'),
            itemClass: `global-component-item global-component-item-${statusTone}`,
            statusClass: `global-component-status global-component-status-${statusTone}`
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

    setSetupWizardStepStorage(step) {
        try {
            window.sessionStorage.setItem(`clarity360.setup.overrideStep.${window.location.hostname}`, String(step));
            window.sessionStorage.setItem(`clarity360.setup.currentStep.${window.location.hostname}`, String(step));
        } catch (error) {
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

    getStatusTone(status, hasRecommendation, showCoverageHint) {
        if (this.isInactiveStatusValue(status)) {
            return 'warning';
        }
        if (showCoverageHint || hasRecommendation) {
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

    evaluateGlobalPriority(row, recommendation, usageMetrics, showCoverageHint) {
        const riskScore = this.toDecimal(recommendation?.riskScore);
        const isInactive = this.isInactiveGlobalComponent(row);

        if (showCoverageHint || riskScore >= 85) {
            return { label: 'Needs Action', rank: 3, tone: 'needs-action' };
        }
        if (isInactive || riskScore >= 70) {
            return { label: 'Critical', rank: 2, tone: 'critical' };
        }
        if (recommendation || usageMetrics?.activeRefs > 0 || usageMetrics?.inactiveRefs > 0) {
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
        return String(status || '').toLowerCase() === 'active';
    }

    isInactiveStatusValue(status) {
        const normalized = String(status || '').toLowerCase();
        return normalized === 'inactive' || normalized === 'obsolete';
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

    buildNextStepDetails(row) {
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

        let deleteGuidance = 'Deletion requires manual review.';
        let deleteAllowed = false;
        if (!isCustomField) {
            deleteGuidance = 'Only custom fields are considered for deletion.';
        } else if (isManagedPackageField) {
            deleteGuidance = 'Managed-package fields should not be deleted from this dashboard. Review the package impact first.';
        } else if (hasConcreteUsage) {
            deleteGuidance = 'Field is referenced by triggers, validation rules, flows, or Apex classes.';
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
            apexClassRefs
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
            } else if (context.hasConcreteUsage) {
                steps.push('Deprecate the field gradually: remove layouts, help text, and automation references before deletion.');
            } else if (context.deleteAllowed) {
                steps.push('Field looks removable. Confirm with the business owner, then delete it and rerun Inventory Refresh.');
            } else if (!context.hasDataKnown) {
                steps.push('Run Usage Scan again to improve data sampling before making a delete decision.');
            }
        }
        if (context.isInactiveGlobal) {
            steps.push('Confirm with the owner that this inactive automation is no longer needed.');
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
        } catch (error) {
            return String(value);
        }
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
