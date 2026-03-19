"""
Shared configuration – reads from .env at project root.
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Walk up to find the .env file regardless of CWD
_root = Path(__file__).resolve().parent.parent
load_dotenv(_root / ".env")


def _require(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise EnvironmentError(
            f"Missing required env var: {key}\n"
            f"Copy .env.example → .env and fill in your values."
        )
    return val


AZURE_TENANT_ID  = _require("AZURE_TENANT_ID")
AZURE_CLIENT_ID  = _require("AZURE_CLIENT_ID")
AZURE_CLIENT_SECRET = _require("AZURE_CLIENT_SECRET")

KEYVAULT_NAME = _require("AZURE_KEYVAULT_NAME")
KEYVAULT_URL  = f"https://{KEYVAULT_NAME}.vault.azure.net"

SECRET_NAME   = os.getenv("SECRET_NAME", "demo-db-password")
ROTATION_INTERVAL_DAYS = int(os.getenv("ROTATION_INTERVAL_DAYS", "30"))

# How often the demo app polls Key Vault for a new secret version (seconds)
SECRET_REFRESH_INTERVAL_SECONDS = int(os.getenv("SECRET_REFRESH_INTERVAL_SECONDS", "10"))
