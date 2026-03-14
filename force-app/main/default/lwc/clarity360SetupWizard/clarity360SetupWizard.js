import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getSetupState from '@salesforce/apex/Clarity360SetupWizardController.getSetupState';
import isSetupComplete from '@salesforce/apex/Clarity360SetupWizardController.isSetupComplete';
import runReadinessChecks from '@salesforce/apex/Clarity360SetupWizardController.runReadinessChecks';
import saveSetupChoices from '@salesforce/apex/Clarity360SetupWizardController.saveSetupChoices';
import runInitialRun from '@salesforce/apex/Clarity360SetupWizardController.runInitialRun';

const LAST_STEP = 4;
const STEP_STORAGE_KEY_PREFIX = 'clarity360.setup.currentStep';
const STEP_OVERRIDE_KEY_PREFIX = 'clarity360.setup.overrideStep';
const READINESS_GROUPS = [
    {
        key: 'configuration',
        label: 'Configuration',
        keys: ['developerConfig', 'runtimeChoices']
    },
    {
        key: 'access',
        label: 'Access',
        keys: ['adminPrivileges', 'configAccess', 'configFieldAccess', 'operationalAccess']
    },
    {
        key: 'platform',
        label: 'Platform Capacity',
        keys: ['asyncCapacity', 'storageHealth', 'coreComponents']
    },
    {
        key: 'connectivity',
        label: 'Connectivity',
        keys: ['namedCredential', 'toolingApi']
    },
    {
        key: 'agent',
        label: 'Agentforce',
        keys: ['agentAssistant']
    }
];

export default class Clarity360SetupWizard extends NavigationMixin(LightningElement) {
    @track currentStep = 1;
    @track isBusy = false;
    @track readinessStatus = 'Unknown';
    @track readinessChecks = [];
    @track expandedGroups = {
        configuration: true,
        access: true,
        platform: false,
        connectivity: true,
        agent: false
    };
    @track initialRunMessage = '';
    @track runUsageScan = false;
    @track showAdvancedOptions = false;
    explicitStepOverride = false;
    @track config = {};
    @track includeStandardObjects = false;
    @track coverageThreshold = null;
    @track excludedObjects = '';
    @track excludedNamespaces = '';
    @track useNamedCredential = false;
    @track enableScheduledScan = false;
    @track scheduleFrequency = null;

    scheduleOptions = [
        { label: 'Daily', value: 'Daily' },
        { label: 'Weekly', value: 'Weekly' },
        { label: 'Monthly', value: 'Monthly' }
    ];

    connectedCallback() {
        this.restoreStepFromStorage();
        this.initialize();
    }

    get currentStepValue() {
        return String(this.currentStep);
    }

    get isStepWelcome() {
        return this.currentStep === 1;
    }

    get isStepReadiness() {
        return this.currentStep === 2;
    }

    get isStepConfig() {
        return this.currentStep === 3;
    }

    get isStepInitialRun() {
        return this.currentStep === 4;
    }

    get hasBlockedReadiness() {
        return (this.readinessChecks || []).some((item) => item?.status === 'Blocked');
    }

    get readinessSummaryLabel() {
        const checks = this.readinessChecks || [];
        let ready = 0;
        let warning = 0;
        let blocked = 0;
        checks.forEach((item) => {
            if (item?.status === 'Ready') {
                ready += 1;
            } else if (item?.status === 'Warning') {
                warning += 1;
            } else if (item?.status === 'Blocked') {
                blocked += 1;
            }
        });
        return `Ready: ${ready} | Warning: ${warning} | Blocked: ${blocked}`;
    }

    get readinessGroups() {
        return READINESS_GROUPS.map((group) => {
            const checks = this.readinessChecks.filter((item) => group.keys.includes(item.key));
            const counts = this.countStatuses(checks);
            const status = counts.blocked > 0 ? 'Blocked' : counts.warning > 0 ? 'Warning' : 'Ready';
            const expanded = this.expandedGroups[group.key] === true;
            return {
                key: group.key,
                label: group.label,
                checks,
                expanded,
                status,
                summary: `Ready ${counts.ready} | Warning ${counts.warning} | Blocked ${counts.blocked}`,
                sectionClass: `readiness-group readiness-group-${status.toLowerCase()}`,
                iconName: expanded ? 'utility:chevrondown' : 'utility:chevronright'
            };
        }).filter((group) => group.checks.length > 0);
    }

    get disableBack() {
        return this.currentStep <= 1 || this.isBusy;
    }

    get disableNext() {
        return this.isBusy || (this.currentStep === 2 && this.hasBlockedReadiness);
    }

    get isScheduleFrequencyDisabled() {
        return this.enableScheduledScan !== true;
    }

    get nextLabel() {
        return this.currentStep === LAST_STEP ? 'Finish Setup' : 'Next';
    }

    get scopeHelpText() {
        return this.includeStandardObjects === true
            ? 'Clarity360 will scan custom objects and standard objects that are in scope.'
            : 'Clarity360 will focus on custom objects only.';
    }

    get coverageHelpText() {
        return 'This threshold helps recommendation logic interpret Apex coverage evidence. Leave blank to use the org default.';
    }

    get showScheduleControls() {
        return this.enableScheduledScan === true;
    }

    get advancedToggleLabel() {
        return this.showAdvancedOptions ? 'Hide' : 'Show';
    }

    async initialize() {
        this.isBusy = true;
        let completed = false;
        try {
            try {
                completed = await isSetupComplete();
            } catch {
                completed = false;
            }
            const state = await getSetupState();
            const loadedConfig = state?.config || {};
            this.applyLoadedConfig(loadedConfig);
            this.readinessStatus = state?.readiness?.overallStatus || 'Unknown';
            this.readinessChecks = this.decorateChecks(state?.readiness?.checks || []);
            completed = completed || state?.isSetupComplete === true;
        } catch (error) {
            this.showError(error, 'Failed to load setup state');
        } finally {
            if (completed && this.explicitStepOverride !== true) {
                this.currentStep = LAST_STEP;
                this.persistStepToStorage();
            }
            this.isBusy = false;
        }
    }

    async handleRunReadiness() {
        this.isBusy = true;
        try {
            const readiness = await runReadinessChecks();
            this.readinessStatus = readiness?.overallStatus || 'Unknown';
            this.readinessChecks = this.decorateChecks(readiness?.checks || []);
        } catch (error) {
            this.showError(error, 'Failed to run readiness checks');
        } finally {
            this.isBusy = false;
        }
    }

    handleIncludeStandardObjectsChange(event) {
        this.includeStandardObjects = event.target.checked === true;
    }

    handleCoverageThresholdChange(event) {
        const rawValue = event.detail?.value;
        this.coverageThreshold = rawValue === '' || rawValue === null || rawValue === undefined ? null : Number(rawValue);
    }

    handleExcludedObjectsChange(event) {
        this.excludedObjects = event.detail?.value || '';
    }

    handleExcludedNamespacesChange(event) {
        this.excludedNamespaces = event.detail?.value || '';
    }

    handleUseNamedCredentialChange(event) {
        this.useNamedCredential = event.target.checked;
    }

    handleEnableScheduledScanChange(event) {
        const enabled = event.target.checked;
        this.enableScheduledScan = enabled;
        this.scheduleFrequency = enabled ? this.scheduleFrequency : null;
    }

    handleScheduleFrequencyChange(event) {
        this.scheduleFrequency = event.detail?.value || null;
    }

    handleToggleGroup(event) {
        const groupKey = event.currentTarget?.dataset?.group;
        if (!groupKey) {
            return;
        }
        this.expandedGroups = {
            ...this.expandedGroups,
            [groupKey]: this.expandedGroups[groupKey] !== true
        };
    }

    handleRunUsageChange(event) {
        this.runUsageScan = event.target.checked;
    }

    handleToggleAdvanced() {
        this.showAdvancedOptions = !this.showAdvancedOptions;
    }

    async handleStartInitialRun() {
        this.isBusy = true;
        try {
            const requestId = `setup-${Date.now()}`;
            const response = await runInitialRun({
                runUsageScan: this.runUsageScan,
                requestId
            });
            this.initialRunMessage = response?.message || 'Initial run submitted.';
            if (response?.success) {
                this.showToast('Success', this.initialRunMessage, 'success');
            } else {
                this.showToast('Error', this.initialRunMessage, 'error');
            }
        } catch (error) {
            this.showError(error, 'Failed to start initial run');
        } finally {
            this.isBusy = false;
        }
    }

    async handleNext() {
        if (this.currentStep > LAST_STEP) {
            return;
        }
        if (this.currentStep === 2 && this.hasBlockedReadiness) {
            this.showToast('Error', 'Resolve blocked readiness checks before proceeding.', 'error');
            return;
        }
        if (this.currentStep === 3) {
            this.syncConfigFromForm();
            await this.persist(false);
        }
        if (this.currentStep === LAST_STEP) {
            this.syncConfigFromForm();
            await this.persist(true);
            if (!this.isBusy) {
                this.currentStep = LAST_STEP;
                this.persistStepToStorage();
                this.navigateToDashboard();
            }
            return;
        }
        if (!this.isBusy) {
            this.currentStep += 1;
            this.persistStepToStorage();
        }
    }

    handleBack() {
        if (this.currentStep <= 1 || this.isBusy) {
            return;
        }
        this.currentStep -= 1;
        this.persistStepToStorage();
    }

    async persist(markSetupComplete) {
        this.isBusy = true;
        try {
            const response = await saveSetupChoices({
                includeStandardObjects: this.includeStandardObjects,
                coverageThreshold: this.coverageThreshold,
                excludedObjects: this.excludedObjects,
                excludedNamespaces: this.excludedNamespaces,
                useNamedCredential: this.useNamedCredential,
                enableScheduledScan: this.enableScheduledScan,
                scheduleFrequency: this.enableScheduledScan ? this.scheduleFrequency : null,
                markSetupComplete
            });
            this.applyLoadedConfig(response?.config || {});
            if (markSetupComplete) {
                this.showToast('Success', 'Setup marked complete.', 'success');
            }
        } catch (error) {
            this.showError(error, 'Failed to save setup configuration');
        } finally {
            this.isBusy = false;
        }
    }

    decorateChecks(checks) {
        return (checks || []).map((item) => ({
            ...item,
            rowClass: `check-row check-${String(item?.status || '').toLowerCase()}`
        }));
    }

    countStatuses(checks) {
        return (checks || []).reduce(
            (summary, item) => {
                if (item?.status === 'Ready') {
                    summary.ready += 1;
                } else if (item?.status === 'Warning') {
                    summary.warning += 1;
                } else if (item?.status === 'Blocked') {
                    summary.blocked += 1;
                }
                return summary;
            },
            { ready: 0, warning: 0, blocked: 0 }
        );
    }

    showError(error, fallbackMessage) {
        const message =
            error?.body?.message ||
            error?.body?.output?.errors?.[0]?.message ||
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

    navigateToDashboard() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Clarity360_Dashboard'
            }
        });
    }

    getStepStorageKey() {
        return `${STEP_STORAGE_KEY_PREFIX}.${window.location.hostname}`;
    }

    restoreStepFromStorage() {
        try {
            const overrideRaw = window.sessionStorage.getItem(this.getStepOverrideKey());
            if (overrideRaw) {
                window.sessionStorage.removeItem(this.getStepOverrideKey());
                const overrideStep = Number(overrideRaw);
                if (!Number.isNaN(overrideStep) && overrideStep >= 1 && overrideStep <= LAST_STEP) {
                    this.currentStep = overrideStep;
                    this.explicitStepOverride = true;
                    return;
                }
            }

            const raw = window.sessionStorage.getItem(this.getStepStorageKey());
            if (!raw) {
                return;
            }
            const saved = Number(raw);
            if (!Number.isNaN(saved) && saved >= 1 && saved <= LAST_STEP) {
                this.currentStep = saved;
            }
        } catch {
            // Ignore storage access failures in restricted browsing contexts.
        }
    }

    persistStepToStorage() {
        try {
            window.sessionStorage.setItem(this.getStepStorageKey(), String(this.currentStep));
        } catch {
            // Ignore storage access failures in restricted browsing contexts.
        }
    }

    getStepOverrideKey() {
        return `${STEP_OVERRIDE_KEY_PREFIX}.${window.location.hostname}`;
    }

    syncConfigFromForm() {
        if (!this.isStepConfig && !this.isStepInitialRun) {
            return;
        }

        const includeStandardObjectsInput = this.template.querySelector('[data-field="includeStandardObjects"]');
        if (includeStandardObjectsInput) {
            this.includeStandardObjects = includeStandardObjectsInput.checked === true;
        }

        const coverageInput = this.template.querySelector('[data-field="coverageThreshold"]');
        if (coverageInput) {
            const rawCoverage = coverageInput.value;
            this.coverageThreshold =
                rawCoverage === '' || rawCoverage === null || rawCoverage === undefined ? null : Number(rawCoverage);
        }

        const excludedObjectsInput = this.template.querySelector('[data-field="excludedObjects"]');
        if (excludedObjectsInput) {
            this.excludedObjects = excludedObjectsInput.value || '';
        }

        const excludedNamespacesInput = this.template.querySelector('[data-field="excludedNamespaces"]');
        if (excludedNamespacesInput) {
            this.excludedNamespaces = excludedNamespacesInput.value || '';
        }

        const namedCredentialInput = this.template.querySelector('[data-field="useNamedCredential"]');
        if (namedCredentialInput) {
            this.useNamedCredential = namedCredentialInput.checked === true;
        }

        const scheduledScanInput = this.template.querySelector('[data-field="enableScheduledScan"]');
        if (scheduledScanInput) {
            this.enableScheduledScan = scheduledScanInput.checked === true;
        }

        const scheduleFrequencyInput = this.template.querySelector('[data-field="scheduleFrequency"]');
        this.scheduleFrequency =
            this.enableScheduledScan && scheduleFrequencyInput ? scheduleFrequencyInput.value || null : null;
    }

    applyLoadedConfig(loadedConfig) {
        this.config = { ...loadedConfig };
        this.includeStandardObjects = loadedConfig?.includeStandardObjects === true;
        this.coverageThreshold = loadedConfig?.coverageThreshold ?? null;
        this.excludedObjects = loadedConfig?.excludedObjects || '';
        this.excludedNamespaces = loadedConfig?.excludedNamespaces || '';
        this.useNamedCredential = loadedConfig?.useNamedCredential === true;
        this.enableScheduledScan = loadedConfig?.enableScheduledScan === true || loadedConfig?.scheduleEnabled === true;
        this.scheduleFrequency = loadedConfig?.scheduleFrequency || null;
    }
}
