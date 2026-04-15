#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/etl-pipeline}"

if [[ "${EUID}" -eq 0 ]]; then
    echo "[setup] Run this script as a regular sudo-capable user, not as root."
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "[setup] This script targets Ubuntu/Debian systems with apt."
    exit 1
fi

source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "[setup] Expected Ubuntu, detected: ${PRETTY_NAME:-unknown}."
fi

echo "[setup] Installing OS packages..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl git gnupg lsb-release ufw

if ! command -v docker >/dev/null 2>&1; then
    echo "[setup] Installing Docker Engine and Compose plugin..."
    sudo install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    printf "deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n" \
        "$(dpkg --print-architecture)" \
        "${VERSION_CODENAME}" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "[setup] Docker already installed: $(docker --version)"
fi

if ! id -nG "$USER" | grep -qw docker; then
    echo "[setup] Adding ${USER} to the docker group..."
    sudo usermod -aG docker "$USER"
    RELOGIN_REQUIRED=1
else
    RELOGIN_REQUIRED=0
fi

sudo install -d -m 0755 -o "$USER" -g "$USER" "$(dirname "$PROJECT_DIR")"
sudo install -d -m 0755 -o "$USER" -g "$USER" "$PROJECT_DIR"
echo "[setup] Project directory ready at ${PROJECT_DIR}"

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow 8080/tcp comment "Airflow UI"
    sudo ufw allow 3000/tcp comment "Metabase UI"
    echo "[setup] Opened firewall ports 8080 and 3000."
fi

echo
echo "[setup] Bootstrap complete."
echo "Next steps:"
echo "  1. cd ${PROJECT_DIR}"
echo "  2. git clone <repo-url> ."
echo "  3. cp deploy/.env.prod.example .env"
echo "  4. cp .dlt/secrets.toml.example .dlt/secrets.toml"
echo "  5. Edit both files with real values"
echo "  6. bash deploy/deploy.sh"

if [[ "${RELOGIN_REQUIRED}" -eq 1 ]]; then
    echo
    echo "[setup] Log out and back in before running Docker commands."
fi
