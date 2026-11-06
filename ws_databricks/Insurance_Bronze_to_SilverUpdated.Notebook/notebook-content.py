# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "00000000-0000-0000-0000-66d8ce417af1",
# META       "default_lakehouse_name": "LH_ADX_Onelake",
# META       "default_lakehouse_workspace_id": "00000000-0000-0000-0000-4f0a9fa9337a",
# META       "known_lakehouses": [
# META         {
# META           "id": "00000000-0000-0000-0000-66d8ce417af1"
# META         }
# META       ]
# META     }
# META   }
# META }

# MARKDOWN ********************

# # Insurance: Bronze → Silver (Microsoft Fabric Lakehouse)
# 
# Attach the **schema-enabled destination Fabric Lakehouse** as this notebook's default Lakehouse; `silver.insurance` is written there. Bronze is read directly through the table shortcut's **ABFS path**, so its Lakehouse does not have to be the default. The notebook identity must have read access to the shortcut and its backing data, plus write access to the destination Lakehouse. Use a **Fabric Runtime 1.3 or later (Spark 3.5+)**, with PySpark as the notebook language. Import this `.ipynb` into Fabric and run all cells in order. No packages or external services are required.
# 
# The source columns match the supplied screenshot. The notebook creates a Delta table at `silver.insurance` with typed dates, integer ages, and `decimal(18,2)` monetary amounts, retaining identifiers as strings (including leading zeros).
# 
# **Write behavior:** this is an intentional **full snapshot replacement**, not an incremental merge. Each successful run replaces the target's data and schema with the current source snapshot. Do not use it where Silver contains historical records absent from Bronze, custom target columns, or concurrent writers. The Bronze table is never modified. An empty source is blocked by default. All tests and reconciliation checks run before the write.
# 
# **Grain:** distinct normalized policy-and-claim business records, not one row per policy or claim key. Different business values remain separate, even when their policy/claim keys match. Exact normalized duplicates retain the latest `_ingest_ts`, with deterministic tie-breaks; duplicate counts are retained. Invalid values participate in duplicate identity so different malformed values are not accidentally merged.
# 
# **Source shortcut:** `abfss://WS_Databricks@onelake.dfs.fabric.microsoft.com/LH_ADX_Onelake.Lakehouse/Tables/bronze/insurance`. The reader expects a **Delta table**, not a Files shortcut, CSV, or plain Parquet folder. It follows the shortcut using OneLake; no credentials are embedded.


# CELL ********************

from pyspark.sql import functions as F, types as T, Window
from pyspark import StorageLevel
import re

SOURCE_PATH = "abfss://WS_Databricks@onelake.dfs.fabric.microsoft.com/LH_ADX_Onelake.Lakehouse/Tables/bronze/insurance"
TARGET_TABLE = "silver.insurance"
ALLOW_EMPTY_SOURCE = False
MAX_AGE = 120

# Source is a OneLake URI; target is a table in the attached default Lakehouse.
if not SOURCE_PATH.startswith("abfss://") or "@onelake.dfs.fabric.microsoft.com/" not in SOURCE_PATH:
    raise ValueError("SOURCE_PATH must be an ABFS URI for the OneLake table shortcut.")
if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*", TARGET_TABLE):
    raise ValueError(f"Use a schema.table identifier: {TARGET_TABLE!r}")
if TARGET_TABLE.casefold() == "bronze.insurance":
    raise ValueError("The Bronze shortcut must not be used as the write target.")
if not isinstance(MAX_AGE, int) or not 0 < MAX_AGE <= 2147483647:
    raise ValueError("MAX_AGE must be a positive integer within the INT range.")

BUSINESS_COLUMNS = [
    "PolicyNumber", "CustomerID", "Gender", "Age", "PolicyType",
    "PolicyStartDate", "PolicyEndDate", "PremiumAmount", "CoverageAmount",
    "ClaimNumber", "ClaimDate", "ClaimAmount", "ClaimStatus",
]
DATE_COLUMNS = ["PolicyStartDate", "PolicyEndDate", "ClaimDate"]
AMOUNT_COLUMNS = ["PremiumAmount", "CoverageAmount", "ClaimAmount"]
REQUIRED_COLUMNS = BUSINESS_COLUMNS + ["_rescued_data", "_source_file", "_ingest_ts"]

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Cleaning and quality rules
# 
# - Trim and collapse whitespace, including nonbreaking spaces; convert empty strings and explicit `null`, `n/a`, `na`, `none` tokens (case-insensitive) to null. Identifiers remain case-sensitive and retain leading zeros; no guessed keys or imputed values.
# - Normalize common gender labels (`M`, `F`, `NB`, etc.); retain unrecognized labels in lower case. Normalize policy types and claim statuses to lower case with spaces instead of underscores/hyphens. No insurer-specific category vocabulary is assumed, and no domain-specific synonyms are merged.
# - Dates: accept exact `yyyy-MM-dd` and slash/dash-separated day/month/year or month/day/year when only one interpretation is valid, or when both yield the same date. **Reject ambiguous dates**, impossible dates, two-digit years, and timestamps. Use Spark `DATE`, without timezone conversion.
# - Age: accept whole digits from 0 through `MAX_AGE`; otherwise null and flag. Monetary values: accept nonnegative plain numbers, optional leading `+`, properly grouped comma thousands, and up to two dot-decimal places. Parenthesized negatives are recognized but rejected. Currency symbols/codes, European decimal commas, scientific notation, overflow, and excess precision are flagged rather than guessed, converted, or rounded. No currency is inferred or converted.
# - Keep **all distinct records**, including invalid ones. Missing policy/customer identifiers, failed type conversions, negative amounts, reversed policy dates, claim details without a claim number, and nonempty rescued data are flagged in `_quality_errors`. Missing optional values are allowed, and no assumptions are made about claim timing or allowed policy/status vocabularies.
# - `_is_valid` means no configured quality errors, not business certification. `_source_values` is JSON with the original business values for the retained representative row. Lineage and original rescued data remain available. Duplicate source files/raw variants are not all retained; Bronze remains the audit source.
# 
# Review/filter `_is_valid` downstream rather than silently discarding invalid rows. These rules can be extended once your insurer's business definitions are known.


# CELL ********************

def clean_text(column):
    value = F.trim(F.regexp_replace(column.cast("string"), r"[\s\u00a0]+", " "))
    return F.when(F.lower(value).isin("", "null", "n/a", "na", "none"), F.lit(None)).otherwise(value)


def safe_date(name):
    value = F.col(name)
    pattern = "^([0-9]{1,2})[/-]([0-9]{1,2})[/-]([0-9]{4})$"
    first = f"regexp_extract(`{name}`, '{pattern}', 1)"
    second = f"regexp_extract(`{name}`, '{pattern}', 2)"
    year = f"regexp_extract(`{name}`, '{pattern}', 3)"
    dmy = F.expr(f"try_cast(concat({year}, '-', lpad({second}, 2, '0'), '-', lpad({first}, 2, '0')) AS DATE)")
    mdy = F.expr(f"try_cast(concat({year}, '-', lpad({first}, 2, '0'), '-', lpad({second}, 2, '0')) AS DATE)")
    separated = value.rlike("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$|^[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}$")
    unambiguous = dmy.isNull() | mdy.isNull() | (dmy == mdy)
    return (
        F.when(value.rlike("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"), F.expr(f"try_cast(`{name}` AS DATE)"))
        .when(separated & unambiguous, F.coalesce(dmy, mdy))
        .otherwise(F.lit(None).cast("date"))
    )


def transform_insurance(source):
    missing = sorted(set(REQUIRED_COLUMNS) - set(source.columns))
    if missing:
        raise ValueError(f"Bronze table is missing required columns: {missing}")
    df = source.select(*REQUIRED_COLUMNS).withColumn(
        "_source_values", F.to_json(F.struct(*[F.col(c).alias(c) for c in BUSINESS_COLUMNS]), {"ignoreNullFields": "false"})
    )
    for name in BUSINESS_COLUMNS:
        df = df.withColumn(f"_text_{name}", clean_text(F.col(name)))
        df = df.withColumn(name, F.col(f"_text_{name}"))
    df = df.withColumn("_ingest_ts", F.expr("try_cast(`_ingest_ts` AS TIMESTAMP)"))
    df = df.withColumn("_source_file", F.col("_source_file").cast("string"))
    df = df.withColumn("_rescued_data", F.col("_rescued_data").cast("string"))
    gender = F.lower(F.col("Gender"))
    df = df.withColumn(
        "Gender",
        F.when(gender.isin("m", "male"), "male")
        .when(gender.isin("f", "female"), "female")
        .when(gender.isin("nb", "nonbinary", "non-binary", "non binary"), "nonbinary")
        .otherwise(gender),
    )
    for name in ("PolicyType", "ClaimStatus"):
        df = df.withColumn(name, F.trim(F.regexp_replace(F.lower(F.col(name)), "[ _-]+", " ")))
    age_value = F.expr("try_cast(`_text_Age` AS INT)")
    df = df.withColumn(
        "Age", F.when(F.col("_text_Age").rlike("^[0-9]+$") & age_value.between(0, MAX_AGE), age_value)
    )
    for name in DATE_COLUMNS:
        df = df.withColumn(name, safe_date(f"_text_{name}"))
    for name in AMOUNT_COLUMNS:
        text_name = f"_text_{name}"
        parsed = F.expr(f"try_cast(regexp_replace(`{text_name}`, ',', '') AS DECIMAL(18,2))")
        valid_format = F.col(text_name).rlike(r"^\+?(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$")
        df = df.withColumn(name, F.when(valid_format & (parsed >= 0), parsed))
    errors = []
    for name in ("PolicyNumber", "CustomerID"):
        errors.append(F.when(F.col(name).isNull(), F.lit(f"{name}:missing")))
    typed_columns = ["Age"] + DATE_COLUMNS + AMOUNT_COLUMNS
    for name in typed_columns:
        suffix = "invalid_or_ambiguous" if name in DATE_COLUMNS else "invalid_or_out_of_range"
        errors.append(F.when(F.col(f"_text_{name}").isNotNull() & F.col(name).isNull(), F.lit(f"{name}:{suffix}")))
    errors.append(F.when(F.col("PolicyEndDate") < F.col("PolicyStartDate"), F.lit("PolicyEndDate:before_start")))
    claim_details = F.lit(False)
    for name in ("ClaimDate", "ClaimAmount", "ClaimStatus"):
        claim_details = claim_details | F.col(f"_text_{name}").isNotNull()
    errors.append(F.when(F.col("ClaimNumber").isNull() & claim_details, F.lit("ClaimNumber:missing_with_claim_details")))
    rescued = F.trim(F.regexp_replace(F.col("_rescued_data"), r"\s+", ""))
    errors.append(F.when(rescued.isNotNull() & ~rescued.isin("", "{}", "[]", "null"), F.lit("source:rescued_data_present")))
    df = df.withColumn("_quality_errors", F.filter(F.array(*errors), lambda error: error.isNotNull()))
    df = df.withColumn("_is_valid", F.size("_quality_errors") == 0)
    invalid_values = F.struct(*[
        F.when(F.col(name).isNull(), F.col(f"_text_{name}")).alias(name)
        for name in typed_columns
    ])
    # Invalid source text distinguishes different failed conversions in duplicate identity.
    identity = F.struct(
        *[F.col(name).alias(name) for name in BUSINESS_COLUMNS],
        invalid_values.alias("invalid_values"),
        F.when(rescued.isNotNull() & ~rescued.isin("", "{}", "[]", "null"), F.col("_rescued_data")).alias("rescued_data"),
    )
    df = df.withColumn("_business_record_hash", F.sha2(F.to_json(identity, {"ignoreNullFields": "false"}), 256))
    return df.select(
        *BUSINESS_COLUMNS, "_rescued_data", "_source_file", "_ingest_ts", "_source_values",
        "_business_record_hash", "_quality_errors", "_is_valid",
    )


def deduplicate_insurance(transformed):
    group = Window.partitionBy("_business_record_hash")
    latest = group.orderBy(
        F.col("_ingest_ts").desc_nulls_last(), F.col("_source_file").asc_nulls_last(),
        F.col("_source_values").asc_nulls_last(), F.col("_rescued_data").asc_nulls_last(),
    )
    return (
        transformed.withColumn("_source_record_count", F.count(F.lit(1)).over(group))
        .withColumn("_row_number", F.row_number().over(latest))
        .filter(F.col("_row_number") == 1).drop("_row_number")
        .withColumn("_duplicate_count", F.col("_source_record_count") - 1)
    )

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Preflight transformation tests
# 
# These small, in-memory Spark tests do not read or modify the Lakehouse. They exercise the same transformation and deduplication functions used by the production cells. Any failed assertion stops the notebook before a target write. Run these cells in Fabric even if you customize the transformation rules.

# CELL ********************

test_schema = T.StructType([T.StructField(name, T.StringType(), True) for name in REQUIRED_COLUMNS])


def fixture(policy, **overrides):
    row = {name: None for name in REQUIRED_COLUMNS}
    row.update({
        "PolicyNumber": policy, "CustomerID": "000123", "Gender": " M ", "Age": "35",
        "PolicyType": " Auto_Insurance ", "PolicyStartDate": "2025-01-01",
        "PolicyEndDate": "2025-12-31", "PremiumAmount": "1,234.50", "CoverageAmount": "100000.00",
        "_ingest_ts": "2026-01-01 00:00:00", "_source_file": "test.csv",
    })
    row.update(overrides)
    return row


fixtures = [
    fixture("00001", ClaimNumber="C001", ClaimDate="13/04/2025", ClaimAmount="+250.00", ClaimStatus=" In_REVIEW "),
    fixture("00002", PolicyStartDate="03/04/2025", Age="121", PremiumAmount="-1.00"),
    fixture("00003", PolicyStartDate="2025-02-29", PremiumAmount="12,34.00"),
    fixture("00004", PolicyStartDate="04/13/2025", Gender="NB", PremiumAmount="99999999999999999.99"),
    fixture("00005", PolicyStartDate="04/04/2025", PremiumAmount="1.234", ClaimAmount="5", _rescued_data='{"extra":"x"}'),
    fixture("00006", PolicyStartDate="2025-12-31", PolicyEndDate="2025-01-01", Age="35.5", PremiumAmount="€5.00"),
    fixture("00007", ClaimNumber="C1", ClaimDate=" N/A ", PremiumAmount="(5.00)", Age="999999999999999999999"),
    fixture("00008", Age=None, PremiumAmount=None, PolicyStartDate="2025-01-01T00:00:00"),
    fixture("00009", PolicyStartDate="29-02-2024", Age="0", Gender=" Custom "),
    fixture("00010", PolicyStartDate="13/04-2025", PremiumAmount="1e3"),
    fixture(" N/A ", CustomerID=" "),
    fixture("DUP", _ingest_ts="2026-01-01 00:00:00"),
    fixture("DUP", Gender="male", PremiumAmount="1234.50", _ingest_ts="2026-02-01 00:00:00"),
    fixture("BAD", Age="bad"),
    fixture("BAD", Age="worse"),
]
transformed_test = transform_insurance(spark.createDataFrame(fixtures, test_schema))
result_test = deduplicate_insurance(transformed_test)
rows = result_test.collect()
by_policy = {row.PolicyNumber: row for row in rows if row.PolicyNumber != "BAD"}
assert len(rows) == len(fixtures) - 1, "Only normalized duplicate records should collapse."
assert by_policy["00001"].CustomerID == "000123"
assert by_policy["00001"].Gender == "male"
assert by_policy["00001"].PolicyType == "auto insurance"
assert by_policy["00001"].ClaimStatus == "in review"
assert str(by_policy["00001"].PremiumAmount) == "1234.50"
assert str(by_policy["00001"].ClaimDate) == "2025-04-13"
assert by_policy["00001"]._is_valid
assert by_policy["00002"].PolicyStartDate is None
assert by_policy["00002"].Age is None and by_policy["00002"].PremiumAmount is None
assert "PolicyStartDate:invalid_or_ambiguous" in by_policy["00002"]._quality_errors
assert by_policy["00003"].PolicyStartDate is None and by_policy["00003"].PremiumAmount is None
assert str(by_policy["00004"].PolicyStartDate) == "2025-04-13"
assert by_policy["00004"].Gender == "nonbinary" and by_policy["00004"].PremiumAmount is None
assert str(by_policy["00005"].PolicyStartDate) == "2025-04-04"
assert by_policy["00005"].PremiumAmount is None
assert "ClaimNumber:missing_with_claim_details" in by_policy["00005"]._quality_errors
assert "source:rescued_data_present" in by_policy["00005"]._quality_errors
assert "PolicyEndDate:before_start" in by_policy["00006"]._quality_errors
assert by_policy["00006"].Age is None and by_policy["00006"].PremiumAmount is None
assert by_policy["00007"].ClaimDate is None and by_policy["00007"].Age is None
assert by_policy["00007"].PremiumAmount is None
assert "ClaimDate:invalid_or_ambiguous" not in by_policy["00007"]._quality_errors
assert by_policy["00008"].PolicyStartDate is None
assert str(by_policy["00009"].PolicyStartDate) == "2024-02-29"
assert by_policy["00009"].Age == 0 and by_policy["00009"].Gender == "custom"
assert by_policy["00010"].PolicyStartDate is None and by_policy["00010"].PremiumAmount is None
assert "PolicyNumber:missing" in by_policy[None]._quality_errors
assert "CustomerID:missing" in by_policy[None]._quality_errors
assert by_policy["DUP"]._source_record_count == 2
assert str(by_policy["DUP"]._ingest_ts) == "2026-02-01 00:00:00"
assert sum(row.PolicyNumber == "BAD" for row in rows) == 2
assert sum(row._source_record_count for row in rows) == len(fixtures)
for name in DATE_COLUMNS:
    assert isinstance(result_test.schema[name].dataType, T.DateType)
for name in AMOUNT_COLUMNS:
    assert result_test.schema[name].dataType == T.DecimalType(18, 2)
assert isinstance(result_test.schema["Age"].dataType, T.IntegerType)
print(f"Preflight passed: {len(fixtures)} source fixtures → {len(rows)} distinct records.")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Read, reconcile, and replace Silver
# 
# The source is loaded with `spark.read.format("delta").load(SOURCE_PATH)` through the Bronze table shortcut and is cached and materialized once to keep a consistent snapshot during this run. Reconciliation verifies that distinct rows plus removed duplicates equals the source count. Quality summaries show counts only; source values and identifiers are not printed. Invalid records are written with flags, not dropped.
# 
# The target schema is created if needed. The Delta overwrite is transactional for the target table, but source and target are not part of a shared multi-table transaction. A failure before the write leaves the old target intact. A post-write verification failure must be investigated before retrying. Schedule runs without concurrent target writers.
# 
# If access fails, verify the shortcut is available and its backing data permissions allow the notebook identity to read it. If Spark reports that the path is not a Delta table, verify the shortcut target format rather than silently falling back to a different file reader. The configured ABFS URI is a cloud path, not a Windows filesystem path.


# CELL ********************

# Read Bronze via table name instead of direct Delta path.
# Fabric blocks path-based access for catalog-managed Lakehouse tables.

# Derive the Lakehouse table name from the configured SOURCE_PATH.
# Example:
#   abfss://.../Tables/bronze/insurance  ->  bronze.insurance
if not (isinstance(SOURCE_PATH, str) and "/Tables/" in SOURCE_PATH):
    raise ValueError(
        "SOURCE_PATH must point to a Lakehouse Tables path like .../Tables/bronze/insurance "
        "for this notebook."
    )

_after_tables = SOURCE_PATH.split("/Tables/")[1]
_parts = _after_tables.strip("/").split("/")
if len(_parts) < 2:
    raise ValueError(
        f"Cannot derive table name from SOURCE_PATH: {SOURCE_PATH!r}. "
        "Expected .../Tables/<schema>/<table>"
    )

_source_table = f"{_parts[0]}.{_parts[1]}"

source_df = (
    spark.table(_source_table)
    .select(*REQUIRED_COLUMNS)
    .persist(StorageLevel.MEMORY_AND_DISK)
)

silver_df = None
try:
    source_count = source_df.count()
    if source_count == 0 and not ALLOW_EMPTY_SOURCE:
        raise ValueError(
            "Bronze is empty. Silver was not replaced. "
            "Set ALLOW_EMPTY_SOURCE=True only intentionally."
        )

    silver_df = (
        deduplicate_insurance(transform_insurance(source_df))
        .withColumn("_processed_at", F.current_timestamp())
        .persist(StorageLevel.MEMORY_AND_DISK)
    )

    stats = silver_df.agg(
        F.count(F.lit(1)).alias("silver_rows"),
        F.coalesce(F.sum("_source_record_count"), F.lit(0)).alias("represented_source_rows"),
        F.coalesce(F.sum("_duplicate_count"), F.lit(0)).alias("duplicates_removed"),
        F.coalesce(F.sum(F.when(F.col("_is_valid"), 1).otherwise(0)), F.lit(0)).alias("valid_rows"),
    ).first()

    if stats.represented_source_rows != source_count:
        raise RuntimeError(
            "Reconciliation failed: source rows were lost or counted multiple times."
        )
    if stats.silver_rows + stats.duplicates_removed != source_count:
        raise RuntimeError(
            "Reconciliation failed: distinct rows plus duplicates differs from source count."
        )
    if (
        silver_df.groupBy("_business_record_hash")
        .count()
        .filter(F.col("count") > 1)
        .limit(1)
        .count()
    ):
        raise RuntimeError(
            "Duplicate business identities remain after deduplication."
        )

    print(
        {
            "source_rows": source_count,
            "silver_rows": stats.silver_rows,
            "duplicates_removed": stats.duplicates_removed,
            "valid_rows": stats.valid_rows,
            "review_rows": stats.silver_rows - stats.valid_rows,
        }
    )

    silver_df.select(F.explode("_quality_errors").alias("quality_error")) \
        .groupBy("quality_error") \
        .count() \
        .orderBy(F.desc("count"), "quality_error") \
        .show(truncate=False)

    target_schema = TARGET_TABLE.split(".")[0]
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS `{target_schema}`")

    silver_df.write \
        .format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .saveAsTable(TARGET_TABLE)

    written_df = spark.table(TARGET_TABLE)
    written_count = written_df.count()
    if written_count != stats.silver_rows:
        raise RuntimeError(
            f"Post-write count mismatch: expected {stats.silver_rows}, "
            f"found {written_count}."
        )

    expected_types = {field.name: field.dataType for field in silver_df.schema.fields}
    actual_types = {field.name: field.dataType for field in written_df.schema.fields}
    if actual_types != expected_types:
        raise RuntimeError(
            "Post-write schema does not match the transformation output."
        )

    print(f"Verified {TARGET_TABLE}: {written_count} records written as Delta.")

finally:
    source_df.unpersist()
    if silver_df is not None:
        silver_df.unpersist()

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Output reference and operational notes
# 
# | Columns | Silver type / purpose |
# |---|---|
# | PolicyNumber, CustomerID, Gender, PolicyType, ClaimNumber, ClaimStatus | String; normalized, no invented identifiers |
# | Age | Integer; nullable when absent/invalid |
# | PolicyStartDate, PolicyEndDate, ClaimDate | Date; nullable when absent/invalid/ambiguous |
# | PremiumAmount, CoverageAmount, ClaimAmount | Decimal(18,2); nullable when absent/invalid |
# | _rescued_data, _source_file | Original source metadata as strings |
# | _ingest_ts | Source ingestion timestamp of retained representative |
# | _source_values | Original business fields as JSON for that representative |
# | _business_record_hash | SHA-256 of normalized business values plus invalid typed input text and nonempty rescued data; lineage excluded |
# | _quality_errors | Array of field-level error labels |
# | _is_valid | Boolean: no configured quality errors |
# | _source_record_count, _duplicate_count | Long: represented Bronze rows and extra copies removed |
# | _processed_at | Timestamp for this transformation run |
# 
# ### Consumption
# 
# ```sql
# SELECT * FROM silver.insurance WHERE _is_valid = true;
# SELECT PolicyNumber, ClaimNumber, _quality_errors, _source_values
# FROM silver.insurance WHERE _is_valid = false;
# ```
# 
# The Silver SQL analytics endpoint may need time to synchronize Lakehouse metadata. The original business columns contain potentially sensitive information: apply your Fabric workspace permissions, retention policies, and access controls to `_source_values` as well as the typed columns. If you do not need raw values in general consumption, expose a view excluding `_source_values` and `_rescued_data`.
# 
# For scheduled execution, attach the correct default Lakehouse and run the whole notebook with a Fabric Notebook activity. Monitor the reconciliation and quality counts. A stable hash identifies equivalent records under **these rules**; it is not an insurer-issued key, and changing normalization rules may change hashes. A policy with multiple claims appears in multiple rows, so policy-level premiums and coverage can be repeated: do not sum them across claims without a separate policy-grain model.

