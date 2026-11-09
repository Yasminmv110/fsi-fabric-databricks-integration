# Demo walkthrough

[Home](../README.md) | [Setup](getting-started.md) | [Validation](validation.md)

## Prepare before presenting

Complete setup, record the data snapshot and load time, and run
[Gold validation](../warehouse/validate-gold.sql). Open the report and confirm
that every visual works before the audience joins. No finished-report
screenshot is included because a live workspace has not been captured here.
Add only approved, redacted screenshots from your validated deployment; never
use a mock screenshot as evidence of a working demo.

## Presenter flow

| Step | Show | Explain or verify |
|---|---|---|
| 1 | [Architecture overview](architecture.md) | Databricks owns Silver; Fabric reads through shortcuts |
| 2 | Mirrored catalog and LH_ADX_Mirror | Selected tables, schema visibility and a real SQL read |
| 3 | Gold warehouse | Physical transformation is separate from zero-copy catalog access |
| 4 | Before and After models | Technical names versus business names and explicit measures |
| 5 | Overview report | The report uses After; totals match SQL at the same filter scope |
| 6, optional | Ontology and Data Agent | Entity context supports exploration, not guaranteed correctness |

Do not present the separate insurance example or Eventstream as a prerequisite
for the CMS report. Do not imply the reverse federation path is deployed.

## Questions and expected answer characteristics

| Question | Expected evidence |
|---|---|
| Show Medicare reimbursement by summary year | Sum of `total_medicare_reimbursement_amt` from the beneficiary fact, grouped by year |
| Which providers have the most inpatient claims in the latest available inpatient year? | Provider fact, Inpatient filter, latest matching year, descending claim count |
| Show diabetes prevalence by state and year | Population summary; sum of diabetes counts divided by sum of beneficiary counts |
| Can beneficiary demographics filter provider claims? | Explain that the model does not provide joint provider/demographic attribution |

Check generated SQL and cited sources, not just fluent prose. Use a matching SQL
baseline for each question. If a query fails or an answer lacks evidence, show
the limitation and stop that branch of the demo instead of claiming success.

### Metric traps to call out

- Beneficiary counts are not additive across years, providers or claim types.
- Provider claim payments and beneficiary Medicare reimbursement are different
  metrics with potentially different year coverage.
- Average group values and prevalence rates should not be averaged unweighted.
- Provider facts support provider/year/claim-type filters, not beneficiary
  state/demographic attribution.

## Evidence and closeout

Record UTC observation time, filter context, SQL result, displayed result,
pass/fail and any tolerance agreed before comparison. Use aggregate evidence
only; keep private identifiers and detailed data outside the repository.

End by explaining what was actually validated, then follow the
[cleanup guidance](getting-started.md). A successful report does not establish
production security, resilience or regulatory compliance.
