# Getting started

[Home](../README.md) | [Architecture](architecture.md) | [Troubleshooting](troubleshooting.md)

## Before you begin

This is a manual, environment-dependent walkthrough, not a tested deployment
script. Start with the mirrored-catalog path. Use an isolated demo workspace
and approved synthetic/public data. Do not connect this sample to production.

| Requirement | Who or where | Ready when |
|---|---|---|
| Fabric capacity with required workloads | Fabric administrator | Warehouse and Lakehouse creation are available |
| Git integration enabled for your provider | Tenant/workspace administrator | Workspace can connect to the repository |
| Repository connection | Fabric workspace administrator | Repository, branch and directory can be selected |
| Unity Catalog source and supported Delta tables | Databricks owner | Selected tables are queryable by the connection identity |
| Source identity and storage/network access | Databricks and Azure administrators | Catalog visibility and underlying data reads both succeed |
| BI and optional AI feature access | Fabric administrator | Required licenses, tenant settings and supported region are confirmed |

Use the permissions in the current [mirroring tutorial](https://learn.microsoft.com/en-us/fabric/mirroring/azure-databricks-tutorial);
do not grant tenant-wide administrator access merely to run the demo.
Keep source and Fabric resources in compatible regions and assess transfer cost.

## 1. Review locally

Clone your approved fork/branch and run from its root:

```powershell
& .\scripts\Test-Repository.ps1
git diff --check
```

Optionally copy `.env.example` to `.env` as a private checklist of identifiers.
Nothing in this repository loads it, authenticates with it, or provisions
resources. Never put tokens, passwords or client secrets in it.

**Expected:** offline checks pass. This does not establish cloud readiness.

## 2. Establish the Silver source

In Databricks, prepare a Unity Catalog schema with these tables:

- `beneficiary_summary`: beneficiary ID and summary year grain.
- `inpatient_claims`: claim ID and claim segment grain.
- `outpatient_claims`: claim ID and claim segment grain.

The [warehouse procedures](../ws_databricks/Fabric%20Data%20Stores/WH_ADX_CMS_Gold.Warehouse/gold/StoredProcedures)
define the exact input columns and conversions. Their comments reference
`bronze_to_silver_cms.py`, which is **not included**. Provide your own reviewed
upstream preparation; renaming unrelated tables is insufficient.

**Stop here if these inputs are unavailable.** You can still review the
architecture and exported models, but cannot claim a runnable end-to-end demo.

## 3. Connect the Fabric exports

1. Use a dedicated demo branch with reviewed, committed exports. Fabric reads
   the remote branch, not uncommitted local changes.
2. In your isolated Fabric workspace, open **Workspace settings > Git integration**.
3. Select the Git provider, repository, branch and the `ws_databricks` directory,
   not the repository root.
4. Follow the [official Git setup](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-get-started)
   and review the incoming changes before choosing **Update from Git**.
5. Check current item support. If an item cannot be restored by Git, recreate it
   through its supported authoring experience; do not assume every export is
   deployable. Record any blockers before proceeding.

**Expected:** supported items appear in the workspace. Imported placeholders
and source bindings still need configuration. Do not edit `.platform` files,
mass-replace IDs, or commit credentials to make synchronization succeed.

## 4. Configure the mirrored catalog and shortcuts

Follow the [mirrored-catalog guide](patterns/mirrored-catalog.md). Configure
the source connection for `ADX_Mirror_CMS_Data` through supported Fabric tools;
if recreation is required, review resulting identities and rebind dependents.

In `LH_ADX_Mirror`, configure OneLake shortcuts to the catalog's `silver`
schema (and `bronze` if needed). The exports contain zero-ID placeholders.
Keep the Lakehouse and Gold warehouse in the same workspace for the existing
three-part SQL references.

Open the Lakehouse SQL analytics endpoint and query each Silver table:

```sql
SELECT TOP (5) * FROM silver.beneficiary_summary;
SELECT TOP (5) * FROM silver.inpatient_claims;
SELECT TOP (5) * FROM silver.outpatient_claims;
```

**Expected:** the tables and required columns are visible; source counts match
the Databricks baseline after metadata synchronization. Record UTC observation
times. A visible catalog name alone does not prove storage access.

## 5. Prepare and load the Gold warehouse

Review the exported SQL project and confirm that `WH_ADX_CMS_Gold` contains its
schema and procedures using a supported warehouse deployment workflow.
This repository does not automate SQL project deployment.

For the included star-schema models, the relevant procedure is
`gold.usp_load_gold_dim_fact`, as declared in its SQL body. Some exported
procedure header comments show a different invocation; use the actual
declaration, not those comments.

**Mutating operation:** the procedure rebuilds tables, drops/replaces existing
objects, and removes earlier non-star tables. Review the entire procedure,
confirm the destination is disposable, and do not run concurrent loads.
Only after explicit approval from your environment owner, run in that warehouse:

```sql
EXEC gold.usp_load_gold_dim_fact;
```

Do not run the legacy `gold.usp_load_gold_cms` as an additional required step.
It produces a different, non-star output shape.

**Expected:** six dimensions and three fact tables are populated. Run
[validate-gold.sql](../warehouse/validate-gold.sql) and interpret every result
as described in the [warehouse guide](../warehouse/README.md).

## 6. Rebind the consumer items

Use the [asset dependency table](asset-catalog.md), in this order:

1. Bind `SM_ADX_Gold_CMS_After` to the target Gold warehouse/OneLake location.
2. Confirm relationships, measures and table visibility.
3. Confirm `RPT_ADX_Gold_CMS_Overview` uses the After model.
4. If demonstrating AI, rebind the Ontology to that model, then configure the
   Data Agent warehouse source and ontology. Test draft behavior before
   publishing through the supported UI.
5. Restore the Before model only if demonstrating the technical/business
   naming comparison; it is not the report's exported target.

**Expected:** the report opens and its totals reconcile with SQL at identical
filter scope. AI features are optional and must not block the core BI demo.

## 7. Record results and clean up

Follow the [demo walkthrough](demo-walkthrough.md) and
[validation checklist](validation.md). Record the branch/commit, item names,
data snapshot, UTC load time, query outputs, discrepancies and feature limits
outside the public repository. Do not publish patient-level data or tenant IDs.

Afterward, stop only Databricks compute you own and remove only disposable
resources created for this demo. Disconnect Git before deleting a demo workspace
if appropriate for your tenant procedure. Capacity and storage can continue to
incur charges; disconnecting Git does not delete or stop them.
