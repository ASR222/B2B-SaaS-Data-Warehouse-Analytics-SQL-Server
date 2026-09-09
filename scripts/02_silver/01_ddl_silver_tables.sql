/*
=============================================================================
  01_ddl_silver_tables.sql
  -------------------------
  Purpose:  Create properly typed, constrained tables in the silver schema.
            This is where we enforce data types, NOT NULL constraints, and
            PRIMARY KEYs that bronze intentionally omits.

  Key differences from bronze:
  - Proper data types (INT, DECIMAL, DATE, BIT) instead of NVARCHAR
  - PRIMARY KEY constraints for uniqueness enforcement
  - NOT NULL on business-critical columns
  - Standardized column naming (no changes, but consistent expectations)

  Why no FOREIGN KEYs in silver?
  - We log referential integrity issues in the quality checks script
    rather than rejecting rows with FK violations. This lets us quantify
    data quality issues before deciding how to handle them (reject vs.
    default vs. flag). In production, you might add FKs after the initial
    load is validated.

  Prerequisites:
  - 00_init/01_create_database.sql has been run
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ===========================================================================
-- CRM Tables (master data first, since subscriptions reference accounts)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- silver.accounts
-- Cleaned version of bronze.crm_accounts
-- Standardized: country names, is_active flag, parsed dates
-- ---------------------------------------------------------------------------
IF OBJECT_ID('silver.accounts', 'U') IS NOT NULL
    DROP TABLE silver.accounts;
GO

CREATE TABLE silver.accounts (
    account_id          INT             NOT NULL PRIMARY KEY,
    company_name        NVARCHAR(150)   NULL,       -- Allow NULL; we flag & report missing names
    industry            NVARCHAR(50)    NULL,
    company_size        NVARCHAR(20)    NULL,
    country             NVARCHAR(60)    NOT NULL,    -- Standardized to canonical names
    region              NVARCHAR(30)    NOT NULL,
    acquisition_channel NVARCHAR(30)    NULL,
    signup_date         DATE            NULL,        -- Parsed from mixed formats
    account_owner       NVARCHAR(80)    NULL,
    is_active           BIT             NOT NULL DEFAULT 1,  -- Normalized from Y/N/yes/no/1/0
    dwh_load_ts         DATETIME2       NOT NULL DEFAULT GETDATE()
);
GO

PRINT '>> Created silver.accounts';
GO

-- ---------------------------------------------------------------------------
-- silver.contacts
-- Cleaned version of bronze.crm_contacts
-- ---------------------------------------------------------------------------
IF OBJECT_ID('silver.contacts', 'U') IS NOT NULL
    DROP TABLE silver.contacts;
GO

CREATE TABLE silver.contacts (
    contact_id          INT             NOT NULL PRIMARY KEY,
    account_id          INT             NOT NULL,
    first_name          NVARCHAR(80)    NULL,
    last_name           NVARCHAR(80)    NULL,
    email               NVARCHAR(150)   NULL,
    phone               NVARCHAR(50)    NULL,       -- Kept as-is; phone normalization is out of scope
    role                NVARCHAR(50)    NULL,
    is_primary          BIT             NOT NULL DEFAULT 0,
    dwh_load_ts         DATETIME2       NOT NULL DEFAULT GETDATE()
);
GO

PRINT '>> Created silver.contacts';
GO

-- ---------------------------------------------------------------------------
-- silver.support_tickets
-- Cleaned version of bronze.crm_support_tickets
-- Satisfaction scores clamped to valid 1-5 range
-- ---------------------------------------------------------------------------
IF OBJECT_ID('silver.support_tickets', 'U') IS NOT NULL
    DROP TABLE silver.support_tickets;
GO

CREATE TABLE silver.support_tickets (
    ticket_id           INT             NOT NULL PRIMARY KEY,
    account_id          INT             NOT NULL,
    contact_id          INT             NULL,        -- Nullable: some tickets don't have a contact
    category            NVARCHAR(30)    NOT NULL,
    priority            NVARCHAR(10)    NOT NULL,
    status              NVARCHAR(15)    NOT NULL,
    created_date        DATETIME2       NOT NULL,
    resolved_date       DATETIME2       NULL,
    satisfaction        INT             NULL,         -- 1-5, NULL if not provided
    dwh_load_ts         DATETIME2       NOT NULL DEFAULT GETDATE()
);
GO

PRINT '>> Created silver.support_tickets';
GO

-- ===========================================================================
-- ERP Tables
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- silver.subscriptions
-- Cleaned version of bronze.erp_subscriptions
-- plan_code uppercased, status lowercased, dates parsed
-- ---------------------------------------------------------------------------
IF OBJECT_ID('silver.subscriptions', 'U') IS NOT NULL
    DROP TABLE silver.subscriptions;
GO

CREATE TABLE silver.subscriptions (
    subscription_id     INT             NOT NULL PRIMARY KEY,
    account_id          INT             NULL,        -- Nullable: some orphan records exist
    plan_code           NVARCHAR(20)    NOT NULL,    -- Standardized to UPPER
    mrr_amount          DECIMAL(10,2)   NOT NULL,
    currency_code       CHAR(3)         NOT NULL DEFAULT 'USD',
    start_date          DATE            NOT NULL,
    end_date            DATE            NULL,        -- NULL = active subscription
    status              NVARCHAR(15)    NOT NULL,    -- Standardized to LOWER
    billing_cycle       NVARCHAR(10)    NOT NULL,
    created_at          DATETIME2       NULL,
    dwh_load_ts         DATETIME2       NOT NULL DEFAULT GETDATE()
);
GO

PRINT '>> Created silver.subscriptions';
GO

-- ---------------------------------------------------------------------------
-- silver.invoices
-- Cleaned version of bronze.erp_invoices
-- Deduplicated by invoice_id (source has ~5 known duplicates)
-- ---------------------------------------------------------------------------
IF OBJECT_ID('silver.invoices', 'U') IS NOT NULL
    DROP TABLE silver.invoices;
GO

CREATE TABLE silver.invoices (
    invoice_id          INT             NOT NULL PRIMARY KEY,
    subscription_id     INT             NOT NULL,
    invoice_date        DATE            NOT NULL,
    amount              DECIMAL(10,2)   NOT NULL,
    tax_amount          DECIMAL(10,2)   NOT NULL DEFAULT 0,
    payment_status      NVARCHAR(15)    NOT NULL,
    payment_date        DATE            NULL,
    created_at          DATETIME2       NULL,
    dwh_load_ts         DATETIME2       NOT NULL DEFAULT GETDATE()
);
GO

PRINT '>> Created silver.invoices';
GO

-- ---------------------------------------------------------------------------
-- silver.usage_metrics
-- Cleaned version of bronze.erp_usage_metrics
-- Negative values corrected to 0
-- ---------------------------------------------------------------------------
IF OBJECT_ID('silver.usage_metrics', 'U') IS NOT NULL
    DROP TABLE silver.usage_metrics;
GO

CREATE TABLE silver.usage_metrics (
    metric_id           INT             NOT NULL PRIMARY KEY,
    subscription_id     INT             NOT NULL,
    metric_date         DATE            NOT NULL,
    api_calls           INT             NOT NULL DEFAULT 0,
    storage_gb          DECIMAL(10,2)   NOT NULL DEFAULT 0,
    active_users        INT             NOT NULL DEFAULT 0,
    dwh_load_ts         DATETIME2       NOT NULL DEFAULT GETDATE()
);
GO

PRINT '>> Created silver.usage_metrics';
GO

PRINT '>> All silver tables created successfully.';
GO
