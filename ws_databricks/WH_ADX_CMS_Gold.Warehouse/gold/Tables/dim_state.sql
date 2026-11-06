CREATE TABLE [gold].[dim_state] (
    [state_code]    VARCHAR (10)  NOT NULL,
    [_gold_load_ts] DATETIME2 (6) NULL
);


GO

ALTER TABLE [gold].[dim_state]
    ADD CONSTRAINT [pk_dim_state] PRIMARY KEY NONCLUSTERED ([state_code] ASC) NOT ENFORCED;


GO