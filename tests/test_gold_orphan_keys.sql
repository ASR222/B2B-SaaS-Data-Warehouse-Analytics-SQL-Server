/*
=============================================================================
  test_gold_orphan_keys.sql
  ---------------------------
  Purpose:  Validate that all surrogate FK values in the fact table reference
            existing dimension rows. Catches fact load bugs where dimension
            keys were mismatched or missing.
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- Fact → dim_customer (customer_key)
SELECT 'fact.customer_key → dim_customer' AS fk_check,
       COUNT(*) AS orphan_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM gold.fact_subscription_events f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_customer dc WHERE dc.customer_key = f.customer_key)

UNION ALL

-- Fact → dim_plan (plan_key)
SELECT 'fact.plan_key → dim_plan',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM gold.fact_subscription_events f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_plan dp WHERE dp.plan_key = f.plan_key)

UNION ALL

-- Fact → dim_date (date_key)
SELECT 'fact.date_key → dim_date',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM gold.fact_subscription_events f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_date dd WHERE dd.date_key = f.date_key);
GO
