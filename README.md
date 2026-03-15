# Clarity360

## Overview

Clarity360 is a Salesforce 2GP managed package repository. The repository uses protected promotion branches, two GitHub Actions pipelines, and no direct pushes to release or production branches.

## Branch strategy

The repository uses exactly 3 branch types:

### `feature/*`

- Created by developers for each piece of work such as `feature/fix-login` or `feature/payment-module`.
- Always branched from the current `release/N` branch.
- Merged back into `release/N` through a pull request only.
- No pipeline runs on `feature/*` branches.
- Deleted after merge.

### `release/1`, `release/2`, `release/3` ...

- One release branch is used per sprint or iteration.
- A new `release/N` branch is cut from the previous `release/N-1` branch at the start of each sprint.
- Pull requests targeting `release/N` trigger the `Release Validation` workflow automatically.
- Merged pull requests into `release/N` trigger the `Release Deploy` workflow, which deploys to the Testing Org only after successful PR validation.
- `release/N` is never merged directly. When the sprint is ready to ship, a pull request is raised from `release/N` to `production`.

### `production`

- `production` is the permanent protected branch.
- It only receives pull requests from `release/N` branches.
- Pull requests targeting `production` trigger the `Production Validation` workflow automatically.
- Merged pull requests into `production` trigger the `Production Release` workflow for package promotion and release tagging.
- No developer pushes directly to this branch.

## Developer workflow

1. Pull the latest changes from the active `release/N` branch.
2. Create a new `feature/your-branch` branch from that `release/N` branch.
3. Write code, commit changes, and push the feature branch.
4. Open a pull request targeting `release/N`.
5. Get 1 approval and a green `release-pipeline`, then merge the pull request.
6. The merge commit to `release/N` automatically deploys the validated source to the Testing Org.
7. When the sprint is complete, the release manager opens a pull request from `release/N` to `production`.
8. Get 2 approvals and a green `production-pipeline`, then merge the pull request.
9. The merge commit to `production` automatically promotes the package version and creates the release tag.

## Branch Protection Rules

Configure these rules manually in GitHub Settings -> Branches after the repository is created.

### Branch pattern: `release/*`

- Require a pull request before merging
- Require at least 1 approving review
- Dismiss stale reviews when new commits are pushed
- Require status checks to pass before merging
- Required status check: `release-pipeline`
- Require branches to be up to date before merging
- Do not allow bypassing the above settings, including for admins

### Branch pattern: `production`

- Require a pull request before merging
- Require at least 2 approving reviews
- Dismiss stale reviews when new commits are pushed
- Require status checks to pass before merging
- Required status check: `production-pipeline`
- Require branches to be up to date before merging
- Do not allow bypassing the above settings, including for admins
- Require linear history
- Restrict who can push so only the `release-manager` GitHub team role can push

## Required GitHub Secrets

Add these secrets in GitHub Settings -> Secrets -> Actions.

| Secret | Description |
| --- | --- |
| `DEVHUB_SFDX_URL` | SFDX auth URL for the Dev Hub org used by `sf org login sfdx-url` |
| `TESTORG_SFDX_URL` | SFDX auth URL for the Testing Org used by `sf org login sfdx-url` |
| `PBOORG_SFDX_URL` | Optional for now. Add this when the PBO Org is available to enable production installation and smoke tests. |
| `PACKAGE_NAME` | Exact package name as registered in the Dev Hub. Required for production packaging and AppExchange release operations. |
| `PACKAGE_ID` | `0Ho` package ID from the Dev Hub. Required for production packaging and release promotion operations. |

## Quality gates

Both pipelines now expose the quality checks as separate GitHub Actions jobs. Pull requests run the validation path against the shared Testing Org. Separate merged-PR workflows run the release deployment and production release paths after the branch protection rules allow the merge.

1. PMD static analysis using `sf scanner run` against all Apex classes and triggers in the package. Any severity 1 or 2 violation fails the `PMD Scan` job.
2. ESLint for LWC and Aura using `npm run lint` against `./force-app/**/*.js`. Any ESLint error fails the `ESLint` job. Warnings are allowed.
3. Salesforce Scanner security rules using `sf scanner run` against `./force-app` with category `Security` and severity threshold `1`. Any security violation fails the `Security Scan` job.
4. XML validation using `xmllint` across `force-app` and `manifest`. Any malformed XML fails the `XML Validation` job.
5. Metadata validation using `sf project deploy start --dry-run` in the shared Testing Org. This catches deploy-time metadata and configuration issues before the merge is allowed.
6. Changed Apex coverage validation using `sf project deploy start --dry-run --test-level RunSpecifiedTests` against the shared Testing Org. When a pull request changes non-test Apex classes or triggers, the workflow validates those changed members with specified tests so each changed class or trigger must meet the 75% requirement individually.
7. Full-package regression validation in the shared Testing Org. The workflow runs a metadata dry-run with `NoTestRun`, then runs `RunLocalTests` separately and compares org-wide coverage before and after. Changed Apex must still meet 75% individually, and shared-org overall coverage is enforced as a non-regression gate until the org baseline reaches 75% or higher.
8. AppExchange PMD review scanning using `sf scanner run --engine pmd-appexchange` with severity threshold `2`.

The final pull request checks remain `release-pipeline` and `production-pipeline`. Those jobs only pass when all upstream validation jobs succeed.

## AppExchange Security Review policy

Salesforce AppExchange security review is a one-time review unless the package introduces new permissions, new external access, new integrations, or materially broader exposure. Use the checklist in [.github/pull_request_template.md](/Users/pallabsaikia/Downloads/Clarity360/.github/pull_request_template.md) to flag changes that require a release manager review and potential re-submission.

Current temporary exception: the production workflow promotes the package version but skips PBO installation and post-install smoke tests until a PBO org is available and `PBOORG_SFDX_URL` is configured.

Current temporary exception: scratch-org validation is disabled to avoid daily Dev Hub signup exhaustion. Pull requests validate against the shared Testing Org with both changed-Apex coverage checks and full-package dry-run validation. Merged pull requests deploy source directly to the Testing Org, then run a dedicated smoke suite. Package creation remains a production concern.

## Pipeline flow diagram

```text
feature/* ──PR──► release/N ──auto──► [Release Validation]
                                          │
                                          ├─ PMD
                                          ├─ ESLint
                                          ├─ Security
                                          ├─ XML
                                          ├─ Metadata
                                          ├─ AppExchange
                                          └─ Testing Org Validation
                                          │
                               merge PR ──┴──► [Release Deploy]
                                                     │
                                            [Deploy Testing Org]
                                                     │
                                            [Post-Deploy Smoke Test]
                                                     │
                                     PR (sprint done)◄──────────────┘
                                              │
                                              ▼
                                         production ──PR──► [Production Validation]
                                                              │
                                                              └─ same validation gates
                                                                      │
                                                           merge PR ──┴──► [Production Release]
                                                                                 │
                                                                         [Promote Released]
                                                                                 │
                                                                          [Create Release Tag]
```
