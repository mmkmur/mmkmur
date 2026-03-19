#!/usr/bin/env bash
# =============================================================
# STEP 2 – Create Microsoft Entra ID App Registration
#          and grant it Key Vault access
# =============================================================
# Usage: bash setup/02_create_app_registration.sh
# =============================================================
set -euo pipefail

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

APP_NAME="sp-secret-poc"

echo ""
echo "=================================================="
echo " Entra ID – App Registration"
echo "=================================================="
echo " App name      : $APP_NAME"
echo " Key Vault     : $AZURE_KEYVAULT_NAME"
echo "=================================================="
echo ""

# ── Create App Registration ─────────────────────────────────
echo "[1/4] Creating App Registration in Entra ID..."
APP_JSON=$(az ad app create --display-name "$APP_NAME" --output json)
APP_ID=$(echo "$APP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['appId'])")
echo "      Client ID : $APP_ID"

# ── Create Service Principal ────────────────────────────────
echo ""
echo "[2/4] Creating Service Principal..."
az ad sp create --id "$APP_ID" --output none

# ── Create a client secret ──────────────────────────────────
echo ""
echo "[3/4] Creating client secret (valid 2 years)..."
SECRET_JSON=$(az ad app credential reset \
  --id "$APP_ID" \
  --years 2 \
  --output json)
CLIENT_SECRET=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
TENANT_ID=$(echo "$SECRET_JSON"    | python3 -c "import sys,json; print(json.load(sys.stdin)['tenant'])")

echo "      Tenant ID      : $TENANT_ID"
echo "      Client ID      : $APP_ID"
echo "      Client Secret  : [hidden – written to .env below]"

# ── Grant Key Vault access policy ──────────────────────────
echo ""
echo "[4/4] Granting Key Vault access policy (get, list, set, delete)..."
az keyvault set-policy \
  --name "$AZURE_KEYVAULT_NAME" \
  --spn "$APP_ID" \
  --secret-permissions get list set delete \
  --output none

# ── Patch .env ──────────────────────────────────────────────
echo ""
echo "Writing credentials to .env ..."

# Use Python for safe in-place editing
python3 - <<PYEOF
import re, pathlib

env_path = pathlib.Path(".env")
text = env_path.read_text()

replacements = {
    "AZURE_TENANT_ID": "$TENANT_ID",
    "AZURE_CLIENT_ID": "$APP_ID",
    "AZURE_CLIENT_SECRET": "$CLIENT_SECRET",
}

for key, val in replacements.items():
    pattern = rf"^{key}=.*$"
    text = re.sub(pattern, f"{key}={val}", text, flags=re.MULTILINE)

env_path.write_text(text)
print("  .env updated.")
PYEOF

echo ""
echo "✅  App Registration complete."
echo "    Service Principal: $APP_NAME"
echo "    Client ID        : $APP_ID"
echo ""
echo "NEXT: Run  bash setup/03_configure_event_grid.sh"
