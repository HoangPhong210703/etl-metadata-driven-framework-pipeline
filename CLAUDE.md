# CLAUDE.md

## Project Overview

Metadata-driven ETL pipeline built on **Apache Airflow 2.10.4** + **dlt** + **dbt**, running in Docker with `LocalExecutor`. Ingests from 3 RDBMS sources (2 PostgreSQL, 1 MariaDB) across 51 tables through a three-layer architecture: bronze (Parquet), staging (PostgreSQL), silver/gold (dbt).

## Quick Reference

```bash
# Run tests
source .venv/Scripts/activate    # Windows Git Bash
python -m pytest tests/ -v

# Start stack
docker compose up --build -d

# Regenerate button DAGs after editing config/dag_config.csv
python dags/dag_init_script.py

# Airflow UI: http://localhost:8080 (admin / admin)
```

## Architecture

```
Button DAG → Coordinator → Get Config → Process Object → Execution DAG
                                                              │
   src2brz: RDBMS → Parquet (dlt)                            │
   brz2stg: Parquet → PostgreSQL warehouse (dlt)              │
   stg2sil: dbt stg → snapshot → silver → test          (auto-triggered via Dataset)
```

- **src2brz** auto-triggers **brz2stg** via `layer_management_config.csv`
- **brz2stg** emits Airflow `Dataset` events that trigger **stg2sil**
- All config is CSV-driven in `config/` — no hardcoded table lists

## Key Coding Rules

### DAG files (dags/)
- DAGs contain **zero business logic** — all logic lives in `src/pipeline/`
- **No top-level heavy imports** — import `src.pipeline.*` inside task function bodies, not at module level
- Only `@audited`, `dag_failure_callback`, `dag_success_callback` may be top-level (needed for decoration/DAG definition)
- `@audited` on every PythonOperator callable
- `render_template_as_native_obj=True` on DAGs passing dicts via Jinja
- Always forward `button` in return dicts through the DAG chain
- Print with prefix: `[component_name] message`

### src/pipeline/
- **Never hardcode paths** — import from `src.pipeline.settings`
- **Never parse .dlt/secrets.toml inline** — use `src.pipeline.credentials`
- Heavy libraries (sqlalchemy, dlt, pandas) must be imported inside functions, not at module level
- `yagmail`/`keyring` are lazily imported inside `send_alert()` only

### dbt (dbt/)
- Schema naming: `stg__{data_subject}__{source_name}`, `sil__{domain}`, `gold__{domain}`
- Silver models use `silver_dedup` macro for multi-source dedup
- Silver model naming: `silver__{domain}__{entity_type}_{name}`
- `generate_schema_name` macro outputs the custom_schema_name directly (no prefix)
- Incremental models use `_dlt_load_id` for watermark, not `write_date`

### Config files (config/)
- `table_config.csv` — master table list for all layers
- `layer_management_config.csv` — auto-trigger rules between layers
- `dag_config.csv` — button DAG generation template
- `freshness_config.csv`, `retention_config.csv`, `alert_config.csv` — monitoring

## Source Systems

| Source | Type | Data Subject | Schema | Tables |
|--------|------|-------------|--------|--------|
| `postgres_crm` | PostgreSQL (Odoo) | accounting | public | 18 tables (account_*) |
| `postgres_timesheet` | PostgreSQL (Odoo) | accounting | public | 29 tables (account_* + cost_allocation_unit) |
| `maria_erp` | MariaDB (ERPNext) | project | appdb | 4 tables (tabProject*) |

## Data Warehouse Schemas

| Schema | Layer | Example |
|--------|-------|---------|
| `stg__accounting__postgres_crm` | staging | Raw Parquet data loaded via dlt |
| `stg__accounting__postgres_timesheet` | staging | Raw Parquet data loaded via dlt |
| `stg__project__maria_erp` | staging | Raw Parquet data loaded via dlt |
| `sil__accounting` | silver | Deduplicated/merged models |
| `meta` | audit | pipeline_audit, dbt_test_results, freshness_check_results |

## Project Structure

```
config/                        # CSV config files (all runtime configuration)
dags/                          # Airflow DAGs (thin shells only)
  coordinator.py               # Parses button ID, routes flow
  layer__execution/            # src2brz, brz2stg, stg2sil DAGs
  monitoring/                  # freshness_check, retention DAGs
src/pipeline/                  # All business logic
  settings.py                  # Centralized paths
  config.py                    # CSV config parsing + dataclasses
  credentials.py               # .dlt/secrets.toml loader
  bronze.py                    # RDBMS → Parquet (dlt)
  staging.py                   # Parquet → warehouse (dlt)
  dbt_runner.py                # dbt subprocess wrappers
  freshness.py                 # Freshness check logic
  layer_management.py          # Layer auto-trigger resolution
  alert.py                     # Email alerting (yagmail)
  audit/                       # @audited decorator + file/DB logging
  cli/                         # CLI entry points for bronze/staging
dbt/                           # dbt project
  models/silver/               # Silver layer SQL models
  macros/                      # silver_dedup, generate_schema_name
  snapshots/                   # SCD-2 definitions
tests/pipeline/                # pytest suite (35 tests)
```

## Docker

- Base image: `apache/airflow:2.10.4-python3.11`
- Executor: `LocalExecutor`, parallelism: 4
- All container paths use `/opt/airflow/` prefix
- Volumes: dags, src, config, .dlt, data, dbt, logs all mounted from host

## Testing

```bash
python -m pytest tests/ -v       # 35 tests across settings, config, bronze, staging, credentials
```

Tests use `tmp_path` fixtures — no real DB/Airflow needed.

## Credentials

Stored in `.dlt/secrets.toml` (gitignored). Structure:
```toml
[sources.postgres_crm]
credentials = "postgresql://..."

[destinations.warehouse]
credentials = "postgresql://..."
```

Copy `.dlt/secrets.toml.example` and fill in values for local development.
