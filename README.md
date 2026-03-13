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
- Pull requests merged into `release/N` trigger the `release-pipeline` workflow automatically.
- The release pipeline runs quality checks, builds a beta package version, and deploys to the Testing Org.
- `release/N` is never merged directly. When the sprint is ready to ship, a pull request is raised from `release/N` to `production`.

### `production`

- `production` is the permanent protected branch.
- It only receives pull requests from `release/N` branches.
- Pull requests merged into `production` trigger the `production-pipeline` workflow automatically.
- The production pipeline reruns quality checks, promotes the package version to Released, and installs it in the PBO Org.
- No developer pushes directly to this branch.

## Developer workflow

1. Pull the latest changes from the active `release/N` branch.
2. Create a new `feature/your-branch` branch from that `release/N` branch.
3. Write code, commit changes, and push the feature branch.
4. Open a pull request targeting `release/N`.
5. Get 1 approval and a green `release-pipeline`, then merge the pull request.
6. The release pipeline automatically deploys the beta package to the Testing Org.
7. When the sprint is complete, the release manager opens a pull request from `release/N` to `production`.
8. Get 2 approvals and a green `production-pipeline`, then merge the pull request.
9. The production pipeline automatically promotes the package version and deploys it to the PBO Org.

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
| `PACKAGE_NAME` | Exact package name as registered in the Dev Hub |
| `PACKAGE_ID` | `0Ho` package ID from the Dev Hub |

## Quality gates

Both pipelines call the shared composite action at `.github/actions/quality-gates/action.yml`. The gates run in this exact order and the pipeline stops immediately if any gate fails.

1. PMD static analysis using `sf scanner run` against `./force-app/**/*.cls` and `./force-app/**/*.trigger` with severity threshold `2`. Any severity 1 or 2 violation fails the pipeline.
2. ESLint for LWC and Aura using `npm run lint` against `./force-app/**/*.js`. Any ESLint error fails the pipeline. Warnings are allowed.
3. Salesforce Scanner security rules using `sf scanner run` against `./force-app` with category `Security` and severity threshold `1`. Any security violation fails the pipeline.
4. Apex unit tests with code coverage using `sf apex run test` against the Testing Org alias `testorg`. Any test failure or org-wide Apex coverage below 75% fails the pipeline.

## AppExchange Security Review policy

Salesforce AppExchange security review is a one-time review unless the package introduces new permissions, new external access, new integrations, or materially broader exposure. Use the checklist in [.github/pull_request_template.md](/Users/pallabsaikia/Downloads/Clarity360/.github/pull_request_template.md) to flag changes that require a release manager review and potential re-submission.

Current temporary exception: the production workflow promotes the package version but skips PBO installation and post-install smoke tests until a PBO org is available and `PBOORG_SFDX_URL` is configured.

## Pipeline flow diagram

```text
feature/* ──PR──► release/N ──auto──► [Quality Gates]
                                          │
                                   [Build beta pkg]
                                          │
                                 [Deploy Testing Org]
                                          │
                       PR (sprint done) ◄─┘
                          │
                       production ──auto──► [Quality Gates]
                                                 │
                                         [Promote Released]
                                                 │
                                        [Deploy PBO Org]
                                                 │
                                     [AppExchange listing]
```
