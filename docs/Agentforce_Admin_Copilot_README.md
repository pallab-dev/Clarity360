# Clarity360 Agentforce Admin Copilot (MVP)

## What was added
- `Clarity360AgentActions` shared read-only Apex logic class (`with sharing`)
- Invocable wrapper classes (one `@InvocableMethod` per class):
  - `Clarity360ExplainRecommendationAction`
  - `Clarity360HighRiskRecsAction`
  - `Clarity360GetRecentScanSummaryAction`
- Actions:
  - `ExplainRecommendation`
  - `GetHighRiskRecommendations`
  - `GetRecentScanSummary`
- Structured output envelope for Agentforce actions:
  - `action`
  - `confidenceScore`
  - `riskScore`
  - `explanation`
  - `status`
  - `summary`

## Setup steps
1. Deploy Apex metadata:
   - `force-app/main/default/classes/Clarity360AgentActions.cls`
   - `force-app/main/default/classes/Clarity360AgentActions.cls-meta.xml`
2. Deploy tests:
   - `force-app/main/default/classes/Clarity360AgentActionsTest.cls`
   - `force-app/main/default/classes/Clarity360AgentActionsTest.cls-meta.xml`
3. Run tests:
   - `Clarity360AgentActionsTest`
4. In Agentforce Builder, create custom actions from invocable Apex methods:
   - `Clarity360ExplainRecommendationAction.run`
   - `Clarity360HighRiskRecsAction.run`
   - `Clarity360GetRecentScanSummaryAction.run`

## Suggested topic/action mapping
- Topic: `Recommendation Explanation`
  - User asks: "Why is this field marked for deprecation?"
  - Action: `ExplainRecommendation`
  - Inputs: `recommendationId` (preferred) or `fieldKey`

- Topic: `High-Risk Cleanup Priorities`
  - User asks: "Show me the highest-risk cleanup items."
  - Action: `GetHighRiskRecommendations`
  - Inputs: `minRiskScore` (default 70), `maxResults`, optional `statusFilter`

- Topic: `Scan Health & Status`
  - User asks: "Summarize recent Clarity360 scans."
  - Action: `GetRecentScanSummary`
  - Inputs: `lookbackDays` (default 30)

## Implementation notes
- All actions are read-only (SOQL only; no DML/callouts).
- Inputs are sanitized/clamped for safe execution.
- Responses are null-safe and always return a structured status envelope (`Invalid Input`, `Not Found`, `No Data`, or record-backed status).

## Phase 1 (UI shell + Agentforce orchestration)
- Dashboard LWC now acts as a shell for Agentforce chat in AI mode.
- Intent routing is expected to be handled by Agentforce topics/actions, not by dashboard UI logic.
- In AI mode, the bottom-right launcher opens an in-dashboard popup chat.
- No additional URL setup is required for this phase.
