/*
=============================================================================
  01_ddl_dim_tables.sql
  ----------------------
  Purpose:  Create dimension tables for the gold-layer star schema.
            These are the "lookup" tables that provide context for the
            fact_subscription_events fact table.

  SCD Strategy:
  - All dimensions include SCD Type 2 infrastructure columns:
    effective_date, expiry_date, is_current
  - Initial implementation uses SCD Type 1 (overwrite via MERGE)
  - Comments indicate where Type 2 logic would be added

  Why surrogate keys?
  - Decouples the warehouse from source system IDs
  - Enables SCD Type 2 (same natural key, multiple rows with different
    surrogate keys for historical versions)
  - Uses IDENTITY for simplicity; in production, consider hash keys
    for deterministic, merge-friendly surrogates

  Prerequisites:
  - 00_init/01_create_database.sql has been run
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ===========================================================================
-- dim_customer
-- Grain: one row per customer (current version under SCD Type 1)
-- With SCD Type 2, there would be one row per customer PER VERSION
-- ===========================================================================
IF OBJECT_ID('gold.dim_customer', 'U') IS NOT NULL
    DROP TABLE gold.dim_customer;
GO

CREATE TABLE gold.dim_customer (
    -- Surrogate key: warehouse-generated, has no business meaning
    customer_key        INT IDENTITY(1,1) PRIMARY KEY,
    
    -- Natural / business key: links back to source system
    account_id          INT             NOT NULL,
    
    -- Descriptive attributes (from CRM)
    company_name        NVARCHAR(150)   NULL,
    industry            NVARCHAR(50)    NULL,
    company_size        NVARCHAR(20)    NULL,
    country             NVARCHAR(60)    NOT NULL,
    region              NVARCHAR(30)    NOT NULL,
    acquisition_channel NVARCHAR(30)    NULL,
    signup_date         DATE            NULL,
    account_owner       NVARCHAR(80)    NULL,
    is_active           BIT             NOT NULL DEFAULT 1,
    
    -- Pre-aggregated metrics (denormalized for query performance)
    -- These are recalculated on each dimension load
    total_contacts      INT             NOT NULL DEFAULT 0,
    open_tickets        INT             NOT NULL DEFAULT 0,
    avg_satisfaction    DECIMAL(3,1)    NULL,
    
    -- SCD metadata columns
    -- Type 1: effective_date = load date, expiry_date = 9999-12-31, is_current = 1
    -- Type 2 (if implemented): on attribute change, expire the old row
    --   (set expiry_date = today, is_current = 0) and insert a new row
    --   (effective_date = today, expiry_date = 9999-12-31, is_current = 1)
    effective_date      DATE            NOT NULL DEFAULT GETDATE(),
    expiry_date         DATE            NOT NULL DEFAULT '9999-12-31',
    is_current          BIT             NOT NULL DEFAULT 1
);
GO

-- Index for lookups by natural key (common join pattern in fact loads)
CREATE NONCLUSTERED INDEX IX_dim_customer_account_id 
    ON gold.dim_customer(account_id) WHERE is_current = 1;
GO

PRINT '>> Created gold.dim_customer';
GO

-- ===========================================================================
-- dim_plan
-- Grain: one row per plan configuration
-- Enriched with derived attributes (plan_name, plan_tier, list_price)
-- ===========================================================================
IF OBJECT_ID('gold.dim_plan', 'U') IS NOT NULL
    DROP TABLE gold.dim_plan;
GO

CREATE TABLE gold.dim_plan (
    plan_key            INT IDENTITY(1,1) PRIMARY KEY,
    
    -- Natural key: composite of plan_code + billing_cycle
    plan_code           NVARCHAR(20)    NOT NULL,
    billing_cycle       NVARCHAR(10)    NOT NULL,
    
    -- Derived / enriched attributes
    plan_name           NVARCHAR(50)    NOT NULL,    -- 'STARTER' → 'Starter Plan'
    plan_tier           NVARCHAR(20)    NOT NULL,    -- basic / professional / enterprise
    list_price          DECIMAL(10,2)   NOT NULL,    -- Standard price for this plan+cycle
    
    -- SCD metadata
    effective_date      DATE            NOT NULL DEFAULT GETDATE(),
    expiry_date         DATE            NOT NULL DEFAULT '9999-12-31',
    is_current          BIT             NOT NULL DEFAULT 1
);
GO

CREATE NONCLUSTERED INDEX IX_dim_plan_code_cycle 
    ON gold.dim_plan(plan_code, billing_cycle) WHERE is_current = 1;
GO

PRINT '>> Created gold.dim_plan';
GO

-- ===========================================================================
-- dim_date
-- Grain: one row per calendar day from 2022-01-01 to 2026-12-31
-- Pre-calculated calendar attributes eliminate runtime date logic in queries
-- 
-- Why a date dimension?
-- - Enables time-based aggregations (fiscal quarter, week of year) without
--   complex DATEPART() calls in every query
-- - Makes MoM/YoY comparisons trivial with self-joins
-- - Standard practice in Kimball-style dimensional modeling
-- ===========================================================================
IF OBJECT_ID('gold.dim_date', 'U') IS NOT NULL
    DROP TABLE gold.dim_date;
GO

CREATE TABLE gold.dim_date (
    date_key            INT             NOT NULL PRIMARY KEY,  -- YYYYMMDD format
    full_date           DATE            NOT NULL,
    day_of_month        INT             NOT NULL,
    day_of_week         INT             NOT NULL,     -- 1=Monday ... 7=Sunday (ISO)
    day_name            NVARCHAR(10)    NOT NULL,
    week_of_year        INT             NOT NULL,
    month_number        INT             NOT NULL,
    month_name          NVARCHAR(10)    NOT NULL,
    quarter             INT             NOT NULL,
    year                INT             NOT NULL,
    is_weekend          BIT             NOT NULL,
    is_month_end        BIT             NOT NULL,
    fiscal_quarter      NVARCHAR(10)    NOT NULL,     -- 'FY25-Q1'
    fiscal_year         INT             NOT NULL
);
GO

PRINT '>> Created gold.dim_date';
GO

PRINT '>> All gold dimension tables created successfully.';
GO
