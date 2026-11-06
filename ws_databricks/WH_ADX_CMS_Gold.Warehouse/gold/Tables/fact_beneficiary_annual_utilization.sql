CREATE TABLE [gold].[fact_beneficiary_annual_utilization] (
    [beneficiary_id]                        VARCHAR (50)    NOT NULL,
    [summary_year]                          INT             NOT NULL,
    [state_code]                            VARCHAR (10)    NOT NULL,
    [demographic_key]                       INT             NOT NULL,
    [county_code]                           VARCHAR (10)    NULL,
    [age_at_year_end]                       INT             NULL,
    [is_deceased]                           INT             NULL,
    [has_esrd]                              INT             NULL,
    [part_a_coverage_months]                INT             NULL,
    [part_b_coverage_months]                INT             NULL,
    [hmo_coverage_months]                   INT             NULL,
    [part_d_coverage_months]                INT             NULL,
    [has_alzheimers]                        INT             NULL,
    [has_heart_failure]                     INT             NULL,
    [has_chronic_kidney_disease]            INT             NULL,
    [has_cancer]                            INT             NULL,
    [has_copd]                              INT             NULL,
    [has_depression]                        INT             NULL,
    [has_diabetes]                          INT             NULL,
    [has_ischemic_heart_disease]            INT             NULL,
    [has_osteoporosis]                      INT             NULL,
    [has_rheumatoid_osteo_arthritis]        INT             NULL,
    [has_stroke_tia]                        INT             NULL,
    [chronic_condition_count]               INT             NULL,
    [inpatient_medicare_reimbursement_amt]  DECIMAL (18, 2) NULL,
    [outpatient_medicare_reimbursement_amt] DECIMAL (18, 2) NULL,
    [carrier_medicare_reimbursement_amt]    DECIMAL (18, 2) NULL,
    [total_medicare_reimbursement_amt]      DECIMAL (18, 2) NULL,
    [total_beneficiary_responsibility_amt]  DECIMAL (18, 2) NULL,
    [inpatient_claim_count]                 INT             NOT NULL,
    [inpatient_length_of_stay_days]         INT             NOT NULL,
    [inpatient_utilization_days]            INT             NOT NULL,
    [inpatient_claim_payment_amt]           DECIMAL (18, 2) NULL,
    [inpatient_cost_share_amt]              DECIMAL (18, 2) NULL,
    [outpatient_claim_count]                INT             NOT NULL,
    [outpatient_visit_days]                 INT             NOT NULL,
    [outpatient_claim_payment_amt]          DECIMAL (18, 2) NULL,
    [outpatient_cost_share_amt]             DECIMAL (18, 2) NULL,
    [total_claim_payment_amt]               DECIMAL (18, 2) NULL,
    [_gold_load_ts]                         DATETIME2 (6)   NULL
);


GO

ALTER TABLE [gold].[fact_beneficiary_annual_utilization]
    ADD CONSTRAINT [fk_fbau_dim_beneficiary] FOREIGN KEY ([beneficiary_id]) REFERENCES [gold].[dim_beneficiary] ([beneficiary_id]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_beneficiary_annual_utilization]
    ADD CONSTRAINT [fk_fbau_dim_demographic] FOREIGN KEY ([demographic_key]) REFERENCES [gold].[dim_demographic] ([demographic_key]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_beneficiary_annual_utilization]
    ADD CONSTRAINT [fk_fbau_dim_state] FOREIGN KEY ([state_code]) REFERENCES [gold].[dim_state] ([state_code]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_beneficiary_annual_utilization]
    ADD CONSTRAINT [fk_fbau_dim_year] FOREIGN KEY ([summary_year]) REFERENCES [gold].[dim_year] ([calendar_year]) NOT ENFORCED;


GO

ALTER TABLE [gold].[fact_beneficiary_annual_utilization]
    ADD CONSTRAINT [pk_fact_beneficiary_annual_utilization] PRIMARY KEY NONCLUSTERED ([beneficiary_id] ASC, [summary_year] ASC) NOT ENFORCED;


GO