#!/usr/bin/env bash
# =============================================================
# STEP 1 – Create Azure Resource Group + Key Vault
# =============================================================
# Prerequisites: Azure CLI installed  →  az login  done
# Usage: bash setup/01_create_resources.sh
# =============================================================
set -euo pipefail

# Load values from .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

REQUIRED=(
  AZURE_SUBSCRIPTION_ID
  AZURE_RESOURCE_GROUP
  AZURE_LOCATION
  AZURE_KEYVAULT_NAME
)
for var in "${REQUIRED[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

echo ""
echo "=================================================="
echo " Secret Management POC – Resource Setup"
echo "=================================================="
echo " Subscription : $AZURE_SUBSCRIPTION_ID"
echo " Resource Group: $AZURE_RESOURCE_GROUP"
echo " Location      : $AZURE_LOCATION"
echo " Key Vault     : $AZURE_KEYVAULT_NAME"
echo "=================================================="
echo ""

# Set active subscription
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# ── Resource Group ──────────────────────────────────────────
echo "[1/3] Creating Resource Group..."
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --output table

# ── Key Vault ───────────────────────────────────────────────
echo ""
echo "[2/3] Creating Azure Key Vault..."
az keyvault create \
  --name "$AZURE_KEYVAULT_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --sku standard \
  --enable-rbac-authorization false \
  --output table

echo ""
echo "[3/3] Enabling soft-delete (already on by default for new vaults)."
echo ""
echo "✅  Key Vault created: https://${AZURE_KEYVAULT_NAME}.vault.azure.net"
echo ""
echo "NEXT: Run  bash setup/02_create_app_registration.sh"
