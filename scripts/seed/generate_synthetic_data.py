"""
generate_synthetic_data.py
--------------------------
Creates 6 synthetic CSV files simulating source data from a B2B SaaS company's
ERP and CRM systems. Intentionally introduces data quality issues (mixed date
formats, inconsistent casing, orphan FKs, out-of-range values) so the silver
layer has real cleaning work to do.

Target scale: ~2K accounts, ~2K subscriptions, ~50K invoices,
              ~100K usage rows, ~4K contacts, ~8K support tickets.

Usage:
    python generate_synthetic_data.py
    (Outputs to ../datasets/ relative to this script)
"""

import os
import random
import string
from datetime import datetime, timedelta
import pandas as pd
import numpy as np

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SEED = 42
random.seed(SEED)
np.random.seed(SEED)

NUM_ACCOUNTS = 2000
NUM_SUBSCRIPTIONS = 2000  # 1:1 with accounts for simplicity
NUM_INVOICES = 50000
NUM_USAGE_ROWS = 100000
NUM_CONTACTS = 4000
NUM_SUPPORT_TICKETS = 8000

DATE_START = datetime(2023, 1, 1)
DATE_END = datetime(2025, 12, 31)

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "datasets")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
INDUSTRIES = [
    "Technology", "Healthcare", "Finance", "Manufacturing", "Retail",
    "Education", "Media", "Real Estate", "Logistics", "Energy",
    "Consulting", "Legal", "Non-Profit", "Government", "Hospitality"
]

COMPANY_SIZES = ["1-50", "51-200", "201-1000", "1000+"]

# Intentionally messy country representations for cleaning exercise
COUNTRIES_CLEAN = {
    "United States": ["US", "United States", "USA", "united states", "U.S.A."],
    "United Kingdom": ["UK", "United Kingdom", "GB", "united kingdom"],
    "Canada": ["Canada", "CA", "canada"],
    "Germany": ["Germany", "DE", "germany"],
    "Australia": ["Australia", "AU", "australia"],
    "France": ["France", "FR"],
    "India": ["India", "IN"],
    "Brazil": ["Brazil", "BR"],
    "Japan": ["Japan", "JP"],
    "Singapore": ["Singapore", "SG"],
}

REGIONS = {
    "United States": "North America",
    "Canada": "North America",
    "United Kingdom": "Europe",
    "Germany": "Europe",
    "France": "Europe",
    "Australia": "Asia-Pacific",
    "India": "Asia-Pacific",
    "Japan": "Asia-Pacific",
    "Singapore": "Asia-Pacific",
    "Brazil": "South America",
}

ACQUISITION_CHANNELS = ["organic", "paid", "referral", "partner"]
PLAN_CODES = ["STARTER", "PRO", "ENTERPRISE"]
PLAN_MRR = {"STARTER": 49.0, "PRO": 149.0, "ENTERPRISE": 499.0}
BILLING_CYCLES = ["monthly", "annual"]
STATUSES_SUB = ["active", "churned", "expired", "trial"]
PAYMENT_STATUSES = ["paid", "pending", "failed", "refunded"]
TICKET_CATEGORIES = ["billing", "technical", "feature_request"]
TICKET_PRIORITIES = ["low", "medium", "high", "critical"]
TICKET_STATUSES = ["open", "in_progress", "resolved", "closed"]
CONTACT_ROLES = ["Admin", "Billing", "Technical", "Executive", "End User"]

FIRST_NAMES = [
    "James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael",
    "Linda", "David", "Elizabeth", "William", "Barbara", "Richard", "Susan",
    "Joseph", "Jessica", "Thomas", "Sarah", "Charles", "Karen", "Arun",
    "Priya", "Wei", "Yuki", "Hans", "Sophie", "Carlos", "Fatima", "Omar", "Liam"
]

LAST_NAMES = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller",
    "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez",
    "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
    "Patel", "Kumar", "Chen", "Tanaka", "Mueller", "Dubois", "Silva", "Ahmed"
]

COMPANY_PREFIXES = [
    "Nova", "Apex", "Vertex", "Nexus", "Quantum", "Stellar", "Pulse",
    "Zenith", "Orbit", "Flux", "Catalyst", "Vanguard", "Elevate", "Forge",
    "Beacon", "Summit", "Stratos", "Ignite", "Nimbus", "Helios"
]

COMPANY_SUFFIXES = [
    "Solutions", "Technologies", "Systems", "Labs", "Group", "Corp",
    "Industries", "Dynamics", "Analytics", "Partners", "Ventures",
    "Innovations", "Digital", "Consulting", "Software"
]

SALES_REPS = [f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}" for _ in range(20)]


def random_date(start: datetime, end: datetime) -> datetime:
    """Generate a random datetime between start and end."""
    delta = end - start
    random_days = random.randint(0, delta.days)
    return start + timedelta(days=random_days)


def messy_date(dt: datetime) -> str:
    """Return a date string in one of several formats to simulate dirty data."""
    fmt = random.choice([
        "%Y-%m-%d",       # 2023-05-15
        "%m/%d/%Y",       # 05/15/2023
        "%d-%b-%Y",       # 15-May-2023
        "%Y/%m/%d",       # 2023/05/15
        "%m-%d-%Y",       # 05-15-2023
    ])
    return dt.strftime(fmt)


def messy_case(value: str) -> str:
    """Randomly alter casing to simulate inconsistent source data."""
    choice = random.random()
    if choice < 0.4:
        return value.lower()
    elif choice < 0.7:
        return value.upper()
    elif choice < 0.9:
        return value.title()
    else:
        return value


def messy_country(canonical: str) -> str:
    """Return a randomly chosen messy variant of a country name."""
    variants = COUNTRIES_CLEAN.get(canonical, [canonical])
    return random.choice(variants)


# ---------------------------------------------------------------------------
# Generate: CRM Accounts
# ---------------------------------------------------------------------------
def generate_accounts() -> pd.DataFrame:
    print("Generating crm_accounts.csv ...")
    rows = []
    used_names = set()

    for i in range(1, NUM_ACCOUNTS + 1):
        # Generate unique company name
        while True:
            name = f"{random.choice(COMPANY_PREFIXES)} {random.choice(COMPANY_SUFFIXES)}"
            if i > 200:  # Add number suffix for uniqueness after initial batch
                name = f"{name} {random.randint(1, 999)}"
            if name not in used_names:
                used_names.add(name)
                break

        country_canonical = random.choice(list(COUNTRIES_CLEAN.keys()))
        signup = random_date(DATE_START - timedelta(days=365), DATE_END - timedelta(days=90))

        # Messy is_active values (intentional DQ issue)
        is_active_variants = ["Y", "N", "yes", "no", "1", "0", "true", "false", "Yes", "No"]
        active = random.choice(is_active_variants) if random.random() < 0.15 else random.choice(["Y", "N"])

        rows.append({
            "account_id": i,
            "company_name": name,
            "industry": random.choice(INDUSTRIES),
            "company_size": random.choice(COMPANY_SIZES),
            "country": messy_country(country_canonical),
            "region": REGIONS.get(country_canonical, "Other"),
            "acquisition_channel": random.choice(ACQUISITION_CHANNELS),
            "signup_date": messy_date(signup),
            "account_owner": random.choice(SALES_REPS),
            "is_active": active,
        })

    df = pd.DataFrame(rows)

    # Introduce ~2% NULL company_name for DQ testing
    null_mask = np.random.random(len(df)) < 0.02
    df.loc[null_mask, "company_name"] = np.nan

    return df


# ---------------------------------------------------------------------------
# Generate: ERP Subscriptions
# ---------------------------------------------------------------------------
def generate_subscriptions(accounts_df: pd.DataFrame) -> pd.DataFrame:
    print("Generating erp_subscriptions.csv ...")
    rows = []

    for i in range(1, NUM_SUBSCRIPTIONS + 1):
        account_id = i if i <= NUM_ACCOUNTS else random.randint(1, NUM_ACCOUNTS)

        plan = random.choice(PLAN_CODES)
        mrr = PLAN_MRR[plan]
        # Add some variance to MRR (discounts, etc.)
        mrr = round(mrr * random.uniform(0.8, 1.2), 2)

        start = random_date(DATE_START, DATE_END - timedelta(days=180))

        # ~25% churned, ~10% expired, ~5% trial
        status_roll = random.random()
        if status_roll < 0.60:
            status = "active"
            end_date = None
        elif status_roll < 0.85:
            status = "churned"
            end_date = messy_date(start + timedelta(days=random.randint(30, 730)))
        elif status_roll < 0.95:
            status = "expired"
            end_date = messy_date(start + timedelta(days=random.randint(365, 1095)))
        else:
            status = "trial"
            end_date = messy_date(start + timedelta(days=14))

        rows.append({
            "subscription_id": i,
            "account_id": account_id,
            "plan_code": messy_case(plan),
            "mrr_amount": mrr,
            "currency_code": random.choice(["USD", "EUR", "GBP"]) if random.random() < 0.1 else "USD",
            "start_date": messy_date(start),
            "end_date": end_date,
            "status": messy_case(status),
            "billing_cycle": random.choice(BILLING_CYCLES),
            "created_at": (start - timedelta(days=random.randint(0, 5))).strftime("%Y-%m-%d %H:%M:%S"),
        })

    df = pd.DataFrame(rows)

    # ~1% orphan account_id (point to non-existent accounts)
    orphan_mask = np.random.random(len(df)) < 0.01
    df.loc[orphan_mask, "account_id"] = np.random.randint(NUM_ACCOUNTS + 100, NUM_ACCOUNTS + 500, orphan_mask.sum())

    # ~1% NULL account_id
    null_mask = np.random.random(len(df)) < 0.01
    df.loc[null_mask, "account_id"] = np.nan

    return df


# ---------------------------------------------------------------------------
# Generate: ERP Invoices
# ---------------------------------------------------------------------------
def generate_invoices(subs_df: pd.DataFrame) -> pd.DataFrame:
    print("Generating erp_invoices.csv ...")
    rows = []
    invoice_id = 1

    # Distribute invoices across subscriptions
    invoices_per_sub = NUM_INVOICES // NUM_SUBSCRIPTIONS  # ~25 each

    for _, sub in subs_df.iterrows():
        sub_id = sub["subscription_id"]
        # Parse start_date (try multiple formats)
        try:
            start = pd.to_datetime(sub["start_date"])
        except Exception:
            start = DATE_START

        num_invoices = random.randint(max(1, invoices_per_sub - 10), invoices_per_sub + 10)

        for j in range(num_invoices):
            inv_date = start + timedelta(days=30 * j)
            if inv_date > DATE_END:
                break

            amount = float(sub["mrr_amount"]) if pd.notna(sub["mrr_amount"]) else 99.0
            tax = round(amount * random.uniform(0.05, 0.15), 2)

            pay_status = random.choices(
                PAYMENT_STATUSES,
                weights=[0.85, 0.07, 0.05, 0.03],
                k=1
            )[0]

            pay_date = None
            if pay_status == "paid":
                pay_date = messy_date(inv_date + timedelta(days=random.randint(0, 15)))
            elif pay_status == "refunded":
                pay_date = messy_date(inv_date + timedelta(days=random.randint(5, 30)))

            rows.append({
                "invoice_id": invoice_id,
                "subscription_id": sub_id,
                "invoice_date": messy_date(inv_date),
                "amount": round(amount, 2),
                "tax_amount": tax,
                "payment_status": pay_status,
                "payment_date": pay_date,
                "created_at": inv_date.strftime("%Y-%m-%d %H:%M:%S"),
            })
            invoice_id += 1

    df = pd.DataFrame(rows)

    # Introduce ~5 duplicate invoice_ids (DQ issue for dedup testing)
    if len(df) > 100:
        dup_indices = np.random.choice(df.index, size=5, replace=False)
        dups = df.loc[dup_indices].copy()
        # Slightly modify amounts to simulate real-world duplicate entries
        dups["amount"] = dups["amount"] + np.random.uniform(-0.5, 0.5, len(dups)).round(2)
        df = pd.concat([df, dups], ignore_index=True)

    return df


# ---------------------------------------------------------------------------
# Generate: ERP Usage Metrics
# ---------------------------------------------------------------------------
def generate_usage_metrics(subs_df: pd.DataFrame) -> pd.DataFrame:
    print("Generating erp_usage_metrics.csv ...")
    rows = []
    metric_id = 1

    # Select a subset of subscriptions to generate usage data for
    sample_subs = subs_df.sample(n=min(800, len(subs_df)), random_state=SEED)

    for _, sub in sample_subs.iterrows():
        sub_id = sub["subscription_id"]
        try:
            start = pd.to_datetime(sub["start_date"])
        except Exception:
            start = DATE_START

        plan = str(sub["plan_code"]).upper()
        # Base usage scales with plan tier
        base_calls = {"STARTER": 100, "PRO": 500, "ENTERPRISE": 2000}.get(plan, 300)
        base_storage = {"STARTER": 1.0, "PRO": 5.0, "ENTERPRISE": 20.0}.get(plan, 3.0)
        base_users = {"STARTER": 3, "PRO": 15, "ENTERPRISE": 50}.get(plan, 10)

        # Generate daily metrics for a random window
        num_days = random.randint(60, min(365, max(61, (DATE_END - start).days)))
        for d in range(0, num_days, random.choice([1, 1, 1, 3, 7])):  # Some daily, some sparse
            metric_date = start + timedelta(days=d)
            if metric_date > DATE_END:
                break

            rows.append({
                "metric_id": metric_id,
                "subscription_id": sub_id,
                "metric_date": metric_date.strftime("%Y-%m-%d"),
                "api_calls": max(0, int(base_calls * random.uniform(0.3, 2.5))),
                "storage_gb": round(max(0.01, base_storage * random.uniform(0.5, 1.8)), 2),
                "active_users": max(1, int(base_users * random.uniform(0.2, 1.5))),
            })
            metric_id += 1

            if metric_id > NUM_USAGE_ROWS:
                break
        if metric_id > NUM_USAGE_ROWS:
            break

    # Introduce some negative values (DQ issue)
    df = pd.DataFrame(rows)
    neg_mask = np.random.random(len(df)) < 0.005
    df.loc[neg_mask, "api_calls"] = -abs(df.loc[neg_mask, "api_calls"])

    return df


# ---------------------------------------------------------------------------
# Generate: CRM Contacts
# ---------------------------------------------------------------------------
def generate_contacts() -> pd.DataFrame:
    print("Generating crm_contacts.csv ...")
    rows = []

    for i in range(1, NUM_CONTACTS + 1):
        # Each account gets ~2 contacts; distribute across accounts
        account_id = ((i - 1) // 2) + 1
        if account_id > NUM_ACCOUNTS:
            account_id = random.randint(1, NUM_ACCOUNTS)

        first = random.choice(FIRST_NAMES)
        last = random.choice(LAST_NAMES)

        # Various phone formats (DQ issue)
        phone_formats = [
            f"+1-{random.randint(200,999)}-{random.randint(100,999)}-{random.randint(1000,9999)}",
            f"({random.randint(200,999)}) {random.randint(100,999)}-{random.randint(1000,9999)}",
            f"{random.randint(200,999)}.{random.randint(100,999)}.{random.randint(1000,9999)}",
            f"+44 {random.randint(1000,9999)} {random.randint(100000,999999)}",
            "",  # Missing phone
        ]

        rows.append({
            "contact_id": i,
            "account_id": account_id,
            "first_name": first,
            "last_name": last,
            "email": f"{first.lower()}.{last.lower()}@company{account_id}.com",
            "phone": random.choice(phone_formats),
            "role": random.choice(CONTACT_ROLES),
            "is_primary": 1 if i % 2 == 1 else 0,  # First contact per account is primary
        })

    df = pd.DataFrame(rows)

    # ~3% duplicate emails (DQ issue)
    dup_mask = np.random.random(len(df)) < 0.03
    if dup_mask.sum() > 0:
        source_emails = df.loc[~dup_mask, "email"].sample(n=min(dup_mask.sum(), (~dup_mask).sum()), replace=True)
        df.loc[dup_mask, "email"] = source_emails.values[:dup_mask.sum()]

    return df


# ---------------------------------------------------------------------------
# Generate: CRM Support Tickets
# ---------------------------------------------------------------------------
def generate_support_tickets() -> pd.DataFrame:
    print("Generating crm_support_tickets.csv ...")
    rows = []

    for i in range(1, NUM_SUPPORT_TICKETS + 1):
        account_id = random.randint(1, NUM_ACCOUNTS)
        # Contact might not belong to the right account (intentional FK issue ~2%)
        if random.random() < 0.02:
            contact_id = random.randint(1, NUM_CONTACTS)
        else:
            # Pick a contact that belongs to this account
            contact_id = (account_id - 1) * 2 + random.choice([1, 2])
            contact_id = min(contact_id, NUM_CONTACTS)

        created = random_date(DATE_START, DATE_END)
        status = random.choice(TICKET_STATUSES)

        resolved = None
        if status in ("resolved", "closed"):
            resolved = created + timedelta(hours=random.randint(1, 720))

        # Satisfaction: mostly 1-5, but ~3% have out-of-range values (DQ issue)
        if random.random() < 0.03:
            satisfaction = random.choice([0, -1, 6, 7, 10, None])
        elif status in ("resolved", "closed") and random.random() < 0.7:
            satisfaction = random.randint(1, 5)
        else:
            satisfaction = None

        rows.append({
            "ticket_id": i,
            "account_id": account_id,
            "contact_id": contact_id,
            "category": random.choice(TICKET_CATEGORIES),
            "priority": random.choice(TICKET_PRIORITIES),
            "status": status,
            "created_date": created.strftime("%Y-%m-%d %H:%M:%S"),
            "resolved_date": resolved.strftime("%Y-%m-%d %H:%M:%S") if resolved else None,
            "satisfaction": satisfaction,
        })

    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Generate in dependency order
    accounts_df = generate_accounts()
    accounts_df.to_csv(os.path.join(OUTPUT_DIR, "crm_accounts.csv"), index=False)
    print(f"  -> {len(accounts_df)} rows written")

    contacts_df = generate_contacts()
    contacts_df.to_csv(os.path.join(OUTPUT_DIR, "crm_contacts.csv"), index=False)
    print(f"  -> {len(contacts_df)} rows written")

    subs_df = generate_subscriptions(accounts_df)
    subs_df.to_csv(os.path.join(OUTPUT_DIR, "erp_subscriptions.csv"), index=False)
    print(f"  -> {len(subs_df)} rows written")

    invoices_df = generate_invoices(subs_df)
    invoices_df.to_csv(os.path.join(OUTPUT_DIR, "erp_invoices.csv"), index=False)
    print(f"  -> {len(invoices_df)} rows written")

    usage_df = generate_usage_metrics(subs_df)
    usage_df.to_csv(os.path.join(OUTPUT_DIR, "erp_usage_metrics.csv"), index=False)
    print(f"  -> {len(usage_df)} rows written")

    tickets_df = generate_support_tickets()
    tickets_df.to_csv(os.path.join(OUTPUT_DIR, "crm_support_tickets.csv"), index=False)
    print(f"  -> {len(tickets_df)} rows written")

    print("\nAll 6 CSV files generated successfully in:", OUTPUT_DIR)


if __name__ == "__main__":
    main()
