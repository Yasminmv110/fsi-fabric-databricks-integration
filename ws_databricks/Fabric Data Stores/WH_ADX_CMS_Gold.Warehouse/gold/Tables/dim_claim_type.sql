CREATE TABLE [gold].[dim_claim_type] (
    [claim_type]             VARCHAR (10)  NOT NULL,
    [claim_type_description] VARCHAR (100) NULL,
    [_gold_load_ts]          DATETIME2 (6) NULL
);


GO

ALTER TABLE [gold].[dim_claim_type]
    ADD CONSTRAINT [pk_dim_claim_type] PRIMARY KEY NONCLUSTERED ([claim_type] ASC) NOT ENFORCED;


GO