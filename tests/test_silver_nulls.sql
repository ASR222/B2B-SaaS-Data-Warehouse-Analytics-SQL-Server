/*
=============================================================================
  test_silver_nulls.sql
  ----------------------
  Purpose:  Validate that NOT NULL columns in silver tables contain no NULLs.
            Catches transformation bugs where TRY_CAST silently returns NULL.
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- Accounts: country and region must not be NULL
SELECT 'silver.accounts.country' AS column_checked,
       COUNT(*) AS null_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM silver.accounts WHERE country IS NULL
UNION ALL
SELECT 'silver.accounts.region',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.accounts WHERE region IS NULL

-- Subscriptions: plan_code, mrr_amount, start_date, status must not be NULL
UNION ALL
SELECT 'silver.subscriptions.plan_code',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.subscriptions WHERE plan_code IS NULL
UNION ALL
SELECT 'silver.subscriptions.mrr_amount',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.subscriptions WHERE mrr_amount IS NULL
UNION ALL
SELECT 'silver.subscriptions.start_date',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.subscriptions WHERE start_date IS NULL
UNION ALL
SELECT 'silver.subscriptions.status',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.subscriptions WHERE status IS NULL

-- Invoices: invoice_date, amount, payment_status must not be NULL
UNION ALL
SELECT 'silver.invoices.invoice_date',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.invoices WHERE invoice_date IS NULL
UNION ALL
SELECT 'silver.invoices.amount',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.invoices WHERE amount IS NULL
UNION ALL
SELECT 'silver.invoices.payment_status',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.invoices WHERE payment_status IS NULL

-- Support tickets: category, priority, status, created_date
UNION ALL
SELECT 'silver.support_tickets.category',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.support_tickets WHERE category IS NULL
UNION ALL
SELECT 'silver.support_tickets.created_date',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM silver.support_tickets WHERE created_date IS NULL;
GO
