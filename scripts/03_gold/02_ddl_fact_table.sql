/*
=============================================================================
  02_ddl_fact_table.sql
  ----------------------
  Purpose:  Create the fact_subscription_events table — the central fact
            table in our gold-layer star schema.

  Grain:    One row per subscription per month, representing the subscription's
            state and associated metrics for that month.

  Why this grain?
  - Monthly is the natural billing cycle for SaaS — MRR is a monthly metric.
  - Aggregating to monthly level from daily usage keeps the fact table
    manageable (~2K subs × 36 months ≈ ~72K rows max) while preserving
    enough detail for cohort analysis and trend reporting.
  - The event_type column (new/renewal/upgrade/downgrade/churn) enables
    revenue movement analysis (a key SaaS metric).

  Measures:
  - mrr_amount: MRR at time of event
  - mrr_change: Delta vs. previous month (for growth/contraction analysis)
  - invoice_amount, tax_amount: actual billed amounts from invoices
  - api_calls_monthly, storage_gb_avg, active_users_avg: usage metrics
  - support_tickets_opened/resolved: operational metrics
  - avg_satisfaction: customer health indicator

  Prerequisites:
  - 03_gold/01_ddl_dim_tables.sql has been run
=============================================================================
*/

USE NovaCRM_DWH;
GO

IF OBJECT_ID('gold.fact_subscription_events', 'U') IS NOT NULL
    DROP TABLE gold.fact_subscription_events;
GO

CREATE TABLE gold.fact_subscription_events (
    -- Surrogate key for the fact row
    event_id                INT IDENTITY(1,1) PRIMARY KEY,
    
    -- Foreign keys to dimension tables (surrogate keys)
    customer_key            INT             NOT NULL,
    plan_key                INT             NOT NULL,
    date_key                INT             NOT NULL,
    
    -- Degenerate dimension: not worth a separate dim table
    event_type              NVARCHAR(20)    NOT NULL,  -- new, renewal, upgrade, downgrade, churn, active
    
    -- Measures: revenue
    mrr_amount              DECIMAL(10,2)   NOT NULL DEFAULT 0,
    mrr_change              DECIMAL(10,2)   NOT NULL DEFAULT 0,  -- Delta from previous month
    invoice_amount          DECIMAL(12,2)   NOT NULL DEFAULT 0,  -- Sum of invoices that month
    tax_amount              DECIMAL(10,2)   NOT NULL DEFAULT 0,
    
    -- Measures: usage (aggregated from daily to monthly)
    api_calls_monthly       INT             NOT NULL DEFAULT 0,
    storage_gb_avg          DECIMAL(10,2)   NOT NULL DEFAULT 0,
    active_users_avg        INT             NOT NULL DEFAULT 0,
    
    -- Measures: support (counts for the month)
    support_tickets_opened  INT             NOT NULL DEFAULT 0,
    support_tickets_resolved INT            NOT NULL DEFAULT 0,
    avg_satisfaction        DECIMAL(3,1)    NULL
);
GO

-- Indexes for common query patterns
-- These cover the most frequent WHERE/GROUP BY columns in reporting views
CREATE NONCLUSTERED INDEX IX_fact_sub_customer 
    ON gold.fact_subscription_events(customer_key);

CREATE NONCLUSTERED INDEX IX_fact_sub_plan 
    ON gold.fact_subscription_events(plan_key);

CREATE NONCLUSTERED INDEX IX_fact_sub_date 
    ON gold.fact_subscription_events(date_key);

CREATE NONCLUSTERED INDEX IX_fact_sub_event_type 
    ON gold.fact_subscription_events(event_type);
GO

PRINT '>> Created gold.fact_subscription_events';
GO
