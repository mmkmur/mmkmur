"""
Quick status check – shows current secret metadata from Key Vault.
Does NOT reveal the full secret value.

Usage: python scripts/check_status.py
"""
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv
from azure.identity import ClientSecretCredential
from azure.keyvault.secrets import SecretClient
from rich.console import Console
from rich.table import Table
from rich import box

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

import src.config as cfg

console = Console()

def main():
    cred = ClientSecretCredential(
        tenant_id=cfg.AZURE_TENANT_ID,
        client_id=cfg.AZURE_CLIENT_ID,
        client_secret=cfg.AZURE_CLIENT_SECRET,
    )
    client = SecretClient(vault_url=cfg.KEYVAULT_URL, credential=cred)

    secret = client.get_secret(cfg.SECRET_NAME)
    props  = secret.properties
    now    = datetime.now(timezone.utc)

    val = secret.value or ""
    masked = val[:4] + "****" + val[-4:] if len(val) >= 8 else "****"

    exp = props.expires_on
    if exp:
        delta = exp - now
        days  = delta.days
        ttl   = f"{days}d {delta.seconds // 3600}h"
    else:
        ttl = "no expiry set"

    table = Table(title="Key Vault Secret Status", box=box.ROUNDED)
    table.add_column("Property", style="bold cyan")
    table.add_column("Value")

    table.add_row("Vault",         cfg.KEYVAULT_NAME)
    table.add_row("Secret name",   cfg.SECRET_NAME)
    table.add_row("Value (masked)", masked)
    table.add_row("Version",       (props.version or "n/a")[:16] + "...")
    table.add_row("Created on",    str(props.created_on))
    table.add_row("Updated on",    str(props.updated_on))
    table.add_row("Expires on",    str(exp))
    table.add_row("Time to expiry", ttl)
    table.add_row("Enabled",       str(props.enabled))

    console.print()
    console.print(table)
    console.print()

    # List all versions
    console.print("[bold]All versions:[/bold]")
    versions_table = Table(box=box.SIMPLE)
    versions_table.add_column("Version", style="cyan")
    versions_table.add_column("Created")
    versions_table.add_column("Expires")
    versions_table.add_column("Enabled")

    for v in client.list_properties_of_secret_versions(cfg.SECRET_NAME):
        versions_table.add_row(
            (v.version or "")[:12] + "...",
            str(v.created_on)[:19],
            str(v.expires_on)[:19] if v.expires_on else "none",
            "✅" if v.enabled else "❌",
        )

    console.print(versions_table)


if __name__ == "__main__":
    main()
