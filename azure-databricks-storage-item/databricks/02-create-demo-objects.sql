-- =============================================================================
-- Step 6: Create Unity Catalog objects whose data lands in OneLake
-- -----------------------------------------------------------------------------
-- Run on serverless compute or Databricks Runtime 18.1+.
-- Replace <ABFSS_PATH> with the external location URL (or a sub-path of it).
-- All data below is synthetic.
-- =============================================================================

-- 1. Catalog that uses the Fabric storage item as managed storage
CREATE CATALOG IF NOT EXISTS insurance_onelake
  MANAGED LOCATION '<ABFSS_PATH>'
  COMMENT 'Demo catalog - managed storage is a Fabric Azure Databricks Storage item';

CREATE SCHEMA IF NOT EXISTS insurance_onelake.claims;

-- 2. Managed Delta tables
CREATE TABLE IF NOT EXISTS insurance_onelake.claims.policies (
  policy_id     STRING,
  customer_name STRING,
  product       STRING,
  annual_premium DECIMAL(10,2),
  start_date    DATE
);

INSERT INTO insurance_onelake.claims.policies VALUES
  ('AUTO-10001', 'Sample Customer A', 'Auto', 1250.00, DATE'2026-01-15'),
  ('HOME-20002', 'Sample Customer B', 'Home', 1890.50, DATE'2026-03-01'),
  ('LIFE-30003', 'Sample Customer C', 'Life',  640.00, DATE'2026-05-20');

CREATE TABLE IF NOT EXISTS insurance_onelake.claims.claims (
  claim_id   STRING,
  policy_id  STRING,
  claim_date DATE,
  amount     DECIMAL(12,2),
  status     STRING
);

INSERT INTO insurance_onelake.claims.claims VALUES
  ('CLM-0001', 'AUTO-10001', DATE'2026-06-02', 4200.00, 'Open'),
  ('CLM-0002', 'HOME-20002', DATE'2026-07-18', 12850.00, 'In review'),
  ('CLM-0003', 'AUTO-10001', DATE'2026-09-09',  980.00, 'Closed');

-- 3. Managed volume for unstructured files (claim photos, PDFs)
CREATE VOLUME IF NOT EXISTS insurance_onelake.claims.insurance
  COMMENT 'Claim documents - stored in OneLake';

-- 4. Verify the data is physically in OneLake
DESCRIBE CATALOG EXTENDED insurance_onelake;            -- Storage Root should be the abfss://...onelake path
DESCRIBE DETAIL insurance_onelake.claims.policies;      -- location should start with abfss://<WorkspaceID>@onelake...

SELECT p.product, COUNT(c.claim_id) AS claims, SUM(c.amount) AS total_claimed
FROM insurance_onelake.claims.policies p
LEFT JOIN insurance_onelake.claims.claims c ON c.policy_id = p.policy_id
GROUP BY p.product;

-- 5. ONLY if Fabric Spark (notebooks / Spark job definitions) must read these
--    tables through a mirrored Azure Databricks catalog: turn off catalog commits.
--    This also turns off features that depend on catalog commits for the table.
-- ALTER TABLE insurance_onelake.claims.policies DROP FEATURE 'catalogManaged';
-- ALTER TABLE insurance_onelake.claims.claims   DROP FEATURE 'catalogManaged';
