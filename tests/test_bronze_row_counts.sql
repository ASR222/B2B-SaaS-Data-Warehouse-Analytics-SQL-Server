/*
=============================================================================
  test_bronze_row_counts.sql
  ---------------------------
  Purpose:  Validate that bronze tables loaded the expected number of rows
            from source CSVs. This is a basic "did the pipeline run?" check.
  
  How to interpret:
  - If row counts are 0, the BULK INSERT likely failed (check file paths).
  - If counts differ significantly from expected, the CSV format may have
    changed (new columns, different delimiters, etc.).
  
  Expected counts (from synthetic data generator):
  - crm_accounts:         ~2,000
  - crm_contacts:         ~4,000
  - crm_support_tickets:  ~8,000
  - erp_subscriptions:    ~2,000
  - erp_invoices:         ~37,000+ (includes ~5 intentional duplicates)
  - erp_usage_metrics:    ~100,000
=============================================================================
*/

USE NovaCRM_DWH;
GO

SELECT 
    'bronze.crm_accounts'        AS table_name, COUNT(*) AS actual_rows, 2000  AS expected_min,
    CASE WHEN COUNT(*) >= 1900 THEN 'PASS' ELSE 'FAIL' END AS status
FROM bronze.crm_accounts
UNION ALL
SELECT 'bronze.crm_contacts',     COUNT(*), 4000,
    CASE WHEN COUNT(*) >= 3800 THEN 'PASS' ELSE 'FAIL' END
FROM bronze.crm_contacts
UNION ALL
SELECT 'bronze.crm_support_tickets', COUNT(*), 8000,
    CASE WHEN COUNT(*) >= 7500 THEN 'PASS' ELSE 'FAIL' END
FROM bronze.crm_support_tickets
UNION ALL
SELECT 'bronze.erp_subscriptions', COUNT(*), 2000,
    CASE WHEN COUNT(*) >= 1900 THEN 'PASS' ELSE 'FAIL' END
FROM bronze.erp_subscriptions
UNION ALL
SELECT 'bronze.erp_invoices',     COUNT(*), 37000,
    CASE WHEN COUNT(*) >= 35000 THEN 'PASS' ELSE 'FAIL' END
FROM bronze.erp_invoices
UNION ALL
SELECT 'bronze.erp_usage_metrics', COUNT(*), 100000,
    CASE WHEN COUNT(*) >= 90000 THEN 'PASS' ELSE 'FAIL' END
FROM bronze.erp_usage_metrics;
GO
