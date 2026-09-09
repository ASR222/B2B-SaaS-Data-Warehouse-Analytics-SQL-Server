/*
=============================================================================
  05_vw_growth_metrics.sql
  -------------------------
  Purpose:  Month-over-Month (MoM) and Year-over-Year (YoY) growth metrics
            plus Net Revenue Retention (NRR).
  
  Business questions answered:
  - What is our MoM and YoY revenue growth rate?
  - What is our Net Revenue Retention rate?
    (NRR > 100% means existing customers are spending MORE over time —
     the gold standard for SaaS health)
  - Are we growing faster from new customers or expansion of existing ones?
  
  Why this matters:
  - Growth rate and NRR are the first two metrics any investor or
    executive asks about. Deloitte consultants present these to C-suites.
  - LAG() window functions for time-series comparison are a frequently
    tested SQL skill in analytics interviews.
=============================================================================
*/

USE NovaCRM_DWH;
GO

IF OBJECT_ID('gold.vw_growth_metrics', 'V') IS NOT NULL
    DROP VIEW gold.vw_growth_metrics;
GO

CREATE VIEW gold.vw_growth_metrics AS
WITH monthly_totals AS (
    SELECT
        d.year,
        d.month_number,
        d.month_name,
        d.fiscal_quarter,
        
        -- Total MRR this month
        SUM(f.mrr_amount) AS total_mrr,
        
        -- Active customer count
        COUNT(DISTINCT f.customer_key) AS active_customers,
        
        -- Revenue components for NRR calculation
        SUM(CASE WHEN f.event_type = 'new'    THEN f.mrr_amount ELSE 0 END) AS new_mrr,
        SUM(CASE WHEN f.event_type = 'churn'  THEN f.mrr_amount ELSE 0 END) AS churned_mrr,
        SUM(CASE WHEN f.event_type = 'active' THEN f.mrr_amount ELSE 0 END) AS existing_mrr,
        
        -- Total invoiced revenue
        SUM(f.invoice_amount) AS total_revenue,
        
        -- Usage aggregates (for efficiency tracking)
        SUM(f.api_calls_monthly) AS total_api_calls,
        AVG(CAST(f.active_users_avg AS FLOAT)) AS avg_active_users
        
    FROM gold.fact_subscription_events f
    INNER JOIN gold.dim_date d ON f.date_key = d.date_key
    GROUP BY d.year, d.month_number, d.month_name, d.fiscal_quarter
)
SELECT
    year,
    month_number,
    month_name,
    fiscal_quarter,
    total_mrr,
    active_customers,
    new_mrr,
    churned_mrr,
    existing_mrr,
    total_revenue,
    total_api_calls,
    avg_active_users,
    
    -- =====================================================================
    -- MoM Growth: compare this month to previous month
    -- Uses LAG() to look back 1 row in chronological order
    -- =====================================================================
    LAG(total_mrr) OVER (ORDER BY year, month_number) AS prev_month_mrr,
    
    CASE 
        WHEN LAG(total_mrr) OVER (ORDER BY year, month_number) > 0
        THEN CAST(
            (total_mrr - LAG(total_mrr) OVER (ORDER BY year, month_number)) * 100.0 /
            LAG(total_mrr) OVER (ORDER BY year, month_number)
        AS DECIMAL(7,2))
        ELSE NULL
    END AS mom_growth_pct,
    
    -- =====================================================================
    -- YoY Growth: compare this month to same month last year
    -- Uses LAG with offset 12 (months)
    -- =====================================================================
    LAG(total_mrr, 12) OVER (ORDER BY year, month_number) AS prev_year_mrr,
    
    CASE 
        WHEN LAG(total_mrr, 12) OVER (ORDER BY year, month_number) > 0
        THEN CAST(
            (total_mrr - LAG(total_mrr, 12) OVER (ORDER BY year, month_number)) * 100.0 /
            LAG(total_mrr, 12) OVER (ORDER BY year, month_number)
        AS DECIMAL(7,2))
        ELSE NULL
    END AS yoy_growth_pct,
    
    -- =====================================================================
    -- Net Revenue Retention (NRR)
    -- Formula: (existing_mrr_this_month) / (total_mrr_last_month) * 100
    -- NRR > 100% = expansion revenue exceeds churn (healthy)
    -- NRR < 100% = churn exceeds expansion (concerning)
    -- =====================================================================
    CASE 
        WHEN LAG(total_mrr) OVER (ORDER BY year, month_number) > 0
        THEN CAST(
            (total_mrr - new_mrr) * 100.0 /
            LAG(total_mrr) OVER (ORDER BY year, month_number)
        AS DECIMAL(7,2))
        ELSE NULL
    END AS net_revenue_retention_pct,
    
    -- =====================================================================
    -- Customer growth metrics
    -- =====================================================================
    LAG(active_customers) OVER (ORDER BY year, month_number) AS prev_month_customers,
    
    active_customers - ISNULL(LAG(active_customers) OVER (ORDER BY year, month_number), 0) 
        AS net_customer_change,
    
    -- Revenue per API call (efficiency metric)
    CASE 
        WHEN total_api_calls > 0 
        THEN CAST(total_revenue / total_api_calls AS DECIMAL(10,4))
        ELSE NULL
    END AS revenue_per_api_call

FROM monthly_totals;
GO

PRINT '>> Created gold.vw_growth_metrics';
GO

/*
-- Sample queries:
-- Monthly growth dashboard
SELECT year, month_number, month_name, total_mrr,
       mom_growth_pct, yoy_growth_pct, net_revenue_retention_pct,
       active_customers, net_customer_change
FROM gold.vw_growth_metrics
ORDER BY year, month_number;

-- NRR trend (key SaaS health metric)
SELECT fiscal_quarter, 
       AVG(net_revenue_retention_pct) AS avg_nrr
FROM gold.vw_growth_metrics
WHERE net_revenue_retention_pct IS NOT NULL
GROUP BY fiscal_quarter
ORDER BY fiscal_quarter;
*/
