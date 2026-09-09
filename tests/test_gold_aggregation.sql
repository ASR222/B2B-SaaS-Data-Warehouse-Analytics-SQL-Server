/*
=============================================================================
  test_gold_aggregation.sql
  ---------------------------
  Purpose:  Cross-validate that gold fact aggregates match silver source totals.
            This is a critical reconciliation check — if these numbers diverge,
            the fact load has a bug (dropped rows, double-counting, etc.).
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- Check 1: Total invoiced revenue should roughly match between layers
-- (Won't match exactly because fact only includes subscriptions with valid
-- dimension joins, but should be within a few percent)
SELECT 
    'Total invoice revenue' AS reconciliation_check,
    (SELECT SUM(amount) FROM silver.invoices) AS silver_total,
    (SELECT SUM(invoice_amount) FROM gold.fact_subscription_events) AS gold_total,
    CASE 
        WHEN ABS(
            ISNULL((SELECT SUM(amount) FROM silver.invoices), 0) - 
            ISNULL((SELECT SUM(invoice_amount) FROM gold.fact_subscription_events), 0)
        ) / NULLIF((SELECT SUM(amount) FROM silver.invoices), 1) < 0.10
        THEN 'PASS (within 10%)'
        ELSE 'WARNING (>10% variance)'
    END AS status;
GO

-- Check 2: Customer count in fact should not exceed dimension count
SELECT 
    'Customer count alignment' AS reconciliation_check,
    (SELECT COUNT(*) FROM gold.dim_customer WHERE is_current = 1) AS dim_customers,
    (SELECT COUNT(DISTINCT customer_key) FROM gold.fact_subscription_events) AS fact_customers,
    CASE 
        WHEN (SELECT COUNT(DISTINCT customer_key) FROM gold.fact_subscription_events) 
             <= (SELECT COUNT(*) FROM gold.dim_customer WHERE is_current = 1)
        THEN 'PASS'
        ELSE 'FAIL - fact has more customers than dimension'
    END AS status;
GO

-- Check 3: No fact rows with future dates beyond current date
SELECT 
    'Future date check' AS reconciliation_check,
    COUNT(*) AS future_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARNING' END AS status
FROM gold.fact_subscription_events f
INNER JOIN gold.dim_date d ON f.date_key = d.date_key
WHERE d.full_date > GETDATE();
GO

-- Check 4: Event type distribution (sanity check)
SELECT 
    event_type,
    COUNT(*) AS row_count,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,1)) AS pct
FROM gold.fact_subscription_events
GROUP BY event_type
ORDER BY row_count DESC;
GO
