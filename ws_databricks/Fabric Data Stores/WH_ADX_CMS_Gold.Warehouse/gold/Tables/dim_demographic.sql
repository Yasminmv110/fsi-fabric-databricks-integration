CREATE TABLE [gold].[dim_demographic] (
    [demographic_key] INT           NOT NULL,
    [sex]             VARCHAR (10)  NOT NULL,
    [race]            VARCHAR (10)  NOT NULL,
    [age_band]        VARCHAR (10)  NOT NULL,
    [sex_sort]        INT           NULL,
    [race_sort]       INT           NULL,
    [age_band_sort]   INT           NULL,
    [_gold_load_ts]   DATETIME2 (6) NULL
);


GO

ALTER TABLE [gold].[dim_demographic]
    ADD CONSTRAINT [pk_dim_demographic] PRIMARY KEY NONCLUSTERED ([demographic_key] ASC) NOT ENFORCED;


GO