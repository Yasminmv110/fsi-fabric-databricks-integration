# Validation

[Home](../README.md) | [Setup](getting-started.md) | [Demo](demo-walkthrough.md)

## Offline checks

Run from the repository root in Windows PowerShell 5.1 or later with Git:

```powershell
& .\scripts\Test-Repository.ps1
& .\scripts\Test-Repository.Tests.ps1
git diff --check
```

If script execution is restricted, use your organization's approved policy;
do not disable security controls merely to run the checker.

The [checker](../scripts/Test-Repository.ps1) reads tracked and non-ignored
untracked files. Deleted files are skipped, but links/references to them fail.
It performs no network calls or cloud mutations.

| Check | Coverage and limits |
|---|---|
| Markdown links/images | Existing local targets in inline links outside fenced code; not anchors, external URLs, reference-style links or full Markdown parsing |
| Markdown fences | Matching backtick/tilde fences; not Markdown style or Mermaid syntax |
| JSON syntax | `.json`, `.platform`, `.pbir`, `.pbism`; not Fabric JSON schema compatibility or SQL strings |
| Report references | Existing model directory for exported `datasetReference.byPath`; not deployed bindings or model semantics |
| Checker regression scenarios | Valid encoded link/reference, missing target, unclosed fence, ignored code example, invalid JSON, missing model |

[GitHub Actions](../.github/workflows/validate.yml) runs the checker, its
regression scenarios, and whitespace checks without Azure/Fabric credentials.
It checks the pushed/PR checkout, not uncommitted local work.

## Manual review before publishing

- Preview the README and both Mermaid diagrams in GitHub or a compatible
  Markdown preview; confirm labels, arrows and layout render correctly.
- Review changed links and current official feature requirements.
- Confirm exported item changes were intentional and made through supported
  workflows. Documentation changes must not rewrite managed exports.
- Review for credentials, detailed data, source tenant endpoints and IDs.
  Enable repository secret scanning/push protection where available; the local
  checker is **not** a secret scanner.

## Live acceptance checklist

Cloud checks require environment-owner approval and may incur costs.

- [ ] Remote branch and supported Fabric items synchronized into an isolated workspace.
- [ ] Source identity can read each selected table and its underlying storage.
- [ ] Silver SQL tables match the source snapshot and required input schema.
- [ ] Reviewed star-schema load produces all six dimensions and three facts.
- [ ] [Gold diagnostics](../warehouse/validate-gold.sql) satisfy every documented expectation.
- [ ] Report/model results match SQL for the same metric and filter scope.
- [ ] Optional agent answers have inspected SQL, correct grain and matching baselines.
- [ ] A controlled source update is observed downstream within a target agreed before testing.
- [ ] Only owned demo resources are stopped/cleaned up afterward.

Record commit, data snapshot, UTC timestamps, expected/actual results and
limitations privately. Do not mark the cloud path verified merely because
the offline checks pass.
