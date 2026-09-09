/*
=============================================================================
  03_load_dimensions.sql
  -----------------------
  Purpose:  Populate the gold-layer dimension tables from silver-layer data.
            Uses MERGE for SCD Type 1 (overwrite) with infrastructure for
            SCD Type 2 documented in comments.

  Load order:
  1. dim_date    — Generated from a date spine (no source dependency)
  2. dim_plan    — Derived from distinct plan_code/billing_cycle in silver
  3. dim_customer — Joined from silver.accounts + aggregated metrics

  SCD Implementation:
  - Current: Type 1 (MERGE with UPDATE on change, INSERT on new)
  - Type 2 upgrade path documented in comments at each MERGE statement
  
  Why MERGE?
  - Atomic INSERT/UPDATE in a single statement
  - SSMS-compatible, standard T-SQL
  - Natural fit for dimension loading where you need upsert semantics
  - The WHEN MATCHED / WHEN NOT MATCHED clauses make the SCD logic explicit

  Prerequisites:
  - Gold DDL has been run (01_ddl_dim_tables.sql, 02_ddl_fact_table.sql)
  - Silver layer is populated
=============================================================================
*/

USE NovaCRM_DWH;
GO

-- ===========================================================================
-- 1. LOAD dim_date (Calendar dimension — generated, not sourced)
-- ===========================================================================
-- dim_date is generated from a recursive CTE date spine, not from source data.
-- This is standard practice: the calendar is infrastructure, not business data.
-- Range: 2022-01-01 to 2026-12-31 (covers our 2023-2025 data with buffer)
-- ===========================================================================

TRUNCATE TABLE gold.dim_date;
GO

-- Recursive CTE to generate every date in the range
;WITH DateSpine AS (
    SELECT CAST('2022-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM DateSpine WHERE dt < '2026-12-31'
)
INSERT INTO gold.dim_date (
    date_key, full_date, day_of_month, day_of_week, day_name,
    week_of_year, month_number, month_name, quarter, year,
    is_weekend, is_month_end, fiscal_quarter, fiscal_year
)
SELECT
    -- date_key: YYYYMMDD integer (e.g., 20230115)
    CAST(FORMAT(dt, 'yyyyMMdd') AS INT) AS date_key,
    dt AS full_date,
    DAY(dt) AS day_of_month,
    
    -- ISO day of week: Monday=1 ... Sunday=7
    -- DATEPART(dw, ...) is SET DATEFIRST dependent, so we normalize
    ((DATEPART(dw, dt) + @@DATEFIRST - 2) % 7) + 1 AS day_of_week,
    
    DATENAME(WEEKDAY, dt) AS day_name,
    DATEPART(ISO_WEEK, dt) AS week_of_year,
    MONTH(dt) AS month_number,
    DATENAME(MONTH, dt) AS month_name,
    DATEPART(QUARTER, dt) AS quarter,
    YEAR(dt) AS year,
    
    -- Weekend flag
    CASE WHEN DATEPART(dw, dt) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend,
    
    -- Month-end flag (is this the last day of the month?)
    CASE WHEN dt = EOMONTH(dt) THEN 1 ELSE 0 END AS is_month_end,
    
    -- Fiscal quarter (calendar-aligned per user preference)
    -- Format: 'FY25-Q1' for Jan-Mar 2025
    'FY' + RIGHT(CAST(YEAR(dt) AS VARCHAR), 2) + '-Q' + CAST(DATEPART(QUARTER, dt) AS VARCHAR) AS fiscal_quarter,
    
    YEAR(dt) AS fiscal_year

FROM DateSpine
OPTION (MAXRECURSION 2000);  -- ~1827 days = 5 years
GO

PRINT '>> Loaded gold.dim_date: ' + CAST((SELECT COUNT(*) FROM gold.dim_date) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- 2. LOAD dim_plan (Derived from silver.subscriptions)
-- ===========================================================================
-- dim_plan is derived from distinct plan_code + billing_cycle combinations,
-- enriched with human-readable names and list prices.
-- ===========================================================================

-- First, clear the table for full reload
-- In a Type 2 implementation, you'd only expire/insert changed rows
TRUNCATE TABLE gold.dim_plan;
GO

-- Reset the identity seed after truncate
DBCC CHECKIDENT ('gold.dim_plan', RESEED, 0);
GO

INSERT INTO gold.dim_plan (
    plan_code, billing_cycle, plan_name, plan_tier, list_price,
    effective_date, expiry_date, is_current
)
SELECT DISTINCT
    s.plan_code,
    s.billing_cycle,
    
    -- Derive human-readable plan name
    CASE s.plan_code
        WHEN 'STARTER'    THEN 'Starter Plan'
        WHEN 'PRO'        THEN 'Professional Plan'
        WHEN 'ENTERPRISE' THEN 'Enterprise Plan'
        ELSE s.plan_code + ' Plan'
    END AS plan_name,
    
    -- Derive tier classification (useful for grouping in reports)
    CASE s.plan_code
        WHEN 'STARTER'    THEN 'basic'
        WHEN 'PRO'        THEN 'professional'
        WHEN 'ENTERPRISE' THEN 'enterprise'
        ELSE 'unknown'
    END AS plan_tier,
    
    -- List price varies by billing cycle
    -- Annual subscribers typically get a discount (~2 months free)
    CASE 
        WHEN s.plan_code = 'STARTER'    AND s.billing_cycle = 'monthly' THEN 49.00
        WHEN s.plan_code = 'STARTER'    AND s.billing_cycle = 'annual'  THEN 490.00
        WHEN s.plan_code = 'PRO'        AND s.billing_cycle = 'monthly' THEN 149.00
        WHEN s.plan_code = 'PRO'        AND s.billing_cycle = 'annual'  THEN 1490.00
        WHEN s.plan_code = 'ENTERPRISE' AND s.billing_cycle = 'monthly' THEN 499.00
        WHEN s.plan_code = 'ENTERPRISE' AND s.billing_cycle = 'annual'  THEN 4990.00
        ELSE 0
    END AS list_price,
    
    CAST(GETDATE() AS DATE) AS effective_date,
    '9999-12-31' AS expiry_date,
    1 AS is_current

FROM silver.subscriptions s
WHERE s.plan_code IN ('STARTER', 'PRO', 'ENTERPRISE');
GO

PRINT '>> Loaded gold.dim_plan: ' + CAST((SELECT COUNT(*) FROM gold.dim_plan) AS VARCHAR) + ' rows';
GO

-- ===========================================================================
-- 3. LOAD dim_customer (MERGE — SCD Type 1)
-- ===========================================================================
-- This MERGE demonstrates the SCD Type 1 pattern: if an attribute changes,
-- we overwrite the existing row. No history is preserved.
--
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │ SCD TYPE 2 UPGRADE PATH (not implemented, but documented):        │
-- │                                                                     │
-- │ To enable Type 2, you would:                                       │
-- │ 1. In WHEN MATCHED AND (attributes differ):                        │
-- │    - Instead of UPDATE, do:                                         │
-- │      a. UPDATE the existing row: SET expiry_date = GETDATE(),      │
-- │         is_current = 0                                              │
-- │      b. INSERT a new row with: effective_date = GETDATE(),         │
-- │         expiry_date = '9999-12-31', is_current = 1                 │
-- │    - MERGE can't do both, so you'd split into two statements:      │
-- │      one UPDATE to expire, one INSERT for the new version.         │
-- │ 2. In the fact table load, join on customer_key WHERE is_current=1 │
-- │    for current state, or use date range overlap for point-in-time. │
-- │ 3. Add a UNIQUE index on (account_id, is_current) filtered to     │
-- │    is_current=1 to enforce single-active-version constraint.       │
-- └─────────────────────────────────────────────────────────────────────┘
-- ===========================================================================

-- Pre-aggregate support metrics per account (used in MERGE source)
-- This CTE rolls up contact counts, ticket counts, and satisfaction scores
;WITH customer_metrics AS (
    SELECT
        a.account_id,
        a.company_name,
        a.industry,
        a.company_size,
        a.country,
        a.region,
        a.acquisition_channel,
        a.signup_date,
        a.account_owner,
        a.is_active,
        ISNULL(c_counts.total_contacts, 0)      AS total_contacts,
        ISNULL(t_counts.open_tickets, 0)         AS open_tickets,
        t_counts.avg_satisfaction                 AS avg_satisfaction
    FROM silver.accounts a
    LEFT JOIN (
        -- Count contacts per account
        SELECT account_id, COUNT(*) AS total_contacts
        FROM silver.contacts
        GROUP BY account_id
    ) c_counts ON a.account_id = c_counts.account_id
    LEFT JOIN (
        -- Aggregate ticket metrics per account
        SELECT 
            account_id,
            SUM(CASE WHEN status IN ('open', 'in_progress') THEN 1 ELSE 0 END) AS open_tickets,
            AVG(CAST(satisfaction AS DECIMAL(3,1))) AS avg_satisfaction
        FROM silver.support_tickets
        GROUP BY account_id
    ) t_counts ON a.account_id = t_counts.account_id
)
MERGE gold.dim_customer AS target
USING customer_metrics AS source
    ON target.account_id = source.account_id AND target.is_current = 1
    
-- SCD Type 1: Update existing row if any attribute changed
WHEN MATCHED AND (
    ISNULL(target.company_name, '') <> ISNULL(source.company_name, '')
    OR ISNULL(target.industry, '') <> ISNULL(source.industry, '')
    OR ISNULL(target.company_size, '') <> ISNULL(source.company_size, '')
    OR target.country <> source.country
    OR target.region <> source.region
    OR target.is_active <> source.is_active
    OR target.total_contacts <> source.total_contacts
    OR target.open_tickets <> source.open_tickets
) THEN UPDATE SET
    target.company_name        = source.company_name,
    target.industry            = source.industry,
    target.company_size        = source.company_size,
    target.country             = source.country,
    target.region              = source.region,
    target.acquisition_channel = source.acquisition_channel,
    target.signup_date         = source.signup_date,
    target.account_owner       = source.account_owner,
    target.is_active           = source.is_active,
    target.total_contacts      = source.total_contacts,
    target.open_tickets        = source.open_tickets,
    target.avg_satisfaction    = source.avg_satisfaction,
    target.effective_date      = CAST(GETDATE() AS DATE)
    -- Note: In SCD Type 2, this UPDATE would instead set:
    --   expiry_date = CAST(GETDATE() AS DATE), is_current = 0
    -- And a separate INSERT would create the new version.

-- New customer: insert with current SCD metadata
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        account_id, company_name, industry, company_size, country, region,
        acquisition_channel, signup_date, account_owner, is_active,
        total_contacts, open_tickets, avg_satisfaction,
        effective_date, expiry_date, is_current
    )
    VALUES (
        source.account_id, source.company_name, source.industry, source.company_size,
        source.country, source.region, source.acquisition_channel, source.signup_date,
        source.account_owner, source.is_active,
        source.total_contacts, source.open_tickets, source.avg_satisfaction,
        CAST(GETDATE() AS DATE), '9999-12-31', 1
    );
GO

PRINT '>> Loaded gold.dim_customer: ' + CAST((SELECT COUNT(*) FROM gold.dim_customer) AS VARCHAR) + ' rows';
GO

PRINT '>> All gold dimensions loaded successfully.';
GO
