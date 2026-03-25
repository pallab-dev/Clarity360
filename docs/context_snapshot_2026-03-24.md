# Clarity360 Context Snapshot (2026-03-24)

## What was gathered
- Repository context was collected from local source and documentation files.
- A complete repository file manifest (excluding `node_modules`) was generated at `docs/context_file_manifest.txt`.
- Salesforce org live context could not be collected in this environment because Salesforce CLI binaries are unavailable.

## Salesforce org access check
- Command attempted: `sf --version && sf org list --json` → `/bin/bash: sf: command not found`.
- Command attempted: `sfdx --version && sfdx force:org:list --json` → `/bin/bash: sfdx: command not found`.
- Result: no direct org session or metadata pull was possible from this runtime.

## Repository inventory summary (excluding node_modules)
- Total files inventoried: **214**.
  - `(root)`: 12
  - `.github`: 7
  - `.husky`: 1
  - `.vscode`: 3
  - `config`: 1
  - `docs`: 5
  - `force-app`: 180
  - `manifest`: 5

## Salesforce metadata footprint (`force-app/main/default`)
- Total metadata files: **180**.
  - `applications`: 1
  - `classes`: 80
  - `customMetadata`: 1
  - `lwc`: 9
  - `objects`: 82
  - `permissionsets`: 1
  - `tabs`: 2
  - `triggers`: 4

### Custom objects / metadata entities
- `Clarity360Config__mdt`
- `Clarity360SetupConfig__c`
- `FieldInventory__c`
- `MetadataComponentInventory__c`
- `Recommendation__c`
- `ScanJob__c`
- `UsageSignal__c`

### Apex classes
- `Clarity360AccessControlService`
- `Clarity360AgentActions`
- `Clarity360AgentActionsTest`
- `Clarity360DashboardController`
- `Clarity360DashboardControllerTest`
- `Clarity360ExplainRecommendationAction`
- `Clarity360GetRecentScanSummaryAction`
- `Clarity360HighRiskRecsAction`
- `Clarity360PostInstallHandler`
- `Clarity360PostInstallHandlerTest`
- `Clarity360ScheduleService`
- `Clarity360ScheduleServiceTest`
- `Clarity360SecureLog`
- `Clarity360Settings`
- `Clarity360SetupConfigService`
- `Clarity360SetupConnectionService`
- `Clarity360SetupOrchestratorService`
- `Clarity360SetupValidationService`
- `Clarity360SetupWizardController`
- `Clarity360SetupWizardControllerTest`
- `DataSampler`
- `DataSamplerTest`
- `DependencySignalService`
- `EvidenceParser`
- `FullScanQueueable`
- `InventoryRefreshQueueable`
- `InventoryService`
- `InventoryServiceTest`
- `MetadataComponentInventoryService`
- `MetadataComponentInventoryServiceTest`
- `RecommendationEngine`
- `RecommendationEngineTest`
- `RecommendationRebuildQueueable`
- `ScanJobRepository`
- `ScanOrchestrator`
- `ScanOrchestratorSchedulable`
- `ScanOrchestratorTest`
- `SignalRepository`
- `ToolingApiService`
- `UsageScanBatch`

### Lightning Web Components
- `clarity360Dashboard`
- `clarity360SetupWizard`

## Primary docs checked for architecture context
- `README.md` (branching, CI/CD gates, deployment policy).
- `docs/README.md` (documentation index and links to as-built docs).
- `sfdx-project.json` (project package directory + API version settings).

## Branch parity note
- For explicit `feature/*` vs `production` latest-file parity, see `docs/branch_context_check_2026-03-24.md`.

