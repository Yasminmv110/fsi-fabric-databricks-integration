-- Run in WH_ADX_CMS_Gold after the reviewed star-schema load.
-- Read-only diagnostics; interpret every result using warehouse/README.md.

SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'gold'
  AND TABLE_NAME IN (
      'dim_year', 'dim_state', 'dim_demographic', 'dim_beneficiary',
      'dim_provider', 'dim_claim_type', 'fact_beneficiary_annual_utilization',
      'fact_provider_annual_summary', 'fact_population_health_summary'
  )
ORDER BY TABLE_NAME;

SELECT 'beneficiary' AS fact_name, COUNT_BIG(*) AS row_count,
       MIN(_gold_load_ts) AS earliest_load_utc, MAX(_gold_load_ts) AS latest_load_utc
FROM gold.fact_beneficiary_annual_utilization
UNION ALL
SELECT 'provider', COUNT_BIG(*), MIN(_gold_load_ts), MAX(_gold_load_ts)
FROM gold.fact_provider_annual_summary
UNION ALL
SELECT 'population', COUNT_BIG(*), MIN(_gold_load_ts), MAX(_gold_load_ts)
FROM gold.fact_population_health_summary;

SELECT 'beneficiary' AS fact_name, COUNT_BIG(*) AS duplicate_groups
FROM (
    SELECT beneficiary_id, summary_year
    FROM gold.fact_beneficiary_annual_utilization
    GROUP BY beneficiary_id, summary_year HAVING COUNT_BIG(*) > 1
) AS beneficiary_duplicates
UNION ALL
SELECT 'provider', COUNT_BIG(*)
FROM (
    SELECT provider_number, claim_year, claim_type
    FROM gold.fact_provider_annual_summary
    GROUP BY provider_number, claim_year, claim_type HAVING COUNT_BIG(*) > 1
) AS provider_duplicates
UNION ALL
SELECT 'population', COUNT_BIG(*)
FROM (
    SELECT summary_year, state_code, demographic_key
    FROM gold.fact_population_health_summary
    GROUP BY summary_year, state_code, demographic_key HAVING COUNT_BIG(*) > 1
) AS population_duplicates;

SELECT 'beneficiary_to_beneficiary' AS relationship, COUNT_BIG(*) AS orphan_rows
FROM gold.fact_beneficiary_annual_utilization AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_beneficiary AS d WHERE d.beneficiary_id = f.beneficiary_id)
UNION ALL
SELECT 'beneficiary_to_year', COUNT_BIG(*)
FROM gold.fact_beneficiary_annual_utilization AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_year AS d WHERE d.calendar_year = f.summary_year)
UNION ALL
SELECT 'beneficiary_to_state', COUNT_BIG(*)
FROM gold.fact_beneficiary_annual_utilization AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_state AS d WHERE d.state_code = f.state_code)
UNION ALL
SELECT 'beneficiary_to_demographic', COUNT_BIG(*)
FROM gold.fact_beneficiary_annual_utilization AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_demographic AS d WHERE d.demographic_key = f.demographic_key);

SELECT 'provider_to_provider' AS relationship, COUNT_BIG(*) AS orphan_rows
FROM gold.fact_provider_annual_summary AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_provider AS d WHERE d.provider_number = f.provider_number)
UNION ALL
SELECT 'provider_to_year', COUNT_BIG(*)
FROM gold.fact_provider_annual_summary AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_year AS d WHERE d.calendar_year = f.claim_year)
UNION ALL
SELECT 'provider_to_claim_type', COUNT_BIG(*)
FROM gold.fact_provider_annual_summary AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_claim_type AS d WHERE d.claim_type = f.claim_type)
UNION ALL
SELECT 'population_to_year', COUNT_BIG(*)
FROM gold.fact_population_health_summary AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_year AS d WHERE d.calendar_year = f.summary_year)
UNION ALL
SELECT 'population_to_state', COUNT_BIG(*)
FROM gold.fact_population_health_summary AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_state AS d WHERE d.state_code = f.state_code)
UNION ALL
SELECT 'population_to_demographic', COUNT_BIG(*)
FROM gold.fact_population_health_summary AS f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_demographic AS d WHERE d.demographic_key = f.demographic_key);

WITH beneficiary AS (
    SELECT summary_year, COUNT_BIG(*) AS observations,
           SUM(total_medicare_reimbursement_amt) AS reimbursement
    FROM gold.fact_beneficiary_annual_utilization GROUP BY summary_year
),
population AS (
    SELECT summary_year, SUM(CAST(beneficiary_count AS bigint)) AS observations,
           SUM(total_medicare_reimbursement_amt) AS reimbursement
    FROM gold.fact_population_health_summary GROUP BY summary_year
)
SELECT b.summary_year AS beneficiary_year, p.summary_year AS population_year,
       b.observations AS beneficiary_observations, p.observations AS population_observations,
       b.reimbursement AS beneficiary_reimbursement, p.reimbursement AS population_reimbursement
FROM beneficiary AS b
FULL OUTER JOIN population AS p ON b.summary_year = p.summary_year
WHERE b.summary_year IS NULL OR p.summary_year IS NULL
   OR b.observations <> p.observations
   OR b.reimbursement <> p.reimbursement
   OR (b.reimbursement IS NULL AND p.reimbursement IS NOT NULL)
   OR (b.reimbursement IS NOT NULL AND p.reimbursement IS NULL);

SELECT claim_year, claim_type,
       SUM(CAST(claim_count AS bigint)) AS claim_count,
       SUM(total_claim_payment_amt) AS claim_payment_usd
FROM gold.fact_provider_annual_summary
GROUP BY claim_year, claim_type
ORDER BY claim_year, claim_type;
