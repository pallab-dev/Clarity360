# Clarity360 As-Built LLD

## 1. What this project is

Clarity360 is a Salesforce DX app that helps admins identify low-value metadata and field cleanup opportunities.

The implemented product has 5 runtime layers:

1. Setup and readiness
2. Inventory scan
3. Usage and dependency scan
4. Recommendation generation
5. Dashboard and Agentforce access

The package is deployed from `force-app/` and is validated/deployed through GitHub Actions in `.github/workflows/ci.yml`.

## 2. Where the project starts

There are 4 practical starting points for understanding the system:

1. Package install
   - `Clarity360PostInstallHandler.cls`
   - Ensures one `Clarity360SetupConfig__c` record exists after install.

2. App navigation
   - `applications/Clarity360.app-meta.xml`
   - Tabs:
     - `Clarity360_Dashboard`
     - `Clarity360_Setup`

3. Setup wizard entry point
   - LWC: `clarity360SetupWizard`
   - Apex: `Clarity360SetupWizardController`

4. Dashboard entry point
   - LWC: `clarity360Dashboard`
   - Apex: `Clarity360DashboardController`

## 3. End-to-end flow from UI to code

### Flow A: Install to setup complete

1. Package installs.
2. `Clarity360PostInstallHandler` creates default runtime config if missing.
3. User opens `Clarity360 Setup` tab.
4. `clarity360SetupWizard` calls:
   - `isSetupComplete()`
   - `getSetupState()`
   - `runReadinessChecks()`
   - `saveRuntimeConfig()`
   - `runInitialRun()`
5. Config is stored in `Clarity360SetupConfig__c`.
6. Readiness checks validate permissions, storage, Tooling API access, UI/component presence, and Agentforce readiness.
7. Setup is marked complete by setting `Clarity360SetupConfig__c.IsSetupComplete__c = true`.

### Flow B: Inventory refresh

1. User clicks `Run Inventory Refresh` from dashboard.
2. `clarity360Dashboard` calls `Clarity360DashboardController.runInventoryRefreshV2()`.
3. Controller checks setup complete.
4. `ScanOrchestrator.runInventoryOnlyV2()` creates/reuses a `ScanJob__c`.
5. `InventoryRefreshQueueable` runs in chunks.
6. `InventoryService` describes org objects and fields.
7. Discovered fields are upserted into `FieldInventory__c`.
8. Removed fields are deleted from `FieldInventory__c`.
9. `ScanJob__c` is updated with progress and completion.

### Flow C: Usage scan

1. User clicks `Run Usage Scan`.
2. `Clarity360DashboardController.runUsageScanV2()` calls `ScanOrchestrator.runUsageScanOnlyV2()`.
3. A `ScanJob__c` is created/reused.
4. `UsageScanBatch` groups `FieldInventory__c` by object.
5. For each object:
   - `DataSampler.scanObject()` samples records
   - counts field non-null usage
   - calls `DependencySignalService.scan()` for dependency evidence
6. Results are upserted into `UsageSignal__c` by `SignalRepository`.
7. Batch finish enqueues `RecommendationRebuildQueueable`.

### Flow D: Full scan

1. User clicks `Run Full Scan`.
2. `Clarity360DashboardController.runFullScanV2()` calls `ScanOrchestrator.runFullScanV2()`.
3. `FullScanQueueable`:
   - runs inventory refresh first
   - then launches `UsageScanBatch`
4. `UsageScanBatch.finish()` triggers recommendation rebuild.

### Flow E: Recommendation generation

1. `RecommendationRebuildQueueable` calls `RecommendationEngine.rebuildAllRecommendations()`.
2. Engine reads latest `UsageSignal__c` rows.
3. It resolves linked `FieldInventory__c`.
4. It builds 2 recommendation families:
   - field-level recommendations from usage signals
   - global metadata recommendations for inactive triggers, inactive validation rules, inactive flows/processes, inactive workflow rules, and Apex classes with coverage evidence
5. Output is upserted into `Recommendation__c`.
6. Stale recommendations are deleted.

### Flow F: Dashboard and Agentforce usage

1. Dashboard LWC loads summary, recommendations, recent jobs, setup state, and AI availability.
2. Apex controller methods return aggregated data from:
   - `FieldInventory__c`
   - `UsageSignal__c`
   - `Recommendation__c`
   - `ScanJob__c`
3. In AI mode, dashboard chat calls `askAgentAssistant()`.
4. That method routes to:
   - `ExplainRecommendation`
   - `GetHighRiskRecommendations`
   - `GetRecentScanSummary`
   - or a simple controller-side ranking/summary path

## 4. Metadata inventory by layer

### Application metadata

- Custom Application: `Clarity360`
- Custom Tabs:
  - `Clarity360_Dashboard`
  - `Clarity360_Setup`
- Permission Set:
  - `Clarity360_Admin`

### UI components

- LWC `clarity360SetupWizard`
  - guided onboarding
  - readiness checks
  - runtime config save
  - initial scan launch

- LWC `clarity360Dashboard`
  - summary tiles
  - recommendation grids
  - scan buttons
  - jobs list
  - field usage modal
  - AI/Agentforce chat shell

### Apex controllers and services

- `Clarity360SetupWizardController`
  - setup UI controller
- `Clarity360DashboardController`
  - dashboard UI controller
- `ScanOrchestrator`
  - async scan launcher
- `InventoryService`
  - object/field discovery
- `DataSampler`
  - record sampling and null-rate analysis
- `DependencySignalService`
  - trigger, validation rule, flow, workflow, Apex dependency evidence
- `RecommendationEngine`
  - recommendation scoring and generation
- `ToolingApiService`
  - Tooling API query/delete abstraction
- `Clarity360AgentActions` + invocable wrappers
  - Agentforce integration

### Async metadata

- Queueables:
  - `InventoryRefreshQueueable`
  - `FullScanQueueable`
  - `RecommendationRebuildQueueable`
- Batch:
  - `UsageScanBatch`
- Schedulable:
  - `ScanOrchestratorSchedulable`

### Triggers included for dependency visibility

- `AccountUsageSignalTrigger`
- `ContactInactiveSignalTrigger`

These are not orchestration triggers. They act as dependency/reference examples so scans can observe active/inactive metadata usage patterns.

### Config metadata

- Custom Metadata Type:
  - `Clarity360Config__mdt`
- Seed record:
  - `Clarity360Config.Default`

Used for defaults like:

- minimum object record count
- Apex coverage threshold
- trigger scan enablement
- validation rule scan enablement
- flow/process scan enablement
- workflow rule scan enablement
- Apex coverage scan enablement
- max Tooling API rows
- sampling limit
- max inventory objects
- max scan objects

Practical ownership after current refactor:

- developer-owned engine thresholds and feature switches come from metadata
- subscriber setup should control scope and behavior preferences, not scan-capacity tuning

## 5. Objects used and what each stores

### `Clarity360SetupConfig__c`

Purpose: subscriber-editable runtime setup/config record.

Important fields:

- `IsSetupComplete__c`
- `ScopeMode__c`
- `IncludeStandardObjects__c`
- `CoverageThreshold__c`
- `UseNamedCredential__c`
- `ConnectionStatus__c`
- `EnableUsageSampling__c`
- `EnableDependencyAnalysis__c`
- `EnableLayoutScan__c`
- `EnableScheduledScan__c`
- `EnableGlobalRecommendations__c`
- `EnableDeletionGuardrails__c`
- `ScheduleEnabled__c`
- `ScheduleFrequency__c`
- `ExcludedObjects__c`
- `ExcludedNamespaces__c`

Used by:

- setup wizard
- readiness checks
- scan orchestrator
- scheduler gate

Note:

- `SamplingLimit__c`, `MaxInventoryObjects__c`, and `MaxScanObjects__c` still exist on the object for backward compatibility, but are no longer treated as primary user-facing setup controls
- runtime scan-capacity guardrails are now developer-managed outside the setup UI

### `FieldInventory__c`

Purpose: catalog of discovered fields in scope.

Important fields:

- `FieldKey__c` as natural key (`Object.Field`)
- `ObjectApiName__c`
- `FieldApiName__c`
- `DataType__c`
- `IsCustomField__c`
- `IncludedInScope__c`
- `LastScannedOn__c`
- `NamespacePrefix__c`
- `IsActive__c`

Used by:

- inventory refresh
- usage scan scope
- recommendation linking
- cleanup deletion

### `UsageSignal__c`

Purpose: usage evidence per field.

Important fields:

- `FieldKey__c`
- `FieldInventory__c`
- `SampleSize__c`
- `NonNullCount__c`
- `NullRatePct__c`
- `IsOnLayout__c`
- `LastObservedOn__c`
- `EvidenceSummary__c`

Used by:

- recommendation engine
- dashboard usage modal
- deletion guardrails
- Agentforce summaries

### `Recommendation__c`

Purpose: output recommendation records for fields and global metadata components.

Important fields:

- `FieldKey__c`
- `FieldInventory__c`
- `Action__c`
- `ConfidenceScore__c`
- `RiskScore__c`
- `EvidenceSummary__c`
- `Status__c`
- `LastEvaluatedOn__c`

Used by:

- dashboard recommendation grid
- Agentforce explanation/high-risk actions
- AI chat ranking
- cleanup prioritization

Note:

- Field-level keys look like `Account.Legacy_Flag__c`
- Global metadata keys look like:
  - `GLOBAL.TRIGGER.*`
  - `GLOBAL.VALRULE.*`
  - `GLOBAL.FLOW.*`
  - `GLOBAL.WORKFLOW.*`
  - `GLOBAL.APEXCLASS.*`

### `ScanJob__c`

Purpose: operational tracking for every scan run.

Important fields:

- `JobType__c`
- `Status__c`
- `StartedOn__c`
- `FinishedOn__c`
- `ProgressPct__c`
- `ScopeSummary__c`
- `TotalObjects__c`
- `PendingObjects__c`
- `ErrorMessage__c`

Used by:

- dashboard recent jobs
- scan deduplication/reuse
- scan progress tracking
- recent scan summary action

## 6. Component-to-object mapping

### Setup Wizard

UI:

- `clarity360SetupWizard`

Controller/services:

- `Clarity360SetupWizardController`
- `Clarity360SetupConfigService`
- `Clarity360SetupValidationService`
- `Clarity360SetupConnectionService`
- `Clarity360SetupOrchestratorService`

Objects touched:

- `Clarity360SetupConfig__c`
- `ScanJob__c`

### Dashboard

UI:

- `clarity360Dashboard`

Controller/services:

- `Clarity360DashboardController`
- `ScanOrchestrator`
- `ToolingApiService`
- `EvidenceParser`

Objects touched:

- `FieldInventory__c`
- `UsageSignal__c`
- `Recommendation__c`
- `ScanJob__c`
- `Clarity360SetupConfig__c`

### Inventory scanning

Classes:

- `ScanOrchestrator`
- `InventoryRefreshQueueable`
- `InventoryService`

Objects touched:

- writes `FieldInventory__c`
- writes `ScanJob__c`

### Usage scanning

Classes:

- `UsageScanBatch`
- `DataSampler`
- `DependencySignalService`
- `SignalRepository`

Objects touched:

- reads `FieldInventory__c`
- writes `UsageSignal__c`
- updates `ScanJob__c`

### Recommendation generation

Classes:

- `RecommendationRebuildQueueable`
- `RecommendationEngine`
- `EvidenceParser`

Objects touched:

- reads `UsageSignal__c`
- reads `FieldInventory__c`
- writes `Recommendation__c`

### Agentforce

Classes:

- `Clarity360AgentActions`
- `Clarity360ExplainRecommendationAction`
- `Clarity360HighRiskRecsAction`
- `Clarity360GetRecentScanSummaryAction`

Objects touched:

- reads `Recommendation__c`
- reads `ScanJob__c`

## 7. How recommendation logic currently works

### Field-level recommendation logic

Main inputs:

- sampled record count
- non-null count
- null rate
- object record count
- active/inactive dependency counts
- Apex class references
- Apex coverage evidence

Current actions returned:

- `Keep`
- `Deprecate`
- `Investigate Dependencies`

High-level logic:

1. No sample data -> `Investigate Dependencies`
2. Has data and low null rate -> `Keep`
3. No data, enough records, no active dependencies, good/no-risk coverage -> `Deprecate`
4. Anything uncertain -> `Investigate Dependencies`

### Global recommendation logic

The engine also creates recommendations for:

- inactive Apex triggers
- inactive validation rules
- inactive flows/processes
- inactive workflow rules
- Apex classes with low or missing coverage context

These are stored in the same `Recommendation__c` object using `GLOBAL.*` keys.

## 8. Security and access model

Implemented controls:

- `Clarity360AccessControlService`
  - read/create assertions
  - `Security.stripInaccessible()` for readable records
- `with sharing` on core classes
- `Clarity360_Admin` permission set
- readiness checks for object/field access

Practical admin requirement:

- User needs admin-style privileges plus access to Clarity360 objects and Apex classes.

## 9. Deployment and CI/CD

Source/deployment model:

- SFDX project
- source under `force-app`
- API version `65.0`

GitHub Actions:

- Node install
- Prettier check
- ESLint
- LWC Jest tests
- Salesforce Code Analyzer
- check-only deploy on PR to `testing`
- full deploy on push to `testing`
- Apex coverage gate at 80%

Manifests:

- `manifest/package.xml`
  - minimal package manifest
- `manifest/cleanup-package.xml`
  - larger metadata package definition used for cleanup/deployment packaging
- `manifest/destructiveChanges-post.xml`
  - removes older/retired classes like `LayoutScanner`, interface-based settings abstractions, and related probe classes

## 10. What is implemented vs what is still partial

### Implemented

- Setup wizard with readiness checks
- Post-install config bootstrap
- Dashboard with scan actions, recommendation grid, jobs list, and usage modal
- Inventory scan for object/field discovery
- Usage scan with data sampling
- Dependency analysis for triggers, validation rules, flows/processes, and Apex classes
- Recommendation generation for field-level and global metadata findings
- Agentforce invocable actions
- Basic AI-mode chat shell in dashboard
- Tooling API delete path for custom field cleanup
- CI pipeline with JS and Apex quality gates

### Partial / not fully wired

- `EnableLayoutScan__c`
  - config exists, but no active layout scan implementation is present
  - `IsOnLayout__c` is currently written as `false` in `DataSampler`

- `EnableDeletionGuardrails__c`
  - config exists, but delete guardrails run unconditionally in controller logic
  - flag is not used to enable/disable behavior

- `EnableDependencyAnalysis__c`
  - runtime scan path now respects this setup flag before applying metadata-level dependency scanners

- `EnableUsageSampling__c`
  - runtime scan launch now checks this flag and skips usage sampling when disabled

- `EnableGlobalRecommendations__c`
  - global recommendation generation is now gated by this field

- `ExcludedObjects__c` and `ExcludedNamespaces__c`
  - now applied in inventory refresh and usage scan scope logic
  - excluded inventory rows and related derived rows are cleaned up during inventory refresh

- `ScheduleEnabled__c` and `ScheduleFrequency__c`
  - setup save now reconciles the scheduled job
  - schedule create/update/remove is now wired to setup state and frequency

- `UseNamedCredential__c`
  - setup now affects Tooling API callout preference order
  - fallback between Named Credential and session still exists

- Setup connection test
  - Apex exists, but setup LWC does not currently expose a dedicated connection-test action

### Technical leftovers visible from manifests

- `manifest/destructiveChanges-post.xml` shows an older design was removed:
  - `LayoutScanner`
  - `Clarity360SettingsProvider`
  - several interface-based abstractions
  - `CoverageGapProbe`

This means the current codebase is already in a simplified "as-built" architecture, and the destructive manifest is part of that cleanup.

## 11. Suggested backlog: what needs to be done next

### Priority 1

- Implement real layout scanning and populate `UsageSignal__c.IsOnLayout__c`
- Add UI exposure for dedicated connection-test action if setup users need explicit callout verification
- Add stronger tests around schedule reconciliation and exclusion cleanup in mixed-org datasets
- Add dashboard/admin visibility into the effective developer-managed scan limits loaded from metadata

### Priority 2

- Make deletion guardrails configurable through `EnableDeletionGuardrails__c`
- Add dashboard visibility/filtering for global recommendations vs field recommendations
- Improve schedule UX by showing current next-run state and allowing clearer enable/disable messaging

### Priority 3

- Add stronger object/field metadata population in `FieldInventory__c`
  - current inventory refresh mainly persists `FieldKey__c`, `ObjectApiName__c`, `FieldApiName__c`
  - fields like `DataType__c`, `IsCustomField__c`, `IncludedInScope__c`, `NamespacePrefix__c`, `LastScannedOn__c` are present in metadata but not fully populated in current logic
- Add stronger observability around partial scan failures
- Add more LWC tests for setup wizard and AI-mode flows

## 12. File map for handoff

If a new developer wants to understand the code fast, this is the best reading order:

1. `README.md`
2. `docs/Agentforce_Admin_Copilot_README.md`
3. `force-app/main/default/applications/Clarity360.app-meta.xml`
4. `force-app/main/default/lwc/clarity360SetupWizard/*`
5. `force-app/main/default/classes/Clarity360SetupWizardController.cls`
6. `force-app/main/default/classes/Clarity360SetupConfigService.cls`
7. `force-app/main/default/classes/Clarity360SetupValidationService.cls`
8. `force-app/main/default/lwc/clarity360Dashboard/*`
9. `force-app/main/default/classes/Clarity360DashboardController.cls`
10. `force-app/main/default/classes/ScanOrchestrator.cls`
11. `force-app/main/default/classes/InventoryService.cls`
12. `force-app/main/default/classes/UsageScanBatch.cls`
13. `force-app/main/default/classes/DataSampler.cls`
14. `force-app/main/default/classes/DependencySignalService.cls`
15. `force-app/main/default/classes/RecommendationEngine.cls`
16. `force-app/main/default/classes/ToolingApiService.cls`
17. `force-app/main/default/objects/*`
18. `.github/workflows/ci.yml`

## 13. Short architecture summary

Clarity360 starts with setup, stores runtime settings in `Clarity360SetupConfig__c`, scans org metadata into `FieldInventory__c`, samples org data and dependencies into `UsageSignal__c`, converts those signals into `Recommendation__c`, tracks execution in `ScanJob__c`, and exposes the results through the dashboard and Agentforce actions.

That is the current implemented flow. The main unfinished areas are layout awareness, dedicated setup connection testing in the UI, configurable deletion guardrails in controller paths, dashboard/admin visibility into effective runtime limits, and stronger observability around partial failures.
