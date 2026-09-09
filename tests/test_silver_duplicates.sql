/*
=============================================================================
  test_silver_duplicates.sql
  ---------------------------
  Purpose:  Verify PK uniqueness across all silver tables.
            If these pass, our deduplication logic worked correctly.
=============================================================================
*/

USE NovaCRM_DWH;
GO

SELECT 'silver.accounts (account_id)' AS pk_check,
       COUNT(*) AS duplicate_groups,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (SELECT account_id FROM silver.accounts GROUP BY account_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'silver.contacts (contact_id)',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT contact_id FROM silver.contacts GROUP BY contact_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'silver.subscriptions (subscription_id)',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT subscription_id FROM silver.subscriptions GROUP BY subscription_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'silver.invoices (invoice_id)',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT invoice_id FROM silver.invoices GROUP BY invoice_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'silver.usage_metrics (metric_id)',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT metric_id FROM silver.usage_metrics GROUP BY metric_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'silver.support_tickets (ticket_id)',
       COUNT(*), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT ticket_id FROM silver.support_tickets GROUP BY ticket_id HAVING COUNT(*) > 1) d;
GO
