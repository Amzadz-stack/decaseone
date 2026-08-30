# Trade Data Engineering Pipeline

## Architecture

```
┌────────────────┐     ┌──────────────────────┐     ┌──────────────────────┐
│  DATA GEN      │ PUT │  TRADE_EVENTS_RAW    │ CDC │  SP: PROCESS_TRADE   │
│ (Python/manual)│────▶│  (landing table)     │────▶│  _EVENTS()           │
│                │     │  + STREAM            │     │  (5 business rules)  │
└────────────────┘     └──────────────────────┘     └──────────┬───────────┘
                                                               │
                       ┌───────────────────────────────────────┼──────────┐
                       │                                       │          │
                       ▼                                       ▼          ▼
            ┌─────────────────────┐             ┌──────────────────────────┐
            │  TRADES_VALID       │             │  TRADES_REJECTED         │
            │  (active trade book)│             │  (compliance audit log)  │
            └─────────────────────┘             └──────────────────────────┘
```

**Two parallel execution paths:**
- **Real-time (Snowflake native):** Stream → Task → Stored Procedure → MERGE
- **Batch (DBT):** `dbt run` → staging view → classification → incremental tables

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Ingestion | Snowflake Internal Stage + COPY INTO |
| Processing | Snowflake Stored Procedures + Streams |
| Transformation | DBT (dbt-snowflake adapter v1.9) |
| Orchestration | Snowflake Tasks (5-min DAG + daily cron) |
| Alerting | Snowflake Alerts + Email Notification Integration |
| Storage | Snowflake (xx.xx) |
| CI/CD | GitHub Actions (lint → test → deploy) |
| Data Generation | Python (generate_trades.py) |

---

## Repository Structure

```
trade-pipeline/
├── .github/
│   └── workflows/
│       └── trade_pipeline_cicd.yml    # CI/CD: lint -> test -> deploy
├── dbt_project/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   └── models/
│       ├── sources.yml
│       ├── schema.yml
│       ├── staging/
│       │   └── stg_raw_trades.sql
│       ├── intermediate/
│       │   └── int_trade_classification.sql
│       └── marts/
│           ├── valid_trades.sql
│           └── rejected_trades.sql
├── terraform/
│   ├── .gitignore                    # Ignore .terraform/, *.tfstate*
│   ├── providers.tf                  # Snowflake provider config
│   ├── main.tf                       # Core terraform settings + backend
│   ├── variables.tf                  # Input variables
│   ├── outputs.tf                    # Output values
│   ├── snowflake.tf                  # All Snowflake resources
│   ├── terraform.tfvars.example      # Example values (committed)
│   └── README.md                     # Terraform usage guide
├── Case studies.sql                  # Master SQL (12 sections)
├── generate_trades.py                # Python trade data generator
├── ARCHITECTURE_DOCUMENT.md          # Technical architecture doc
└── README.md                         # Project documentation

---

## Setup & Execution Guide

### Prerequisites

- Snowflake account with role `US_SNOW_LLE_DEVELOPERS_RW_LG` (or equivalent)
- Warehouse: `DATA_TESTING_WH_XSMALL`
- Database: `xx`, Schema: `xx`
- Python 3.9+ (for data generator)
- dbt-snowflake (for DBT path)

### Step 1: Create Infrastructure

Run the DDL sections (1–3) from `Case studies.sql` in Snowflake:
- Creates tables: `TRADE_EVENTS_RAW`, `TRADES_VALID`, `TRADES_REJECTED`, `PIPELINE_RUN_LOG`
- Creates stage, file format, and stream

### Step 2: Create Stored Procedures

Run section 4–5 from `Case studies.sql`:
- `PROCESS_TRADE_EVENTS()` — core validation with all 5 business rules
- `LOAD_TRADES_FROM_STAGE()` — COPY INTO from internal stage
- `EXPIRE_STALE_TRADES()` — daily expiry sweep

### Step 3: Create Tasks (Orchestration)

Run section 6 from `Case studies.sql`:
- `TASK_LOAD_FROM_STAGE` — root task, every 5 minutes
- `TASK_PROCESS_TRADES` — child task, stream-triggered
- `TASK_EXPIRE_TRADES` — daily at midnight UTC

### Step 4: Create Alerts (Monitoring)

Run section 7 from `Case studies.sql`:
- Requires ACCOUNTADMIN to create the notification integration first
- 3 alerts: pipeline failure, high rejection rate, stalled pipeline

### Step 5: Generate Test Data

```bash
# Generate 500 trades and upload to Snowflake
python generate_trades.py --count 500 --upload

# Or generate locally only
python generate_trades.py --count 200 --output trades_batch.json
```

### Step 6: Run DBT (Alternative Path)

```bash
# Parse (syntax validation)
dbt parse --project-dir dbt_project

# Run models (creates DBT_TRADES_VALID, DBT_TRADES_REJECTED)
dbt run --project-dir dbt_project

# Run 22 schema tests
dbt test --project-dir dbt_project

# Full build (run + test)
dbt build --project-dir dbt_project
```

---

## Business Rules (Validation Logic)

| Rule | Description | Rejection Code |
|------|-------------|----------------|
| R1 | Reject trades with version lower than existing | `REJECT_VERSION_TOO_LOW` |
| R2 | Replace (UPSERT) trades with same version | N/A (accepted as update) |
| R3 | Reject trades with maturity date before today | `REJECT_MATURITY_IN_PAST` |
| R4 | Mark trades as EXPIRED if maturity has passed | N/A (status = EXPIRED) |
| R5 | Reject BOND trades with notional < 1,000 | `REJECT_BOND_NOTIONAL_TOO_LOW` |

All rejected trades are logged to `TRADES_REJECTED` with:
- Rejection code and human-readable reason
- Full original payload snapshot
- Timestamp of rejection

---

## Snowflake Objects Created

| Object | Type | Purpose |
|--------|------|---------|
| `TRADE_EVENTS_RAW` 				| Table       		| Raw landing table |
| `TRADES_VALID`				 	| Table       		| Active trade book |
| `TRADES_REJECTED` 				| Table       		| Rejection audit log |
| `PIPELINE_RUN_LOG` 				| Table       		| Run execution metrics |
| `TRADE_EVENTS_STREAM` 			| Stream      		| CDC on raw table |
| `TRADE_INGEST_STAGE` 				| Stage 	  		| File upload drop-zone |
| `TRADE_JSON_FF` 					| File Format 		| JSON parsing config |
| `PROCESS_TRADE_EVENTS` 			| Procedure 		| Core validation SP |
| `LOAD_TRADES_FROM_STAGE` 			| Procedure 		| COPY INTO wrapper |
| `EXPIRE_STALE_TRADES` 			| Procedure 		| Daily expiry sweep |
| `TASK_LOAD_FROM_STAGE` 			| Task 				|			 5-min file load |
| `TASK_PROCESS_TRADES` 			| Task 				| Stream-triggered validation |
| `TASK_EXPIRE_TRADES` 				| Task 				| Daily cron expiry |
| `ALERT_PIPELINE_FAILURE` 			| Alert 			| Email on failure |
| `ALERT_HIGH_REJECTION_RATE` 		| Alert 			| Email if >30% rejected |
| `ALERT_PIPELINE_STALLED` 			| Alert 			| Email if no run in 30 min |
| `V_TRADE_BOOK_SUMMARY` 			| View 				| Trade status dashboard |
| `V_REJECTION_SUMMARY` 			| View 				| Hourly rejection metrics |
| `V_PIPELINE_HEALTH` 				| View 				| Last 24h run health |
| `STG_RAW_TRADES` 					| View (dbt) 		| Staging model |
| `DBT_TRADES_VALID` 				| Table (dbt) 		| Accepted trades via dbt |
| `DBT_TRADES_REJECTED` 			| Table (dbt) 		| Rejected trades via dbt |

---

## Monitoring & Alerting

### Pipeline Health Checks

```sql
-- Last 24h pipeline runs
SELECT * FROM V_PIPELINE_HEALTH;

-- Trade book summary
SELECT * FROM V_TRADE_BOOK_SUMMARY;

-- Rejection trends
SELECT * FROM V_REJECTION_SUMMARY;

-- Task execution history
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP())
))
ORDER BY scheduled_time DESC;
```

### Alert Configuration

Alerts require a notification integration (ACCOUNTADMIN):
```sql
CREATE NOTIFICATION INTEGRATION TRADE_PIPELINE_EMAIL_NI
    TYPE = EMAIL ENABLED = TRUE;
```

---

## Handling Edge Cases

| Scenario | How It's Handled |
|----------|-----------------|
| File arrival delays | Stream-triggered tasks only fire when data exists; stalled alert fires after 30 min |
| Data quality issues | 5 validation rules + 30% rejection rate alert + full rejection logging |
| Task failures | Exception handler writes to PIPELINE_RUN_LOG; failure alert emails within 10 min |
| Duplicate events | Version-based idempotency (same version = replace, lower = reject) |
| Intra-batch conflicts | ROW_NUMBER deduplication: highest version per trade_ref wins within a batch |

---

## Scalability (10,000x Growth)

| Current | At Scale |
|---------|----------|
| XSMALL warehouse | LARGE or multi-cluster warehouse |
| Tasks (5 min batch) | Snowpipe (continuous micro-batch) |
| Single stream | Multiple streams on partitioned raw tables |
| Incremental merge | Dynamic Tables for declarative refresh |
| Single schema | Partitioned by trade_date clustering key |

---

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/trade_pipeline_cicd.yml`) runs:

1. **On PR:** `dbt parse` + SQLFluff lint (no Snowflake connection needed)
2. **On push to develop:** `dbt run` + `dbt test` against a CI schema
3. **On push to main:** Full production deploy with post-deploy tests

Required GitHub Secrets:
- `SNOWFLAKE_ACCOUNT`
- `SNOWFLAKE_USER`
- `SNOWFLAKE_PASSWORD`
- `SNOWFLAKE_ROLE`
- `SNOWFLAKE_WAREHOUSE`
