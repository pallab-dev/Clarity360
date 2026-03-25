# Clarity360 Maintenance Guide

## Why There Are Many Classes

The package is already split by responsibility, which is the right tradeoff for managed-package safety:

- Setup and onboarding: `Clarity360SetupWizardController`, `Clarity360SetupConfigService`, `Clarity360SetupValidationService`, `Clarity360PostInstallHandler`
- Scan orchestration: `ScanOrchestrator`, `InventoryRefreshQueueable`, `UsageScanBatch`, `RecommendationRebuildQueueable`, `ScanOrchestratorSchedulable`
- Inventory and evidence: `InventoryService`, `DataSampler`, `LayoutScanService`, `DependencySignalService`, `MetadataComponentInventoryService`, `SignalRepository`
- Recommendations and reporting: `RecommendationEngine`, `Clarity360ScanReportService`, `GovernorTrendService`
- UI facade: `Clarity360DashboardController`, `Clarity360SetupWizardController`
- Security and infrastructure: `Clarity360AccessControlService`, `ToolingApiService`, `ScanJobRepository`, `Clarity360SecureLog`

The count looks high because Apex does not support folders or namespaces inside the package source. Functionally, these classes are a few bounded modules, not one large tangled codebase.

## What Not To Merge

Avoid merging these concerns just to reduce file count:

- Controllers with services
- Queueables and batches with synchronous services
- Setup validation with scan execution
- Access-control logic with business logic

That would reduce the visible class count but increase regression risk, test setup cost, and PMD/security noise.

## Current Scan Guardrails

First-time installs already have several protections for large orgs:

- Inventory scope is capped by `Clarity360Config.Default`:
  - `MaxInventoryObjects__c = 200`
  - `MaxScanObjects__c = 30`
  - `SamplingLimit__c = 5000`
- Inventory processing is chunked in [InventoryRefreshQueueable.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/InventoryRefreshQueueable.cls) with `OBJECTS_PER_CHUNK = 10`
- Inventory refresh also limits per-object field inventory in [InventoryService.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/InventoryService.cls) with `MAX_FIELDS_PER_OBJECT = 200`
- Usage sampling runs as a batch with batch size `1` in [UsageScanBatch.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/UsageScanBatch.cls)
- If storage is exhausted, [ScanOrchestrator.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/ScanOrchestrator.cls) attempts to purge derived data (`UsageSignal__c`, `Recommendation__c`, old `ScanJob__c`) before retrying job creation
- Setup readiness already warns on async capacity and storage health in [Clarity360SetupValidationService.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/Clarity360SetupValidationService.cls)

## First-Install Runtime Behavior

For a fresh customer org, the current path is:

1. Post install creates the setup config record if missing.
2. Admin completes Setup Wizard.
3. Full scan starts inventory first.
4. Inventory chains queueables until all scoped objects are processed.
5. Usage scan runs only after inventory completes.
6. Recommendation rebuild runs after usage evidence is written.

This means the first run is intentionally large, but it is not a single monolithic transaction.

## Practical Handoff Guidance

When sharing this project with another engineer, point them to these files first:

- [Clarity360DashboardController.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/Clarity360DashboardController.cls)
- [ScanOrchestrator.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/ScanOrchestrator.cls)
- [InventoryService.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/InventoryService.cls)
- [DataSampler.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/DataSampler.cls)
- [RecommendationEngine.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/RecommendationEngine.cls)
- [Clarity360Settings.cls](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/classes/Clarity360Settings.cls)
- [clarity360Dashboard.js](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/lwc/clarity360Dashboard/clarity360Dashboard.js)
- [clarity360SetupWizard.js](/Users/pallabsaikia/Downloads/Clarity360/force-app/main/default/lwc/clarity360SetupWizard/clarity360SetupWizard.js)

That gives a new contributor the package boundary, orchestration model, and UI flow without reading every Apex file first.
