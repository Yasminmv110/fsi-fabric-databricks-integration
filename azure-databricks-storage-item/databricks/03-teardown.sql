-- =============================================================================
-- Teardown (run BEFORE scripts/99-teardown.ps1)
-- Drops the demo catalog and its OneLake data, then the external location.
-- =============================================================================
DROP CATALOG IF EXISTS insurance_onelake CASCADE;
DROP EXTERNAL LOCATION IF EXISTS onelake_dbx_storage;
-- The storage credential can be kept for reuse, or dropped in Catalog Explorer.
