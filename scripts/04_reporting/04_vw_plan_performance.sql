/*
=============================================================================
  04_vw_plan_performance.sql
  ---------------------------
  Purpose:  Analyze performance of each subscription plan tier.
  
  Business questions answered:
  - Which plan tier generates the most revenue?
  - What is the retention rate per plan?
  - How does usage intensity differ across plans?
  - What's the upgrade/downgrade distribution?
  
  Why this matters:
  - Pricing and packaging decisions are major consulting deliverables.
    Showing you can analyze plan performance demonstrates commercial
    awareness beyond just technical SQL skills.
=============================================================================
*/

USE NovaCRM_DWH;
GO

IF OBJECT_ID('gold.vw_plan_performance', 'V') IS NOT NULL
    DROP VIEW gold.vw_plan_performance;
GO

CREATE VIEW gold.vw_plan_performance AS
SELECT
    p.plan_code,
    p.plan_name,
    p.plan_tier,
    p.billing_cycle,
    p.list_price,
    
    -- Revenue metrics
    COUNT(DISTINCT f.customer_key) AS total_customers,
    SUM(f.mrr_amount) AS total_mrr,
    AVG(f.mrr_amount) AS avg_mrr_per_customer,
    SUM(f.invoice_amount) AS total_invoiced_revenue,
    
    -- Plan mix: what % of total MRR comes from this plan
    CAST(
        SUM(f.mrr_amount) * 100.0 / 
        NULLIF(SUM(SUM(f.mrr_amount)) OVER(), 0) 
    AS DECIMAL(5,2)) AS mrr_share_pct,
    
    -- Event distribution: how do subscriptions flow through lifecycle stages
    SUM(CASE WHEN f.event_type = 'new'    THEN 1 ELSE 0 END) AS new_events,
    SUM(CASE WHEN f.event_type = 'active' THEN 1 ELSE 0 END) AS active_events,
    SUM(CASE WHEN f.event_type = 'churn'  THEN 1 ELSE 0 END) AS churn_events,
    
    -- Churn rate per plan: churn events / total events
    CASE
        WHEN COUNT(*) > 0
        THEN CAST(
            SUM(CASE WHEN f.event_type = 'churn' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
        AS DECIMAL(5,2))
        ELSE 0
    END AS churn_rate_pct,
    
    -- Usage intensity: higher usage = stickier product
    AVG(CAST(f.api_calls_monthly AS FLOAT)) AS avg_api_calls,
    AVG(f.storage_gb_avg) AS avg_storage_gb,
    AVG(CAST(f.active_users_avg AS FLOAT)) AS avg_active_users,
    
    -- Support burden per plan: high-support plans may need better onboarding
    AVG(CAST(f.support_tickets_opened AS FLOAT)) AS avg_tickets_per_month,
    AVG(f.avg_satisfaction) AS avg_satisfaction,
    
    -- Discount analysis: how far is actual MRR from list price
    -- Negative = discount, positive = premium (shouldn't happen)
    AVG(f.mrr_amount) - p.list_price AS avg_discount_from_list

FROM gold.fact_subscription_events f
INNER JOIN gold.dim_plan p ON f.plan_key = p.plan_key
GROUP BY p.plan_code, p.plan_name, p.plan_tier, p.billing_cycle, p.list_price;
GO

PRINT '>> Created gold.vw_plan_performance';
GO

/*
-- Sample queries:
-- Plan revenue comparison
SELECT plan_name, billing_cycle, total_customers, total_mrr, 
       mrr_share_pct, churn_rate_pct
FROM gold.vw_plan_performance
ORDER BY total_mrr DESC;

-- Which plan has the best retention?
SELECT plan_name, churn_rate_pct, avg_api_calls, avg_satisfaction
FROM gold.vw_plan_performance
ORDER BY churn_rate_pct ASC;
*/
