# Troubleshooting

[Home](../README.md) | [Setup](getting-started.md) | [Asset catalog](asset-catalog.md)

Work from source access to downstream consumers. Record the exact error, item,
identity and UTC time privately. Do not post tokens or connection strings.

| Symptom | Check | Next action |
|---|---|---|
| Git connects but no expected items appear | Remote branch and Git directory | Select `ws_databricks`; local uncommitted files are not synchronized |
| An export cannot be restored | Current Git support for the item type and placeholder metadata | Recreate through supported Fabric tools or record a blocker; do not hand-edit `.platform` |
| Catalog or tables are missing | Connection identity's Unity Catalog privileges, selection and supported Delta features | Test access as that identity and review the current mirroring tutorial |
| Catalog visible but reads fail | Storage permissions, firewall and network path | Validate the actual data read separately from catalog access |
| ADLS firewall blocks access | Fabric Workspace Identity and current network-security requirements | Follow the official mirroring instructions; do not open public access as a shortcut |
| Lakehouse shortcuts fail | Target workspace/item IDs and table paths | Recreate/rebind through Fabric; zero IDs are placeholders |
| Silver tables are missing from SQL | Shortcut configuration and SQL endpoint metadata propagation | Confirm source existence, then allow/verify endpoint synchronization |
| Gold load cannot resolve source tables | Same workspace, `LH_ADX_Mirror` name, Silver input schema | Compare against actual procedure references; do not rename arbitrary tables |
| Gold load rejects empty/duplicate data | Upstream transformation and source grain | Correct the source; do not bypass procedure checks |
| Procedure name in a comment does not execute | Actual `CREATE PROCEDURE` declaration | Use `gold.usp_load_gold_dim_fact` for the star-schema path after review |
| Model fails to read data | SQL endpoint or OneLake location still points to the source environment | Rebind the model with supported authoring tools |
| Report opens but visuals fail | Deployed model binding, table names, relationships and access | Confirm After is the report target and test measures individually |
| Totals disagree | Snapshot, filter scope, year coverage and metric grain | Compare the same fact/metric; provider payments need not equal reimbursement |
| Agent query fails or answer is misleading | Selected tables, generated SQL, few-shots and ontology mappings | Test draft queries directly and correct through supported authoring; JSON validity is not SQL validity |
| OneLake federation fails in Databricks | Runtime, foreign catalog, identity settings and OneLake endpoints | Follow the separate federation guide; mirrored-catalog setup is not sufficient |

## Known setup gaps

- Source data and `bronze_to_silver_cms.py` are not included.
- Exported bindings are environment-dependent; placeholders are not valid IDs.
- Stored procedure header examples can differ from their actual declarations.
- Agent example SQL is exported content, not a validated test suite.
- No local check proves Fabric item-schema compatibility, refresh behavior,
  Mermaid rendering, SQL execution or end-to-end cloud operation.

## Official references

- [Mirrored Databricks setup](https://learn.microsoft.com/en-us/fabric/mirroring/azure-databricks-tutorial)
- [Fabric Git integration](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-get-started)
- [OneLake catalog federation](https://learn.microsoft.com/en-us/azure/databricks/query-federation/onelake)
