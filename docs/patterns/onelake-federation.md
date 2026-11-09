# Fabric-owned data consumed in Databricks

[Home](../../README.md) | [Architecture](../architecture.md) | [Main demo setup](../getting-started.md)

## When to choose this path

Choose OneLake catalog federation when Fabric owns Lakehouse or Warehouse data
and Databricks needs governed, read-only access. Unity Catalog queries read
OneLake data without copying it. This is the reverse direction of mirroring
Databricks catalogs into Fabric.

**Coverage:** reference guidance only. The repository does not deploy a
connection, storage credential or foreign catalog, and the exported item named
`onelake_storage_insurance` is not proof of this configuration.

## Setup outline

Use the current [official OneLake federation guide](https://learn.microsoft.com/en-us/azure/databricks/query-federation/onelake)
for exact commands and permissions. Do not substitute generic JDBC federation
or assume the mirrored-catalog credentials are reusable.

1. Confirm a Unity Catalog-enabled workspace, compatible compute/runtime or SQL
   warehouse, and network access to the Fabric workspace's OneLake endpoints.
2. Ask the Fabric administrator to confirm external OneLake access and the
   identity/delegated-token settings required by the current guide.
3. Configure the supported managed identity/Access Connector or service
   principal authentication. Keep secrets in approved secret management.
4. Grant only the Fabric data access and Unity Catalog creation privileges
   needed for the connection and foreign catalog.
5. Create the connection, storage credential and foreign catalog using the
   documented workflow; select the intended Fabric workspace/items.
6. Run read-only queries in Databricks and compare results with the Fabric
   source at identical snapshot and filter scope.

Compute requirements, supported items, authentication methods and network
constraints change. Verify the current documentation before provisioning;
this repository does not certify a runtime version.

## Success criteria

- Authorized Databricks users can discover the selected foreign tables.
- Query counts and aggregates match the Fabric baseline.
- Reads succeed without write access or unnecessary workspace-wide privileges.
- A controlled Fabric data update becomes visible within a measured target.
- Query compute and any cross-region transfer costs are understood.

Keep deployment evidence private. Record this path as untested until its
connection and query behavior have been verified in your environment.
