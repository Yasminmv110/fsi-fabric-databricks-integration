/* =====================================================================================
   CMS DE-SynPUF: Silver -> Gold star schema load procedure
   Target : Fabric Data Warehouse  [WH_ADX_CMS_Gold]   (run this script in that warehouse)
   Source : Lakehouse SQL endpoint [LH_ADX_Mirror].[silver] (shortcuts to the Databricks
            silver Delta tables built by bronze_to_silver_cms.py)

     [LH_ADX_Mirror].[silver].[beneficiary_summary]  grain: beneficiary_id + summary_year
     [LH_ADX_Mirror].[silver].[inpatient_claims]     grain: claim_id + claim_segment
     [LH_ADX_Mirror].[silver].[outpatient_claims]    grain: claim_id + claim_segment

   Gold star schema (PK = primary key, FK = foreign key; all keys are NOT ENFORCED)

     Dimensions
       gold.dim_year          PK calendar_year
       gold.dim_state         PK state_code
       gold.dim_demographic   PK demographic_key   (sex x race x age_band, 75 rows)
       gold.dim_beneficiary   PK beneficiary_id
       gold.dim_provider      PK provider_number
       gold.dim_claim_type    PK claim_type

     Facts
       gold.fact_beneficiary_annual_utilization  PK beneficiary_id + summary_year
           FK beneficiary_id -> dim_beneficiary, summary_year -> dim_year,
              state_code -> dim_state, demographic_key -> dim_demographic
       gold.fact_provider_annual_summary         PK provider_number + claim_year + claim_type
           FK provider_number -> dim_provider, claim_year -> dim_year,
              claim_type -> dim_claim_type
       gold.fact_population_health_summary       PK summary_year + state_code + demographic_key
           FK summary_year -> dim_year, state_code -> dim_state,
              demographic_key -> dim_demographic

   Deploy : run this whole file once. It is a single CREATE OR ALTER batch, so it needs
            no GO separators and can be run again safely.
   Run    : EXEC dbo.usp_load_gold_cms;

   Idempotency and safety
   * Each run rebuilds every gold table in full from silver. Running it again with the
     same silver data gives the same gold data, including the same key values.
   * The new data is built into gold.*__stage tables first. While that happens, users
     still read the current gold tables.
   * Checks run on the staged data: source not empty, no duplicate keys, no fact rows
     without a matching dimension row, and row counts that reconcile. If any check
     fails, the procedure stops and the gold tables are not changed.
   * In one short transaction, the procedure drops the old tables (facts first, because
     their foreign keys point at the dimensions), renames the stage tables, and adds
     the keys again. Users see either the old set or the new set, never a mix.
   * The swap also drops the three tables from the earlier, non-star version
     (gold.beneficiary_annual_utilization, gold.provider_annual_summary,
     gold.population_health_summary), which the fact_ tables replace.
   * Leftover stage tables from a failed run are dropped at the start and in CATCH.
   * Don't run two loads at the same time, because they share the stage table names.

   Fabric notes
   * Fabric only allows PRIMARY KEY / UNIQUE as NONCLUSTERED NOT ENFORCED and FOREIGN
     KEY as NOT ENFORCED, and only through ALTER TABLE. Fabric never checks them; the
     checks in this procedure are what guarantee the keys are actually valid. They
     document the model and help the query optimizer. Power BI relationships still
     need to be set up in the semantic model.
   * Key columns are wrapped in ISNULL so CTAS creates them as NOT NULL.
   * The Lakehouse and this warehouse must be in the same workspace for three-part
     (cross-database) names to work.
   * Delta types appear in the Lakehouse SQL endpoint as: string -> VARCHAR(8000),
     boolean -> BIT, timestamp -> DATETIME2(6), and decimal and date keep their type.
     Strings are cast to sized VARCHARs. BIT flags are cast to INT so they can be
     summed, because SUM(BIT) isn't allowed.
   * The Lakehouse SQL endpoint syncs Delta metadata asynchronously. After a Databricks
     reload, make sure the endpoint is in sync before you run this procedure.
   * A claim can have two segment rows, so claims are rolled up to one row per
     claim_id first. Counts are distinct claims, and amounts are summed across segments.
   * claim_year is YEAR(claim_from_date). Claims without a valid from-date are left
     out of the year-based tables.
   ===================================================================================== */
CREATE   PROCEDURE gold.usp_load_gold_dim_fact
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @load_ts            DATETIME2(6) = SYSUTCDATETIME();
    DECLARE @silver_rows        BIGINT;
    DECLARE @bau_rows           BIGINT;
    DECLARE @bau_dups           BIGINT;
    DECLARE @pas_rows           BIGINT;
    DECLARE @pas_dups           BIGINT;
    DECLARE @phs_rows           BIGINT;
    DECLARE @phs_dups           BIGINT;
    DECLARE @phs_benes          BIGINT;
    DECLARE @dim_year_rows      BIGINT;
    DECLARE @dim_state_rows     BIGINT;
    DECLARE @dim_demo_rows      BIGINT;
    DECLARE @dim_bene_rows      BIGINT;
    DECLARE @dim_prov_rows      BIGINT;
    DECLARE @dim_ctype_rows     BIGINT;
    DECLARE @dim_dups           BIGINT;
    DECLARE @orph_bene          BIGINT;
    DECLARE @orph_year          BIGINT;
    DECLARE @orph_state         BIGINT;
    DECLARE @orph_demo          BIGINT;
    DECLARE @orph_prov          BIGINT;
    DECLARE @orph_ctype         BIGINT;
    DECLARE @msg                NVARCHAR(2048);

    BEGIN TRY
        IF SCHEMA_ID(N'gold') IS NULL
            EXEC (N'CREATE SCHEMA gold');

        DROP TABLE IF EXISTS gold.dim_year__stage;
        DROP TABLE IF EXISTS gold.dim_state__stage;
        DROP TABLE IF EXISTS gold.dim_demographic__stage;
        DROP TABLE IF EXISTS gold.dim_beneficiary__stage;
        DROP TABLE IF EXISTS gold.dim_provider__stage;
        DROP TABLE IF EXISTS gold.dim_claim_type__stage;
        DROP TABLE IF EXISTS gold.fact_beneficiary_annual_utilization__stage;
        DROP TABLE IF EXISTS gold.fact_provider_annual_summary__stage;
        DROP TABLE IF EXISTS gold.fact_population_health_summary__stage;

        /* -----------------------------------------------------------------------------
           dim_demographic
              Every combination of sex, race, and age band (3 x 5 x 5 = 75 rows), each
              including an 'Unknown' member. The key is calculated from fixed sort
              orders (sex*100 + race*10 + age_band), so it is the same on every run.
              The fact table calculates the same key with the same CASE logic.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.dim_demographic__stage
        AS
        SELECT
            ISNULL(CAST(s.sort_order * 100 + r.sort_order * 10 + a.sort_order AS INT), 0)
                                                        AS demographic_key,
            ISNULL(CAST(s.val AS VARCHAR(10)), '')      AS sex,
            ISNULL(CAST(r.val AS VARCHAR(10)), '')      AS race,
            ISNULL(CAST(a.val AS VARCHAR(10)), '')      AS age_band,
            CAST(s.sort_order AS INT)                   AS sex_sort,
            CAST(r.sort_order AS INT)                   AS race_sort,
            CAST(a.sort_order AS INT)                   AS age_band_sort,
            @load_ts                                    AS _gold_load_ts
        FROM (
                  SELECT 1 AS sort_order, 'Female'  AS val
        UNION ALL SELECT 2,               'Male'
        UNION ALL SELECT 3,               'Unknown'
        ) AS s
        CROSS JOIN (
                  SELECT 1 AS sort_order, 'White'    AS val
        UNION ALL SELECT 2,               'Black'
        UNION ALL SELECT 3,               'Hispanic'
        UNION ALL SELECT 4,               'Other'
        UNION ALL SELECT 5,               'Unknown'
        ) AS r
        CROSS JOIN (
                  SELECT 1 AS sort_order, 'Under 65' AS val
        UNION ALL SELECT 2,               '65-74'
        UNION ALL SELECT 3,               '75-84'
        UNION ALL SELECT 4,               '85+'
        UNION ALL SELECT 5,               'Unknown'
        ) AS a;

        /* -----------------------------------------------------------------------------
           dim_claim_type
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.dim_claim_type__stage
        AS
        SELECT
            ISNULL(CAST('Inpatient' AS VARCHAR(10)), '')                         AS claim_type,
            CAST('Part A institutional inpatient claims' AS VARCHAR(100))        AS claim_type_description,
            @load_ts                                                             AS _gold_load_ts
        UNION ALL
        SELECT
            ISNULL(CAST('Outpatient' AS VARCHAR(10)), ''),
            CAST('Part B institutional outpatient claims' AS VARCHAR(100)),
            @load_ts;

        /* -----------------------------------------------------------------------------
           dim_beneficiary
              One row per beneficiary. Attributes come from the beneficiary's most
              recent summary year. death_date is the latest one recorded in any year.
              Attributes that change by year (state, age, coverage, conditions) stay on
              the fact table.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.dim_beneficiary__stage
        AS
        SELECT
            ISNULL(CAST(x.beneficiary_id AS VARCHAR(50)), '')  AS beneficiary_id,
            x.birth_date,
            x.max_death_date                                   AS death_date,
            ISNULL(CAST(x.sex AS VARCHAR(10)), 'Unknown')      AS sex,
            ISNULL(CAST(x.race AS VARCHAR(10)), 'Unknown')     AS race,
            ISNULL(CAST(x.state_code AS VARCHAR(10)), 'Unknown')
                                                               AS latest_state_code,
            CAST(x.county_code AS VARCHAR(10))                 AS latest_county_code,
            x.first_summary_year,
            x.last_summary_year,
            @load_ts                                           AS _gold_load_ts
        FROM (
            SELECT
                beneficiary_id,
                birth_date,
                sex,
                race,
                state_code,
                county_code,
                MAX(death_date)   OVER (PARTITION BY beneficiary_id)   AS max_death_date,
                MIN(summary_year) OVER (PARTITION BY beneficiary_id)   AS first_summary_year,
                MAX(summary_year) OVER (PARTITION BY beneficiary_id)   AS last_summary_year,
                ROW_NUMBER()      OVER (PARTITION BY beneficiary_id
                                        ORDER BY summary_year DESC)    AS rn
            FROM [LH_ADX_Mirror].[silver].[beneficiary_summary]
        ) AS x
        WHERE x.rn = 1;

        /* -----------------------------------------------------------------------------
           fact_beneficiary_annual_utilization
              One row per beneficiary per summary year, with conditions, annual
              reimbursement from the summary file, and that year's inpatient and
              outpatient claim totals. Beneficiaries with no claims get 0. Claims only
              count when they match a beneficiary-year in the summary file.
              Strings are cast to VARCHAR(10) before ISNULL, so 'Unknown' fits and is
              never truncated.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.fact_beneficiary_annual_utilization__stage
        AS
        SELECT
            ISNULL(CAST(b.beneficiary_id AS VARCHAR(50)), '')                 AS beneficiary_id,
            ISNULL(b.summary_year, 0)                                         AS summary_year,
            ISNULL(CAST(b.state_code AS VARCHAR(10)), 'Unknown')              AS state_code,
            ISNULL(CAST(
                  CASE b.sex  WHEN 'Female'   THEN 100
                              WHEN 'Male'     THEN 200
                              ELSE 300 END
                + CASE b.race WHEN 'White'    THEN 10
                              WHEN 'Black'    THEN 20
                              WHEN 'Hispanic' THEN 30
                              WHEN 'Other'    THEN 40
                              ELSE 50 END
                + CASE WHEN b.age_at_year_end IS NULL THEN 5
                       WHEN b.age_at_year_end < 65    THEN 1
                       WHEN b.age_at_year_end < 75    THEN 2
                       WHEN b.age_at_year_end < 85    THEN 3
                       ELSE 4 END
              AS INT), 0)                                                     AS demographic_key,
            CAST(b.county_code AS VARCHAR(10))                                AS county_code,
            b.age_at_year_end,
            CAST(b.is_deceased AS INT)                                        AS is_deceased,
            CAST(b.has_esrd AS INT)                                           AS has_esrd,
            b.part_a_coverage_months,
            b.part_b_coverage_months,
            b.hmo_coverage_months,
            b.part_d_coverage_months,

            CAST(b.has_alzheimers AS INT)                                     AS has_alzheimers,
            CAST(b.has_heart_failure AS INT)                                  AS has_heart_failure,
            CAST(b.has_chronic_kidney_disease AS INT)                         AS has_chronic_kidney_disease,
            CAST(b.has_cancer AS INT)                                         AS has_cancer,
            CAST(b.has_copd AS INT)                                           AS has_copd,
            CAST(b.has_depression AS INT)                                     AS has_depression,
            CAST(b.has_diabetes AS INT)                                       AS has_diabetes,
            CAST(b.has_ischemic_heart_disease AS INT)                         AS has_ischemic_heart_disease,
            CAST(b.has_osteoporosis AS INT)                                   AS has_osteoporosis,
            CAST(b.has_rheumatoid_osteo_arthritis AS INT)                     AS has_rheumatoid_osteo_arthritis,
            CAST(b.has_stroke_tia AS INT)                                     AS has_stroke_tia,
            b.chronic_condition_count,

            b.inpatient_medicare_reimbursement_amt,
            b.outpatient_medicare_reimbursement_amt,
            b.carrier_medicare_reimbursement_amt,
            b.total_medicare_reimbursement_amt,
            CAST(ISNULL(b.inpatient_beneficiary_responsibility_amt, 0)
               + ISNULL(b.outpatient_beneficiary_responsibility_amt, 0)
               + ISNULL(b.carrier_beneficiary_responsibility_amt, 0) AS DECIMAL(18,2))
                                                                              AS total_beneficiary_responsibility_amt,

            ISNULL(ip.inpatient_claim_count, 0)                               AS inpatient_claim_count,
            ISNULL(ip.inpatient_length_of_stay_days, 0)                       AS inpatient_length_of_stay_days,
            ISNULL(ip.inpatient_utilization_days, 0)                          AS inpatient_utilization_days,
            CAST(ISNULL(ip.inpatient_claim_payment_amt, 0) AS DECIMAL(18,2))  AS inpatient_claim_payment_amt,
            CAST(ISNULL(ip.inpatient_cost_share_amt, 0) AS DECIMAL(18,2))     AS inpatient_cost_share_amt,

            ISNULL(op.outpatient_claim_count, 0)                              AS outpatient_claim_count,
            ISNULL(op.outpatient_visit_days, 0)                               AS outpatient_visit_days,
            CAST(ISNULL(op.outpatient_claim_payment_amt, 0) AS DECIMAL(18,2)) AS outpatient_claim_payment_amt,
            CAST(ISNULL(op.outpatient_cost_share_amt, 0) AS DECIMAL(18,2))    AS outpatient_cost_share_amt,

            CAST(ISNULL(ip.inpatient_claim_payment_amt, 0)
               + ISNULL(op.outpatient_claim_payment_amt, 0) AS DECIMAL(18,2)) AS total_claim_payment_amt,

            @load_ts                                                          AS _gold_load_ts
        FROM [LH_ADX_Mirror].[silver].[beneficiary_summary] AS b
        LEFT JOIN (
            SELECT
                c.beneficiary_id,
                c.claim_year,
                COUNT(*)                     AS inpatient_claim_count,
                SUM(c.length_of_stay_days)   AS inpatient_length_of_stay_days,
                SUM(c.utilization_day_count) AS inpatient_utilization_days,
                SUM(c.claim_payment_amt)     AS inpatient_claim_payment_amt,
                SUM(c.cost_share_amt)        AS inpatient_cost_share_amt
            FROM (
                SELECT
                    beneficiary_id,
                    claim_id,
                    YEAR(MIN(claim_from_date))            AS claim_year,
                    MAX(length_of_stay_days)              AS length_of_stay_days,
                    SUM(ISNULL(utilization_day_count, 0)) AS utilization_day_count,
                    SUM(ISNULL(claim_payment_amt, 0))     AS claim_payment_amt,
                    SUM(ISNULL(inpatient_deductible_amt, 0)
                      + ISNULL(part_a_coinsurance_amt, 0)
                      + ISNULL(blood_deductible_amt, 0))  AS cost_share_amt
                FROM [LH_ADX_Mirror].[silver].[inpatient_claims]
                GROUP BY beneficiary_id, claim_id
            ) AS c
            WHERE c.claim_year IS NOT NULL
            GROUP BY c.beneficiary_id, c.claim_year
        ) AS ip
            ON  ip.beneficiary_id = b.beneficiary_id
            AND ip.claim_year     = b.summary_year
        LEFT JOIN (
            SELECT
                c.beneficiary_id,
                c.claim_year,
                COUNT(*)                          AS outpatient_claim_count,
                COUNT(DISTINCT c.claim_from_date) AS outpatient_visit_days,
                SUM(c.claim_payment_amt)          AS outpatient_claim_payment_amt,
                SUM(c.cost_share_amt)             AS outpatient_cost_share_amt
            FROM (
                SELECT
                    beneficiary_id,
                    claim_id,
                    MIN(claim_from_date)                  AS claim_from_date,
                    YEAR(MIN(claim_from_date))            AS claim_year,
                    SUM(ISNULL(claim_payment_amt, 0))     AS claim_payment_amt,
                    SUM(ISNULL(part_b_deductible_amt, 0)
                      + ISNULL(part_b_coinsurance_amt, 0)
                      + ISNULL(blood_deductible_amt, 0))  AS cost_share_amt
                FROM [LH_ADX_Mirror].[silver].[outpatient_claims]
                GROUP BY beneficiary_id, claim_id
            ) AS c
            WHERE c.claim_year IS NOT NULL
            GROUP BY c.beneficiary_id, c.claim_year
        ) AS op
            ON  op.beneficiary_id = b.beneficiary_id
            AND op.claim_year     = b.summary_year;

        /* -----------------------------------------------------------------------------
           fact_provider_annual_summary
              One row per provider, claim year, and claim type. Claims without a
              provider number or a valid from-date are left out.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.fact_provider_annual_summary__stage
        AS
        SELECT
            ISNULL(c.provider_number, '')                                 AS provider_number,
            ISNULL(c.claim_year, 0)                                       AS claim_year,
            ISNULL(c.claim_type, '')                                      AS claim_type,
            COUNT(*)                                                      AS claim_count,
            COUNT(DISTINCT c.beneficiary_id)                              AS beneficiary_count,
            CAST(SUM(c.claim_payment_amt) AS DECIMAL(18,2))               AS total_claim_payment_amt,
            CAST(AVG(c.claim_payment_amt) AS DECIMAL(18,2))               AS avg_claim_payment_amt,
            CAST(SUM(c.primary_payer_paid_amt) AS DECIMAL(18,2))          AS total_primary_payer_paid_amt,
            CAST(SUM(c.cost_share_amt) AS DECIMAL(18,2))                  AS total_beneficiary_cost_share_amt,
            CAST(AVG(CAST(c.claim_duration_days AS DECIMAL(18,4))) AS DECIMAL(9,2))
                                                                          AS avg_claim_duration_days,
            SUM(c.length_of_stay_days)                                    AS total_length_of_stay_days,
            CAST(AVG(CAST(c.length_of_stay_days AS DECIMAL(18,4))) AS DECIMAL(9,2))
                                                                          AS avg_length_of_stay_days,
            CAST(AVG(CAST(c.diagnosis_code_count AS DECIMAL(18,4))) AS DECIMAL(9,2))
                                                                          AS avg_diagnosis_code_count,
            CAST(AVG(CAST(c.procedure_code_count AS DECIMAL(18,4))) AS DECIMAL(9,2))
                                                                          AS avg_procedure_code_count,
            @load_ts                                                      AS _gold_load_ts
        FROM (
            SELECT
                CAST('Inpatient' AS VARCHAR(10))                          AS claim_type,
                CAST(MIN(provider_number) AS VARCHAR(50))                 AS provider_number,
                beneficiary_id,
                claim_id,
                YEAR(MIN(claim_from_date))                                AS claim_year,
                SUM(ISNULL(claim_payment_amt, 0))                         AS claim_payment_amt,
                SUM(ISNULL(primary_payer_paid_amt, 0))                    AS primary_payer_paid_amt,
                SUM(ISNULL(inpatient_deductible_amt, 0)
                  + ISNULL(part_a_coinsurance_amt, 0)
                  + ISNULL(blood_deductible_amt, 0))                      AS cost_share_amt,
                DATEDIFF(DAY, MIN(claim_from_date), MAX(claim_thru_date)) AS claim_duration_days,
                MAX(length_of_stay_days)                                  AS length_of_stay_days,
                MAX(diagnosis_code_count)                                 AS diagnosis_code_count,
                MAX(procedure_code_count)                                 AS procedure_code_count
            FROM [LH_ADX_Mirror].[silver].[inpatient_claims]
            GROUP BY beneficiary_id, claim_id

            UNION ALL

            SELECT
                CAST('Outpatient' AS VARCHAR(10)),
                CAST(MIN(provider_number) AS VARCHAR(50)),
                beneficiary_id,
                claim_id,
                YEAR(MIN(claim_from_date)),
                SUM(ISNULL(claim_payment_amt, 0)),
                SUM(ISNULL(primary_payer_paid_amt, 0)),
                SUM(ISNULL(part_b_deductible_amt, 0)
                  + ISNULL(part_b_coinsurance_amt, 0)
                  + ISNULL(blood_deductible_amt, 0)),
                DATEDIFF(DAY, MIN(claim_from_date), MAX(claim_thru_date)),
                CAST(NULL AS INT),
                MAX(diagnosis_code_count),
                MAX(procedure_code_count)
            FROM [LH_ADX_Mirror].[silver].[outpatient_claims]
            GROUP BY beneficiary_id, claim_id
        ) AS c
        WHERE c.claim_year IS NOT NULL
          AND c.provider_number IS NOT NULL
        GROUP BY c.provider_number, c.claim_year, c.claim_type;

        /* -----------------------------------------------------------------------------
           fact_population_health_summary
              One row per year, state, and demographic group. It is built from the
              staged beneficiary fact, so all gold tables come from the same snapshot.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.fact_population_health_summary__stage
        AS
        SELECT
            ISNULL(u.summary_year, 0)                                     AS summary_year,
            ISNULL(u.state_code, 'Unknown')                               AS state_code,
            ISNULL(u.demographic_key, 0)                                  AS demographic_key,

            COUNT(*)                                                      AS beneficiary_count,
            SUM(u.is_deceased)                                            AS deceased_count,
            SUM(u.has_esrd)                                               AS esrd_count,
            CAST(AVG(CAST(u.age_at_year_end AS DECIMAL(18,4))) AS DECIMAL(9,2))
                                                                          AS avg_age,
            CAST(AVG(CAST(u.chronic_condition_count AS DECIMAL(18,4))) AS DECIMAL(9,2))
                                                                          AS avg_chronic_condition_count,
            SUM(CASE WHEN u.chronic_condition_count >= 3 THEN 1 ELSE 0 END)
                                                                          AS multi_chronic_3plus_count,

            SUM(u.has_alzheimers)                                         AS alzheimers_count,
            SUM(u.has_heart_failure)                                      AS heart_failure_count,
            SUM(u.has_chronic_kidney_disease)                             AS chronic_kidney_disease_count,
            SUM(u.has_cancer)                                             AS cancer_count,
            SUM(u.has_copd)                                               AS copd_count,
            SUM(u.has_depression)                                         AS depression_count,
            SUM(u.has_diabetes)                                           AS diabetes_count,
            SUM(u.has_ischemic_heart_disease)                             AS ischemic_heart_disease_count,
            SUM(u.has_osteoporosis)                                       AS osteoporosis_count,
            SUM(u.has_rheumatoid_osteo_arthritis)                         AS rheumatoid_osteo_arthritis_count,
            SUM(u.has_stroke_tia)                                         AS stroke_tia_count,
            CAST(SUM(u.has_diabetes) * 1.0 / COUNT(*) AS DECIMAL(9,4))    AS diabetes_prevalence_rate,
            CAST(SUM(u.has_heart_failure) * 1.0 / COUNT(*) AS DECIMAL(9,4))
                                                                          AS heart_failure_prevalence_rate,
            CAST(SUM(u.has_ischemic_heart_disease) * 1.0 / COUNT(*) AS DECIMAL(9,4))
                                                                          AS ischemic_heart_disease_prevalence_rate,

            CAST(SUM(u.total_medicare_reimbursement_amt) AS DECIMAL(18,2))
                                                                          AS total_medicare_reimbursement_amt,
            CAST(SUM(u.total_medicare_reimbursement_amt) / COUNT(*) AS DECIMAL(18,2))
                                                                          AS medicare_reimbursement_per_beneficiary_amt,
            CAST(SUM(u.total_beneficiary_responsibility_amt) AS DECIMAL(18,2))
                                                                          AS total_beneficiary_responsibility_amt,

            SUM(u.inpatient_claim_count)                                  AS inpatient_claim_count,
            SUM(u.inpatient_length_of_stay_days)                          AS inpatient_length_of_stay_days,
            SUM(u.outpatient_claim_count)                                 AS outpatient_claim_count,
            CAST(SUM(u.inpatient_claim_payment_amt) AS DECIMAL(18,2))     AS inpatient_claim_payment_amt,
            CAST(SUM(u.outpatient_claim_payment_amt) AS DECIMAL(18,2))    AS outpatient_claim_payment_amt,
            CAST(SUM(u.inpatient_claim_count) * 1000.0 / COUNT(*) AS DECIMAL(18,2))
                                                                          AS inpatient_claims_per_1000,
            CAST(SUM(u.outpatient_claim_count) * 1000.0 / COUNT(*) AS DECIMAL(18,2))
                                                                          AS outpatient_claims_per_1000,

            @load_ts                                                      AS _gold_load_ts
        FROM gold.fact_beneficiary_annual_utilization__stage AS u
        GROUP BY u.summary_year, u.state_code, u.demographic_key;

        /* -----------------------------------------------------------------------------
           dim_year, dim_state, dim_provider
              Built from the staged facts, so every key used by a fact is present.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.dim_year__stage
        AS
        SELECT
            ISNULL(y.calendar_year, 0)   AS calendar_year,
            @load_ts                     AS _gold_load_ts
        FROM (
            SELECT summary_year AS calendar_year FROM gold.fact_beneficiary_annual_utilization__stage
            UNION
            SELECT claim_year                    FROM gold.fact_provider_annual_summary__stage
        ) AS y;

        CREATE TABLE gold.dim_state__stage
        AS
        SELECT
            ISNULL(s.state_code, 'Unknown')  AS state_code,
            @load_ts                         AS _gold_load_ts
        FROM (
            SELECT DISTINCT state_code FROM gold.fact_beneficiary_annual_utilization__stage
        ) AS s;

        CREATE TABLE gold.dim_provider__stage
        AS
        SELECT
            ISNULL(p.provider_number, '')                                         AS provider_number,
            MIN(p.claim_year)                                                     AS first_claim_year,
            MAX(p.claim_year)                                                     AS last_claim_year,
            MAX(CASE WHEN p.claim_type = 'Inpatient'  THEN 1 ELSE 0 END)          AS has_inpatient_claims,
            MAX(CASE WHEN p.claim_type = 'Outpatient' THEN 1 ELSE 0 END)          AS has_outpatient_claims,
            @load_ts                                                              AS _gold_load_ts
        FROM gold.fact_provider_annual_summary__stage AS p
        GROUP BY p.provider_number;

        /* -----------------------------------------------------------------------------
           Checks on the staged data. Any failure stops the load before the swap.
           ----------------------------------------------------------------------------- */
        SELECT @silver_rows = COUNT_BIG(*) FROM [LH_ADX_Mirror].[silver].[beneficiary_summary];

        SELECT @bau_rows = COUNT_BIG(*),
               @bau_dups = COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(beneficiary_id, '|', summary_year))
        FROM gold.fact_beneficiary_annual_utilization__stage;

        SELECT @pas_rows = COUNT_BIG(*),
               @pas_dups = COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(provider_number, '|', claim_year, '|', claim_type))
        FROM gold.fact_provider_annual_summary__stage;

        SELECT @phs_rows  = COUNT_BIG(*),
               @phs_dups  = COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(summary_year, '|', state_code, '|', demographic_key)),
               @phs_benes = ISNULL(SUM(CAST(beneficiary_count AS BIGINT)), 0)
        FROM gold.fact_population_health_summary__stage;

        SELECT @dim_year_rows  = COUNT_BIG(*) FROM gold.dim_year__stage;
        SELECT @dim_state_rows = COUNT_BIG(*) FROM gold.dim_state__stage;
        SELECT @dim_demo_rows  = COUNT_BIG(*) FROM gold.dim_demographic__stage;
        SELECT @dim_bene_rows  = COUNT_BIG(*) FROM gold.dim_beneficiary__stage;
        SELECT @dim_prov_rows  = COUNT_BIG(*) FROM gold.dim_provider__stage;
        SELECT @dim_ctype_rows = COUNT_BIG(*) FROM gold.dim_claim_type__stage;

        SELECT @dim_dups =
              (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT calendar_year)   FROM gold.dim_year__stage)
            + (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT state_code)      FROM gold.dim_state__stage)
            + (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT demographic_key) FROM gold.dim_demographic__stage)
            + (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT beneficiary_id)  FROM gold.dim_beneficiary__stage)
            + (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT provider_number) FROM gold.dim_provider__stage)
            + (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT claim_type)      FROM gold.dim_claim_type__stage);

        SELECT @orph_bene =
              (SELECT COUNT_BIG(*) FROM gold.fact_beneficiary_annual_utilization__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_beneficiary__stage AS d WHERE d.beneficiary_id = f.beneficiary_id));

        SELECT @orph_year =
              (SELECT COUNT_BIG(*) FROM gold.fact_beneficiary_annual_utilization__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_year__stage AS d WHERE d.calendar_year = f.summary_year))
            + (SELECT COUNT_BIG(*) FROM gold.fact_provider_annual_summary__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_year__stage AS d WHERE d.calendar_year = f.claim_year))
            + (SELECT COUNT_BIG(*) FROM gold.fact_population_health_summary__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_year__stage AS d WHERE d.calendar_year = f.summary_year));

        SELECT @orph_state =
              (SELECT COUNT_BIG(*) FROM gold.fact_beneficiary_annual_utilization__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_state__stage AS d WHERE d.state_code = f.state_code))
            + (SELECT COUNT_BIG(*) FROM gold.fact_population_health_summary__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_state__stage AS d WHERE d.state_code = f.state_code));

        SELECT @orph_demo =
              (SELECT COUNT_BIG(*) FROM gold.fact_beneficiary_annual_utilization__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_demographic__stage AS d WHERE d.demographic_key = f.demographic_key))
            + (SELECT COUNT_BIG(*) FROM gold.fact_population_health_summary__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_demographic__stage AS d WHERE d.demographic_key = f.demographic_key));

        SELECT @orph_prov =
              (SELECT COUNT_BIG(*) FROM gold.fact_provider_annual_summary__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_provider__stage AS d WHERE d.provider_number = f.provider_number));

        SELECT @orph_ctype =
              (SELECT COUNT_BIG(*) FROM gold.fact_provider_annual_summary__stage AS f
               WHERE NOT EXISTS (SELECT 1 FROM gold.dim_claim_type__stage AS d WHERE d.claim_type = f.claim_type));

        IF @silver_rows = 0 OR @pas_rows = 0
            THROW 50001, 'Gold load aborted: silver source returned no rows (check the LH_ADX_Mirror shortcuts and SQL endpoint sync).', 1;

        IF @bau_dups > 0 OR @pas_dups > 0 OR @phs_dups > 0 OR @dim_dups > 0
        BEGIN
            SET @msg = CONCAT(N'Gold load aborted: duplicate keys found. fact_beneficiary_annual_utilization=', @bau_dups,
                              N', fact_provider_annual_summary=', @pas_dups,
                              N', fact_population_health_summary=', @phs_dups,
                              N', dimensions=', @dim_dups, N'.');
            THROW 50002, @msg, 1;
        END;

        IF @bau_rows <> @silver_rows OR @phs_benes <> @bau_rows
        BEGIN
            SET @msg = CONCAT(N'Gold load aborted: beneficiary counts do not reconcile. silver=', @silver_rows,
                              N', fact_beneficiary_annual_utilization=', @bau_rows,
                              N', fact_population_health_summary=', @phs_benes, N'.');
            THROW 50003, @msg, 1;
        END;

        IF @orph_bene + @orph_year + @orph_state + @orph_demo + @orph_prov + @orph_ctype > 0
        BEGIN
            SET @msg = CONCAT(N'Gold load aborted: fact rows without a matching dimension row. beneficiary=', @orph_bene,
                              N', year=', @orph_year,
                              N', state=', @orph_state,
                              N', demographic=', @orph_demo,
                              N', provider=', @orph_prov,
                              N', claim_type=', @orph_ctype, N'.');
            THROW 50004, @msg, 1;
        END;

        /* -----------------------------------------------------------------------------
           Swap stage -> gold and add keys, in a single short transaction.
           Facts are dropped before dimensions because their foreign keys reference
           the dimensions.
           ----------------------------------------------------------------------------- */
        BEGIN TRANSACTION;

            DROP TABLE IF EXISTS gold.fact_beneficiary_annual_utilization;
            DROP TABLE IF EXISTS gold.fact_provider_annual_summary;
            DROP TABLE IF EXISTS gold.fact_population_health_summary;

            DROP TABLE IF EXISTS gold.beneficiary_annual_utilization;
            DROP TABLE IF EXISTS gold.provider_annual_summary;
            DROP TABLE IF EXISTS gold.population_health_summary;

            DROP TABLE IF EXISTS gold.dim_year;
            DROP TABLE IF EXISTS gold.dim_state;
            DROP TABLE IF EXISTS gold.dim_demographic;
            DROP TABLE IF EXISTS gold.dim_beneficiary;
            DROP TABLE IF EXISTS gold.dim_provider;
            DROP TABLE IF EXISTS gold.dim_claim_type;

            EXEC sp_rename 'gold.dim_year__stage',                             'dim_year';
            EXEC sp_rename 'gold.dim_state__stage',                            'dim_state';
            EXEC sp_rename 'gold.dim_demographic__stage',                      'dim_demographic';
            EXEC sp_rename 'gold.dim_beneficiary__stage',                      'dim_beneficiary';
            EXEC sp_rename 'gold.dim_provider__stage',                         'dim_provider';
            EXEC sp_rename 'gold.dim_claim_type__stage',                       'dim_claim_type';
            EXEC sp_rename 'gold.fact_beneficiary_annual_utilization__stage',  'fact_beneficiary_annual_utilization';
            EXEC sp_rename 'gold.fact_provider_annual_summary__stage',         'fact_provider_annual_summary';
            EXEC sp_rename 'gold.fact_population_health_summary__stage',       'fact_population_health_summary';

            ALTER TABLE gold.dim_year        ADD CONSTRAINT pk_dim_year        PRIMARY KEY NONCLUSTERED (calendar_year)   NOT ENFORCED;
            ALTER TABLE gold.dim_state       ADD CONSTRAINT pk_dim_state       PRIMARY KEY NONCLUSTERED (state_code)      NOT ENFORCED;
            ALTER TABLE gold.dim_demographic ADD CONSTRAINT pk_dim_demographic PRIMARY KEY NONCLUSTERED (demographic_key) NOT ENFORCED;
            ALTER TABLE gold.dim_beneficiary ADD CONSTRAINT pk_dim_beneficiary PRIMARY KEY NONCLUSTERED (beneficiary_id)  NOT ENFORCED;
            ALTER TABLE gold.dim_provider    ADD CONSTRAINT pk_dim_provider    PRIMARY KEY NONCLUSTERED (provider_number) NOT ENFORCED;
            ALTER TABLE gold.dim_claim_type  ADD CONSTRAINT pk_dim_claim_type  PRIMARY KEY NONCLUSTERED (claim_type)      NOT ENFORCED;

            ALTER TABLE gold.fact_beneficiary_annual_utilization
                ADD CONSTRAINT pk_fact_beneficiary_annual_utilization
                PRIMARY KEY NONCLUSTERED (beneficiary_id, summary_year) NOT ENFORCED;
            ALTER TABLE gold.fact_provider_annual_summary
                ADD CONSTRAINT pk_fact_provider_annual_summary
                PRIMARY KEY NONCLUSTERED (provider_number, claim_year, claim_type) NOT ENFORCED;
            ALTER TABLE gold.fact_population_health_summary
                ADD CONSTRAINT pk_fact_population_health_summary
                PRIMARY KEY NONCLUSTERED (summary_year, state_code, demographic_key) NOT ENFORCED;

            ALTER TABLE gold.fact_beneficiary_annual_utilization
                ADD CONSTRAINT fk_fbau_dim_beneficiary FOREIGN KEY (beneficiary_id)
                REFERENCES gold.dim_beneficiary (beneficiary_id) NOT ENFORCED;
            ALTER TABLE gold.fact_beneficiary_annual_utilization
                ADD CONSTRAINT fk_fbau_dim_year FOREIGN KEY (summary_year)
                REFERENCES gold.dim_year (calendar_year) NOT ENFORCED;
            ALTER TABLE gold.fact_beneficiary_annual_utilization
                ADD CONSTRAINT fk_fbau_dim_state FOREIGN KEY (state_code)
                REFERENCES gold.dim_state (state_code) NOT ENFORCED;
            ALTER TABLE gold.fact_beneficiary_annual_utilization
                ADD CONSTRAINT fk_fbau_dim_demographic FOREIGN KEY (demographic_key)
                REFERENCES gold.dim_demographic (demographic_key) NOT ENFORCED;

            ALTER TABLE gold.fact_provider_annual_summary
                ADD CONSTRAINT fk_fpas_dim_provider FOREIGN KEY (provider_number)
                REFERENCES gold.dim_provider (provider_number) NOT ENFORCED;
            ALTER TABLE gold.fact_provider_annual_summary
                ADD CONSTRAINT fk_fpas_dim_year FOREIGN KEY (claim_year)
                REFERENCES gold.dim_year (calendar_year) NOT ENFORCED;
            ALTER TABLE gold.fact_provider_annual_summary
                ADD CONSTRAINT fk_fpas_dim_claim_type FOREIGN KEY (claim_type)
                REFERENCES gold.dim_claim_type (claim_type) NOT ENFORCED;

            ALTER TABLE gold.fact_population_health_summary
                ADD CONSTRAINT fk_fphs_dim_year FOREIGN KEY (summary_year)
                REFERENCES gold.dim_year (calendar_year) NOT ENFORCED;
            ALTER TABLE gold.fact_population_health_summary
                ADD CONSTRAINT fk_fphs_dim_state FOREIGN KEY (state_code)
                REFERENCES gold.dim_state (state_code) NOT ENFORCED;
            ALTER TABLE gold.fact_population_health_summary
                ADD CONSTRAINT fk_fphs_dim_demographic FOREIGN KEY (demographic_key)
                REFERENCES gold.dim_demographic (demographic_key) NOT ENFORCED;

        COMMIT TRANSACTION;

        SELECT 'gold.dim_year' AS table_name, @dim_year_rows AS row_count, @load_ts AS load_ts
        UNION ALL SELECT 'gold.dim_state',                           @dim_state_rows, @load_ts
        UNION ALL SELECT 'gold.dim_demographic',                     @dim_demo_rows,  @load_ts
        UNION ALL SELECT 'gold.dim_beneficiary',                     @dim_bene_rows,  @load_ts
        UNION ALL SELECT 'gold.dim_provider',                        @dim_prov_rows,  @load_ts
        UNION ALL SELECT 'gold.dim_claim_type',                      @dim_ctype_rows, @load_ts
        UNION ALL SELECT 'gold.fact_beneficiary_annual_utilization', @bau_rows,       @load_ts
        UNION ALL SELECT 'gold.fact_provider_annual_summary',        @pas_rows,       @load_ts
        UNION ALL SELECT 'gold.fact_population_health_summary',      @phs_rows,       @load_ts;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DROP TABLE IF EXISTS gold.dim_year__stage;
        DROP TABLE IF EXISTS gold.dim_state__stage;
        DROP TABLE IF EXISTS gold.dim_demographic__stage;
        DROP TABLE IF EXISTS gold.dim_beneficiary__stage;
        DROP TABLE IF EXISTS gold.dim_provider__stage;
        DROP TABLE IF EXISTS gold.dim_claim_type__stage;
        DROP TABLE IF EXISTS gold.fact_beneficiary_annual_utilization__stage;
        DROP TABLE IF EXISTS gold.fact_provider_annual_summary__stage;
        DROP TABLE IF EXISTS gold.fact_population_health_summary__stage;

        THROW;
    END CATCH;
END;

GO