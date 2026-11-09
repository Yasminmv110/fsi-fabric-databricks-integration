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
| Privacy patterns | Non-placeholder GUIDs and 20/32-character hex object IDs in file contents/names, environment cloud hosts, common token/private-key signatures and credential assignments; failures redact values |
| Checker regression scenarios | Fifteen success/failure scenarios covering links, fences, JSON, report references, GUID values/filenames, object IDs, cloud hosts and credentials |

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
  privacy patterns are not a complete security scanner.

## Identifier and history policy

The [privacy checker](../scripts/Test-Privacy.ps1) runs as part of the repository
check and may also run on its own. GUIDs in the synthetic namespace
`00000000-0000-0000-0000-xxxxxxxxxxxx` are placeholders, not original resources.
Report/page/visual hex IDs are also synthetic: 20-character IDs begin with ten
zeros; compact 32-character IDs begin with twenty zeros. Their mappings must
remain consistent across definitions, expressions and filenames.
The all-zero placeholder cannot preserve unique object identities; regenerate
and rebind exported items through supported tooling before deployment.
Functional fields such as `beneficiary_id`, public schema version paths, Git
hashes, and public Git authorship metadata are not environment credentials.

The checker covers tracked/non-ignored working files, not ignored local settings,
Git objects, commit messages, remote branches, PR refs, caches or forks.
After a historical disclosure, cleaning the latest tree is insufficient:
rewrite affected history only with owner approval, verify rewritten content and
ref names, and push with explicit leases. Collaborators must replace old clones
or carefully resynchronize without merging old history back.

Existing clones, GitHub caches, forks and hidden pull-request refs can retain
old objects after a force push. Contact GitHub Support for retained-object
cleanup where needed. Revoke/rotate any real credential immediately if found;
rewriting history does not invalidate it.

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
