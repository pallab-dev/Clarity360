# Clarity360

## Overview

Clarity360 is a Salesforce 2GP managed package repository. The repository now uses a single protected `production` branch. All validation happens on pull requests before merge, with checks staged from fast changed-file validation through org validation, package smoke, and manual UAT.

## Branch Strategy

The repository uses 2 branch types:

### `feature/*`

- Created by developers for each piece of work.
- Branched from the latest `production`.
- Merged back into `production` through a pull request only.
- Deleted after merge.

### `production`

- Permanent protected branch.
- Receives pull requests from `feature/*`.
- Pull requests targeting `production` trigger the `Production PR Validation` workflow.
- Merged pull requests into `production` trigger the production release workflow for package promotion and release tagging.
- No direct developer pushes to this branch.

## Pull Request Flow

1. Branch from `production`.
2. Push your feature branch and open a pull request to `production`.
3. The PR workflow runs these stages in order:
   - `Detect Changes`
   - `Delta Quality Gates`
   - `Changed Apex Coverage`
   - `Platform Safety Gates`
   - `Testing Org Integration`
   - `Scratch Org Package Smoke`
   - `Manual UAT`
   - `pr-pipeline`
4. Merge only after `pr-pipeline` is green and the PR has the required approval.

## Validation Model

### Unit Tests -> PR

- Changed-file validation runs first.
- Changed Apex classes and triggers are validated by coverage, not by filename conventions.
- If a PR does not change non-test Apex or triggers, changed-member coverage is skipped.
- LWC Jest tests run on the PR workflow.

### Integration Tests -> Testing Org

- PR content is deployed to the shared Testing Org before merge.
- Integration validation runs there after static and changed-member checks pass.
- The Testing Org layer runs the dedicated Apex integration suite listed in [.github/apex/integration-tests.txt](/Users/pallabsaikia/Downloads/Clarity360/.github/apex/integration-tests.txt).

### Package Smoke -> Scratch Org

- A scratch org is created for the PR after platform safety gates pass.
- A package version is created from the PR source and installed into a fresh scratch org for install validation.
- A second package version is created from the base branch source and installed first in another scratch org, then upgraded to the PR package version.
- `Clarity360SmokeTest` is reserved for package install and upgrade smoke validation.
- No PBO org is required for this validation path.

### Manual UAT -> Testing Org

- Manual UAT is the final pre-merge gate.
- Configure the `testing-org-uat` GitHub environment with required reviewers to enforce approval.

## Platform Safety Gates

The PR workflow includes both changed-file and full-source platform safety checks before org deployment:

- PMD for Apex and triggers
- ESLint for LWC JavaScript
- LWC Jest
- XML validation for changed metadata
- Salesforce Scanner security rules
- AppExchange PMD review scan
- Coverage enforcement for changed Apex members only

These checks are intended to catch CRUD/FLS, sharing, governor limit, bulkification, and related secure coding issues before Testing Org or scratch org time is consumed.

## Local Quality Gates

Use the same checks locally before handing the package to another engineer:

- `npm run lint`
- `npm run test:unit:lwc`
- `npm run lint:apex`
- `npm run lint:apex:appexchange`

The Apex PMD ruleset lives at [config/pmd-ruleset.xml](/Users/pallabsaikia/Downloads/Clarity360/config/pmd-ruleset.xml).

## Branch Protection Rules

Configure these rules manually in GitHub Settings -> Branches.

### Branch pattern: `production`

- Require a pull request before merging
- Require at least 1 approving review
- Dismiss stale reviews when new commits are pushed
- Require status checks to pass before merging
- Required status check: `pr-pipeline`
- Require branches to be up to date before merging
- Do not allow bypassing the above settings, including for admins
- Require linear history

## Required GitHub Secrets

Add these secrets in GitHub Settings -> Secrets -> Actions.

| Secret | Description |
| --- | --- |
| `DEVHUB_SFDX_URL` | SFDX auth URL for the Dev Hub org used to create PR scratch orgs |
| `TESTORG_SFDX_URL` | SFDX auth URL for the shared Testing Org used for integration validation and UAT |
| `PACKAGE_ID` | `0Ho` package ID from the Dev Hub used for PR package validation and release operations |

## Release Flow

After a PR is merged to `production`, the release workflow in [.github/workflows/production-release.yml](/Users/pallabsaikia/Downloads/Clarity360/.github/workflows/production-release.yml) verifies that the PR validation workflow succeeded, then promotes the package version when `.version-id` is present and creates a release tag.
