CREATE TABLE [gold].[fact_provider_annual_summary] (
    [provider_number]                  VARCHAR (50)    NOT NULL,
    [claim_year]                       INT             NOT NULL,
    [claim_type]                       VARCHAR (10)    NOT NULL,
    [claim_count]                      INT             NULL,
    [beneficiary_count]                INT             NULL,
    [total_claim_payment_amt]          DECIMAL (18, 2) NULL,
    [avg_claim_payment_amt]            DECIMAL (18, 2) NULL,
    [total_primary_payer_paid_amt]     DECIMAL (18, 2) NULL,
    [total_beneficiary_cost_share_amt] DECIMAL (18, 2) NULL,
    [avg_claim_duration_days]          DECIMAL (9, 2)  NULL,
    [total_length_of_stay_days]        INT             NULL,
    [avg_length_of_stay_days]          DECIMAL (9, 2)  NULL,
    [avg_diagnosis_code_count]         DECIMAL (9, 2)  NULL,
    [avg_procedure_code_count]         DECIMAL (9, 2)  NULL,
    [_gold_load_ts]                    DATETIME2 (6)   NULL
);


GO

ALTER TABLE [gold].[fact_provider_annual_summary]
    ADD CONSTRAINT [fk_fpas_dim_claim_type] FOREIGN KEY ([claim_type]) REFERENCES [gold].[dim_claim_type] ([claim_type]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_provider_annual_summary]
    ADD CONSTRAINT [fk_fpas_dim_provider] FOREIGN KEY ([provider_number]) REFERENCES [gold].[dim_provider] ([provider_number]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_provider_annual_summary]
    ADD CONSTRAINT [fk_fpas_dim_year] FOREIGN KEY ([claim_year]) REFERENCES [gold].[dim_year] ([calendar_year]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_provider_annual_summary]
    ADD CONSTRAINT [pk_fact_provider_annual_summary] PRIMARY KEY NONCLUSTERED ([provider_number] ASC, [claim_year] ASC, [claim_type] ASC) NOT ENFORCED;


GO