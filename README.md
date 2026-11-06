# Microsoft Fabric + Azure Databricks demo

A demo repository for exploring Azure Databricks data engineering alongside
Microsoft Fabric analytics. Existing Fabric workspace exports live under
[`ws_databricks/`](ws_databricks/); this scaffold adds navigation, contribution
guidance, and a place to record design decisions.

## Disclaimer

This is a demonstration, not a production-ready solution or an official Microsoft
product sample. It is provided as-is under the [MIT license](LICENSE), without
warranty. No deployment, connectivity, data accuracy, security posture, or
end-to-end behavior has been validated by this scaffold. Exported items may
contain environment-specific references and require manual configuration.
Use synthetic or approved, de-identified data only; never commit credentials or
customer data. Fabric capacity, Azure resources, and Databricks compute may incur
charges. Review permissions, regional availability, feature support, and costs
before running a demo.

## Status

| Area | Status | Notes |
| --- | --- | --- |
| Repository documentation | Scaffolded | Getting started, architecture, contribution guidance, and ADR template |
| Fabric workspace artifacts | Present; not validated | Existing exports are preserved unchanged |
| Azure Databricks integration | Not validated | Requires an accessible workspace, Unity Catalog, and configured connections |
| Local configuration | Example only | No code currently loads the environment variables |
| Provisioning and deployment | Not provided | No automated infrastructure or deployment workflow |
| End-to-end tests | Not provided | Validate connections, permissions, refreshes, and results in your environment |

## Start here

| Goal | Start here |
| --- | --- |
| Understand the intended flow and its limitations | [Architecture](docs/architecture.md) |
| Explore the existing workspace exports | [Fabric workspace artifacts](ws_databricks/) |
| Prepare local configuration placeholders | [Environment example](.env.example) |
| Contribute safely | [Contribution guide](CONTRIBUTING.md) |
| Record a design choice | [ADR template](decisions/adr-template.md) |

### Prepare for a demo

1. Read the disclaimer and [architecture](docs/architecture.md).
2. Obtain access to a suitable Fabric workspace and capacity, and an Azure
   Databricks workspace with Unity Catalog. Confirm supported features and
   permissions using the official documentation linked in the architecture.
3. If useful for your own tooling, copy the example locally:

   ```powershell
   Copy-Item .env.example .env
   ```

   Replace placeholders with your environment's identifiers. The file is not
   automatically loaded and does not create resources or authenticate you.
   Local environment files are ignored by Git; do not put secrets in tracked files.
4. Review the existing exports and map their dependencies to your environment.
   This repository does not currently provide a reproducible import or run procedure.
5. Before presenting, validate source access, Fabric connections, data freshness,
   semantic model refresh, and report results using approved demo data. Stop or
   remove demo resources when finished, subject to your environment's policies.

## Repository layout

```text
.
|-- README.md
|-- CONTRIBUTING.md
|-- LICENSE
|-- .env.example
|-- .gitignore
|-- docs/
|   `-- architecture.md
|-- decisions/
|   `-- adr-template.md
`-- ws_databricks/                  Existing Fabric workspace exports
    |-- Readme.md
    |-- Agents/
    |-- Azure Databricks Store/
    |-- Business Intelligence/
    `-- Fabric Data Stores/
```

Fabric item folders (such as `.Notebook`, `.Lakehouse`, `.Warehouse`,
`.MirroredAzureDatabricksCatalog`, `.SemanticModel`, and `.Report`) contain
service-managed definitions. This documentation scaffold does not create or
modify any of them.