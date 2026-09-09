/*
=============================================================================
  02_vw_churn_analysis.sql
  -------------------------
  Purpose:  Churn rate analysis by month and customer cohort.
  
  Business questions answered:
  - What is our monthly churn rate?
  - Which signup cohorts (by quarter) retain customers best?
  - Is churn improving or worsening over time?
  
  Why this matters:
  - Churn is the #1 value destroyer in SaaS. A 5% monthly churn rate means
    you lose ~46% of customers annually. Understanding churn patterns is
    essential for any consulting engagement focused on growth strategy.
  - Cohort analysis is a more sophisticated lens than raw churn rate — it
    controls for the "when did they join?" variable.
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ---------------------------------------------------------------------------
-- View 1: Monthly churn rate
-- Churn rate = (customers who churned this month) / (customers active at start of month)
-- ---------------------------------------------------------------------------
IF OBJECT_ID('gold.vw_churn_analysis', 'V') IS NOT NULL
    DROP VIEW gold.vw_churn_analysis;
GO

CREATE VIEW gold.vw_churn_analysis AS
WITH monthly_stats AS (
    SELECT
        d.year,
        d.month_number,
        d.month_name,
        d.fiscal_quarter,
        
        -- Total active customers this month (all event types except churn)
        COUNT(DISTINCT CASE 
            WHEN f.event_type <> 'churn' THEN f.customer_key 
        END) AS active_customers,
        
        -- Customers who churned this month
        COUNT(DISTINCT CASE 
            WHEN f.event_type = 'churn' THEN f.customer_key 
        END) AS churned_customers,
        
        -- New customers this month
        COUNT(DISTINCT CASE 
            WHEN f.event_type = 'new' THEN f.customer_key 
        END) AS new_customers,
        
        -- Revenue lost to churn
        SUM(CASE WHEN f.event_type = 'churn' THEN f.mrr_amount ELSE 0 END) AS churned_mrr
        
    FROM gold.fact_subscription_events f
    INNER JOIN gold.dim_date d ON f.date_key = d.date_key
    GROUP BY d.year, d.month_number, d.month_name, d.fiscal_quarter
)
SELECT
    year,
    month_number,
    month_name,
    fiscal_quarter,
    active_customers,
    churned_customers,
    new_customers,
    churned_mrr,
    
    -- Gross churn rate: what % of customers left this month
    CASE 
        WHEN active_customers + churned_customers > 0
        THEN CAST(churned_customers * 100.0 / (active_customers + churned_customers) AS DECIMAL(5,2))
        ELSE 0 
    END AS churn_rate_pct,
    
    -- Net customer growth: new minus churned
    new_customers - churned_customers AS net_customer_growth,
    
    -- Logo retention rate: what % of customers stayed
    CASE 
        WHEN active_customers + churned_customers > 0
        THEN CAST(active_customers * 100.0 / (active_customers + churned_customers) AS DECIMAL(5,2))
        ELSE 100 
    END AS retention_rate_pct

FROM monthly_stats;
GO

PRINT '>> Created gold.vw_churn_analysis';
GO

/*
-- Sample query: Monthly churn trend
SELECT year, month_number, month_name, 
       churn_rate_pct, net_customer_growth, churned_mrr
FROM gold.vw_churn_analysis
ORDER BY year, month_number;

-- Quarterly summary
SELECT fiscal_quarter, 
       AVG(churn_rate_pct) AS avg_monthly_churn,
       SUM(churned_customers) AS total_churned,
       SUM(churned_mrr) AS total_churned_mrr
FROM gold.vw_churn_analysis
GROUP BY fiscal_quarter
ORDER BY fiscal_quarter;
*/
