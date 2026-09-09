/*
=============================================================================
  04_load_fact.sql
  -----------------
  Purpose:  Populate the fact_subscription_events table by joining silver-layer
            data with gold dimensions. This is the final step that brings
            together subscriptions, invoices, usage, and support data into
            a single queryable fact table.

  Logic:
  1. For each subscription, generate one row per active month (from start_date
     to end_date or current date).
  2. Classify each month as an event_type:
     - 'new'     : first month of the subscription
     - 'churn'   : last month (if status = churned)
     - 'active'  : any other month the subscription is active
  3. Aggregate invoices, usage, and support tickets to monthly level.
  4. Join to dimension tables to get surrogate keys.

  Why a CTE-based approach?
  - Generates the monthly spine for each subscription using a cross-join
    with dim_date, then left-joins measures onto it.
  - This is more readable and maintainable than procedural cursor-based
    approaches — and it's a single-pass INSERT-SELECT.

  Prerequisites:
  - All gold dimensions are loaded (03_load_dimensions.sql)
  - Silver layer is populated
=============================================================================
*/

USE NovaCRM_DWH;
GO

TRUNCATE TABLE gold.fact_subscription_events;
GO

-- Reset identity seed for clean fact load
DBCC CHECKIDENT ('gold.fact_subscription_events', RESEED, 0);
GO

-- ===========================================================================
-- Step 1: Build the monthly subscription spine
-- For each subscription, generate one row per month it was active.
-- Then join in measures and dimension keys.
-- ===========================================================================

;WITH 

-- Get the distinct months from our date dimension
monthly_periods AS (
    SELECT DISTINCT
        year,
        month_number,
        MIN(date_key) AS month_start_key,   -- First day of month (for date_key FK)
        MIN(full_date) AS month_start_date,
        MAX(full_date) AS month_end_date
    FROM gold.dim_date
    GROUP BY year, month_number
),

-- Cross-join subscriptions with months to create the spine
-- Then filter to only months where the subscription was active
subscription_months AS (
    SELECT
        s.subscription_id,
        s.account_id,
        s.plan_code,
        s.billing_cycle,
        s.mrr_amount,
        s.status AS sub_status,
        s.start_date,
        s.end_date,
        mp.year,
        mp.month_number,
        mp.month_start_key,
        mp.month_start_date,
        mp.month_end_date,
        
        -- Determine event type for this subscription-month
        CASE
            -- First month of the subscription
            WHEN YEAR(s.start_date) = mp.year 
                 AND MONTH(s.start_date) = mp.month_number
                THEN 'new'
            -- Last month if churned
            WHEN s.status = 'churned' 
                 AND s.end_date IS NOT NULL
                 AND YEAR(s.end_date) = mp.year 
                 AND MONTH(s.end_date) = mp.month_number
                THEN 'churn'
            -- Last month if expired
            WHEN s.status = 'expired'
                 AND s.end_date IS NOT NULL
                 AND YEAR(s.end_date) = mp.year 
                 AND MONTH(s.end_date) = mp.month_number
                THEN 'expired'
            -- Otherwise: active month
            ELSE 'active'
        END AS event_type
        
    FROM silver.subscriptions s
    CROSS JOIN monthly_periods mp
    WHERE 
        -- Subscription must have started on or before this month
        s.start_date <= mp.month_end_date
        -- And not ended before this month started (or still active)
        AND (s.end_date IS NULL OR s.end_date >= mp.month_start_date)
),

-- Aggregate invoices to monthly level per subscription
monthly_invoices AS (
    SELECT
        i.subscription_id,
        YEAR(i.invoice_date)  AS inv_year,
        MONTH(i.invoice_date) AS inv_month,
        SUM(i.amount)         AS total_invoice_amount,
        SUM(i.tax_amount)     AS total_tax_amount
    FROM silver.invoices i
    GROUP BY i.subscription_id, YEAR(i.invoice_date), MONTH(i.invoice_date)
),

-- Aggregate usage metrics to monthly level per subscription
monthly_usage AS (
    SELECT
        um.subscription_id,
        YEAR(um.metric_date)  AS usage_year,
        MONTH(um.metric_date) AS usage_month,
        SUM(um.api_calls)     AS total_api_calls,
        AVG(um.storage_gb)    AS avg_storage_gb,
        AVG(um.active_users)  AS avg_active_users
    FROM silver.usage_metrics um
    GROUP BY um.subscription_id, YEAR(um.metric_date), MONTH(um.metric_date)
),

-- Aggregate support tickets to monthly level per account
monthly_support AS (
    SELECT
        t.account_id,
        YEAR(t.created_date)  AS ticket_year,
        MONTH(t.created_date) AS ticket_month,
        COUNT(*)              AS tickets_opened,
        SUM(CASE WHEN t.status IN ('resolved', 'closed') THEN 1 ELSE 0 END) AS tickets_resolved,
        AVG(CAST(t.satisfaction AS DECIMAL(3,1))) AS avg_satisfaction
    FROM silver.support_tickets t
    GROUP BY t.account_id, YEAR(t.created_date), MONTH(t.created_date)
)

-- ===========================================================================
-- Step 2: Final INSERT — join everything together with dimension keys
-- ===========================================================================
INSERT INTO gold.fact_subscription_events (
    customer_key, plan_key, date_key, event_type,
    mrr_amount, mrr_change, invoice_amount, tax_amount,
    api_calls_monthly, storage_gb_avg, active_users_avg,
    support_tickets_opened, support_tickets_resolved, avg_satisfaction
)
SELECT
    -- Dimension keys (surrogate)
    dc.customer_key,
    dp.plan_key,
    sm.month_start_key AS date_key,
    
    -- Event classification
    sm.event_type,
    
    -- Revenue measures
    sm.mrr_amount,
    0 AS mrr_change,  -- Calculated in a post-processing step (see below)
    ISNULL(mi.total_invoice_amount, 0)  AS invoice_amount,
    ISNULL(mi.total_tax_amount, 0)      AS tax_amount,
    
    -- Usage measures (monthly aggregates)
    ISNULL(mu.total_api_calls, 0)       AS api_calls_monthly,
    ISNULL(mu.avg_storage_gb, 0)        AS storage_gb_avg,
    ISNULL(CAST(mu.avg_active_users AS INT), 0) AS active_users_avg,
    
    -- Support measures
    ISNULL(ms.tickets_opened, 0)        AS support_tickets_opened,
    ISNULL(ms.tickets_resolved, 0)      AS support_tickets_resolved,
    ms.avg_satisfaction

FROM subscription_months sm

-- Join to dim_customer (current version)
INNER JOIN gold.dim_customer dc
    ON sm.account_id = dc.account_id AND dc.is_current = 1

-- Join to dim_plan (current version)
INNER JOIN gold.dim_plan dp
    ON sm.plan_code = dp.plan_code 
    AND sm.billing_cycle = dp.billing_cycle
    AND dp.is_current = 1

-- Left join monthly aggregates (not every sub has invoices/usage every month)
LEFT JOIN monthly_invoices mi
    ON sm.subscription_id = mi.subscription_id
    AND sm.year = mi.inv_year
    AND sm.month_number = mi.inv_month

LEFT JOIN monthly_usage mu
    ON sm.subscription_id = mu.subscription_id
    AND sm.year = mu.usage_year
    AND sm.month_number = mu.usage_month

LEFT JOIN monthly_support ms
    ON sm.account_id = ms.account_id
    AND sm.year = ms.ticket_year
    AND sm.month_number = ms.ticket_month;
GO

PRINT '>> Loaded gold.fact_subscription_events: ' + CAST((SELECT COUNT(*) FROM gold.fact_subscription_events) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- Step 3: Post-processing — Calculate mrr_change (delta vs. previous month)
-- Using LAG() window function to compare each subscription's MRR with
-- its previous month. This enables net new MRR / churn MRR reporting.
-- ===========================================================================
;WITH mrr_deltas AS (
    SELECT
        f.event_id,
        f.mrr_amount - ISNULL(
            LAG(f.mrr_amount) OVER (
                PARTITION BY dc.account_id 
                ORDER BY f.date_key
            ), 0
        ) AS calculated_mrr_change
    FROM gold.fact_subscription_events f
    INNER JOIN gold.dim_customer dc ON f.customer_key = dc.customer_key
)
UPDATE f
SET f.mrr_change = d.calculated_mrr_change
FROM gold.fact_subscription_events f
INNER JOIN mrr_deltas d ON f.event_id = d.event_id;
GO

PRINT '>> Updated mrr_change for all fact rows.';
GO

-- ===========================================================================
-- Verification: row counts and sample data
-- ===========================================================================
PRINT '>> Fact table load complete.';

SELECT 
    'Total fact rows' AS metric, 
    COUNT(*) AS value 
FROM gold.fact_subscription_events
UNION ALL
SELECT 
    'Distinct customers', 
    COUNT(DISTINCT customer_key) 
FROM gold.fact_subscription_events
UNION ALL
SELECT 
    'Distinct months', 
    COUNT(DISTINCT date_key) 
FROM gold.fact_subscription_events
UNION ALL
SELECT 
    'Event types', 
    COUNT(DISTINCT event_type) 
FROM gold.fact_subscription_events;
GO

-- Event type distribution
SELECT 
    event_type,
    COUNT(*) AS event_count,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,1)) AS pct
FROM gold.fact_subscription_events
GROUP BY event_type
ORDER BY event_count DESC;
GO
