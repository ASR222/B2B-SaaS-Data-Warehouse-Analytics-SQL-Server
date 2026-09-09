# Star Schema Design

This diagram represents the core Kimball dimensional modeling design (Star Schema) employed in the Gold layer of the NovaCRM Analytics Data Warehouse. It uses the `fact_subscription_events` table as the central point linking all dimensional context.

```mermaid
classDiagram
    class fact_subscription_events {
        +int event_id [PK]
        +int customer_key [FK]
        +int plan_key [FK]
        +int date_key [FK]
        +nvarchar event_type
        +decimal mrr_amount
        +decimal mrr_change
        +decimal invoice_amount
        +int api_calls_monthly
        +int active_users_avg
    }
    
    class dim_customer {
        +int customer_key [PK]
        +int account_id [Natural Key]
        +nvarchar company_name
        +nvarchar industry
        +nvarchar country
        +bit is_active
        +datetime effective_date
        +datetime expiry_date
    }

    class dim_plan {
        +int plan_key [PK]
        +nvarchar plan_code [Natural Key]
        +nvarchar plan_name
        +nvarchar plan_tier
        +decimal list_price
    }

    class dim_date {
        +int date_key [PK]
        +date full_date
        +int month_number
        +int year
        +nvarchar fiscal_quarter
    }

    dim_customer "1" -- "*" fact_subscription_events : Contains
    dim_plan "1" -- "*" fact_subscription_events : Defines
    dim_date "1" -- "*" fact_subscription_events : Happens in
```

### Design Principles Used:
1. **Surrogate Keys**: Ensure data independence from operational source system keys and allows storing historical data (SCD).
2. **Conformed Dimensions**: `dim_date` handles logic for financial and calendar years across the organization.
3. **Monthly Snapshot / Event Grain**: The fact table rolls up daily data to a monthly event grain suitable for computing SaaS metrics (MRR, Churn) effectively.
