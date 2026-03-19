"""
Azure Function – Secret Rotation Handler
=========================================
Trigger  : Azure Event Grid  →  Microsoft.KeyVault.SecretNearExpiry
Action   : Generate a new random secret value and write it back to
           Key Vault with a fresh expiry date (ROTATION_INTERVAL_DAYS).

Event Grid delivers the event as a CloudEvent or EventGrid schema.
The function handles both.

Local testing
-------------
  cd function
  cp local.settings.json.example local.settings.json   # fill in values
  func start

Then fire a test event:
  python ../scripts/simulate_near_expiry.py
"""
import json
import logging
import os
import secrets
from datetime import datetime, timezone, timedelta

import azure.functions as func
from azure.identity import ClientSecretCredential
from azure.keyvault.secrets import SecretClient

logger = logging.getLogger(__name__)
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


# ── Helpers ──────────────────────────────────────────────────────────────────

def _get_keyvault_client() -> SecretClient:
    credential = ClientSecretCredential(
        tenant_id=os.environ["AZURE_TENANT_ID"],
        client_id=os.environ["AZURE_CLIENT_ID"],
        client_secret=os.environ["AZURE_CLIENT_SECRET"],
    )
    vault_url = f"https://{os.environ['AZURE_KEYVAULT_NAME']}.vault.azure.net"
    return SecretClient(vault_url=vault_url, credential=credential)


def _rotate(secret_name: str) -> dict:
    """
    Generate a new secret value, write it to Key Vault with a new expiry,
    and return a summary dict.
    """
    client = _get_keyvault_client()
    rotation_days = int(os.environ.get("ROTATION_INTERVAL_DAYS", "30"))

    new_value = secrets.token_hex(16)          # 32-char hex = 128 bits of entropy
    new_expiry = datetime.now(timezone.utc) + timedelta(days=rotation_days)

    client.set_secret(
        secret_name,
        new_value,
        expires_on=new_expiry,
    )

    logger.info(
        "Secret '%s' rotated. New expiry: %s",
        secret_name,
        new_expiry.isoformat(),
    )

    return {
        "secret_name": secret_name,
        "rotated_at": datetime.now(timezone.utc).isoformat(),
        "new_expiry": new_expiry.isoformat(),
        "new_value_prefix": new_value[:4] + "****",   # log prefix only – never log full secret
    }


# ── Event Grid trigger ────────────────────────────────────────────────────────

@app.event_grid_trigger(arg_name="event", event_name="RotateSecret")
def RotateSecret(event: func.EventGridEvent) -> None:
    """
    Invoked by Event Grid when Key Vault fires SecretNearExpiry.

    Event data shape (Microsoft.KeyVault.SecretNearExpiry):
    {
      "Id": "...",
      "data": {
        "Id": "https://<vault>.vault.azure.net/secrets/<name>/<version>",
        "VaultName": "...",
        "ObjectType": "Secret",
        "ObjectName": "<secret-name>",
        "Version": "<version-id>",
        "NBF": null,
        "EXP": <unix-timestamp>
      },
      "eventType": "Microsoft.KeyVault.SecretNearExpiry",
      ...
    }
    """
    logger.info("Event received: %s", event.event_type)

    data = event.get_json()
    secret_name = data.get("ObjectName") or os.environ.get("SECRET_NAME", "demo-db-password")
    logger.info("Rotating secret: %s", secret_name)

    result = _rotate(secret_name)
    logger.info("Rotation result: %s", json.dumps(result))


# ── HTTP trigger (manual rotation for demo / local testing) ──────────────────

@app.route(route="rotate", methods=["POST"])
def rotate_http(req: func.HttpRequest) -> func.HttpResponse:
    """
    POST /api/rotate
    Body (JSON, optional): { "secret_name": "demo-db-password" }

    Used by:
      - scripts/simulate_near_expiry.py  (local demo)
      - Any HTTP client for ad-hoc rotation
    """
    try:
        body = req.get_json() if req.get_body() else {}
    except ValueError:
        body = {}

    secret_name = (
        body.get("secret_name")
        or req.params.get("secret_name")
        or os.environ.get("SECRET_NAME", "demo-db-password")
    )

    logger.info("HTTP-triggered rotation for secret: %s", secret_name)

    try:
        result = _rotate(secret_name)
        return func.HttpResponse(
            json.dumps({"status": "rotated", **result}, indent=2),
            status_code=200,
            mimetype="application/json",
        )
    except Exception as exc:
        logger.error("Rotation failed: %s", exc, exc_info=True)
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(exc)}),
            status_code=500,
            mimetype="application/json",
        )
