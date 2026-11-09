# Fabric asset catalog

[Home](../README.md) | [Setup](getting-started.md) | [Architecture](architecture.md)

All paths below are under the service-managed export root. Preserve item folder
names and metadata; use supported Fabric authoring/export workflows for changes.
Inventory describes files, not successful deployment or data availability.

## Inventory and dependency order

| Export | Purpose and dependency | Rebinding or validation |
|---|---|---|
| [ADX_Mirror_CMS_Data](../ws_databricks/Azure%20Databricks%20Store/ADX_Mirror_CMS_Data.MirroredAzureDatabricksCatalog) | Databricks catalog for the CMS path | Source workspace, catalog selection, connection identity and data reads |
| [onelake_storage_insurance](../ws_databricks/Azure%20Databricks%20Store/onelake_storage_insurance.MirroredAzureDatabricksCatalog) | Separate mirrored catalog example; same item type as above | Source catalog and storage connection; not evidence of OneLake federation |
| [LH_ADX_Mirror](../ws_databricks/Fabric%20Data%20Stores/LH_ADX_Mirror.Lakehouse) | Bronze/silver shortcuts to a Databricks catalog item | Target item/workspace IDs; Silver SQL endpoint visibility |
| [LH_ADX_Onelake](../ws_databricks/Fabric%20Data%20Stores/LH_ADX_Onelake.Lakehouse) | Separate insurance shortcut under bronze | Target catalog item/workspace and insurance table |
| [WH_ADX_CMS_Gold](../ws_databricks/Fabric%20Data%20Stores/WH_ADX_CMS_Gold.Warehouse) | Gold DDL and load procedures; reads LH_ADX_Mirror Silver tables | SQL project deployment, cross-database reads and approved load execution |
| [SM_ADX_Gold_CMS_Before](../ws_databricks/Business%20Intelligence/SM_ADX_Gold_CMS_Before.SemanticModel) | Technical `dim_`/`fact_` names with SQL endpoint expression | Warehouse endpoint/database binding; comparison only |
| [SM_ADX_Gold_CMS_After](../ws_databricks/Business%20Intelligence/SM_ADX_Gold_CMS_After.SemanticModel) | Business-friendly names, measures and Direct Lake expression | OneLake workspace/item binding and model relationships |
| [RPT_ADX_Gold_CMS_Overview](../ws_databricks/Business%20Intelligence/RPT_ADX_Gold_CMS_Overview.Report) | Relative reference to the After model | Confirm deployed report-to-model binding and visual totals |
| [Ontology_ADX_Gold_CMS](../ws_databricks/Business%20Intelligence/Ontology_ADX_Gold_CMS.Ontology) | Entity mappings referencing the After model | Workspace/model connection, entity mappings and permissions |
| [DA_ADX_Gold_CMS](../ws_databricks/Agents/DA_ADX_Gold_CMS.DataAgent) | Gold warehouse source and ontology context in draft/published definitions | Warehouse/ontology IDs, selected tables, instructions and example SQL |
| Eventstream under [Azure Databricks Store](../ws_databricks/Azure%20Databricks%20Store) | Optional export; not required by the traced CMS load | Current name, source/sink connections and support must be reviewed |

Eventstream names can contain generated or placeholder identifiers. Discover
the current `.Eventstream` folder rather than treating its name as an API.

## Important distinctions

- **Before versus After:** the exports show technical versus business-oriented
  model surfaces, not a benchmark proving performance or accuracy improvement.
  The report references After.
- **Legacy versus star load:** `gold.usp_load_gold_cms` produces non-star summary
  tables; `gold.usp_load_gold_dim_fact` produces the six dimensions and three
  facts referenced by the included models.
- **Configuration versus data:** exports include definitions, not source data
  or a populated warehouse. The referenced upstream preparation notebook is
  absent; see [notebook requirements](../notebooks/README.md).
- **AI examples versus verified behavior:** inspect and test the exported
  few-shot SQL before use. Local JSON syntax checks do not validate SQL strings,
  entity semantics or agent answers.

## Rebinding checklist

- [ ] Source catalog connection and table selection tested.
- [ ] Lakehouse shortcut target IDs resolved in the destination workspace.
- [ ] Warehouse SQL project and intended procedure deployed.
- [ ] Model endpoint/OneLake paths point to the destination.
- [ ] Report references the intended model.
- [ ] Ontology references that model and authorized entities.
- [ ] Agent draft source and ontology configured; tested before publishing.
- [ ] No unintended exported item changes or credentials included in Git.
