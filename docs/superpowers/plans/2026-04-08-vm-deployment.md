# VM Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the ETL pipeline (Airflow + dbt + dlt) to a Linux VM with Docker Compose, including Metabase for dashboards.

**Architecture:** The stack runs entirely in Docker via `docker-compose.yaml`. The VM needs Docker, the repo, secrets, and network access to source databases (10.22.4.47 PostgreSQL, 10.22.5.26 MariaDB) and the warehouse (10.22.4.47:5432/raw_db). Metabase is added as a service connecting to the same warehouse.

**Tech Stack:** Docker 24+, Docker Compose v2, Git, Ubuntu 22.04+ (or RHEL/Rocky 9)

---

## File Structure

```
Files to create:
  docker-compose.prod.yaml        — Production override (Metabase, resource limits, restart policies)
  deploy/setup-vm.sh              — VM bootstrap script (Docker, dirs, firewall)
  deploy/deploy.sh                — Pull repo, copy secrets, start stack
  deploy/.env.prod.example        — Production env template
  deploy/README.md                — Deployment runbook

Files to modify:
  docker-compose.yaml             — None (kept as-is, prod overrides via -f)
  Dockerfile                      — None (already production-ready)
```

---

### Task 1: VM Bootstrap Script

**Files:**
- Create: `deploy/setup-vm.sh`

This script runs once on a fresh VM to install Docker and prepare directories.

- [ ] **Step 1: Create the bootstrap script**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== ETL Pipeline VM Setup ==="

# 1. Install Docker (Ubuntu/Debian)
if ! command -v docker &> /dev/null; then
    echo "[setup] Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "[setup] Docker installed. Log out and back in for group changes."
else
    echo "[setup] Docker already installed: $(docker --version)"
fi

# 2. Create project directory
PROJECT_DIR="/opt/etl-pipeline"
sudo mkdir -p "$PROJECT_DIR"
sudo chown "$USER:$USER" "$PROJECT_DIR"
echo "[setup] Project directory: $PROJECT_DIR"

# 3. Create persistent data directories
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/logs"
echo "[setup] Data and log directories created."

# 4. Open firewall ports (if ufw is active)
if command -v ufw &> /dev/null && sudo ufw status | grep -q "active"; then
    sudo ufw allow 8080/tcp comment "Airflow Webserver"
    sudo ufw allow 3000/tcp comment "Metabase"
    echo "[setup] Firewall ports 8080 and 3000 opened."
fi

echo "=== Setup complete ==="
echo "Next: clone the repo into $PROJECT_DIR and run deploy/deploy.sh"
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x deploy/setup-vm.sh
git add deploy/setup-vm.sh
git commit -m "deploy: add VM bootstrap script"
```

---

### Task 2: Production Environment Template

**Files:**
- Create: `deploy/.env.prod.example`

- [ ] **Step 1: Create the production env template**

```dotenv
# === Airflow ===
AIRFLOW_UID=50000
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags
AIRFLOW__WEBSERVER__SECRET_KEY=CHANGE-ME-generate-with-python3-c-import-secrets-secrets.token_hex(32)

# === SMTP (email alerting) ===
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_MAIL_FROM=your-email@gmail.com

# === Warehouse (for dbt profiles.yml) ===
WAREHOUSE_HOST=10.22.4.47
WAREHOUSE_PORT=5432
WAREHOUSE_USER=odoo
WAREHOUSE_PASSWORD=odoo
WAREHOUSE_DB=raw_db

# === Metabase ===
MB_DB_TYPE=postgres
MB_DB_DBNAME=metabase
MB_DB_PORT=5432
MB_DB_USER=metabase
MB_DB_PASS=metabase
MB_DB_HOST=metabase-db
```

- [ ] **Step 2: Commit**

```bash
git add deploy/.env.prod.example
git commit -m "deploy: add production env template"
```

---

### Task 3: Production Docker Compose Override

**Files:**
- Create: `docker-compose.prod.yaml`

This file is used with `docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d`. It adds Metabase, a Metabase DB, resource limits, and production settings.

- [ ] **Step 1: Create the production override**

```yaml
# Usage: docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d
services:

  airflow-webserver:
    restart: always
    deploy:
      resources:
        limits:
          memory: 1G

  airflow-scheduler:
    restart: always
    environment:
      # dbt profiles.yml reads these
      WAREHOUSE_HOST: "${WAREHOUSE_HOST}"
      WAREHOUSE_PORT: "${WAREHOUSE_PORT}"
      WAREHOUSE_USER: "${WAREHOUSE_USER}"
      WAREHOUSE_PASSWORD: "${WAREHOUSE_PASSWORD}"
      WAREHOUSE_DB: "${WAREHOUSE_DB}"
    deploy:
      resources:
        limits:
          memory: 2G

  # --- Metabase ---
  metabase-db:
    image: postgres:16
    environment:
      POSTGRES_USER: "${MB_DB_USER:-metabase}"
      POSTGRES_PASSWORD: "${MB_DB_PASS:-metabase}"
      POSTGRES_DB: "${MB_DB_DBNAME:-metabase}"
    volumes:
      - metabase-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U metabase"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: always

  metabase:
    image: metabase/metabase:latest
    ports:
      - "3000:3000"
    environment:
      MB_DB_TYPE: "${MB_DB_TYPE:-postgres}"
      MB_DB_DBNAME: "${MB_DB_DBNAME:-metabase}"
      MB_DB_PORT: "${MB_DB_PORT:-5432}"
      MB_DB_USER: "${MB_DB_USER:-metabase}"
      MB_DB_PASS: "${MB_DB_PASS:-metabase}"
      MB_DB_HOST: metabase-db
    depends_on:
      metabase-db:
        condition: service_healthy
    restart: always
    deploy:
      resources:
        limits:
          memory: 2G

volumes:
  metabase-db-data:
```

- [ ] **Step 2: Commit**

```bash
git add docker-compose.prod.yaml
git commit -m "deploy: add production docker-compose override with Metabase"
```

---

### Task 4: Deployment Script

**Files:**
- Create: `deploy/deploy.sh`

This script is run on the VM to pull latest code and (re)start the stack.

- [ ] **Step 1: Create the deployment script**

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/opt/etl-pipeline"
REPO_URL="${1:-}"

echo "=== ETL Pipeline Deployment ==="

# 1. Clone or pull
if [ -n "$REPO_URL" ] && [ ! -d "$PROJECT_DIR/.git" ]; then
    echo "[deploy] Cloning repo..."
    git clone "$REPO_URL" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

if [ -d ".git" ]; then
    echo "[deploy] Pulling latest..."
    git pull --ff-only
fi

# 2. Check required files
if [ ! -f ".env" ]; then
    echo "[deploy] ERROR: .env not found. Copy from deploy/.env.prod.example and fill in values:"
    echo "  cp deploy/.env.prod.example .env"
    exit 1
fi

if [ ! -f ".dlt/secrets.toml" ]; then
    echo "[deploy] ERROR: .dlt/secrets.toml not found. Copy from .dlt/secrets.toml.example and fill in values:"
    echo "  cp .dlt/secrets.toml.example .dlt/secrets.toml"
    exit 1
fi

# 3. Build and start
echo "[deploy] Building images..."
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml build

echo "[deploy] Starting stack..."
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d

# 4. Wait for Airflow to be ready
echo "[deploy] Waiting for Airflow webserver..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo "[deploy] Airflow is ready."
        break
    fi
    sleep 5
done

# 5. Install dbt deps inside scheduler container
SCHEDULER=$(docker compose -f docker-compose.yaml -f docker-compose.prod.yaml ps -q airflow-scheduler)
if [ -n "$SCHEDULER" ]; then
    echo "[deploy] Installing dbt dependencies..."
    docker exec "$SCHEDULER" bash -c "cd /opt/airflow/dbt && dbt deps"
fi

# 6. Generate button DAGs
echo "[deploy] Generating button DAGs..."
docker exec "$SCHEDULER" python /opt/airflow/dags/dag_init_script.py

echo "=== Deployment complete ==="
echo "Airflow:  http://$(hostname -I | awk '{print $1}'):8080  (admin / admin)"
echo "Metabase: http://$(hostname -I | awk '{print $1}'):3000"
echo ""
echo "Next steps:"
echo "  1. Change Airflow admin password"
echo "  2. Set up Metabase (first-time setup at :3000)"
echo "  3. In Metabase, add PnL Warehouse database:"
echo "     Host: ${WAREHOUSE_HOST:-10.22.4.47}, Port: ${WAREHOUSE_PORT:-5432}"
echo "     DB: ${WAREHOUSE_DB:-raw_db}, User: ${WAREHOUSE_USER:-odoo}"
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x deploy/deploy.sh
git add deploy/deploy.sh
git commit -m "deploy: add deployment script with health checks"
```

---

### Task 5: Deployment Runbook

**Files:**
- Create: `deploy/README.md`

- [ ] **Step 1: Create the runbook**

```markdown
# Deployment Guide

## Prerequisites

- Ubuntu 22.04+ VM (or RHEL/Rocky 9)
- Minimum 4 CPU, 8 GB RAM, 50 GB disk
- Network access to source databases:
  - `10.22.4.47:15432` — postgres_crm (Odoo CRM)
  - `10.22.4.47:5432` — postgres_timesheet (Odoo Timesheet) + warehouse (raw_db)
  - `10.22.5.26:3306` — maria_erp (ERPNext)
- Ports 8080 (Airflow) and 3000 (Metabase) open

## First-Time Setup

```bash
# 1. Bootstrap the VM (installs Docker, creates /opt/etl-pipeline)
bash deploy/setup-vm.sh

# 2. Log out and back in (for Docker group)
exit
# reconnect via SSH

# 3. Clone the repo
git clone <repo-url> /opt/etl-pipeline
cd /opt/etl-pipeline

# 4. Create secrets
cp deploy/.env.prod.example .env
# Edit .env — set AIRFLOW__WEBSERVER__SECRET_KEY and WAREHOUSE_* values

cp .dlt/secrets.toml.example .dlt/secrets.toml
# Edit .dlt/secrets.toml — set real database credentials

# 5. Deploy
bash deploy/deploy.sh
```

## Updating

```bash
cd /opt/etl-pipeline
bash deploy/deploy.sh
```

This pulls latest code, rebuilds images if needed, and restarts services.

## Services

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| Airflow | http://VM_IP:8080 | admin / admin |
| Metabase | http://VM_IP:3000 | (first-time setup) |

## Logs

```bash
# Airflow scheduler logs (most useful)
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml logs -f airflow-scheduler

# All services
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml logs -f

# dbt run logs (inside container)
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml exec airflow-scheduler \
  cat /opt/airflow/dbt/target/run_results.json
```

## Restart / Stop

```bash
cd /opt/etl-pipeline

# Restart all
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml restart

# Stop all
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml down

# Stop and remove data volumes (DESTRUCTIVE)
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml down -v
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Airflow webserver won't start | Check `.env` exists and `SECRET_KEY` is set |
| dbt fails with "no relation" | Run `dbt deps` inside scheduler: `docker exec <scheduler> bash -c "cd /opt/airflow/dbt && dbt deps"` |
| Can't reach source DBs | Check network/firewall: `docker exec <scheduler> pg_isready -h 10.22.4.47 -p 5432` |
| Metabase can't reach warehouse | Use host IP (not localhost) when adding DB in Metabase. From Metabase container, warehouse is at the VM's host network |
| Scheduler OOM killed | Increase memory limit in `docker-compose.prod.yaml` |
```

- [ ] **Step 2: Commit**

```bash
git add deploy/README.md
git commit -m "deploy: add deployment runbook"
```

---

### Task 6: Add WAREHOUSE env vars to base docker-compose scheduler

**Files:**
- Modify: `docker-compose.yaml` (airflow-scheduler environment section)

The scheduler runs dbt, which reads `WAREHOUSE_*` env vars via `dbt/profiles.yml`. Currently these aren't passed. The prod override adds them, but the base compose should forward them too so dev works the same way.

- [ ] **Step 1: Add warehouse env vars to the shared airflow-common block**

In `docker-compose.yaml`, add to the `environment` section of `x-airflow-common`:

```yaml
    WAREHOUSE_HOST: "${WAREHOUSE_HOST:-10.22.4.47}"
    WAREHOUSE_PORT: "${WAREHOUSE_PORT:-5432}"
    WAREHOUSE_USER: "${WAREHOUSE_USER:-odoo}"
    WAREHOUSE_PASSWORD: "${WAREHOUSE_PASSWORD:-odoo}"
    WAREHOUSE_DB: "${WAREHOUSE_DB:-raw_db}"
```

- [ ] **Step 2: Verify docker compose config parses**

```bash
docker compose -f docker-compose.yaml config --quiet
```

Expected: no output (success)

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yaml
git commit -m "deploy: forward WAREHOUSE env vars to Airflow containers for dbt"
```

---

### Task 7: Smoke Test on VM

This task is manual — run on the target VM after deploying.

- [ ] **Step 1: Run bootstrap**

```bash
scp -r deploy/ user@VM_IP:/tmp/
ssh user@VM_IP "bash /tmp/deploy/setup-vm.sh"
```

- [ ] **Step 2: Clone and configure**

```bash
ssh user@VM_IP
cd /opt/etl-pipeline
git clone <repo-url> .
cp deploy/.env.prod.example .env
# Edit .env with real values
cp .dlt/secrets.toml.example .dlt/secrets.toml
# Edit secrets.toml with real credentials
```

- [ ] **Step 3: Deploy and verify**

```bash
bash deploy/deploy.sh
```

Verify checklist:
- [ ] `docker compose ps` shows 5 services running (airflow-db, airflow-init exited, airflow-webserver, airflow-scheduler, metabase-db, metabase)
- [ ] `curl http://localhost:8080/health` returns `{"metadatabase":{"status":"healthy"},"scheduler":{"status":"healthy"}}`
- [ ] `curl http://localhost:3000/api/health` returns `{"status":"ok"}`
- [ ] Airflow UI loads at `http://VM_IP:8080` with DAGs visible
- [ ] Metabase loads at `http://VM_IP:3000`
