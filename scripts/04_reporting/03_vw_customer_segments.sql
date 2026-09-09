/*
=============================================================================
  03_vw_customer_segments.sql
  ----------------------------
  Purpose:  Customer segmentation using an RFM-adapted model for SaaS.
  
  Traditional RFM (Retail):
  - Recency: days since last purchase
  - Frequency: number of purchases
  - Monetary: total spend
  
  SaaS-adapted RFM:
  - Recency: days since last invoice (proxy for engagement)
  - Frequency: average monthly usage intensity (API calls / users)
  - Monetary: total MRR value (lifetime revenue proxy)
  
  Business questions answered:
  - Who are our most valuable customers?
  - Which customers are at risk of churning (low engagement)?
  - How should we prioritize customer success outreach?
  
  Segment definitions:
  - Champions:     High value, high engagement, recent activity
  - Loyal:         Moderate+ value, consistent engagement
  - At Risk:       Previously active but declining engagement
  - Needs Attention: Low engagement across all dimensions
  - New:           Recently acquired, not enough history to classify
=============================================================================
*/

USE NovaCRM_DWH;
GO

IF OBJECT_ID('gold.vw_customer_segments', 'V') IS NOT NULL
    DROP VIEW gold.vw_customer_segments;
GO

CREATE VIEW gold.vw_customer_segments AS
WITH customer_rfm AS (
    SELECT
        dc.customer_key,
        dc.account_id,
        dc.company_name,
        dc.industry,
        dc.company_size,
        dc.country,
        dc.region,
        dc.acquisition_channel,
        dc.is_active,
        
        -- R: Recency — days since most recent fact event
        -- Lower is better (more recent = more engaged)
        DATEDIFF(DAY, MAX(dd.full_date), GETDATE()) AS days_since_last_activity,
        
        -- F: Frequency — average monthly usage intensity
        AVG(CAST(f.api_calls_monthly AS FLOAT)) AS avg_monthly_api_calls,
        AVG(CAST(f.active_users_avg AS FLOAT)) AS avg_monthly_users,
        
        -- M: Monetary — total and average MRR
        SUM(f.mrr_amount) AS lifetime_mrr,
        AVG(f.mrr_amount) AS avg_mrr,
        SUM(f.invoice_amount) AS lifetime_revenue,
        
        -- Additional engagement signals
        COUNT(DISTINCT f.date_key) AS months_active,
        SUM(f.support_tickets_opened) AS total_tickets,
        AVG(f.avg_satisfaction) AS avg_satisfaction,
        
        -- Churn signal: did this customer have a churn event?
        MAX(CASE WHEN f.event_type = 'churn' THEN 1 ELSE 0 END) AS has_churned
        
    FROM gold.fact_subscription_events f
    INNER JOIN gold.dim_customer dc ON f.customer_key = dc.customer_key
    INNER JOIN gold.dim_date dd ON f.date_key = dd.date_key
    GROUP BY
        dc.customer_key, dc.account_id, dc.company_name, dc.industry,
        dc.company_size, dc.country, dc.region, dc.acquisition_channel,
        dc.is_active
),
scored AS (
    SELECT
        *,
        -- Score each dimension 1-5 using NTILE (quintiles)
        NTILE(5) OVER (ORDER BY days_since_last_activity DESC) AS recency_score,   -- 5 = most recent
        NTILE(5) OVER (ORDER BY avg_monthly_api_calls ASC)     AS frequency_score, -- 5 = highest usage
        NTILE(5) OVER (ORDER BY lifetime_mrr ASC)              AS monetary_score   -- 5 = highest value
    FROM customer_rfm
    WHERE has_churned = 0  -- Only segment active customers
)
SELECT
    customer_key,
    account_id,
    company_name,
    industry,
    company_size,
    country,
    region,
    acquisition_channel,
    days_since_last_activity,
    avg_monthly_api_calls,
    avg_monthly_users,
    lifetime_mrr,
    avg_mrr,
    lifetime_revenue,
    months_active,
    total_tickets,
    avg_satisfaction,
    recency_score,
    frequency_score,
    monetary_score,
    
    -- Combined RFM score (simple sum; range 3-15)
    recency_score + frequency_score + monetary_score AS rfm_total,
    
    -- Human-readable segment assignment
    CASE
        -- Champions: top quintile in all three dimensions
        WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4
            THEN 'Champion'
        -- Loyal: good across the board
        WHEN recency_score >= 3 AND monetary_score >= 3
            THEN 'Loyal'
        -- At Risk: high value but declining engagement
        WHEN recency_score <= 2 AND monetary_score >= 3
            THEN 'At Risk'
        -- New: recently acquired, few months of data
        WHEN months_active <= 3
            THEN 'New'
        -- Needs Attention: low scores overall
        ELSE 'Needs Attention'
    END AS customer_segment

FROM scored;
GO

PRINT '>> Created gold.vw_customer_segments';
GO

/*
-- Sample queries:
-- Segment distribution
SELECT customer_segment, COUNT(*) AS customer_count,
       AVG(lifetime_mrr) AS avg_lifetime_mrr,
       AVG(avg_satisfaction) AS avg_satisfaction
FROM gold.vw_customer_segments
GROUP BY customer_segment
ORDER BY avg_lifetime_mrr DESC;

-- At Risk customers (prioritize for outreach)
SELECT company_name, industry, country, lifetime_mrr, 
       days_since_last_activity, avg_satisfaction
FROM gold.vw_customer_segments
WHERE customer_segment = 'At Risk'
ORDER BY lifetime_mrr DESC;
*/
