# FSI Fabric + Databricks Integration Demo

Explore three ways Azure Databricks and Microsoft Fabric can share data without copying it, and how that data feeds Fabric analytics, Power BI reports, and natural-language questions. Intended for data engineers, solution engineers, and demo presenters.

**Status: exported demo assets, not a one-click deployment.** Live connections, source data, upstream transformations, and tenant-specific bindings are not provided. 

## What you can demonstrate

This demo covers three integration patterns:

| # | Pattern | Where the data is stored | Direction |
|---|---|---|---|
| 1 | Azure Databricks with ADLS Gen2 storage, mirrored into Fabric | Your ADLS Gen2 account | Databricks → Fabric |
| 2 | OneLake catalog federation | OneLake (Fabric) | Fabric → Databricks |
| 3 | Azure Databricks using OneLake as storage through the Azure Databricks Storage item | OneLake (Fabric storage item) | Databricks writes to OneLake |

### 1. Azure Databricks with ADLS Gen2 as storage

Unity Catalog tables stored in ADLS Gen2 are surfaced in Fabric through a **Mirrored Azure Databricks catalog**, so no data is copied.

- Discover Databricks Unity Catalog tables in Fabric.
- Access the mirrored tables through Lakehouse shortcuts.
- Build a Gold warehouse star schema and consume it through a semantic model, report, ontology, and Data Agent.

```mermaid
flowchart TD
    subgraph OwnerPlatform["Databricks - source ownership"]
        SourceTables[("Silver Delta tables on ADLS")]
        SourceCatalog["Unity Catalog"]
    end
    subgraph ConsumerPlatform["Fabric - analytics workspace"]
        CatalogItem["Mirrored Databricks catalog"]
        ShortcutLake["Lakehouse shortcuts and SQL endpoint"]
        GoldStore[("Gold Warehouse star schema")]
        BusinessModel["Power BI semantic model"]
        OverviewReport["Power BI report"]
        BusinessOntology["Business ontology"]
        QuestionAgent["Data Agent"]
    end
    AccessIdentity["Microsoft Entra identities"]
    SourceCatalog -.->|"catalog metadata sync"| CatalogItem
    SourceTables -->|"read through catalog shortcuts"| CatalogItem
    CatalogItem -->|"OneLake shortcuts"| ShortcutLake
    ShortcutLake -->|"reviewed Gold load procedures"| GoldStore
    GoldStore -->|"Direct Lake data access"| BusinessModel
    BusinessModel -->|"report queries"| OverviewReport
    BusinessModel -->|"business entity mappings"| BusinessOntology
    GoldStore -->|"warehouse queries"| QuestionAgent
    BusinessOntology -->|"entity context"| QuestionAgent
    AccessIdentity -.->|"source and consumer permissions"| SourceCatalog
    AccessIdentity -.->|"workspace and item access"| CatalogItem
```

### 2. OneLake catalog federation

Databricks reads Fabric OneLake data through Unity Catalog without copying it.

- Query Fabric lakehouse tables from Databricks as a federated catalog.
- Govern access to Fabric data through Unity Catalog.
  
```mermaid
%%{init: {"theme": "base", "themeVariables": {"primaryColor": "#ECECFF", "primaryTextColor": "#000000", "primaryBorderColor": "#9370DB", "lineColor": "#555555", "secondaryColor": "#FFFFDE", "tertiaryColor": "#FFFFDE", "clusterBkg": "#FFFFDE", "clusterBorder": "#9370DB", "edgeLabelBackground": "#EEEEEE"}}}%%
flowchart TD
    subgraph SourcePlatform["Fabric - source ownership and storage"]
        FabricLakehouse["Fabric lakehouse"]
        SourceTables[("Delta table files<br/>in OneLake")]
        FabricLakehouse -->|"stores table data"| SourceTables
    end
    subgraph ConsumerPlatform["Azure Databricks - compute and governance"]
        StorageCredential["Unity Catalog<br/>storage credential"]
        FabricConnection["Unity Catalog connection<br/>Type: OneLake"]
        ForeignCatalog["Unity Catalog foreign catalog<br/>Fabric lakehouse tables"]
        CatalogPermissions["Unity Catalog<br/>permissions"]
        DatabricksCompute["Databricks SQL or Spark compute"]
        DatabricksUsers["Databricks users and workloads"]
        StorageCredential -.->|"authenticates connection"| FabricConnection
        FabricConnection -.->|"connection used by"| ForeignCatalog
        CatalogPermissions -.->|"govern Databricks access"| ForeignCatalog
        ForeignCatalog -.->|"table metadata and authorization"| DatabricksCompute
        DatabricksUsers -->|"query federated tables"| DatabricksCompute
    end
    AccessIdentity["Access Connector for Azure Databricks<br/>Microsoft Entra managed identity"]
    AccessIdentity -.->|"referenced by"| StorageCredential
    AccessIdentity -.->|"granted Fabric and OneLake read permissions"| FabricLakehouse
    FabricLakehouse -.->|"expose lakehouse table metadata"| ForeignCatalog
    SourceTables -->|"read-only access from Databricks<br/>no data copy"| DatabricksCompute
    classDef lavender fill:#ECECFF,stroke:#9370DB,color:#000000;
    class FabricLakehouse,SourceTables,StorageCredential,FabricConnection,ForeignCatalog,CatalogPermissions,DatabricksCompute,DatabricksUsers,AccessIdentity lavender;
    style SourcePlatform fill:#FFFFDE,stroke:#9370DB,color:#000000
    style ConsumerPlatform fill:#FFFFDE,stroke:#9370DB,color:#000000
```

### 3. Azure Databricks using OneLake as storage

A Unity Catalog external location points at an **Azure Databricks Storage item** in Fabric, and a catalog uses it as managed storage. Databricks keeps the compute and governance, while the table and volume files are stored in OneLake.

- Create Unity Catalog managed tables and volumes whose data is stored in OneLake.
- Restrict data access to the Databricks managed identity through OneLake security.
- Let Fabric users read the data through a mirrored Azure Databricks catalog.
```mermaid
%%{init: {"theme": "base", "themeVariables": {"primaryColor": "#ECECFF", "primaryTextColor": "#000000", "primaryBorderColor": "#9370DB", "lineColor": "#555555", "secondaryColor": "#FFFFDE", "tertiaryColor": "#FFFFDE", "clusterBkg": "#FFFFDE", "clusterBorder": "#9370DB", "edgeLabelBackground": "#EEEEEE"}}}%%
flowchart TD
    subgraph OwnerPlatform["Azure Databricks - compute and governance"]
        DatabricksUsers["Databricks users and workloads"]
        DatabricksCompute["Databricks SQL or Spark compute"]
        ManagedCatalog["Unity Catalog<br/>managed tables and volumes"]
        CatalogPermissions["Unity Catalog<br/>permissions"]
        ExternalLocation["Unity Catalog external location<br/>Storage type: OneLake"]
        StorageCredential["Unity Catalog<br/>storage credential"]
        DatabricksUsers -->|"create and use tables and volumes"| DatabricksCompute
        ManagedCatalog -.->|"object metadata and authorization"| DatabricksCompute
        CatalogPermissions -.->|"govern Databricks access"| ManagedCatalog
        ManagedCatalog -.->|"managed storage path within"| ExternalLocation
        StorageCredential -.->|"authenticates storage access"| ExternalLocation
    end
    AccessIdentity["Access Connector for Azure Databricks<br/>Microsoft Entra managed identity"]
    subgraph StoragePlatform["Fabric - OneLake storage"]
        StorageItem["Azure Databricks Storage item"]
        OneLakeSecurity["OneLake security role<br/>ReadWrite: Databricks managed identity only"]
        TableFiles[("Managed table files<br/>in OneLake")]
        VolumeFiles[("Managed volume files<br/>in OneLake")]
        OneLakeSecurity -.->|"controls direct data access"| StorageItem
        StorageItem -->|"stores"| TableFiles
        StorageItem -->|"stores"| VolumeFiles
    end
    subgraph ConsumerPlatform["Fabric - analytics consumption"]
        MirroredCatalog["Mirrored Azure Databricks catalog<br/>Table metadata and OneLake shortcuts"]
        SqlEndpoint["SQL analytics endpoint<br/>Read-only table queries"]
        FabricUsers["Fabric users and workloads"]
        FabricPermissions["Fabric workspace and<br/>mirrored item permissions"]
        MirroredCatalog -.->|"exposes mirrored tables"| SqlEndpoint
        FabricUsers -->|"query tables"| SqlEndpoint
        FabricPermissions -.->|"authorize consumer access"| MirroredCatalog
    end
    AccessIdentity -.->|"referenced by"| StorageCredential
    AccessIdentity -.->|"only member of storage security role"| OneLakeSecurity
    AccessIdentity -.->|"Viewer role on Fabric workspace"| StorageItem
    ExternalLocation -.->|"ID-based ABFSS path to item Files folder"| StorageItem
    DatabricksCompute -->|"read and write table data"| TableFiles
    DatabricksCompute -->|"read and write volume data"| VolumeFiles
    ManagedCatalog -.->|"sync selected catalog and table metadata"| MirroredCatalog
    TableFiles -->|"read through mirrored catalog shortcuts<br/>no table data replication"| SqlEndpoint
    classDef lavender fill:#ECECFF,stroke:#9370DB,color:#000000;
    class DatabricksUsers,DatabricksCompute,ManagedCatalog,CatalogPermissions,ExternalLocation,StorageCredential,AccessIdentity,StorageItem,OneLakeSecurity,TableFiles,VolumeFiles,MirroredCatalog,SqlEndpoint,FabricUsers,FabricPermissions lavender;
    style OwnerPlatform fill:#FFFFDE,stroke:#9370DB,color:#000000
    style StoragePlatform fill:#FFFFDE,stroke:#9370DB,color:#000000
    style ConsumerPlatform fill:#FFFFDE,stroke:#9370DB,color:#000000
```

  
> [!NOTE]
> The Azure Databricks Storage item is not yet supported by Fabric Git integration, so it isn't exported with the other Fabric items. See [azure-databricks-storage-item](azure-databricks-storage-item/README_AzureDatabricksStorage.md) for scripts and steps to recreate it. Parts of patterns 2 and 3 are in preview; check current Microsoft documentation before relying on them.

The included analytics assets use **CMS beneficiary and provider claims concepts**; they are a healthcare/insurance example. Data files and the upstream data preparation notebook are not included.

## Start here

| Your goal | Read this |
|---|---|
| Understand the design and data direction | [Architecture and diagrams](docs/architecture.md) |
| Set up the main demo | [Getting started](docs/getting-started.md) |
| Find an exported item or its dependencies | [Asset catalog](docs/asset-catalog.md) |
| Present the demo and check results | [Demo walkthrough](docs/demo-walkthrough.md) |
| Resolve a setup or data issue | [Troubleshooting](docs/troubleshooting.md) |
| Make a contribution | [Contributing](CONTRIBUTING.md) |

## Choose an integration path

| Path | Data owner and consumer | Repository coverage |
|---|---|---|
| [Mirrored Databricks catalog](docs/patterns/mirrored-catalog.md) | Databricks owns tables; Fabric reads them | Catalog items, shortcuts, warehouse, BI and agent exports |
| [OneLake catalog federation](docs/patterns/onelake-federation.md) | Fabric owns tables; Databricks reads them | Reference guidance; no connection or foreign-catalog deployment |
| [OneLake as Databricks storage](#azure-databricks-using-onelake-as-storage) | Databricks owns tables, stored in OneLake; Fabric reads them through a mirrored catalog | Setup scripts and SQL in `azure-databricks-storage-item`; the storage item itself isn't exported because Fabric Git doesn't support it yet |

The Azure Databricks catalog item in Fabric is part of the mirrored-catalog
path, not a third independent integration pattern. Catalog mirroring
synchronizes metadata; shortcuts access the underlying data without replication.

## Quick start

1. Review the [prerequisites and setup gates](docs/getting-started.md).
2. Use an isolated Fabric demo workspace and an approved Databricks source.
3. Configure the mirrored catalog and verify the three required Silver tables.
4. Restore supported exports using Fabric Git integration, then rebind
   connections and downstream items through supported authoring tools.
5. Load the Gold star schema only after reviewing its rebuild behavior.
6. Run the [read-only validation queries](warehouse/validate-gold.sql), then
   follow the [report and agent walkthrough](docs/demo-walkthrough.md).

Follow the detailed guide before running cloud operations. Merely cloning this
repository or copying [.env.example](.env.example) does not configure resources.
No repository code loads that file.

## Repository map

| Location | Purpose |
|---|---|
| [docs](docs) | Architecture, setup, pattern guides, demo and troubleshooting |
| [ws_databricks](ws_databricks) | Service-managed Fabric item exports; preserve their hierarchy |
| [warehouse](warehouse/README.md) | Read-only validation examples; authoritative DDL stays in the exports |
| [notebooks](notebooks/README.md) | Upstream notebook requirements; no runnable notebook included |
| [scripts](scripts) | Dependency-free offline repository checks |
| [decisions](decisions) | Architecture decision template and future accepted decisions |

### Naming

`FSI` means financial services industry; `CMS` refers to Centers for Medicare
& Medicaid Services; `LH`, `WH`, and `SM` mean Lakehouse, Warehouse, and Semantic
Model.

## Validate locally

From the repository root in PowerShell:

```powershell
& .\scripts\Test-Repository.ps1
git diff --check
```

The checker validates local Markdown file targets and fence balance, JSON syntax,
and report-to-model relative paths. It does not render Mermaid, validate Fabric
schemas, execute SQL, scan for all secrets, or prove cloud connectivity.
See [validation guidance](docs/validation.md).

## Safety, cost and limitations

Use approved synthetic or public demo data, never customer or patient data.
Review exports for environment identifiers before publishing; placeholders do
not constitute a security certification. Keep credentials out of Git.

Fabric capacity, Databricks compute, storage and network traffic can incur
charges. Stop demo compute and remove only resources you own after the session.
This is not a production deployment blueprint: validate access controls,
networking, licensing, data quality and supportability in your tenant.
