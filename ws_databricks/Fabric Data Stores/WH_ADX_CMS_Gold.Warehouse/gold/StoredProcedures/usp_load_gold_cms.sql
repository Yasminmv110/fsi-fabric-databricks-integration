/* =====================================================================================
   CMS DE-SynPUF: Silver -> Gold load procedure
   Target : Fabric Data Warehouse  [WH_ADX_CMS_Gold]   (run this script in that warehouse)
   Source : Lakehouse SQL endpoint [LH_ADX_Mirror].[silver] (shortcuts to the Databricks
            silver Delta tables built by bronze_to_silver_cms.py)

     [LH_ADX_Mirror].[silver].[beneficiary_summary]  grain: beneficiary_id + summary_year
     [LH_ADX_Mirror].[silver].[inpatient_claims]     grain: claim_id + claim_segment
     [LH_ADX_Mirror].[silver].[outpatient_claims]    grain: claim_id + claim_segment

   Gold tables created or replaced:
     gold.beneficiary_annual_utilization  grain: beneficiary_id + summary_year
     gold.provider_annual_summary         grain: provider_number + claim_year + claim_type
     gold.population_health_summary       grain: summary_year + state_code + sex + race + age_band

   Deploy : run this whole file once. It is a single CREATE OR ALTER batch, so it needs
            no GO separators and can be run again safely.
   Run    : EXEC dbo.usp_load_gold_cms;

   Idempotency and safety
   * Each run rebuilds every gold table in full from silver. Running it again with the
     same silver data gives the same gold data.
   * The new data is built into gold.*__stage tables first. While that happens, users
     still read the current gold tables.
   * Checks run on the staged data: source not empty, no duplicate keys, and row counts
     that reconcile. If any check fails, the procedure stops and the gold tables are
     not changed.
   * All three tables are swapped in one short transaction (DROP, then sp_rename). Users
     see either the old set or the new set, never a mix.
   * Leftover stage tables from a failed run are dropped at the start and in CATCH.
   * Don't run two loads at the same time, because they share the stage table names.

   Fabric notes
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
CREATE   PROCEDURE gold.usp_load_gold_cms
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @load_ts        DATETIME2(6) = SYSUTCDATETIME();
    DECLARE @silver_rows    BIGINT;
    DECLARE @bau_rows       BIGINT;
    DECLARE @bau_dups       BIGINT;
    DECLARE @pas_rows       BIGINT;
    DECLARE @pas_dups       BIGINT;
    DECLARE @phs_rows       BIGINT;
    DECLARE @phs_dups       BIGINT;
    DECLARE @phs_benes      BIGINT;
    DECLARE @msg            NVARCHAR(2048);

    BEGIN TRY
        IF SCHEMA_ID(N'gold') IS NULL
            EXEC (N'CREATE SCHEMA gold');

        DROP TABLE IF EXISTS gold.beneficiary_annual_utilization__stage;
        DROP TABLE IF EXISTS gold.provider_annual_summary__stage;
        DROP TABLE IF EXISTS gold.population_health_summary__stage;

        /* -----------------------------------------------------------------------------
           1. beneficiary_annual_utilization
              One row per beneficiary per summary year. It has demographics, chronic
              conditions, annual reimbursement from the summary file, and that year's
              inpatient and outpatient claim totals. Beneficiaries with no claims get 0.
              Claims only count when they match a beneficiary-year in the summary file.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.beneficiary_annual_utilization__stage
        AS
        SELECT
            CAST(b.beneficiary_id AS VARCHAR(50))                             AS beneficiary_id,
            b.summary_year,
            b.birth_date,
            b.death_date,
            CAST(b.sex AS VARCHAR(10))                                        AS sex,
            CAST(b.race AS VARCHAR(10))                                       AS race,
            CAST(b.state_code AS VARCHAR(10))                                 AS state_code,
            CAST(b.county_code AS VARCHAR(10))                                AS county_code,
            b.age_at_year_end,
            CAST(CASE
                    WHEN b.age_at_year_end IS NULL THEN 'Unknown'
                    WHEN b.age_at_year_end < 65    THEN 'Under 65'
                    WHEN b.age_at_year_end < 75    THEN '65-74'
                    WHEN b.age_at_year_end < 85    THEN '75-84'
                    ELSE '85+'
                 END AS VARCHAR(10))                                          AS age_band,
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
           2. provider_annual_summary
              One row per provider, claim year, and claim type (Inpatient or
              Outpatient). Claims without a provider number or a valid from-date
              are left out.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.provider_annual_summary__stage
        AS
        SELECT
            c.provider_number,
            c.claim_year,
            c.claim_type,
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
           3. population_health_summary
              One row per year, state, sex, race, and age band. It is built from the
              staged beneficiary table, so all three gold tables come from the same
              snapshot. COALESCE is used instead of ISNULL because ISNULL returns the
              first argument's type, which would cut 'Unknown' to fit a short column.
           ----------------------------------------------------------------------------- */
        CREATE TABLE gold.population_health_summary__stage
        AS
        SELECT
            u.summary_year,
            u.state_code,
            u.sex,
            u.race,
            u.age_band,

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
        FROM (
            SELECT
                summary_year,
                CAST(COALESCE(state_code, 'Unknown') AS VARCHAR(10)) AS state_code,
                CAST(COALESCE(sex, 'Unknown') AS VARCHAR(10))        AS sex,
                CAST(COALESCE(race, 'Unknown') AS VARCHAR(10))       AS race,
                age_band,
                age_at_year_end,
                chronic_condition_count,
                is_deceased,
                has_esrd,
                has_alzheimers,
                has_heart_failure,
                has_chronic_kidney_disease,
                has_cancer,
                has_copd,
                has_depression,
                has_diabetes,
                has_ischemic_heart_disease,
                has_osteoporosis,
                has_rheumatoid_osteo_arthritis,
                has_stroke_tia,
                total_medicare_reimbursement_amt,
                total_beneficiary_responsibility_amt,
                inpatient_claim_count,
                inpatient_length_of_stay_days,
                outpatient_claim_count,
                inpatient_claim_payment_amt,
                outpatient_claim_payment_amt
            FROM gold.beneficiary_annual_utilization__stage
        ) AS u
        GROUP BY u.summary_year, u.state_code, u.sex, u.race, u.age_band;

        /* -----------------------------------------------------------------------------
           Checks on the staged data. Any failure stops the load before the swap.
           ----------------------------------------------------------------------------- */
        SELECT @silver_rows = COUNT_BIG(*) FROM [LH_ADX_Mirror].[silver].[beneficiary_summary];

        SELECT @bau_rows = COUNT_BIG(*),
               @bau_dups = COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(beneficiary_id, '|', summary_year))
        FROM gold.beneficiary_annual_utilization__stage;

        SELECT @pas_rows = COUNT_BIG(*),
               @pas_dups = COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(provider_number, '|', claim_year, '|', claim_type))
        FROM gold.provider_annual_summary__stage;

        SELECT @phs_rows  = COUNT_BIG(*),
               @phs_dups  = COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(summary_year, '|', state_code, '|', sex, '|', race, '|', age_band)),
               @phs_benes = ISNULL(SUM(CAST(beneficiary_count AS BIGINT)), 0)
        FROM gold.population_health_summary__stage;

        IF @silver_rows = 0 OR @pas_rows = 0
            THROW 50001, 'Gold load aborted: silver source returned no rows (check the LH_ADX_Mirror shortcuts and SQL endpoint sync).', 1;

        IF @bau_dups > 0 OR @pas_dups > 0 OR @phs_dups > 0
        BEGIN
            SET @msg = CONCAT(N'Gold load aborted: duplicate keys found. beneficiary_annual_utilization=', @bau_dups,
                              N', provider_annual_summary=', @pas_dups,
                              N', population_health_summary=', @phs_dups, N'.');
            THROW 50002, @msg, 1;
        END;

        IF @bau_rows <> @silver_rows OR @phs_benes <> @bau_rows
        BEGIN
            SET @msg = CONCAT(N'Gold load aborted: beneficiary counts do not reconcile. silver=', @silver_rows,
                              N', beneficiary_annual_utilization=', @bau_rows,
                              N', population_health_summary=', @phs_benes, N'.');
            THROW 50003, @msg, 1;
        END;

        /* -----------------------------------------------------------------------------
           Swap stage -> gold in a single short transaction.
           ----------------------------------------------------------------------------- */
        BEGIN TRANSACTION;

            DROP TABLE IF EXISTS gold.beneficiary_annual_utilization;
            DROP TABLE IF EXISTS gold.provider_annual_summary;
            DROP TABLE IF EXISTS gold.population_health_summary;

            EXEC sp_rename 'gold.beneficiary_annual_utilization__stage', 'beneficiary_annual_utilization';
            EXEC sp_rename 'gold.provider_annual_summary__stage',        'provider_annual_summary';
            EXEC sp_rename 'gold.population_health_summary__stage',      'population_health_summary';

        COMMIT TRANSACTION;

        SELECT 'gold.beneficiary_annual_utilization' AS table_name, @bau_rows AS row_count, @load_ts AS load_ts
        UNION ALL
        SELECT 'gold.provider_annual_summary',        @pas_rows, @load_ts
        UNION ALL
        SELECT 'gold.population_health_summary',      @phs_rows, @load_ts;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DROP TABLE IF EXISTS gold.beneficiary_annual_utilization__stage;
        DROP TABLE IF EXISTS gold.provider_annual_summary__stage;
        DROP TABLE IF EXISTS gold.population_health_summary__stage;

        THROW;
    END CATCH;
END;

GO