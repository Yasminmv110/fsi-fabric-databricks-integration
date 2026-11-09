# Notebooks

No runnable notebook is included. This folder documents the missing upstream
preparation step; it is not an executable part of the demo.

The exported warehouse procedures refer to `bronze_to_silver_cms.py`. Before
running them, provide reviewed Databricks transformations producing Silver Delta
tables with the required columns and grains:

| Table | Grain |
|---|---|
| `beneficiary_summary` | Beneficiary ID and summary year |
| `inpatient_claims` | Claim ID and claim segment |
| `outpatient_claims` | Claim ID and claim segment |

Use the actual SQL source references in the
[warehouse procedures](../ws_databricks/Fabric%20Data%20Stores/WH_ADX_CMS_Gold.Warehouse/gold/StoredProcedures)
as the input contract. Use approved synthetic/public data, not customer or
patient data. Do not claim that a notebook exists or that the source is ready
until its schema and output have been tested.

Future notebook contributions should document runtime, libraries, parameters,
input provenance, expected output schema, permissions, cost and repeatability.
Keep credentials outside notebook cells and clear sensitive outputs.

Return to [getting started](../docs/getting-started.md).
