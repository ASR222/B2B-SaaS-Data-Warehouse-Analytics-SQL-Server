# Data Catalog — NovaCRM Analytics Data Warehouse

This document describes every table and column in the data warehouse, organized by layer (bronze → silver → gold). Use this as a reference when writing queries or explaining the data model in interviews.

---

## Bronze Layer (`bronze` schema)

All columns are `NVARCHAR(255)` — raw data as-is from source CSVs. No type enforcement, no constraints.

### bronze.erp_subscriptions

| Column | Type | Description |
|--------|------|-------------|
| `subscription_id` | NVARCHAR(255) | Raw subscription ID from ERP |
| `account_id` | NVARCHAR(255) | Raw customer account reference |
| `plan_code` | NVARCHAR(255) | Subscription tier (mixed case: `starter`, `PRO`, etc.) |
| `mrr_amount` | NVARCHAR(255) | Monthly recurring revenue string |
| `currency_code` | NVARCHAR(255) | Currency (mostly USD) |
| `start_date` | NVARCHAR(255) | Subscription start (mixed date formats) |
| `end_date` | NVARCHAR(255) | Subscription end (NULL if active) |
| `status` | NVARCHAR(255) | Subscription state (mixed case) |
| `billing_cycle` | NVARCHAR(255) | `monthly` or `annual` |
| `created_at` | NVARCHAR(255) | Row creation timestamp from source |
| `dwh_load_ts` | DATETIME2 | ETL metadata: when row was ingested |

### bronze.erp_invoices

| Column | Type | Description |
|--------|------|-------------|
| `invoice_id` | NVARCHAR(255) | Raw invoice ID (has ~5 duplicates) |
| `subscription_id` | NVARCHAR(255) | Parent subscription reference |
| `invoice_date` | NVARCHAR(255) | Billing date (mixed formats) |
| `amount` | NVARCHAR(255) | Invoice amount string |
| `tax_amount` | NVARCHAR(255) | Tax charged string |
| `payment_status` | NVARCHAR(255) | `paid`, `pending`, `failed`, `refunded` |
| `payment_date` | NVARCHAR(255) | Payment receipt date (nullable) |
| `created_at` | NVARCHAR(255) | Row creation timestamp |
| `dwh_load_ts` | DATETIME2 | ETL metadata |

### bronze.erp_usage_metrics

| Column | Type | Description |
|--------|------|-------------|
| `metric_id` | NVARCHAR(255) | Raw metric ID |
| `subscription_id` | NVARCHAR(255) | Parent subscription reference |
| `metric_date` | NVARCHAR(255) | Day of measurement |
| `api_calls` | NVARCHAR(255) | API call count (may have negative values) |
| `storage_gb` | NVARCHAR(255) | Storage consumed in GB |
| `active_users` | NVARCHAR(255) | Daily active users for this account |
| `dwh_load_ts` | DATETIME2 | ETL metadata |

### bronze.crm_accounts

| Column | Type | Description |
|--------|------|-------------|
| `account_id` | NVARCHAR(255) | Raw account ID |
| `company_name` | NVARCHAR(255) | Company name (~2% NULL) |
| `industry` | NVARCHAR(255) | Industry vertical |
| `company_size` | NVARCHAR(255) | Employee count range |
| `country` | NVARCHAR(255) | Country (inconsistent: `US`, `USA`, `United States`) |
| `region` | NVARCHAR(255) | Geographic region |
| `acquisition_channel` | NVARCHAR(255) | How customer was acquired |
| `signup_date` | NVARCHAR(255) | Account creation date (mixed formats) |
| `account_owner` | NVARCHAR(255) | Sales rep name |
| `is_active` | NVARCHAR(255) | Active flag (messy: `Y`/`N`/`yes`/`no`/`1`/`0`/`true`/`false`) |
| `dwh_load_ts` | DATETIME2 | ETL metadata |

### bronze.crm_contacts

| Column | Type | Description |
|--------|------|-------------|
| `contact_id` | NVARCHAR(255) | Raw contact ID |
| `account_id` | NVARCHAR(255) | Parent account reference |
| `first_name` | NVARCHAR(255) | Contact first name |
| `last_name` | NVARCHAR(255) | Contact last name |
| `email` | NVARCHAR(255) | Email address (~3% duplicates) |
| `phone` | NVARCHAR(255) | Phone number (inconsistent formats) |
| `role` | NVARCHAR(255) | Contact role |
| `is_primary` | NVARCHAR(255) | Primary contact flag |
| `dwh_load_ts` | DATETIME2 | ETL metadata |

### bronze.crm_support_tickets

| Column | Type | Description |
|--------|------|-------------|
| `ticket_id` | NVARCHAR(255) | Raw ticket ID |
| `account_id` | NVARCHAR(255) | Parent account reference |
| `contact_id` | NVARCHAR(255) | Contact who raised the ticket |
| `category` | NVARCHAR(255) | `billing`, `technical`, `feature_request` |
| `priority` | NVARCHAR(255) | `low`, `medium`, `high`, `critical` |
| `status` | NVARCHAR(255) | Ticket state |
| `created_date` | NVARCHAR(255) | When ticket was opened |
| `resolved_date` | NVARCHAR(255) | When resolved (nullable) |
| `satisfaction` | NVARCHAR(255) | CSAT score (~3% out-of-range: 0, -1, 6, 7, 10) |
| `dwh_load_ts` | DATETIME2 | ETL metadata |

---

## Silver Layer (`silver` schema)

Properly typed, cleaned, standardized. PKs enforced.

### silver.accounts
**Grain:** One row per customer account.

| Column | Type | Nullable | Cleaning Applied |
|--------|------|----------|-----------------|
| `account_id` | INT | No (PK) | Cast from NVARCHAR |
| `company_name` | NVARCHAR(150) | Yes | Trimmed; NULLs preserved for DQ reporting |
| `industry` | NVARCHAR(50) | Yes | Trimmed |
| `company_size` | NVARCHAR(20) | Yes | Trimmed |
| `country` | NVARCHAR(60) | No | Standardized (US/USA → United States) |
| `region` | NVARCHAR(30) | No | Trimmed |
| `acquisition_channel` | NVARCHAR(30) | Yes | Lowercased |
| `signup_date` | DATE | Yes | Parsed via TRY_CONVERT |
| `account_owner` | NVARCHAR(80) | Yes | Trimmed |
| `is_active` | BIT | No | Normalized (Y/yes/1/true → 1) |
| `dwh_load_ts` | DATETIME2 | No | Load timestamp |

### silver.contacts
**Grain:** One row per contact person.

| Column | Type | Nullable | Cleaning Applied |
|--------|------|----------|-----------------|
| `contact_id` | INT | No (PK) | Cast from NVARCHAR |
| `account_id` | INT | No | Cast; rows with NULL dropped |
| `first_name` | NVARCHAR(80) | Yes | Trimmed |
| `last_name` | NVARCHAR(80) | Yes | Trimmed |
| `email` | NVARCHAR(150) | Yes | Lowercased, trimmed |
| `phone` | NVARCHAR(50) | Yes | Trimmed (not normalized) |
| `role` | NVARCHAR(50) | Yes | Trimmed |
| `is_primary` | BIT | No | Cast from NVARCHAR |
| `dwh_load_ts` | DATETIME2 | No | Load timestamp |

### silver.subscriptions
**Grain:** One row per subscription.

| Column | Type | Nullable | Cleaning Applied |
|--------|------|----------|-----------------|
| `subscription_id` | INT | No (PK) | Cast from NVARCHAR |
| `account_id` | INT | Yes | Cast; NULLs = orphan records |
| `plan_code` | NVARCHAR(20) | No | UPPER-cased |
| `mrr_amount` | DECIMAL(10,2) | No | ABS() for safety, default 0 |
| `currency_code` | CHAR(3) | No | UPPER, default 'USD' |
| `start_date` | DATE | No | Parsed via TRY_CONVERT |
| `end_date` | DATE | Yes | Parsed; NULL = active |
| `status` | NVARCHAR(15) | No | LOWER-cased |
| `billing_cycle` | NVARCHAR(10) | No | LOWER-cased |
| `created_at` | DATETIME2 | Yes | Parsed |
| `dwh_load_ts` | DATETIME2 | No | Load timestamp |

### silver.invoices
**Grain:** One row per invoice (deduplicated).

| Column | Type | Nullable | Cleaning Applied |
|--------|------|----------|-----------------|
| `invoice_id` | INT | No (PK) | Deduplicated via ROW_NUMBER |
| `subscription_id` | INT | No | Cast |
| `invoice_date` | DATE | No | Parsed |
| `amount` | DECIMAL(10,2) | No | Cast, default 0 |
| `tax_amount` | DECIMAL(10,2) | No | Cast, default 0 |
| `payment_status` | NVARCHAR(15) | No | Lowercased |
| `payment_date` | DATE | Yes | Parsed |
| `created_at` | DATETIME2 | Yes | Parsed |
| `dwh_load_ts` | DATETIME2 | No | Load timestamp |

### silver.usage_metrics
**Grain:** One row per daily usage measurement per subscription.

| Column | Type | Nullable | Cleaning Applied |
|--------|------|----------|-----------------|
| `metric_id` | INT | No (PK) | Cast |
| `subscription_id` | INT | No | Cast |
| `metric_date` | DATE | No | Parsed |
| `api_calls` | INT | No | ABS() to correct negatives |
| `storage_gb` | DECIMAL(10,2) | No | ABS() |
| `active_users` | INT | No | ABS() |
| `dwh_load_ts` | DATETIME2 | No | Load timestamp |

### silver.support_tickets
**Grain:** One row per support ticket.

| Column | Type | Nullable | Cleaning Applied |
|--------|------|----------|-----------------|
| `ticket_id` | INT | No (PK) | Cast |
| `account_id` | INT | No | Cast |
| `contact_id` | INT | Yes | Cast |
| `category` | NVARCHAR(30) | No | Lowercased |
| `priority` | NVARCHAR(10) | No | Lowercased |
| `status` | NVARCHAR(15) | No | Lowercased |
| `created_date` | DATETIME2 | No | Parsed |
| `resolved_date` | DATETIME2 | Yes | Parsed |
| `satisfaction` | INT | Yes | Clamped to 1-5; out-of-range → NULL |
| `dwh_load_ts` | DATETIME2 | No | Load timestamp |

---

## Gold Layer (`gold` schema)

Star schema optimized for analytical queries.

### gold.dim_customer
**Grain:** One row per customer (current version, SCD Type 1).

| Column | Type | Description |
|--------|------|-------------|
| `customer_key` | INT IDENTITY (PK) | Surrogate key |
| `account_id` | INT | Natural/business key |
| `company_name` | NVARCHAR(150) | Customer name |
| `industry` | NVARCHAR(50) | Industry vertical |
| `company_size` | NVARCHAR(20) | Employee range |
| `country` | NVARCHAR(60) | Standardized country |
| `region` | NVARCHAR(30) | Geographic region |
| `acquisition_channel` | NVARCHAR(30) | How acquired |
| `signup_date` | DATE | Account creation date |
| `account_owner` | NVARCHAR(80) | Sales rep |
| `is_active` | BIT | Active flag |
| `total_contacts` | INT | Pre-aggregated contact count |
| `open_tickets` | INT | Pre-aggregated open ticket count |
| `avg_satisfaction` | DECIMAL(3,1) | Pre-aggregated CSAT average |
| `effective_date` | DATE | SCD: when this version became current |
| `expiry_date` | DATE | SCD: 9999-12-31 if current |
| `is_current` | BIT | SCD: 1 = current version |

### gold.dim_plan
**Grain:** One row per plan_code + billing_cycle combination.

| Column | Type | Description |
|--------|------|-------------|
| `plan_key` | INT IDENTITY (PK) | Surrogate key |
| `plan_code` | NVARCHAR(20) | Natural key (STARTER/PRO/ENTERPRISE) |
| `billing_cycle` | NVARCHAR(10) | monthly / annual |
| `plan_name` | NVARCHAR(50) | Human-readable name |
| `plan_tier` | NVARCHAR(20) | basic / professional / enterprise |
| `list_price` | DECIMAL(10,2) | Standard price for this combination |
| `effective_date` | DATE | SCD metadata |
| `expiry_date` | DATE | SCD metadata |
| `is_current` | BIT | SCD flag |

### gold.dim_date
**Grain:** One row per calendar day (2022-01-01 to 2026-12-31).

| Column | Type | Description |
|--------|------|-------------|
| `date_key` | INT (PK) | YYYYMMDD integer |
| `full_date` | DATE | Calendar date |
| `day_of_month` | INT | 1-31 |
| `day_of_week` | INT | 1 (Mon) - 7 (Sun), ISO |
| `day_name` | NVARCHAR(10) | Monday, Tuesday, etc. |
| `week_of_year` | INT | ISO week number |
| `month_number` | INT | 1-12 |
| `month_name` | NVARCHAR(10) | January, February, etc. |
| `quarter` | INT | 1-4 |
| `year` | INT | Calendar year |
| `is_weekend` | BIT | 1 if Saturday/Sunday |
| `is_month_end` | BIT | 1 if last day of month |
| `fiscal_quarter` | NVARCHAR(10) | FY25-Q1 format |
| `fiscal_year` | INT | Fiscal year (= calendar year) |

### gold.fact_subscription_events
**Grain:** One row per subscription per month.

| Column | Type | Description |
|--------|------|-------------|
| `event_id` | INT IDENTITY (PK) | Surrogate key |
| `customer_key` | INT (FK → dim_customer) | Customer dimension key |
| `plan_key` | INT (FK → dim_plan) | Plan dimension key |
| `date_key` | INT (FK → dim_date) | Date dimension key (month start) |
| `event_type` | NVARCHAR(20) | new / active / churn / expired |
| `mrr_amount` | DECIMAL(10,2) | MRR at time of event |
| `mrr_change` | DECIMAL(10,2) | MRR delta vs. previous month |
| `invoice_amount` | DECIMAL(12,2) | Sum of invoices that month |
| `tax_amount` | DECIMAL(10,2) | Sum of tax that month |
| `api_calls_monthly` | INT | Total API calls that month |
| `storage_gb_avg` | DECIMAL(10,2) | Avg daily storage (GB) |
| `active_users_avg` | INT | Avg daily active users |
| `support_tickets_opened` | INT | Tickets opened that month |
| `support_tickets_resolved` | INT | Tickets resolved that month |
| `avg_satisfaction` | DECIMAL(3,1) | Avg CSAT score that month |
