/*
=============================================================================
  03_quality_checks.sql
  ----------------------
  Purpose:  Comprehensive data quality validation for the silver layer.
            Each check produces a result set that can be reviewed manually
            or piped into a DQ dashboard. This maps directly to Deloitte's
            JD requirement for "data privacy, security, and risk management"
            and demonstrates "attention to detail/quality."

  Check categories:
  1. NULL / MISSING VALUE checks — critical fields that shouldn't be empty
  2. DUPLICATE checks — PK uniqueness verification
  3. REFERENTIAL INTEGRITY checks — FK relationships across tables
  4. DOMAIN / RANGE checks — values within expected boundaries
  5. CONSISTENCY checks — cross-field logic validation

  How to use:
  - Run this script after 02_transform_silver.sql
  - Each check outputs a result set with a check_name, status (PASS/FAIL),
    and details. Zero rows in a FAIL result = check passed.
  - In a production pipeline, these would feed into an alerting system.
    Here, they serve as auditable evidence of data quality due diligence.
=============================================================================
*/

USE NovaCRM_DWH;
GO

PRINT '================================================================';
PRINT '  DATA QUALITY CHECKS — SILVER LAYER';
PRINT '  Run Date: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '================================================================';
GO

-- ===========================================================================
-- 1. NULL / MISSING VALUE CHECKS
-- ===========================================================================
PRINT '';
PRINT '--- 1. NULL / MISSING VALUE CHECKS ---';
GO

-- Check 1.1: Accounts with NULL company_name
-- Expectation: ~2% of rows (intentional DQ issue in source data)
-- Business impact: Can't identify the customer in reports
SELECT 
    'CHK_1.1' AS check_id,
    'NULL company_name in silver.accounts' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status,
    CAST(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM silver.accounts), 0) AS DECIMAL(5,2)) AS pct_of_total
FROM silver.accounts
WHERE company_name IS NULL OR LTRIM(RTRIM(company_name)) = '';
GO

-- Check 1.2: Subscriptions with NULL account_id (orphan subscriptions)
-- Expectation: ~1% of rows (orphan records from ERP)
-- Business impact: Can't link subscription revenue to a customer
SELECT 
    'CHK_1.2' AS check_id,
    'NULL account_id in silver.subscriptions' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status,
    CAST(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM silver.subscriptions), 0) AS DECIMAL(5,2)) AS pct_of_total
FROM silver.subscriptions
WHERE account_id IS NULL;
GO

-- Check 1.3: Invoices with zero amount
-- Expectation: should be rare — a $0 invoice is suspicious
SELECT 
    'CHK_1.3' AS check_id,
    'Zero-amount invoices in silver.invoices' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'PASS' END AS status,
    CAST(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM silver.invoices), 0) AS DECIMAL(5,2)) AS pct_of_total
FROM silver.invoices
WHERE amount = 0;
GO

-- Check 1.4: Subscriptions with NULL start_date
-- These should have been filtered during silver load
SELECT 
    'CHK_1.4' AS check_id,
    'NULL start_date in silver.subscriptions' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE start_date IS NULL;
GO

-- ===========================================================================
-- 2. DUPLICATE CHECKS (PK Uniqueness)
-- ===========================================================================
PRINT '';
PRINT '--- 2. DUPLICATE CHECKS ---';
GO

-- Check 2.1: Duplicate account_ids in silver.accounts
SELECT 
    'CHK_2.1' AS check_id,
    'Duplicate account_id in silver.accounts' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM (
    SELECT account_id, COUNT(*) AS cnt
    FROM silver.accounts
    GROUP BY account_id
    HAVING COUNT(*) > 1
) dups;
GO

-- Check 2.2: Duplicate subscription_ids in silver.subscriptions
SELECT 
    'CHK_2.2' AS check_id,
    'Duplicate subscription_id in silver.subscriptions' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM (
    SELECT subscription_id, COUNT(*) AS cnt
    FROM silver.subscriptions
    GROUP BY subscription_id
    HAVING COUNT(*) > 1
) dups;
GO

-- Check 2.3: Duplicate invoice_ids in silver.invoices
-- If this passes, our dedup in transform_silver.sql worked correctly
SELECT 
    'CHK_2.3' AS check_id,
    'Duplicate invoice_id in silver.invoices (post-dedup)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM (
    SELECT invoice_id, COUNT(*) AS cnt
    FROM silver.invoices
    GROUP BY invoice_id
    HAVING COUNT(*) > 1
) dups;
GO

-- Check 2.4: Duplicate contact emails (not necessarily a data error,
-- but worth flagging for review)
SELECT 
    'CHK_2.4' AS check_id,
    'Duplicate emails in silver.contacts' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'PASS' END AS status
FROM (
    SELECT email, COUNT(*) AS cnt
    FROM silver.contacts
    WHERE email IS NOT NULL AND email <> ''
    GROUP BY email
    HAVING COUNT(*) > 1
) dups;
GO

-- ===========================================================================
-- 3. REFERENTIAL INTEGRITY CHECKS
-- ===========================================================================
PRINT '';
PRINT '--- 3. REFERENTIAL INTEGRITY CHECKS ---';
GO

-- Check 3.1: Subscriptions referencing non-existent accounts
-- These are "orphan" records — the subscription exists but the customer doesn't
SELECT 
    'CHK_3.1' AS check_id,
    'Orphan subscriptions (account_id not in silver.accounts)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.subscriptions s
WHERE s.account_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM silver.accounts a WHERE a.account_id = s.account_id
  );
GO

-- Check 3.2: Invoices referencing non-existent subscriptions
SELECT 
    'CHK_3.2' AS check_id,
    'Orphan invoices (subscription_id not in silver.subscriptions)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.invoices i
WHERE NOT EXISTS (
    SELECT 1 FROM silver.subscriptions s WHERE s.subscription_id = i.subscription_id
);
GO

-- Check 3.3: Usage metrics referencing non-existent subscriptions
SELECT 
    'CHK_3.3' AS check_id,
    'Orphan usage_metrics (subscription_id not in silver.subscriptions)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.usage_metrics um
WHERE NOT EXISTS (
    SELECT 1 FROM silver.subscriptions s WHERE s.subscription_id = um.subscription_id
);
GO

-- Check 3.4: Support tickets referencing non-existent accounts
SELECT 
    'CHK_3.4' AS check_id,
    'Orphan support_tickets (account_id not in silver.accounts)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.support_tickets t
WHERE NOT EXISTS (
    SELECT 1 FROM silver.accounts a WHERE a.account_id = t.account_id
);
GO

-- Check 3.5: Contacts referencing non-existent accounts
SELECT 
    'CHK_3.5' AS check_id,
    'Orphan contacts (account_id not in silver.accounts)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.contacts c
WHERE NOT EXISTS (
    SELECT 1 FROM silver.accounts a WHERE a.account_id = c.account_id
);
GO

-- ===========================================================================
-- 4. DOMAIN / RANGE CHECKS
-- ===========================================================================
PRINT '';
PRINT '--- 4. DOMAIN / RANGE CHECKS ---';
GO

-- Check 4.1: Subscription status contains only expected values
SELECT 
    'CHK_4.1' AS check_id,
    'Unexpected subscription status values' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE status NOT IN ('active', 'churned', 'expired', 'trial');
GO

-- Check 4.2: Plan codes are valid
SELECT 
    'CHK_4.2' AS check_id,
    'Unexpected plan_code values' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE plan_code NOT IN ('STARTER', 'PRO', 'ENTERPRISE');
GO

-- Check 4.3: MRR amounts are positive
SELECT 
    'CHK_4.3' AS check_id,
    'Negative or zero MRR amounts' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE mrr_amount <= 0;
GO

-- Check 4.4: Satisfaction scores in 1-5 range (after clamping)
SELECT 
    'CHK_4.4' AS check_id,
    'Out-of-range satisfaction scores (should be NULL or 1-5)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.support_tickets
WHERE satisfaction IS NOT NULL 
  AND satisfaction NOT BETWEEN 1 AND 5;
GO

-- Check 4.5: Invoice amounts are non-negative
SELECT 
    'CHK_4.5' AS check_id,
    'Negative invoice amounts' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.invoices
WHERE amount < 0;
GO

-- Check 4.6: Usage metrics are non-negative (after ABS correction)
SELECT 
    'CHK_4.6' AS check_id,
    'Negative usage metric values (post-correction)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.usage_metrics
WHERE api_calls < 0 OR storage_gb < 0 OR active_users < 0;
GO

-- ===========================================================================
-- 5. CONSISTENCY / BUSINESS LOGIC CHECKS
-- ===========================================================================
PRINT '';
PRINT '--- 5. CONSISTENCY CHECKS ---';
GO

-- Check 5.1: Subscription end_date before start_date
-- A subscription can't end before it starts — indicates a data entry error
SELECT 
    'CHK_5.1' AS check_id,
    'Subscription end_date before start_date' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE end_date IS NOT NULL AND end_date < start_date;
GO

-- Check 5.2: Active subscriptions should not have an end_date
SELECT 
    'CHK_5.2' AS check_id,
    'Active subscriptions with end_date set' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE status = 'active' AND end_date IS NOT NULL;
GO

-- Check 5.3: Churned/expired subscriptions should have an end_date
SELECT 
    'CHK_5.3' AS check_id,
    'Churned/expired subscriptions without end_date' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE status IN ('churned', 'expired') AND end_date IS NULL;
GO

-- Check 5.4: Resolved/closed tickets should have a resolved_date
SELECT 
    'CHK_5.4' AS check_id,
    'Resolved/closed tickets without resolved_date' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'PASS' END AS status
FROM silver.support_tickets
WHERE status IN ('resolved', 'closed') AND resolved_date IS NULL;
GO

-- Check 5.5: Dates within expected range (2022-2026)
-- Catches obviously wrong dates like 1900-01-01 or 2099-12-31
SELECT 
    'CHK_5.5' AS check_id,
    'Subscription dates outside expected range (2022-2026)' AS check_name,
    COUNT(*) AS violations,
    CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'PASS' END AS status
FROM silver.subscriptions
WHERE start_date < '2022-01-01' OR start_date > '2026-12-31'
   OR (end_date IS NOT NULL AND (end_date < '2022-01-01' OR end_date > '2028-12-31'));
GO

-- ===========================================================================
-- SUMMARY: Aggregate all check results
-- ===========================================================================
PRINT '';
PRINT '================================================================';
PRINT '  DATA QUALITY CHECKS COMPLETE';
PRINT '  Review results above for any FAIL or WARNING statuses.';
PRINT '  Timestamp: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '================================================================';
GO
