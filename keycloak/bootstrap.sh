#!/bin/bash
# Bootstrap script — runs once on VM first boot via Azure Custom Script Extension.
# Installs Docker, copies docker-compose, and starts Keycloak.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq docker.io docker-compose curl jq

systemctl enable --now docker

mkdir -p /opt/keycloak
cat > /opt/keycloak/docker-compose.yml << 'EOF'
version: "3.9"

services:
  postgres:
    image: postgres:15
    restart: unless-stopped
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: keycloak_db_pass
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "keycloak"]
      interval: 10s
      retries: 5

  keycloak:
    image: quay.io/keycloak/keycloak:24.0
    restart: unless-stopped
    command: start
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: keycloak_db_pass
      KC_HOSTNAME_STRICT: "false"
      KC_HTTP_ENABLED: "true"
      KC_PROXY: edge          # App Gateway terminates TLS, Keycloak trusts X-Forwarded headers
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: ChangeMe123!   # CHANGE THIS before production use
      KC_HEALTH_ENABLED: "true"
      KC_METRICS_ENABLED: "true"
    ports:
      - "8080:8080"
    volumes:
      - keycloak_data:/opt/keycloak/data

volumes:
  postgres_data:
  keycloak_data:
EOF

cd /opt/keycloak
docker-compose up -d

# Wait for Keycloak to be healthy before exiting (max 3 minutes)
echo "Waiting for Keycloak to become healthy..."
for i in $(seq 1 36); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health/ready || echo "000")
  if [ "$STATUS" = "200" ]; then
    echo "Keycloak is healthy."
    break
  fi
  sleep 5
done
