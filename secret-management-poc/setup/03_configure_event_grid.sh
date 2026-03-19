#!/usr/bin/env bash
# =============================================================
# STEP 3 – Configure Azure Event Grid System Topic on Key Vault
#          and subscribe it to the local Azure Function endpoint
#
# Flow:
#   Key Vault  ──(SecretNearExpiry event)──►  Event Grid
#              ──(webhook)──►  Azure Function (running locally via ngrok)
#              ──(rotates secret)──►  Key Vault
# =============================================================
# Prerequisites:
#   - Azure Function running locally:  cd function && func start
#   - ngrok exposing port 7071:        ngrok http 7071
#   - Set NGROK_URL below (or pass as env var)
#
# Usage:
#   NGROK_URL=https://abc123.ngrok-free.app bash setup/03_configure_event_grid.sh
# =============================================================
set -euo pipefail

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

REQUIRED=(
  AZURE_SUBSCRIPTION_ID
  AZURE_RESOURCE_GROUP
  AZURE_KEYVAULT_NAME
  NGROK_URL
)
for var in "${REQUIRED[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set. Pass it as env var:"
    echo "  NGROK_URL=https://abc.ngrok-free.app bash setup/03_configure_event_grid.sh"
    exit 1
  fi
done

KEYVAULT_RESOURCE_ID=$(az keyvault show \
  --name "$AZURE_KEYVAULT_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id -o tsv)

TOPIC_NAME="evgt-${AZURE_KEYVAULT_NAME}"
SUBSCRIPTION_NAME="sub-secret-rotation"

# Function endpoint – Event Grid calls this when SecretNearExpiry fires
FUNCTION_ENDPOINT="${NGROK_URL}/runtime/webhooks/eventgrid?functionName=RotateSecret"

echo ""
echo "=================================================="
echo " Event Grid – System Topic Setup"
echo "=================================================="
echo " Key Vault      : $AZURE_KEYVAULT_NAME"
echo " Topic Name     : $TOPIC_NAME"
echo " Webhook URL    : $FUNCTION_ENDPOINT"
echo "=================================================="
echo ""

# ── Register Event Grid provider (idempotent) ────────────────
echo "[1/3] Registering Microsoft.EventGrid provider..."
az provider register --namespace Microsoft.EventGrid --wait
echo "      Done."

# ── Create System Topic ──────────────────────────────────────
echo ""
echo "[2/3] Creating Event Grid System Topic on Key Vault..."
az eventgrid system-topic create \
  --name "$TOPIC_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --source "$KEYVAULT_RESOURCE_ID" \
  --topic-type "microsoft.keyvault.vaults" \
  --location "$AZURE_LOCATION" \
  --output table

# ── Create Event Subscription ────────────────────────────────
echo ""
echo "[3/3] Creating Event Subscription (SecretNearExpiry → Azure Function)..."
az eventgrid system-topic event-subscription create \
  --name "$SUBSCRIPTION_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --system-topic-name "$TOPIC_NAME" \
  --endpoint-type webhook \
  --endpoint "$FUNCTION_ENDPOINT" \
  --included-event-types "Microsoft.KeyVault.SecretNearExpiry" \
  --output table

echo ""
echo "✅  Event Grid configured."
echo "    Topic           : $TOPIC_NAME"
echo "    Subscription    : $SUBSCRIPTION_NAME"
echo "    Listens for     : Microsoft.KeyVault.SecretNearExpiry"
echo "    Rotates to      : $FUNCTION_ENDPOINT"
echo ""
echo "NEXT: Run  bash setup/04_seed_secret.sh  to create the initial secret"
