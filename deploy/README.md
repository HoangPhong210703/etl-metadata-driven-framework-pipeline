# Deployment Runbook

Deployment guide for the metadata-driven ETL pipeline on an Ubuntu VM using Docker Compose.

## Prerequisites

| Requirement | Minimum |
|---|---|
| OS | Ubuntu 22.04+ |
| CPU | 4 vCPU |
| RAM | 8 GB |
| Disk | 40 GB |
| Inbound ports | 8080 (Airflow), 3000 (Metabase) |
| Outbound access | Source databases and warehouse |

### Source Systems

| Alias | Host | Port | Type |
|---|---|---|---|
| `postgres_crm` | `10.22.4.47` | `15432` | PostgreSQL |
| `postgres_timesheet` | `10.22.4.47` | `5432` | PostgreSQL |
| `maria_erp` | `10.22.5.26` | `3306` | MariaDB |
| `warehouse` | `10.22.4.47` | `5432` | PostgreSQL (`raw_db`) |

## Files Added For VM Deployments

- `docker-compose.prod.yaml`: production-only services for Metabase.
- `deploy/setup-vm.sh`: bootstraps Docker and prepares the VM.
- `deploy/deploy.sh`: builds, initializes, and starts the stack.
- `deploy/.env.prod.example`: production environment template.
- `.dlt/secrets.toml.example`: example dlt credentials file.

## First-Time Setup

### 1. Bootstrap the VM

```bash
git clone <repo-url> /tmp/etl-pipeline
cd /tmp/etl-pipeline
bash deploy/setup-vm.sh
```

If the script adds your user to the `docker` group, log out and back in before continuing.

### 2. Clone the Repository Onto the VM

```bash
cd /opt/etl-pipeline
git clone <repo-url> .
```

If you are deploying an unpublished local checkout, copy the repository contents to `/opt/etl-pipeline` instead of cloning from Git.

### 3. Configure Environment Variables

```bash
cd /opt/etl-pipeline
cp deploy/.env.prod.example .env
```

Edit `.env` and set at least:

- `AIRFLOW__CORE__FERNET_KEY`
- `AIRFLOW__WEBSERVER__SECRET_KEY`
- `AIRFLOW_ADMIN_PASSWORD`
- `WAREHOUSE_HOST`
- `WAREHOUSE_PORT`
- `WAREHOUSE_USER`
- `WAREHOUSE_PASSWORD`
- `WAREHOUSE_DB`

SMTP settings are optional unless you want Airflow email alerts.

### 4. Configure dlt Secrets

```bash
cp .dlt/secrets.toml.example .dlt/secrets.toml
```

Edit `.dlt/secrets.toml` with the real source and warehouse credentials.

### 5. Deploy

```bash
bash deploy/deploy.sh
```

The script will:

1. Build the Airflow image.
2. Start PostgreSQL containers for Airflow and Metabase.
3. Run `airflow-init` for DB migration and admin user creation.
4. Start Airflow webserver, scheduler, and Metabase.
5. Run `dbt deps`.
6. Generate button DAGs from `config/dag_config.csv`.

## Access URLs

- Airflow: `http://<vm-ip>:8080`
- Metabase: `http://<vm-ip>:3000`

Airflow login uses the admin values from `.env`.

## Updating The Deployment

```bash
cd /opt/etl-pipeline
git pull --ff-only
bash deploy/deploy.sh
```

Rebuilds are safe to run on each deployment. DAGs, config, dbt project files, `.dlt`, `data`, and `logs` are bind-mounted from the host.

## Verification

```bash
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml ps
curl http://localhost:8080/health
curl http://localhost:3000/api/health
```

Expected results:

- Airflow health endpoint returns HTTP `200`.
- Metabase health endpoint returns HTTP `200`.
- Airflow scheduler and webserver are both running.

## Logs

```bash
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml logs -f
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml logs -f airflow-scheduler
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml logs -f airflow-webserver
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml logs -f metabase
```

Airflow task logs are also available on the host under `./logs`.

## Stop Or Tear Down

```bash
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml down
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml down -v
```

`down -v` removes PostgreSQL and Metabase volumes and destroys service data.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `airflow-init` fails | Check `docker compose logs airflow-init airflow-db` and verify the Airflow metadata DB is healthy. |
| Airflow UI stays unavailable | Check `docker compose logs airflow-webserver` and confirm port `8080` is open. |
| DAGs do not appear | Run `docker compose -f docker-compose.yaml -f docker-compose.prod.yaml exec -T airflow-scheduler python /opt/airflow/dags/dag_init_script.py` and inspect scheduler import errors. |
| dbt commands fail | Run `docker compose -f docker-compose.yaml -f docker-compose.prod.yaml exec -T airflow-scheduler bash -lc "cd /opt/airflow/dbt && dbt deps"`. |
| dlt cannot connect to sources | Validate `.dlt/secrets.toml` and test network access from the VM to `10.22.4.47` and `10.22.5.26`. |
| Metabase is missing | Make sure you started with both compose files: `-f docker-compose.yaml -f docker-compose.prod.yaml`. |
