# Snowflake Data Pipeline with dbt

A production-grade data pipeline built on Snowflake using dbt for transformations, GitHub Actions for CI/CD, and Snowflake Tasks for scheduling. The pipeline processes Tasty Bytes food truck operational data through a multi-layer architecture from raw ingestion to business-ready analytics.

## Architecture

```
                        ┌─────────────────────────────────────────────────┐
                        │              TASTY_BYTES_DBT_DB                  │
                        │                                                 │
  S3 (source data)      │   RAW Schema        DEV / PROD Schema          │
  ──────────────────▶   │   ┌──────────┐      ┌──────────────────────┐   │
                        │   │ COUNTRY   │      │ Staging (views)      │   │
                        │   │ FRANCHISE │──▶   │  raw_pos_*           │   │
                        │   │ LOCATION  │      │  raw_customer_*      │   │
                        │   │ MENU      │      └──────────┬───────────┘   │
                        │   │ TRUCK     │                 │               │
                        │   │ ORDER_*   │      ┌──────────▼───────────┐   │
                        │   │ CUSTOMER_ │      │ Marts (tables)       │   │
                        │   │  LOYALTY  │      │  orders              │   │
                        │   └──────────┘      │  customer_loyalty_   │   │
                        │                      │    metrics           │   │
                        │                      │  sales_data_by_truck │   │
                        │                      │  sales_metrics_by_   │   │
                        │                      │    location (Python) │   │
                        │                      └──────────────────────┘   │
                        └─────────────────────────────────────────────────┘
```

## Project Structure

```
.
├── .github/workflows/
│   ├── incoming_pr.yml                # CI: test on PR to main, deploy on push to dev
│   └── pr_merged.yml                  # CD: deploy to production on merge to main
├── tasty_bytes_dbt_demo/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   ├── schedules.sql                  # Snowflake Task definitions
│   ├── macros/
│   │   └── generate_schema_name.sql   # Multi-environment schema routing
│   ├── models/
│   │   ├── staging/                   # Views — clean and rename raw columns
│   │   │   ├── __sources.yml          # Source definitions with 50+ data tests
│   │   │   ├── raw_pos_country.sql
│   │   │   ├── raw_pos_franchise.sql
│   │   │   ├── raw_pos_location.sql
│   │   │   ├── raw_pos_menu.sql
│   │   │   ├── raw_pos_order_detail.sql
│   │   │   ├── raw_pos_order_header.sql
│   │   │   ├── raw_pos_truck.sql
│   │   │   └── raw_customer_customer_loyalty.sql
│   │   └── marts/                     # Tables — aggregated business metrics
│   │       ├── orders.sql
│   │       ├── customer_loyalty_metrics.sql
│   │       ├── sales_data_by_truck.sql
│   │       └── sales_metrics_by_location.py   # Python model
│   ├── tests/generic/
│   │   └── test_is_positive_amount.sql
│   └── setup/
│       ├── tasty_bytes_setup.sql       # Environment + source data setup
│       └── ci_cd_setup.sql            # GitHub Actions OIDC service user
├── .gitignore
└── LICENSE
```

## Data Model

### Source Layer (`RAW` schema)

8 source tables loaded from S3:

| Table | Description |
|-------|-------------|
| `COUNTRY` | Country and city reference data |
| `FRANCHISE` | Franchise ownership records |
| `LOCATION` | Business locations with Placekeys |
| `MENU` | Food truck menu items and pricing |
| `TRUCK` | Food truck fleet data |
| `ORDER_HEADER` | Order transactions |
| `ORDER_DETAIL` | Order line items |
| `CUSTOMER_LOYALTY` | Customer loyalty program data |

### Staging Layer (views)

8 staging views that clean, rename, and standardize raw columns. Materialized as **views** for zero storage cost.

### Marts Layer (tables)

| Model | Type | Description |
|-------|------|-------------|
| `orders` | SQL | Joined order data with truck, location, and menu details |
| `customer_loyalty_metrics` | SQL | Aggregated customer spending and loyalty insights |
| `sales_data_by_truck` | SQL | Revenue and order metrics per truck |
| `sales_metrics_by_location` | Python | Location-level sales analytics using Snowpark |

### Data Quality

50+ data tests defined in `__sources.yml`:
- **not_null** — enforced on all primary keys and critical fields
- **unique** — on primary keys (LOCATION_ID, MENU_ID, TRUCK_ID)
- **relationships** — foreign key integrity (ORDER_DETAIL → ORDER_HEADER, TRUCK → FRANCHISE, ORDER_HEADER → LOCATION, TRUCK)
- **is_positive_amount** — custom generic test for monetary and quantity fields

## Environments

| Target | Schema | Warehouse | Purpose |
|--------|--------|-----------|---------|
| `dev` | `TASTY_BYTES_DBT_DB.DEV` | `TASTY_BYTES_DBT_WH` | Development and testing |
| `prod` | `TASTY_BYTES_DBT_DB.PROD` | `TASTY_BYTES_DBT_WH` | Production analytics |

The `generate_schema_name` macro routes models to the correct schema based on the active target. When a custom schema is specified, it uses the custom name directly; otherwise, it defaults to the target schema (`dev` or `prod`).

## CI/CD Pipeline

### Branch Strategy

```
feature branch ──▶ push to dev ──▶ deploy + test in DEV
                       │
                   open PR to main ──▶ test only (no deploy)
                       │
                   merge to main ──▶ deploy to PROD
```

### `incoming_pr.yml` — Dev CI/CD

| Trigger | Action |
|---------|--------|
| Push to `dev` | Deploy dbt project to dev + build and test |
| PR to `main` | Build and test only (no deploy) |

Steps:
1. Install Snowflake CLI with OIDC authentication
2. Test Snowflake connectivity
3. Deploy dbt project object (dev push only)
4. `dbt build --target dev` — builds all models and runs tests

### `pr_merged.yml` — Production Deployment

Triggers on merge to `main`:
1. Install Snowflake CLI with OIDC authentication
2. Deploy production dbt project object with `--default-target prod`
3. Optionally run `schedules.sql` to create/update Snowflake Tasks

### Authentication

CI/CD uses **OIDC** (OpenID Connect) — no long-lived credentials stored in GitHub. The `ci_cd_setup.sql` script creates a Snowflake service user with OIDC workload identity tied to the GitHub repo and environment.

## Scheduling

`schedules.sql` defines two Snowflake Tasks for automated execution:

| Task | Schedule | Description |
|------|----------|-------------|
| `run_tasty_bytes_subset` | Every 12 hours | Builds a priority subset of models |
| `run_tasty_bytes_full` | After subset completes | Full DAG build with all models and tests |

Tasks run in sequence — the full build waits for the subset to complete.

## Snowflake Objects

| Object | Type | Location |
|--------|------|----------|
| Database | Database | `TASTY_BYTES_DBT_DB` |
| Warehouse | Warehouse | `TASTY_BYTES_DBT_WH` |
| Source data | Tables | `TASTY_BYTES_DBT_DB.RAW` |
| Dev models | Views/Tables | `TASTY_BYTES_DBT_DB.DEV` |
| Prod models | Views/Tables | `TASTY_BYTES_DBT_DB.PROD` |
| Dev project | DBT PROJECT | `TASTY_BYTES_DBT_DB.DEV.TASTY_BYTES_V2` |
| Prod project | DBT PROJECT | `TASTY_BYTES_DBT_DB.PROD.TASTY_BYTES_V2` |

## Setup

### 1. Snowflake Environment

Run `tasty_bytes_dbt_demo/setup/tasty_bytes_setup.sql` in a Snowflake worksheet. This creates the warehouse, database, schemas, GitHub integration, and loads source data from S3.

### 2. CI/CD Service User

Run `tasty_bytes_dbt_demo/setup/ci_cd_setup.sql` after updating the OIDC subject to match your GitHub repo:

```sql
SUBJECT = 'repo:<your_org>/<your_repo>:environment:prod'
```

### 3. GitHub Configuration

Set the following in your repo (Settings → Secrets and Variables → Actions):

| Type | Key | Value |
|------|-----|-------|
| Secret | `SNOWFLAKE_ACCOUNT` | Your Snowflake account identifier |
| Variable | `SNOWFLAKE_DATABASE` | `TASTY_BYTES_DBT_DB` |
| Variable | `SNOWFLAKE_SCHEMA` | `DEV` |

Create a `prod` environment (Settings → Environments).

### 4. Workspace Development

Connect a Snowsight workspace to your GitHub fork. Run dbt commands directly:

```bash
dbt deps
dbt run --target dev
dbt test
dbt build
```

## References

- [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [CI/CD for dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/tutorials/dbt-projects-on-snowflake-ci-cd-tutorial)
- [Snowflake Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
