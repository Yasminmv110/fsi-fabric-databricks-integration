CREATE TABLE [gold].[fact_population_health_summary] (
    [summary_year]                               INT             NOT NULL,
    [state_code]                                 VARCHAR (10)    NOT NULL,
    [demographic_key]                            INT             NOT NULL,
    [beneficiary_count]                          INT             NULL,
    [deceased_count]                             INT             NULL,
    [esrd_count]                                 INT             NULL,
    [avg_age]                                    DECIMAL (9, 2)  NULL,
    [avg_chronic_condition_count]                DECIMAL (9, 2)  NULL,
    [multi_chronic_3plus_count]                  INT             NULL,
    [alzheimers_count]                           INT             NULL,
    [heart_failure_count]                        INT             NULL,
    [chronic_kidney_disease_count]               INT             NULL,
    [cancer_count]                               INT             NULL,
    [copd_count]                                 INT             NULL,
    [depression_count]                           INT             NULL,
    [diabetes_count]                             INT             NULL,
    [ischemic_heart_disease_count]               INT             NULL,
    [osteoporosis_count]                         INT             NULL,
    [rheumatoid_osteo_arthritis_count]           INT             NULL,
    [stroke_tia_count]                           INT             NULL,
    [diabetes_prevalence_rate]                   DECIMAL (9, 4)  NULL,
    [heart_failure_prevalence_rate]              DECIMAL (9, 4)  NULL,
    [ischemic_heart_disease_prevalence_rate]     DECIMAL (9, 4)  NULL,
    [total_medicare_reimbursement_amt]           DECIMAL (18, 2) NULL,
    [medicare_reimbursement_per_beneficiary_amt] DECIMAL (18, 2) NULL,
    [total_beneficiary_responsibility_amt]       DECIMAL (18, 2) NULL,
    [inpatient_claim_count]                      INT             NULL,
    [inpatient_length_of_stay_days]              INT             NULL,
    [outpatient_claim_count]                     INT             NULL,
    [inpatient_claim_payment_amt]                DECIMAL (18, 2) NULL,
    [outpatient_claim_payment_amt]               DECIMAL (18, 2) NULL,
    [inpatient_claims_per_1000]                  DECIMAL (18, 2) NULL,
    [outpatient_claims_per_1000]                 DECIMAL (18, 2) NULL,
    [_gold_load_ts]                              DATETIME2 (6)   NULL
);


GO

ALTER TABLE [gold].[fact_population_health_summary]
    ADD CONSTRAINT [fk_fphs_dim_demographic] FOREIGN KEY ([demographic_key]) REFERENCES [gold].[dim_demographic] ([demographic_key]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_population_health_summary]
    ADD CONSTRAINT [fk_fphs_dim_state] FOREIGN KEY ([state_code]) REFERENCES [gold].[dim_state] ([state_code]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_population_health_summary]
    ADD CONSTRAINT [fk_fphs_dim_year] FOREIGN KEY ([summary_year]) REFERENCES [gold].[dim_year] ([calendar_year]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_population_health_summary]
    ADD CONSTRAINT [pk_fact_population_health_summary] PRIMARY KEY NONCLUSTERED ([summary_year] ASC, [state_code] ASC, [demographic_key] ASC) NOT ENFORCED;


GO