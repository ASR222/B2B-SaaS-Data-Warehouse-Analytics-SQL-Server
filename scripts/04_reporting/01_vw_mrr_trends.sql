/*
=============================================================================
  01_vw_mrr_trends.sql
  ---------------------
  Purpose:  Monthly Recurring Revenue (MRR) trend analysis.
  
  Business questions answered:
  - What is our total MRR each month?
  - How does MRR break down by plan tier?
  - What are the components of MRR movement (new, expansion, contraction, churn)?
  
  Why this matters for Deloitte:
  - MRR is THE health metric for SaaS businesses. Being able to decompose
    MRR movement shows understanding of revenue drivers — critical for
    any consulting engagement with tech clients.
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ---------------------------------------------------------------------------
-- View 1: Monthly MRR summary with plan tier breakdown
-- ---------------------------------------------------------------------------
IF OBJECT_ID('gold.vw_mrr_trends', 'V') IS NOT NULL
    DROP VIEW gold.vw_mrr_trends;
GO

CREATE VIEW gold.vw_mrr_trends AS
SELECT
    d.year,
    d.month_number,
    d.month_name,
    d.fiscal_quarter,
    p.plan_tier,
    
    -- Total MRR: sum of all active subscription MRR that month
    SUM(f.mrr_amount) AS total_mrr,
    
    -- Active subscription count
    COUNT(DISTINCT f.customer_key) AS active_customers,
    
    -- Average Revenue Per Account (ARPA) — key SaaS metric
    CASE 
        WHEN COUNT(DISTINCT f.customer_key) > 0 
        THEN SUM(f.mrr_amount) / COUNT(DISTINCT f.customer_key)
        ELSE 0 
    END AS arpa,
    
    -- MRR movement components
    SUM(CASE WHEN f.event_type = 'new'    THEN f.mrr_amount ELSE 0 END) AS new_mrr,
    SUM(CASE WHEN f.event_type = 'churn'  THEN f.mrr_amount ELSE 0 END) AS churned_mrr,
    
    -- Net new MRR = new - churned
    SUM(CASE WHEN f.event_type = 'new' THEN f.mrr_amount ELSE 0 END) -
    SUM(CASE WHEN f.event_type = 'churn' THEN f.mrr_amount ELSE 0 END) AS net_new_mrr,
    
    -- Billed revenue (from actual invoices, may differ from MRR)
    SUM(f.invoice_amount) AS total_invoiced

FROM gold.fact_subscription_events f
INNER JOIN gold.dim_date d ON f.date_key = d.date_key
INNER JOIN gold.dim_plan p ON f.plan_key = p.plan_key
GROUP BY d.year, d.month_number, d.month_name, d.fiscal_quarter, p.plan_tier;
GO

PRINT '>> Created gold.vw_mrr_trends';
GO

/*
-- Sample query:
SELECT * FROM gold.vw_mrr_trends
ORDER BY year, month_number, plan_tier;

-- Total MRR by month (all tiers combined):
SELECT year, month_number, month_name,
       SUM(total_mrr) AS total_mrr,
       SUM(active_customers) AS total_customers,
       SUM(net_new_mrr) AS net_new_mrr
FROM gold.vw_mrr_trends
GROUP BY year, month_number, month_name
ORDER BY year, month_number;
*/
