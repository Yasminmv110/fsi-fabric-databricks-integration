-- =============================================================================
-- Step 5 (optional SQL route): OneLake external location
-- -----------------------------------------------------------------------------
-- The documented route is Catalog Explorer (README Step 5): Storage type = OneLake.
-- Use this SQL only if your workspace accepts it; otherwise use the UI.
--
-- Replace:
--   <ABFSS_PATH>          value printed by scripts/01-create-storage-item.ps1
--                         abfss://<WorkspaceID>@onelake.dfs.fabric.microsoft.com/<StorageItemID>/Files/
--   onelake_cred          the storage credential you created in Step 4
-- Requires: CREATE EXTERNAL LOCATION on the metastore and on the credential.
-- =============================================================================

CREATE EXTERNAL LOCATION IF NOT EXISTS onelake_dbx_storage
  URL '<ABFSS_PATH>'
  WITH (STORAGE CREDENTIAL onelake_cred)
  COMMENT 'Fabric Azure Databricks Storage item used as Unity Catalog managed storage';

-- Check it
DESCRIBE EXTERNAL LOCATION onelake_dbx_storage;
