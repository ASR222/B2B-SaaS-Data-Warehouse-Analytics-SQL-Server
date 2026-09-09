/*
=============================================================================
  02_transform_silver.sql
  ------------------------
  Purpose:  Transform bronze data into the silver layer. This is the core
            "cleaning" script — it handles:
            
            1. Type casting (NVARCHAR → INT, DECIMAL, DATE, BIT)
            2. Date parsing (multiple source formats → standard DATE)
            3. Case standardization (plan_code → UPPER, status → LOWER)
            4. Country name normalization (US/USA/U.S.A. → United States)
            5. Boolean normalization (Y/N/yes/no/1/0/true/false → BIT)
            6. Deduplication (invoices with duplicate PKs)
            7. Value clamping (satisfaction scores outside 1-5 → NULL)
            8. Negative value correction (usage metrics)

  Design decisions:
  - INSERT-SELECT pattern (not MERGE): silver is a full-refresh from bronze.
    MERGE is reserved for the gold layer where we need SCD logic.
  - TRY_CAST / TRY_CONVERT: gracefully handles unparseable values by returning
    NULL instead of throwing errors — critical for dirty source data.
  - COALESCE for defaults: when a TRY_CAST returns NULL, we fall back to
    sensible defaults rather than losing the row entirely.

  Prerequisites:
  - Bronze tables are loaded (01_bronze/02_load_bronze.sql)
  - Silver DDL exists (02_silver/01_ddl_silver_tables.sql)
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ===========================================================================
-- 1. ACCOUNTS (CRM)
-- Cleaning: country standardization, is_active normalization, date parsing
-- ===========================================================================
TRUNCATE TABLE silver.accounts;
GO

INSERT INTO silver.accounts (
    account_id,
    company_name,
    industry,
    company_size,
    country,
    region,
    acquisition_channel,
    signup_date,
    account_owner,
    is_active,
    dwh_load_ts
)
SELECT
    TRY_CAST(account_id AS INT) AS account_id,
    
    -- Trim whitespace but preserve NULLs — quality checks will flag missing names
    LTRIM(RTRIM(company_name)) AS company_name,
    
    LTRIM(RTRIM(industry)) AS industry,
    LTRIM(RTRIM(company_size)) AS company_size,
    
    -- Standardize country names: map all variants to canonical form
    -- This is a common real-world cleaning task — source systems rarely agree
    -- on how to represent the same country.
    CASE 
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('US', 'USA', 'UNITED STATES', 'U.S.A.')
            THEN 'United States'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('UK', 'GB', 'UNITED KINGDOM')
            THEN 'United Kingdom'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('CA', 'CANADA')
            THEN 'Canada'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('DE', 'GERMANY')
            THEN 'Germany'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('AU', 'AUSTRALIA')
            THEN 'Australia'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('FR', 'FRANCE')
            THEN 'France'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('IN', 'INDIA')
            THEN 'India'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('BR', 'BRAZIL')
            THEN 'Brazil'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('JP', 'JAPAN')
            THEN 'Japan'
        WHEN UPPER(LTRIM(RTRIM(country))) IN ('SG', 'SINGAPORE')
            THEN 'Singapore'
        ELSE LTRIM(RTRIM(country))  -- Pass through unknown countries as-is
    END AS country,
    
    LTRIM(RTRIM(region)) AS region,
    LOWER(LTRIM(RTRIM(acquisition_channel))) AS acquisition_channel,
    
    -- Parse dates from multiple formats using TRY_CONVERT
    -- TRY_CONVERT returns NULL for unparseable strings instead of throwing
    TRY_CONVERT(DATE, signup_date) AS signup_date,
    
    LTRIM(RTRIM(account_owner)) AS account_owner,
    
    -- Normalize boolean: map all variants to BIT (0/1)
    -- This is a textbook data quality exercise — source systems use every
    -- possible representation of true/false.
    CASE 
        WHEN LOWER(LTRIM(RTRIM(is_active))) IN ('y', 'yes', '1', 'true')  THEN 1
        WHEN LOWER(LTRIM(RTRIM(is_active))) IN ('n', 'no', '0', 'false')  THEN 0
        ELSE 1  -- Default to active if unrecognized
    END AS is_active,
    
    GETDATE() AS dwh_load_ts

FROM bronze.crm_accounts
WHERE TRY_CAST(account_id AS INT) IS NOT NULL;  -- Drop rows with non-numeric account_id
GO

PRINT '>> Loaded silver.accounts: ' + CAST((SELECT COUNT(*) FROM silver.accounts) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- 2. CONTACTS (CRM)
-- Cleaning: type casting, email trimming
-- ===========================================================================
TRUNCATE TABLE silver.contacts;
GO

INSERT INTO silver.contacts (
    contact_id,
    account_id,
    first_name,
    last_name,
    email,
    phone,
    role,
    is_primary,
    dwh_load_ts
)
SELECT
    TRY_CAST(contact_id AS INT),
    TRY_CAST(account_id AS INT),
    LTRIM(RTRIM(first_name)),
    LTRIM(RTRIM(last_name)),
    LOWER(LTRIM(RTRIM(email))),       -- Emails should always be lowercase
    LTRIM(RTRIM(phone)),               -- Phone normalization is out of scope
    LTRIM(RTRIM(role)),
    ISNULL(TRY_CAST(is_primary AS BIT), 0),
    GETDATE()
FROM bronze.crm_contacts
WHERE TRY_CAST(contact_id AS INT) IS NOT NULL
  AND TRY_CAST(account_id AS INT) IS NOT NULL;
GO

PRINT '>> Loaded silver.contacts: ' + CAST((SELECT COUNT(*) FROM silver.contacts) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- 3. SUPPORT TICKETS (CRM)
-- Cleaning: satisfaction score clamping, date parsing
-- ===========================================================================
TRUNCATE TABLE silver.support_tickets;
GO

INSERT INTO silver.support_tickets (
    ticket_id,
    account_id,
    contact_id,
    category,
    priority,
    status,
    created_date,
    resolved_date,
    satisfaction,
    dwh_load_ts
)
SELECT
    TRY_CAST(ticket_id AS INT),
    TRY_CAST(account_id AS INT),
    TRY_CAST(contact_id AS INT),
    LOWER(LTRIM(RTRIM(category))),
    LOWER(LTRIM(RTRIM(priority))),
    LOWER(LTRIM(RTRIM(status))),
    TRY_CONVERT(DATETIME2, created_date),
    TRY_CONVERT(DATETIME2, resolved_date),
    
    -- Clamp satisfaction to valid 1-5 range; out-of-range → NULL
    -- Why NULL instead of rejecting the row? The ticket itself is valid data;
    -- only the satisfaction score is suspect. Nullifying preserves the ticket
    -- for operational reporting while flagging the score for review.
    CASE 
        WHEN TRY_CAST(satisfaction AS INT) BETWEEN 1 AND 5 
            THEN TRY_CAST(satisfaction AS INT)
        ELSE NULL
    END AS satisfaction,
    
    GETDATE()
FROM bronze.crm_support_tickets
WHERE TRY_CAST(ticket_id AS INT) IS NOT NULL
  AND TRY_CONVERT(DATETIME2, created_date) IS NOT NULL;
GO

PRINT '>> Loaded silver.support_tickets: ' + CAST((SELECT COUNT(*) FROM silver.support_tickets) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- 4. SUBSCRIPTIONS (ERP)
-- Cleaning: case standardization, date parsing, type casting
-- ===========================================================================
TRUNCATE TABLE silver.subscriptions;
GO

INSERT INTO silver.subscriptions (
    subscription_id,
    account_id,
    plan_code,
    mrr_amount,
    currency_code,
    start_date,
    end_date,
    status,
    billing_cycle,
    created_at,
    dwh_load_ts
)
SELECT
    TRY_CAST(subscription_id AS INT),
    TRY_CAST(account_id AS INT),     -- NULL for orphan records (intentional)
    UPPER(LTRIM(RTRIM(plan_code))),   -- Standardize to UPPER: 'starter' → 'STARTER'
    
    -- MRR: ensure positive; use ABS as a safety net
    ABS(ISNULL(TRY_CAST(mrr_amount AS DECIMAL(10,2)), 0)),
    
    UPPER(ISNULL(LTRIM(RTRIM(currency_code)), 'USD')),
    
    -- Parse start_date from mixed formats
    TRY_CONVERT(DATE, start_date) AS start_date,
    TRY_CONVERT(DATE, end_date) AS end_date,
    
    LOWER(LTRIM(RTRIM(status))),       -- Standardize to LOWER: 'Active' → 'active'
    LOWER(LTRIM(RTRIM(billing_cycle))),
    TRY_CONVERT(DATETIME2, created_at),
    GETDATE()
FROM bronze.erp_subscriptions
WHERE TRY_CAST(subscription_id AS INT) IS NOT NULL
  AND TRY_CONVERT(DATE, start_date) IS NOT NULL;  -- Must have a parseable start date
GO

PRINT '>> Loaded silver.subscriptions: ' + CAST((SELECT COUNT(*) FROM silver.subscriptions) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- 5. INVOICES (ERP)
-- Cleaning: deduplication, date parsing, type casting
-- Dedup strategy: keep the row with the highest amount when duplicate
-- invoice_ids exist (arbitrary but deterministic tiebreaker).
-- ===========================================================================
TRUNCATE TABLE silver.invoices;
GO

INSERT INTO silver.invoices (
    invoice_id,
    subscription_id,
    invoice_date,
    amount,
    tax_amount,
    payment_status,
    payment_date,
    created_at,
    dwh_load_ts
)
SELECT
    invoice_id,
    subscription_id,
    invoice_date,
    amount,
    tax_amount,
    payment_status,
    payment_date,
    created_at,
    GETDATE()
FROM (
    SELECT
        TRY_CAST(invoice_id AS INT) AS invoice_id,
        TRY_CAST(subscription_id AS INT) AS subscription_id,
        TRY_CONVERT(DATE, invoice_date) AS invoice_date,
        ISNULL(TRY_CAST(amount AS DECIMAL(10,2)), 0) AS amount,
        ISNULL(TRY_CAST(tax_amount AS DECIMAL(10,2)), 0) AS tax_amount,
        LOWER(LTRIM(RTRIM(payment_status))) AS payment_status,
        TRY_CONVERT(DATE, payment_date) AS payment_date,
        TRY_CONVERT(DATETIME2, created_at) AS created_at,
        -- ROW_NUMBER for deduplication: partition by PK, keep the first occurrence
        -- ordered by highest amount (deterministic tiebreaker for duplicates)
        ROW_NUMBER() OVER (
            PARTITION BY TRY_CAST(invoice_id AS INT) 
            ORDER BY TRY_CAST(amount AS DECIMAL(10,2)) DESC
        ) AS rn
    FROM bronze.erp_invoices
    WHERE TRY_CAST(invoice_id AS INT) IS NOT NULL
      AND TRY_CONVERT(DATE, invoice_date) IS NOT NULL
) deduped
WHERE rn = 1;  -- Keep only the first row per invoice_id
GO

PRINT '>> Loaded silver.invoices: ' + CAST((SELECT COUNT(*) FROM silver.invoices) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- 6. USAGE METRICS (ERP)
-- Cleaning: negative values → 0, type casting
-- ===========================================================================
TRUNCATE TABLE silver.usage_metrics;
GO

INSERT INTO silver.usage_metrics (
    metric_id,
    subscription_id,
    metric_date,
    api_calls,
    storage_gb,
    active_users,
    dwh_load_ts
)
SELECT
    TRY_CAST(metric_id AS INT),
    TRY_CAST(subscription_id AS INT),
    TRY_CONVERT(DATE, metric_date),
    
    -- Correct negative values: usage metrics can't be negative
    -- ABS is a pragmatic choice; in a real pipeline you might flag these
    -- for manual review instead.
    ABS(ISNULL(TRY_CAST(api_calls AS INT), 0)),
    ABS(ISNULL(TRY_CAST(storage_gb AS DECIMAL(10,2)), 0)),
    ABS(ISNULL(TRY_CAST(active_users AS INT), 0)),
    
    GETDATE()
FROM bronze.erp_usage_metrics
WHERE TRY_CAST(metric_id AS INT) IS NOT NULL
  AND TRY_CONVERT(DATE, metric_date) IS NOT NULL;
GO

PRINT '>> Loaded silver.usage_metrics: ' + CAST((SELECT COUNT(*) FROM silver.usage_metrics) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- Summary
-- ===========================================================================
PRINT '>> Silver layer transformation complete. Row counts:';
SELECT 'accounts'          AS table_name, COUNT(*) AS row_count FROM silver.accounts
UNION ALL
SELECT 'contacts',         COUNT(*) FROM silver.contacts
UNION ALL
SELECT 'support_tickets',  COUNT(*) FROM silver.support_tickets
UNION ALL
SELECT 'subscriptions',    COUNT(*) FROM silver.subscriptions
UNION ALL
SELECT 'invoices',         COUNT(*) FROM silver.invoices
UNION ALL
SELECT 'usage_metrics',    COUNT(*) FROM silver.usage_metrics;
GO
