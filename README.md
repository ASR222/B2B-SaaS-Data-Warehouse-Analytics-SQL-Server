# NovaCRM Analytics — SaaS Data Warehouse & Analytics

A production-quality SQL Server data warehouse implementing **medallion architecture** (bronze → silver → gold) for a fictional B2B SaaS company. Built to demonstrate data engineering, data modeling, ETL development, and analytical reporting — skills directly applicable to technology consulting roles.

---

## Problem Statement

**NovaCRM Analytics** is a B2B SaaS company that sells a CRM platform to mid-market businesses. The company has two internal source systems that don't talk to each other:

- **ERP System** — handles subscriptions, billing (invoices), and product usage metering
- **CRM System** — manages customer accounts, contacts, and support interactions

**The business challenge:** Executives need unified dashboards showing MRR trends, churn analysis, customer health scoring, and plan performance — but the data is siloed, inconsistent, and riddled with quality issues (mixed date formats, duplicates, orphan records, inconsistent casing).

**This project solves it** by building a SQL Server data warehouse that consolidates both sources into a star schema optimized for analytical queries.

---

## Architecture

```
  ┌──────────────┐     ┌──────────────┐
  │   ERP        │     │   CRM        │
  │  (CSV Files) │     │  (CSV Files) │
  │              │     │              │
  │ subscriptions│     │ accounts     │
  │ invoices     │     │ contacts     │
  │ usage_metrics│     │ support_tix  │
  └──────┬───────┘     └──────┬───────┘
         │                    │
         ▼                    ▼
  ┌─────────────────────────────────────┐
  │         BRONZE LAYER                │
  │   Raw landing (all NVARCHAR)        │
  │   No constraints, no transforms     │
  │   Preserves source fidelity         │
  └──────────────┬──────────────────────┘
                 │  Type casting, cleaning,
                 │  dedup, standardization
                 ▼
  ┌─────────────────────────────────────┐
  │         SILVER LAYER                │
  │   Typed, cleaned, validated         │
  │   PKs enforced, dates parsed        │
  │   Country names standardized        │
  │   + Data quality checks (20+ tests) │
  └──────────────┬──────────────────────┘
                 │  Star schema modeling,
                 │  SCD, surrogate keys
                 ▼
  ┌─────────────────────────────────────┐
  │         GOLD LAYER                  │
  │   Star schema (fact + dimensions)   │
  │   fact_subscription_events          │
  │   dim_customer, dim_plan, dim_date  │
  │   + 5 analytical reporting views    │
  └─────────────────────────────────────┘
```

### Layer-by-Layer Explanation

| Layer | Schema | Purpose | Key Technique |
|-------|--------|---------|---------------|
| **Bronze** | `bronze.*` | Raw CSV landing zone. All columns are `NVARCHAR(255)` to absorb any source data without type-casting failures. | `BULK INSERT`, full-refresh truncate+load |
| **Silver** | `silver.*` | Cleaned, typed, deduplicated data. Business rules applied (country standardization, boolean normalization, date parsing). | `TRY_CAST`/`TRY_CONVERT`, `ROW_NUMBER()` dedup, `CASE` standardization |
| **Gold** | `gold.*` | Star schema optimized for analytics. Surrogate keys, SCD Type 1 with Type 2 infrastructure, pre-aggregated dimensions. | `MERGE` (SCD), `LAG()` window functions, CTE date spine |

---

## Project Structure

```
saas-data-warehouse/
├── README.md                          # This file
├── DATA_CATALOG.md                    # Column-level documentation
├── TESTING.md                         # Data quality strategy
├── datasets/                          # Generated CSV source files
├── scripts/
│   ├── seed/generate_synthetic_data.py  # Data generator (Python/pandas)
│   ├── 00_init/01_create_database.sql   # DB + schema creation
│   ├── 01_bronze/                       # Raw landing DDL + load
│   ├── 02_silver/                       # Clean + transform + DQ checks
│   ├── 03_gold/                         # Star schema DDL + loads
│   └── 04_reporting/                    # Analytical views
├── tests/                             # Data quality test scripts
└── docs/                             # Architecture diagrams
```

---

## How to Run Locally

### Prerequisites
- SQL Server Express or Developer Edition (2019+)
- SQL Server Management Studio (SSMS)
- Python 3.8+ with `pandas` and `numpy` (for data generation only)

### Step-by-Step

```bash
# 1. Generate synthetic data
cd scripts/seed
pip install pandas numpy
python generate_synthetic_data.py
# → Creates 6 CSV files in datasets/

# 2. Open SSMS and run scripts IN ORDER:
#    a. scripts/00_init/01_create_database.sql
#    b. scripts/01_bronze/01_ddl_bronze_tables.sql
#    c. scripts/01_bronze/02_load_bronze.sql
#       ⚠️ Update the <<DATASETS_PATH>> placeholder with your absolute path
#    d. scripts/02_silver/01_ddl_silver_tables.sql
#    e. scripts/02_silver/02_transform_silver.sql
#    f. scripts/02_silver/03_quality_checks.sql     (review results)
#    g. scripts/03_gold/01_ddl_dim_tables.sql
#    h. scripts/03_gold/02_ddl_fact_table.sql
#    i. scripts/03_gold/03_load_dimensions.sql
#    j. scripts/03_gold/04_load_fact.sql
#    k. scripts/04_reporting/*.sql                   (create all views)

# 3. Run data quality tests
#    Execute each script in tests/ and verify PASS results

# 4. Query the reporting views
SELECT * FROM gold.vw_mrr_trends ORDER BY year, month_number;
SELECT * FROM gold.vw_churn_analysis ORDER BY year, month_number;
SELECT * FROM gold.vw_customer_segments WHERE customer_segment = 'At Risk';
```

---

## Business Questions Answered

### 1. MRR Trends (`gold.vw_mrr_trends`)
> *What is our Monthly Recurring Revenue, and how does it break down by plan tier?*

```sql
SELECT year, month_number, month_name,
       SUM(total_mrr) AS total_mrr,
       SUM(new_mrr) AS new_mrr,
       SUM(churned_mrr) AS churned_mrr,
       SUM(net_new_mrr) AS net_new_mrr
FROM gold.vw_mrr_trends
GROUP BY year, month_number, month_name
ORDER BY year, month_number;
```

### 2. Churn Analysis (`gold.vw_churn_analysis`)
> *What is our monthly churn rate, and is it improving?*

```sql
SELECT fiscal_quarter,
       AVG(churn_rate_pct) AS avg_monthly_churn,
       SUM(churned_customers) AS total_churned,
       AVG(retention_rate_pct) AS avg_retention
FROM gold.vw_churn_analysis
GROUP BY fiscal_quarter
ORDER BY fiscal_quarter;
```

### 3. Customer Segmentation (`gold.vw_customer_segments`)
> *Which customers are at risk of churning, and who are our champions?*

```sql
SELECT customer_segment,
       COUNT(*) AS customer_count,
       AVG(lifetime_mrr) AS avg_lifetime_value,
       AVG(avg_satisfaction) AS avg_csat
FROM gold.vw_customer_segments
GROUP BY customer_segment
ORDER BY avg_lifetime_value DESC;
```

### 4. Plan Performance (`gold.vw_plan_performance`)
> *Which plan tier drives the most revenue and has the best retention?*

```sql
SELECT plan_name, billing_cycle, total_customers,
       total_mrr, mrr_share_pct, churn_rate_pct
FROM gold.vw_plan_performance
ORDER BY total_mrr DESC;
```

### 5. Growth Metrics (`gold.vw_growth_metrics`)
> *What is our MoM/YoY growth rate and Net Revenue Retention?*

```sql
SELECT year, month_name, total_mrr,
       mom_growth_pct, yoy_growth_pct,
       net_revenue_retention_pct
FROM gold.vw_growth_metrics
ORDER BY year, month_number;
```

---

## Key Technical Highlights

| Skill Area | Techniques Used |
|-----------|----------------|
| **Data Modeling** | Star schema, surrogate keys, SCD Type 1 (with Type 2 architecture), date dimension generation |
| **ETL/ELT** | BULK INSERT, TRUNCATE+INSERT (full refresh), MERGE (upsert), TRY_CAST/TRY_CONVERT |
| **Data Quality** | 20+ automated DQ checks (nulls, duplicates, referential integrity, domain validation, business logic consistency) |
| **SQL Analytics** | Window functions (LAG, ROW_NUMBER, NTILE, SUM OVER), CTEs, CASE expressions, conditional aggregation |
| **SaaS Metrics** | MRR, churn rate, NRR, ARPA, RFM segmentation, cohort analysis |

---

## Tech Stack

- **SQL Server Express** — on-premise relational database
- **T-SQL** — all warehouse logic (DDL, ETL, views, tests)
- **Python/pandas** — synthetic data generation only
- **SSMS** — development and execution environment

---

## License

This is a portfolio project for educational and demonstration purposes.
