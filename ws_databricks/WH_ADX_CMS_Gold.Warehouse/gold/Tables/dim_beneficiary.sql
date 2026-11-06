CREATE TABLE [gold].[dim_beneficiary] (
    [beneficiary_id]     VARCHAR (50)  NOT NULL,
    [birth_date]         DATE          NULL,
    [death_date]         DATE          NULL,
    [sex]                VARCHAR (10)  NOT NULL,
    [race]               VARCHAR (10)  NOT NULL,
    [latest_state_code]  VARCHAR (10)  NOT NULL,
    [latest_county_code] VARCHAR (10)  NULL,
    [first_summary_year] INT           NULL,
    [last_summary_year]  INT           NULL,
    [_gold_load_ts]      DATETIME2 (6) NULL
);


GO

ALTER TABLE [gold].[dim_beneficiary]
    ADD CONSTRAINT [pk_dim_beneficiary] PRIMARY KEY NONCLUSTERED ([beneficiary_id] ASC) NOT ENFORCED;


GO