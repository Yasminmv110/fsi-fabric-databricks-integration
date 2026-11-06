-- Fabric notebook source

-- METADATA ********************

-- META {
-- META   "kernel_info": {
-- META     "name": "synapse_pyspark"
-- META   },
-- META   "dependencies": {
-- META     "lakehouse": {
-- META       "default_lakehouse": "00000000-0000-0000-0000-66d8ce417af1",
-- META       "default_lakehouse_name": "LH_ADX_Onelake",
-- META       "default_lakehouse_workspace_id": "00000000-0000-0000-0000-4f0a9fa9337a",
-- META       "known_lakehouses": [
-- META         {
-- META           "id": "00000000-0000-0000-0000-66d8ce417af1"
-- META         }
-- META       ]
-- META     }
-- META   }
-- META }

-- CELL ********************

-- Welcome to your new notebook
-- Type here in the cell editor to add code!


-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

SELECT * FROM `bronze`.`insurance` LIMIT 1000

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }
