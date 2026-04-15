#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_CMD=(docker compose -f docker-compose.yaml -f docker-compose.prod.yaml)

wait_for_http() {
    local name="$1"
    local url="$2"
    local attempt

    for attempt in $(seq 1 60); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            echo "[deploy] ${name} is healthy."
            return 0
        fi
        sleep 5
    done

    echo "[deploy] ${name} did not become healthy in time: ${url}"
    return 1
}

if ! command -v docker >/dev/null 2>&1; then
    echo "[deploy] Docker is not installed."
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "[deploy] Docker Compose v2 is required."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[deploy] curl is required for health checks."
    exit 1
fi

cd "$PROJECT_DIR"

mkdir -p data logs .dlt

if [[ ! -f ".env" ]]; then
    echo "[deploy] Missing .env. Copy deploy/.env.prod.example to .env and fill in the values."
    exit 1
fi

if [[ ! -f ".dlt/secrets.toml" ]]; then
    echo "[deploy] Missing .dlt/secrets.toml. Copy .dlt/secrets.toml.example to .dlt/secrets.toml and fill in the values."
    exit 1
fi

echo "[deploy] Validating compose configuration..."
"${COMPOSE_CMD[@]}" config --quiet

echo "[deploy] Building Airflow image..."
"${COMPOSE_CMD[@]}" build

echo "[deploy] Starting metadata databases..."
"${COMPOSE_CMD[@]}" up -d airflow-db metabase-db

echo "[deploy] Running Airflow initialization..."
"${COMPOSE_CMD[@]}" up --abort-on-container-exit --exit-code-from airflow-init airflow-init

echo "[deploy] Starting application services..."
"${COMPOSE_CMD[@]}" up -d airflow-webserver airflow-scheduler metabase

wait_for_http "Airflow" "http://localhost:8080/health"
wait_for_http "Metabase" "http://localhost:3000/api/health"

echo "[deploy] Installing dbt packages..."
"${COMPOSE_CMD[@]}" exec -T airflow-scheduler bash -lc "cd /opt/airflow/dbt && dbt deps"

echo "[deploy] Generating button DAGs..."
"${COMPOSE_CMD[@]}" exec -T airflow-scheduler python /opt/airflow/dags/dag_init_script.py

VM_IP="$(hostname -I | awk '{print $1}')"
VM_IP="${VM_IP:-localhost}"

echo
echo "[deploy] Deployment complete."
echo "Airflow:  http://${VM_IP}:8080"
echo "Metabase: http://${VM_IP}:3000"
