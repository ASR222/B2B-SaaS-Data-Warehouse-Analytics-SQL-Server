/*
=============================================================================
  01_ddl_bronze_tables.sql
  -------------------------
  Purpose:  Create raw landing tables in the bronze schema. Every column is
            NVARCHAR to absorb whatever the source CSVs contain without
            type-casting failures. A dwh_load_ts column captures when each
            row was ingested.

  Design decisions:
  - All NVARCHAR(255): wide enough for any source field, but bounded to catch
    accidental file-parsing issues (a VARCHAR(MAX) column would silently
    swallow multi-line garbage).
  - No PRIMARY KEY constraints: bronze preserves source fidelity, including
    duplicates. We enforce uniqueness in silver.
  - DROP + CREATE pattern: makes the pipeline rerunnable (full-reload).
    In production you'd use TRUNCATE or incremental loads, but for a portfolio
    demo, idempotent full-reload is cleaner.

  Prerequisites:
  - Run 00_init/01_create_database.sql first.
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ===========================================================================
-- ERP SOURCE TABLES
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- bronze.erp_subscriptions
-- Source: erp_subscriptions.csv (ERP system)
-- Grain: one row per subscription record as exported from source
-- ---------------------------------------------------------------------------
IF OBJECT_ID('bronze.erp_subscriptions', 'U') IS NOT NULL
    DROP TABLE bronze.erp_subscriptions;
GO

CREATE TABLE bronze.erp_subscriptions (
    subscription_id     NVARCHAR(255),
    account_id          NVARCHAR(255),
    plan_code           NVARCHAR(255),
    mrr_amount          NVARCHAR(255),
    currency_code       NVARCHAR(255),
    start_date          NVARCHAR(255),
    end_date            NVARCHAR(255),
    status              NVARCHAR(255),
    billing_cycle       NVARCHAR(255),
    created_at          NVARCHAR(255),
    dwh_load_ts         DATETIME2 DEFAULT GETDATE()  -- ETL metadata: when this row landed
);
GO

PRINT '>> Created bronze.erp_subscriptions';
GO

-- ---------------------------------------------------------------------------
-- bronze.erp_invoices
-- Source: erp_invoices.csv (ERP system)
-- Grain: one row per invoice line as exported from source
-- ---------------------------------------------------------------------------
IF OBJECT_ID('bronze.erp_invoices', 'U') IS NOT NULL
    DROP TABLE bronze.erp_invoices;
GO

CREATE TABLE bronze.erp_invoices (
    invoice_id          NVARCHAR(255),
    subscription_id     NVARCHAR(255),
    invoice_date        NVARCHAR(255),
    amount              NVARCHAR(255),
    tax_amount          NVARCHAR(255),
    payment_status      NVARCHAR(255),
    payment_date        NVARCHAR(255),
    created_at          NVARCHAR(255),
    dwh_load_ts         DATETIME2 DEFAULT GETDATE()
);
GO

PRINT '>> Created bronze.erp_invoices';
GO

-- ---------------------------------------------------------------------------
-- bronze.erp_usage_metrics
-- Source: erp_usage_metrics.csv (ERP system)
-- Grain: one row per daily usage measurement per subscription
-- ---------------------------------------------------------------------------
IF OBJECT_ID('bronze.erp_usage_metrics', 'U') IS NOT NULL
    DROP TABLE bronze.erp_usage_metrics;
GO

CREATE TABLE bronze.erp_usage_metrics (
    metric_id           NVARCHAR(255),
    subscription_id     NVARCHAR(255),
    metric_date         NVARCHAR(255),
    api_calls           NVARCHAR(255),
    storage_gb          NVARCHAR(255),
    active_users        NVARCHAR(255),
    dwh_load_ts         DATETIME2 DEFAULT GETDATE()
);
GO

PRINT '>> Created bronze.erp_usage_metrics';
GO

-- ===========================================================================
-- CRM SOURCE TABLES
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- bronze.crm_accounts
-- Source: crm_accounts.csv (CRM system)
-- Grain: one row per customer account
-- ---------------------------------------------------------------------------
IF OBJECT_ID('bronze.crm_accounts', 'U') IS NOT NULL
    DROP TABLE bronze.crm_accounts;
GO

CREATE TABLE bronze.crm_accounts (
    account_id          NVARCHAR(255),
    company_name        NVARCHAR(255),
    industry            NVARCHAR(255),
    company_size        NVARCHAR(255),
    country             NVARCHAR(255),
    region              NVARCHAR(255),
    acquisition_channel NVARCHAR(255),
    signup_date         NVARCHAR(255),
    account_owner       NVARCHAR(255),
    is_active           NVARCHAR(255),
    dwh_load_ts         DATETIME2 DEFAULT GETDATE()
);
GO

PRINT '>> Created bronze.crm_accounts';
GO

-- ---------------------------------------------------------------------------
-- bronze.crm_contacts
-- Source: crm_contacts.csv (CRM system)
-- Grain: one row per contact person
-- ---------------------------------------------------------------------------
IF OBJECT_ID('bronze.crm_contacts', 'U') IS NOT NULL
    DROP TABLE bronze.crm_contacts;
GO

CREATE TABLE bronze.crm_contacts (
    contact_id          NVARCHAR(255),
    account_id          NVARCHAR(255),
    first_name          NVARCHAR(255),
    last_name           NVARCHAR(255),
    email               NVARCHAR(255),
    phone               NVARCHAR(255),
    role                NVARCHAR(255),
    is_primary          NVARCHAR(255),
    dwh_load_ts         DATETIME2 DEFAULT GETDATE()
);
GO

PRINT '>> Created bronze.crm_contacts';
GO

-- ---------------------------------------------------------------------------
-- bronze.crm_support_tickets
-- Source: crm_support_tickets.csv (CRM system)
-- Grain: one row per support ticket
-- ---------------------------------------------------------------------------
IF OBJECT_ID('bronze.crm_support_tickets', 'U') IS NOT NULL
    DROP TABLE bronze.crm_support_tickets;
GO

CREATE TABLE bronze.crm_support_tickets (
    ticket_id           NVARCHAR(255),
    account_id          NVARCHAR(255),
    contact_id          NVARCHAR(255),
    category            NVARCHAR(255),
    priority            NVARCHAR(255),
    status              NVARCHAR(255),
    created_date        NVARCHAR(255),
    resolved_date       NVARCHAR(255),
    satisfaction        NVARCHAR(255),
    dwh_load_ts         DATETIME2 DEFAULT GETDATE()
);
GO

PRINT '>> Created bronze.crm_support_tickets';
GO

PRINT '>> All bronze tables created successfully.';
GO
