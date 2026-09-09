# Bronze Layer ERD

The Bronze layer represents the raw landing zone. Data here mirrors the source CSV structure identically. All fields are stored as flexible character types (e.g., `VARCHAR`, `NVARCHAR`) to ensure robust ingestion regardless of source data quality issues like mixed date formats or unexpected characters.

```mermaid
erDiagram
    bronze_erp_subscriptions {
        varchar subscription_id
        varchar account_id
        varchar plan_code
        varchar mrr_amount
        varchar currency_code
        varchar start_date
        varchar end_date
        varchar status
        varchar billing_cycle
        varchar created_at
        datetime dwh_load_ts "ETL metadata"
    }
    bronze_erp_invoices {
        varchar invoice_id
        varchar subscription_id
        varchar invoice_date
        varchar amount
        varchar tax_amount
        varchar payment_status
        varchar payment_date
        varchar created_at
        datetime dwh_load_ts
    }
    bronze_erp_usage_metrics {
        varchar metric_id
        varchar subscription_id
        varchar metric_date
        varchar api_calls
        varchar storage_gb
        varchar active_users
        datetime dwh_load_ts
    }
    bronze_crm_accounts {
        varchar account_id
        varchar company_name
        varchar industry
        varchar company_size
        varchar country
        varchar region
        varchar acquisition_channel
        varchar signup_date
        varchar account_owner
        varchar is_active
        datetime dwh_load_ts
    }
    bronze_crm_contacts {
        varchar contact_id
        varchar account_id
        varchar first_name
        varchar last_name
        varchar email
        varchar phone
        varchar role
        varchar is_primary
        datetime dwh_load_ts
    }
    bronze_crm_support_tickets {
        varchar ticket_id
        varchar account_id
        varchar contact_id
        varchar category
        varchar priority
        varchar status
        varchar created_date
        varchar resolved_date
        varchar satisfaction
        datetime dwh_load_ts
    }
```
