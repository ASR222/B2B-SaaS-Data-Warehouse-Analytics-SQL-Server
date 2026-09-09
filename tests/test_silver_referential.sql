/*
=============================================================================
  test_silver_referential.sql
  ----------------------------
  Purpose:  Validate FK relationships across silver tables.
            Catches orphan records that reference non-existent parent rows.
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- Subscriptions → Accounts (account_id)
SELECT 'subscriptions.account_id → accounts' AS fk_check,
       COUNT(*) AS orphan_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL - orphans found' END AS status
FROM silver.subscriptions s
WHERE s.account_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM silver.accounts a WHERE a.account_id = s.account_id)

UNION ALL

-- Invoices → Subscriptions (subscription_id)
SELECT 'invoices.subscription_id → subscriptions',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL - orphans found' END
FROM silver.invoices i
WHERE NOT EXISTS (SELECT 1 FROM silver.subscriptions s WHERE s.subscription_id = i.subscription_id)

UNION ALL

-- Usage Metrics → Subscriptions (subscription_id)
SELECT 'usage_metrics.subscription_id → subscriptions',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL - orphans found' END
FROM silver.usage_metrics um
WHERE NOT EXISTS (SELECT 1 FROM silver.subscriptions s WHERE s.subscription_id = um.subscription_id)

UNION ALL

-- Contacts → Accounts (account_id)
SELECT 'contacts.account_id → accounts',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL - orphans found' END
FROM silver.contacts c
WHERE NOT EXISTS (SELECT 1 FROM silver.accounts a WHERE a.account_id = c.account_id)

UNION ALL

-- Support Tickets → Accounts (account_id)
SELECT 'support_tickets.account_id → accounts',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL - orphans found' END
FROM silver.support_tickets t
WHERE NOT EXISTS (SELECT 1 FROM silver.accounts a WHERE a.account_id = t.account_id);
GO
