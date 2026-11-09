# Warehouse

Supporting, read-only SQL lives here. Authoritative DDL and load procedures stay
in the [exported Warehouse item](../ws_databricks/Fabric%20Data%20Stores/WH_ADX_CMS_Gold.Warehouse);
do not duplicate or move them.

## Run validation

After the approved star-schema load, open the SQL query editor for
`WH_ADX_CMS_Gold` and run [validate-gold.sql](validate-gold.sql).
The script contains only read queries. It does not load data, repair rows, or
raise an error automatically when a result violates an expectation.

| Result | Expected interpretation |
|---|---|
| Table inventory | All six dimensions and three facts exist |
| Fact counts and load timestamps | All three facts are nonempty; UTC load times match your planned load window |
| Duplicate grains | Three rows, each reporting zero duplicate groups |
| Beneficiary fact orphan counts | All four counts are zero |
| Provider/population fact orphan counts | All six counts are zero |
| Beneficiary/population reconciliation | Zero rows; same yearly beneficiary observations and reimbursement |
| Provider baseline | Year/type aggregates to compare with the report at matching scope |

Missing tables cause subsequent queries to fail; stop and complete setup.
An empty result is a pass only for the reconciliation query. Duplicate and
orphan queries must return their documented rows with zero counts; inventory,
freshness and baseline results must not be empty.

The load timestamp measures Gold loading, not source freshness. For an
end-to-end freshness test, record a controlled source update time and its
first observed downstream time. Agree a target before testing.

Keep the source snapshot stable while comparing. For these same-load decimal
reimbursement totals, expect exact agreement; investigate any difference.
Do not reconcile provider payments against beneficiary reimbursement: their
metrics and coverage differ.

Cloud SQL execution is manual and potentially billable. Offline checks parse
neither T-SQL semantics nor query plans. See [validation](../docs/validation.md).
