# Testing & Data Quality — NovaCRM Analytics Data Warehouse

This document describes the data quality testing strategy, test inventory, and expected results. All tests are SQL scripts in the `/tests` directory that produce PASS/FAIL/WARNING result sets.

---

## Testing Philosophy

Data quality is not optional — it's a core pipeline requirement. Our approach mirrors enterprise data governance practices:

1. **Prevent** — Bronze layer absorbs everything; silver layer applies transformations that fix known issues (standardization, dedup, clamping).
2. **Detect** — Quality check scripts run after each silver load to identify remaining issues.
3. **Report** — Each check produces a structured result (check_id, check_name, violation_count, status) that could feed into an alerting system.
4. **Reconcile** — Gold-layer tests cross-validate aggregates between layers to catch load bugs.

---

## Test Inventory

### Bronze Layer Tests

| Script | Purpose | Expected Result |
|--------|---------|-----------------|
| `test_bronze_row_counts.sql` | Validates that BULK INSERT loaded expected row counts | PASS for all 6 tables |

### Silver Layer Tests

#### Null Checks (`test_silver_nulls.sql`)

| Check | Column | Expected |
|-------|--------|----------|
| NOT NULL: country | `silver.accounts.country` | PASS — all standardized |
| NOT NULL: region | `silver.accounts.region` | PASS |
| NOT NULL: plan_code | `silver.subscriptions.plan_code` | PASS — UPPER-cased |
| NOT NULL: mrr_amount | `silver.subscriptions.mrr_amount` | PASS — defaults to 0 |
| NOT NULL: start_date | `silver.subscriptions.start_date` | PASS — filtered on load |
| NOT NULL: status | `silver.subscriptions.status` | PASS |
| NOT NULL: invoice_date | `silver.invoices.invoice_date` | PASS |
| NOT NULL: amount | `silver.invoices.amount` | PASS |
| NOT NULL: payment_status | `silver.invoices.payment_status` | PASS |
| NOT NULL: category | `silver.support_tickets.category` | PASS |
| NOT NULL: created_date | `silver.support_tickets.created_date` | PASS |

#### Duplicate Checks (`test_silver_duplicates.sql`)

| Check | Table | Expected |
|-------|-------|----------|
| PK uniqueness | `silver.accounts (account_id)` | PASS |
| PK uniqueness | `silver.contacts (contact_id)` | PASS |
| PK uniqueness | `silver.subscriptions (subscription_id)` | PASS |
| PK uniqueness | `silver.invoices (invoice_id)` | PASS — dedup applied |
| PK uniqueness | `silver.usage_metrics (metric_id)` | PASS |
| PK uniqueness | `silver.support_tickets (ticket_id)` | PASS |

#### Referential Integrity (`test_silver_referential.sql`)

| Check | Relationship | Expected |
|-------|-------------|----------|
| FK validation | subscriptions.account_id → accounts | FAIL — ~1% orphan records (intentional) |
| FK validation | invoices.subscription_id → subscriptions | PASS or minor FAIL |
| FK validation | usage_metrics.subscription_id → subscriptions | PASS |
| FK validation | contacts.account_id → accounts | PASS |
| FK validation | support_tickets.account_id → accounts | PASS |

> **Note:** The subscription orphan records (account_id pointing to non-existent accounts) are an intentional data quality issue seeded in the synthetic data. In a real pipeline, these would be flagged and routed to a data steward for resolution.

### Silver Layer In-Script Checks (`03_quality_checks.sql`)

The comprehensive quality check script covers 20+ checks across 5 categories:

| Category | Check IDs | What It Catches |
|----------|-----------|-----------------|
| **1. Null/Missing** | CHK_1.1–1.4 | NULL company names, orphan subscriptions, zero amounts |
| **2. Duplicates** | CHK_2.1–2.4 | Duplicate PKs (should all pass after dedup), duplicate emails (warning) |
| **3. Referential Integrity** | CHK_3.1–3.5 | Orphan records across all FK relationships |
| **4. Domain/Range** | CHK_4.1–4.6 | Invalid status values, negative amounts, out-of-range scores |
| **5. Consistency** | CHK_5.1–5.5 | End date before start date, status/date mismatches, out-of-range dates |

### Gold Layer Tests

| Script | Purpose | Expected |
|--------|---------|----------|
| `test_gold_orphan_keys.sql` | Validates fact FK → dimension integrity | PASS for all 3 dimensions |
| `test_gold_aggregation.sql` | Cross-validates revenue totals between silver and gold | PASS or WARNING (minor variance acceptable due to join filtering) |

---

## Data Quality Issues by Design

These issues were intentionally seeded in the synthetic data to exercise the cleaning pipeline:

| Issue | Source | How It's Handled |
|-------|--------|-----------------|
| Mixed date formats (`YYYY-MM-DD`, `MM/DD/YYYY`, etc.) | All date columns | `TRY_CONVERT(DATE, ...)` in silver transform |
| Inconsistent casing (`starter`/`STARTER`/`Starter`) | plan_code, status | `UPPER()`/`LOWER()` standardization |
| Country name variants (`US`/`USA`/`United States`) | crm_accounts.country | `CASE WHEN UPPER(...) IN (...)` mapping |
| Boolean variants (`Y`/`N`/`yes`/`no`/`1`/`0`/`true`/`false`) | crm_accounts.is_active | `CASE WHEN LOWER(...) IN (...)` → BIT |
| ~5 duplicate invoice IDs | erp_invoices | `ROW_NUMBER()` dedup in silver |
| ~2% NULL company names | crm_accounts | Preserved as NULL; flagged in DQ checks |
| ~1% orphan account_ids (non-existent) | erp_subscriptions | Loaded with NULL account_id; flagged in DQ checks |
| ~0.5% negative API call counts | erp_usage_metrics | `ABS()` correction in silver |
| ~3% out-of-range satisfaction scores (0, -1, 6, 7, 10) | crm_support_tickets | Clamped to 1-5 range; out-of-range → NULL |
| ~3% duplicate emails | crm_contacts | Flagged as WARNING in DQ checks (not an error per se) |

---

## How to Run All Tests

```sql
-- In SSMS, execute each test script and review the result sets:
-- 1. tests/test_bronze_row_counts.sql
-- 2. tests/test_silver_nulls.sql
-- 3. tests/test_silver_duplicates.sql
-- 4. tests/test_silver_referential.sql
-- 5. scripts/02_silver/03_quality_checks.sql  (comprehensive in-script checks)
-- 6. tests/test_gold_orphan_keys.sql
-- 7. tests/test_gold_aggregation.sql
```

Every check outputs a result set with:
- `check_id` or `column_checked` — identifies the test
- `violations` or `null_count` — count of issues found
- `status` — `PASS`, `FAIL`, or `WARNING`
