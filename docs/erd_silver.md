# Silver Layer ERD

The Silver layer enforces schema consistency, data types, and normalizes key business fields (like standardizing country names or fixing boolean flags). Referential integrity starts to take shape here, even if strict Foreign Key constraints are omitted to handle 'orphan' record logging gracefully.

```mermaid
erDiagram
    silver_accounts ||--o{ silver_contacts : "has"
    silver_accounts ||--o{ silver_subscriptions : "holds"
    silver_accounts ||--o{ silver_support_tickets : "raises"
    silver_subscriptions ||--o{ silver_invoices : "generates"
    silver_subscriptions ||--o{ silver_usage_metrics : "tracks"

    silver_accounts {
        int account_id PK
        nvarchar company_name
        nvarchar industry
        nvarchar company_size
        nvarchar country "Standardized (US→United States)"
        nvarchar region
        nvarchar acquisition_channel
        date signup_date "Parsed from mixed formats"
        nvarchar account_owner
        bit is_active "Normalized to 0/1"
        datetime dwh_load_ts
    }
    silver_subscriptions {
        int subscription_id PK
        int account_id FK
        nvarchar plan_code "UPPER-cased"
        decimal mrr_amount
        char currency_code
        date start_date "Parsed"
        date end_date "Nullable"
        nvarchar status "LOWER-cased"
        nvarchar billing_cycle
        datetime created_at
        datetime dwh_load_ts
    }
    silver_invoices {
        int invoice_id PK
        int subscription_id FK
        date invoice_date
        decimal amount
        decimal tax_amount
        nvarchar payment_status
        date payment_date
        datetime created_at
        datetime dwh_load_ts
    }
    silver_usage_metrics {
        int metric_id PK
        int subscription_id FK
        date metric_date
        int api_calls
        decimal storage_gb
        int active_users
        datetime dwh_load_ts
    }
    silver_contacts {
        int contact_id PK
        int account_id FK
        nvarchar first_name
        nvarchar last_name
        nvarchar email
        nvarchar phone
        nvarchar role
        bit is_primary
        datetime dwh_load_ts
    }
    silver_support_tickets {
        int ticket_id PK
        int account_id FK
        int contact_id FK
        nvarchar category
        nvarchar priority
        nvarchar status
        datetime created_date
        datetime resolved_date
        int satisfaction "Clamped to 1-5 range"
        datetime dwh_load_ts
    }
```
