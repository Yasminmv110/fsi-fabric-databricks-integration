CREATE TABLE [gold].[dim_year] (
    [calendar_year] INT           NOT NULL,
    [_gold_load_ts] DATETIME2 (6) NULL
);


GO

ALTER TABLE [gold].[dim_year]
    ADD CONSTRAINT [pk_dim_year] PRIMARY KEY NONCLUSTERED ([calendar_year] ASC) NOT ENFORCED;


GO