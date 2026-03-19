#!/usr/bin/env bash
# =============================================================
# STEP 4 – Create the initial secret in Key Vault
#          with a 30-day expiry so Event Grid can fire near-expiry
# =============================================================
set -euo pipefail

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

ROTATION_DAYS="${ROTATION_INTERVAL_DAYS:-30}"

# Compute expiry = now + ROTATION_DAYS (ISO-8601)
EXPIRY_DATE=$(python3 -c "
from datetime import datetime, timezone, timedelta
expiry = datetime.now(timezone.utc) + timedelta(days=${ROTATION_DAYS})
print(expiry.strftime('%Y-%m-%dT%H:%M:%SZ'))
")

# Generate an initial secret value (random 32-char hex)
INITIAL_VALUE=$(python3 -c "import secrets; print(secrets.token_hex(16))")

echo ""
echo "=================================================="
echo " Seeding initial secret"
echo "=================================================="
echo " Key Vault   : $AZURE_KEYVAULT_NAME"
echo " Secret name : ${SECRET_NAME:-demo-db-password}"
echo " Expiry      : $EXPIRY_DATE  (${ROTATION_DAYS} days from now)"
echo " Value       : [hidden]"
echo "=================================================="
echo ""

az keyvault secret set \
  --vault-name "$AZURE_KEYVAULT_NAME" \
  --name "${SECRET_NAME:-demo-db-password}" \
  --value "$INITIAL_VALUE" \
  --expires "$EXPIRY_DATE" \
  --description "Demo DB password – managed by secret rotation POC" \
  --output table

echo ""
echo "✅  Secret seeded successfully."
echo "    It will trigger SecretNearExpiry 30 days before expiry."
echo ""
echo "To verify:"
echo "  az keyvault secret show --vault-name $AZURE_KEYVAULT_NAME --name ${SECRET_NAME:-demo-db-password}"
echo ""
echo "NEXT:"
echo "  1. Start the Azure Function:  cd function && func start"
echo "  2. Start ngrok in new terminal:  ngrok http 7071"
echo "  3. Run the Event Grid setup:  NGROK_URL=https://xxx.ngrok-free.app bash setup/03_configure_event_grid.sh"
echo "  4. Start the demo app:  python demo_app.py"
echo "  5. Simulate rotation now:  python scripts/simulate_near_expiry.py"
