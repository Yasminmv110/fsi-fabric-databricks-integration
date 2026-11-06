# Contributing

## Scope

Keep contributions focused on the Microsoft Fabric + Azure Databricks demo.
Read the [README](README.md) and [architecture](docs/architecture.md) first.
Use a branch and submit a pull request describing the purpose, changes,
validation performed, and any limitations.

## Protect Fabric workspace exports

- Do not create, rename, delete, or manually edit Fabric item folders as part of
  documentation or scaffolding work.
- This includes folders ending in `.Notebook`, `.Lakehouse`, `.Warehouse`,
  `.MirroredAzureDatabricksCatalog`, `.Eventstream`, `.DataAgent`, `.Ontology`,
  `.SemanticModel`, `.Report`, and any other Fabric item type, including their
  nested files and metadata.
- If an item change is explicitly in scope for a separate contribution, use
  supported Fabric authoring/export and source-control workflows, and clearly
  describe the resulting item changes in the pull request.
- Preserve unrelated local changes and existing environment-specific references.

## Configuration and data

- Keep `.env.example` limited to documented, non-secret placeholders.
- Keep local settings in ignored environment files; never commit tokens,
  passwords, connection strings containing secrets, or customer data.
- Prefer Microsoft Entra authentication and approved secret management for
  future integrations. Grant only the access needed for the demo.
- Do not provision resources, run paid workloads, or change workspace settings
  merely to validate a documentation contribution.

## Documentation and decisions

- Update related documentation when behavior, prerequisites, or setup changes.
- Distinguish proposed architecture, existing artifacts, and verified behavior.
- Record significant choices by copying the [ADR template](decisions/adr-template.md)
  to `decisions/NNNN-short-title.md`. Use sequential numbers starting at `0001`.
  The template itself is not an accepted decision.
- Describe alternatives, consequences, and how the decision will be validated.

## Validation and pull request checklist

- [ ] Links and repository paths resolve; examples contain placeholders only.
- [ ] Status claims match the evidence, with untested paths labeled explicitly.
- [ ] No unintended Fabric item changes appear in the diff.
- [ ] No local environment files, credentials, or customer data are staged.
- [ ] Relevant documentation and ADRs are updated.
- [ ] Validation steps and outcomes are included in the pull request.

For documentation-only changes, review links, Markdown rendering, and
`git diff --check`; cloud execution is not required. There is currently no
automated build or test suite for this scaffold. Future executable changes
should include focused tests and a reproducible, cost-aware validation procedure.
