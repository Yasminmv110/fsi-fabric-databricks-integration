# Databricks-owned data consumed in Fabric

[Home](../../README.md) | [Architecture](../architecture.md) | [Setup](../getting-started.md)

## When to choose this path

Choose this when Databricks owns the Delta tables and Fabric users need SQL,
Power BI or downstream analytics. The mirrored catalog synchronizes Unity
Catalog structure; shortcuts read the underlying data without replication.
The later Gold load is a separate, materializing transformation.

## Configuration sequence

1. Confirm the connection identity can see the Unity Catalog catalog, schema
   and supported tables. Review table-feature limitations in the
   [official tutorial](https://learn.microsoft.com/en-us/fabric/mirroring/azure-databricks-tutorial).
2. In Fabric, use **New item > Mirrored Azure Databricks catalog**, or configure
   a restored item through its supported authoring experience.
3. Select/create an approved connection, select the catalog and schemas/tables,
   and review whether future catalog changes should synchronize automatically.
4. Confirm the created catalog item and its SQL analytics endpoint expose the
   selected tables. Test an actual data read.
5. In the demo Lakehouse, choose **New shortcut > Microsoft OneLake**, select
   the catalog item and required tables/schema, then create the shortcuts.
6. Validate Silver visibility before loading Gold or binding consumers.

For ADLS protected by a storage firewall, follow the tutorial's Workspace
Identity and network-security instructions. Catalog authorization, storage
permissions and network reachability are separate checks; fixing one does not
automatically fix the others.

## Repository mapping

- CMS catalog: `ADX_Mirror_CMS_Data`.
- CMS Lakehouse: `LH_ADX_Mirror`, with bronze/silver shortcuts.
- Separate insurance example: `onelake_storage_insurance` and `LH_ADX_Onelake`.
- Consumers: Gold warehouse, semantic models, report, ontology and Data Agent.

See [all asset paths and rebindings](../asset-catalog.md).
The Fabric catalog item is the implementation surface for this pattern, not a
third separate "storage item" integration mechanism.

## Success criteria and limits

- Selected source tables can be queried from the Fabric SQL endpoint.
- Counts reconcile at the same source snapshot, with observed UTC timestamps.
- Metadata/data propagation is measured, not described as instantaneous.
- A controlled source update appears within your agreed freshness target.
- Credentials and environment-specific connection details stay outside Git.

Catalog changes and SQL endpoint synchronization can lag. Do not promise
transactional, real-time propagation or a fixed latency from this sample.

Reference: [Mirrored Azure Databricks catalogs](https://learn.microsoft.com/en-us/fabric/mirroring/azure-databricks).
