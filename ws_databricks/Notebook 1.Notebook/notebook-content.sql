-- Fabric notebook source

-- METADATA ********************

-- META {
-- META   "kernel_info": {
-- META     "name": "synapse_pyspark"
-- META   },
-- META   "dependencies": {
-- META     "warehouse": {
-- META       "default_warehouse": "00000000-0000-0000-0000-14d6e11c1b98",
-- META       "known_warehouses": [
-- META         {
-- META           "id": "00000000-0000-0000-0000-14d6e11c1b98",
-- META           "type": "Lakewarehouse"
-- META         }
-- META       ]
-- META     }
-- META   }
-- META }

-- CELL ********************

-- MAGIC %%sql
-- MAGIC 
-- MAGIC CREATE OR REPLACE TABLE LH_ADX_Onelake.bronze.insurance_copy
-- MAGIC USING DELTA
-- MAGIC AS
-- MAGIC SELECT
-- MAGIC     PolicyNumber,
-- MAGIC     CustomerID,
-- MAGIC     Gender,
-- MAGIC     Age,
-- MAGIC     PolicyType,
-- MAGIC     PolicyStartDate,
-- MAGIC     PolicyEndDate,
-- MAGIC     PremiumAmount,
-- MAGIC     CoverageAmount,
-- MAGIC     ClaimNumber,
-- MAGIC     ClaimDate,
-- MAGIC     ClaimAmount,
-- MAGIC     ClaimStatus,
-- MAGIC     _rescued_data,
-- MAGIC     _source_file,
-- MAGIC     _ingest_ts
-- MAGIC FROM LH_ADX_Onelake.bronze.insurance;

-- METADATA ********************

-- META {
-- META   "language": "sql",
-- META   "language_group": "sqldatawarehouse"
-- META }
