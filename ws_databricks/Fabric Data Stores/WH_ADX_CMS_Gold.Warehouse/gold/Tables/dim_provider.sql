CREATE TABLE [gold].[dim_provider] (
    [provider_number]       VARCHAR (50)  NOT NULL,
    [first_claim_year]      INT           NULL,
    [last_claim_year]       INT           NULL,
    [has_inpatient_claims]  INT           NULL,
    [has_outpatient_claims] INT           NULL,
    [_gold_load_ts]         DATETIME2 (6) NULL
);


GO

ALTER TABLE [gold].[dim_provider]
    ADD CONSTRAINT [pk_dim_provider] PRIMARY KEY NONCLUSTERED ([provider_number] ASC) NOT ENFORCED;


GO