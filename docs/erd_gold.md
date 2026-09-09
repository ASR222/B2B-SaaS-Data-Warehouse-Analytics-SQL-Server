# Gold Layer ERD

The Gold layer uses dimensional modeling (star schema) for high-performance analytical queries. The fact table tracks monthly subscription events, joining with standardized dimension tables (`dim_customer`, `dim_plan`, `dim_date`) that manage historical context (SCD infrastructure).

```mermaid
erDiagram
    fact_subscription_events }o--|| dim_customer : "customer_key"
    fact_subscription_events }o--|| dim_plan : "plan_key"
    fact_subscription_events }o--|| dim_date : "date_key"

    dim_customer {
        int customer_key PK "Surrogate key"
        int account_id "Natural key (business key)"
        nvarchar company_name
        nvarchar industry
        nvarchar company_size
        nvarchar country
        nvarchar region
        nvarchar acquisition_channel
        date signup_date
        nvarchar account_owner
        bit is_active
        int total_contacts "Pre-aggregated"
        int open_tickets "Pre-aggregated"
        decimal avg_satisfaction "Pre-aggregated"
        datetime effective_date "SCD metadata"
        datetime expiry_date "SCD metadata (9999-12-31 if current)"
        bit is_current "SCD flag"
    }
    dim_plan {
        int plan_key PK "Surrogate key"
        nvarchar plan_code "Natural key"
        nvarchar plan_name "Derived: STARTER→Starter Plan"
        nvarchar plan_tier "Derived: basic/professional/enterprise"
        decimal list_price "Reference price for the tier"
        nvarchar billing_cycle
        datetime effective_date
        datetime expiry_date
        bit is_current
    }
    dim_date {
        int date_key PK "YYYYMMDD integer"
        date full_date
        int day_of_month
        int day_of_week
        nvarchar day_name
        int week_of_year
        int month_number
        nvarchar month_name
        int quarter
        int year
        bit is_weekend
        bit is_month_end
        nvarchar fiscal_quarter "Maps calendar to fiscal"
        int fiscal_year
    }
    fact_subscription_events {
        int event_id PK "Surrogate key"
        int customer_key FK
        int plan_key FK
        int date_key FK
        nvarchar event_type "new, renewal, upgrade, downgrade, churn"
        decimal mrr_amount "MRR at time of event"
        decimal mrr_change "Delta vs. previous MRR for this sub"
        decimal invoice_amount "Sum of invoices in that month"
        decimal tax_amount
        int api_calls_monthly "Aggregated usage"
        decimal storage_gb_avg "Avg daily storage that month"
        int active_users_avg "Avg DAU that month"
        int support_tickets_opened
        int support_tickets_resolved
        decimal avg_satisfaction
    }
```
