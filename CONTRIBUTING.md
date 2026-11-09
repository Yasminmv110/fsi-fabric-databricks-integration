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

An explicitly approved privacy sanitization is an exception to the manual-edit
restriction: replace original environment identifiers consistently, including
filenames and embedded configuration, then validate the resulting templates.
Do not treat sanitized exports as deployable without recreating/rebinding items.

## Configuration and data

- Keep `.env.example` limited to documented, non-secret placeholders.
- Keep local settings in ignored environment files; never commit tokens,
  passwords, connection strings containing secrets, or customer data.
- Published GUID values must use the synthetic placeholder namespace
  `00000000-0000-0000-0000-xxxxxxxxxxxx` (hexadecimal suffix). Use distinct
  placeholders for distinct source values and reuse each mapping consistently.
  The all-zero value is an unresolved placeholder, not a live resource.
- Replace source hostnames with `HOST_PLACEHOLDER` and source workspace names
  with `WORKSPACE_NAME_PLACEHOLDER`. Preserve public schema URLs and functional
  column names such as `beneficiary_id`.
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

For documentation and supporting-script changes, run from the repository root:

```powershell
& .\scripts\Test-Repository.ps1
& .\scripts\Test-Repository.Tests.ps1
git diff --check
```

Also preview Markdown and Mermaid rendering. The offline checks and GitHub
Actions workflow do not execute SQL, validate service-managed schemas, detect
every secret format, or prove cloud behavior. See [validation](docs/validation.md)
for exact coverage and the separate, approval-required live acceptance checks.

Keep onboarding prose in `docs/`, read-only SQL examples in `warehouse/`, and
offline checks in `scripts/`. Do not duplicate exported DDL or create empty
folders to imply an implemented feature. Future executable changes should
include focused tests and a reproducible, cost-aware validation procedure.
