/*
=============================================================================
  02_load_bronze.sql
  -------------------
  Purpose:  Load raw CSV files into bronze landing tables using BULK INSERT.
            This is the "Extract" step of our ETL pipeline — data lands
            exactly as the source system exported it.

  Why BULK INSERT?
  - Native T-SQL, no external tools needed (SSIS, Python, etc.)
  - Fastest way to load flat files into SQL Server Express
  - The FIRSTROW=2 skips the CSV header row
  - FIELDTERMINATOR=',' and ROWTERMINATOR='\n' match standard CSV format

  Important: Update the file paths below to match YOUR local directory.
  The placeholder uses a relative-style path — replace with the absolute
  path to your /datasets folder.

  Prerequisites:
  - 00_init/01_create_database.sql has been run
  - 01_bronze/01_ddl_bronze_tables.sql has been run
  - CSV files exist in the datasets/ folder (run generate_synthetic_data.py)
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ===========================================================================
-- IMPORTANT: Set this to the absolute path of your datasets folder.
-- Example: C:\Users\yourname\projects\saas-data-warehouse\datasets\
-- 
-- SQL Server BULK INSERT requires an absolute path — relative paths
-- won't work. This is a common gotcha for beginners.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Truncate all bronze tables before reload (full-refresh pattern)
-- Why truncate instead of delete? TRUNCATE is minimally logged and doesn't
-- fire triggers — much faster for bulk operations.
-- ---------------------------------------------------------------------------
TRUNCATE TABLE bronze.erp_subscriptions;
TRUNCATE TABLE bronze.erp_invoices;
TRUNCATE TABLE bronze.erp_usage_metrics;
TRUNCATE TABLE bronze.crm_accounts;
TRUNCATE TABLE bronze.crm_contacts;
TRUNCATE TABLE bronze.crm_support_tickets;

PRINT '>> All bronze tables truncated for fresh load.';
GO

-- ---------------------------------------------------------------------------
-- Load ERP Subscriptions
-- Expected: ~2,000 rows
-- ---------------------------------------------------------------------------
BULK INSERT bronze.erp_subscriptions
FROM '<<DATASETS_PATH>>\erp_subscriptions.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,           -- Skip header row
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK                  -- Table-level lock for faster bulk load
);
GO

PRINT '>> Loaded bronze.erp_subscriptions';
SELECT COUNT(*) AS erp_subscriptions_count FROM bronze.erp_subscriptions;
GO

-- ---------------------------------------------------------------------------
-- Load ERP Invoices
-- Expected: ~37,000+ rows
-- ---------------------------------------------------------------------------
BULK INSERT bronze.erp_invoices
FROM '<<DATASETS_PATH>>\erp_invoices.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);
GO

PRINT '>> Loaded bronze.erp_invoices';
SELECT COUNT(*) AS erp_invoices_count FROM bronze.erp_invoices;
GO

-- ---------------------------------------------------------------------------
-- Load ERP Usage Metrics
-- Expected: ~100,000 rows
-- ---------------------------------------------------------------------------
BULK INSERT bronze.erp_usage_metrics
FROM '<<DATASETS_PATH>>\erp_usage_metrics.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);
GO

PRINT '>> Loaded bronze.erp_usage_metrics';
SELECT COUNT(*) AS erp_usage_metrics_count FROM bronze.erp_usage_metrics;
GO

-- ---------------------------------------------------------------------------
-- Load CRM Accounts
-- Expected: ~2,000 rows
-- ---------------------------------------------------------------------------
BULK INSERT bronze.crm_accounts
FROM '<<DATASETS_PATH>>\crm_accounts.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);
GO

PRINT '>> Loaded bronze.crm_accounts';
SELECT COUNT(*) AS crm_accounts_count FROM bronze.crm_accounts;
GO

-- ---------------------------------------------------------------------------
-- Load CRM Contacts
-- Expected: ~4,000 rows
-- ---------------------------------------------------------------------------
BULK INSERT bronze.crm_contacts
FROM '<<DATASETS_PATH>>\crm_contacts.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);
GO

PRINT '>> Loaded bronze.crm_contacts';
SELECT COUNT(*) AS crm_contacts_count FROM bronze.crm_contacts;
GO

-- ---------------------------------------------------------------------------
-- Load CRM Support Tickets
-- Expected: ~8,000 rows
-- ---------------------------------------------------------------------------
BULK INSERT bronze.crm_support_tickets
FROM '<<DATASETS_PATH>>\crm_support_tickets.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);
GO

PRINT '>> Loaded bronze.crm_support_tickets';
SELECT COUNT(*) AS crm_support_tickets_count FROM bronze.crm_support_tickets;
GO

-- ---------------------------------------------------------------------------
-- Summary: verify all loads
-- ---------------------------------------------------------------------------
PRINT '>> Bronze layer load complete. Row counts:';
SELECT 'erp_subscriptions'    AS table_name, COUNT(*) AS row_count FROM bronze.erp_subscriptions
UNION ALL
SELECT 'erp_invoices',        COUNT(*) FROM bronze.erp_invoices
UNION ALL
SELECT 'erp_usage_metrics',   COUNT(*) FROM bronze.erp_usage_metrics
UNION ALL
SELECT 'crm_accounts',        COUNT(*) FROM bronze.crm_accounts
UNION ALL
SELECT 'crm_contacts',        COUNT(*) FROM bronze.crm_contacts
UNION ALL
SELECT 'crm_support_tickets', COUNT(*) FROM bronze.crm_support_tickets;
GO
