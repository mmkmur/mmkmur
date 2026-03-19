"""
Simulate a SecretNearExpiry event for local demo purposes.

Two modes
---------
1. HTTP (default) – calls the Azure Function's HTTP endpoint directly.
   Use this when the Function is running locally (func start).

2. Event Grid – posts a real Event Grid event to the Function's
   EventGrid webhook endpoint (requires ngrok to be running).

Usage
-----
  # Default – calls local Function HTTP endpoint
  python scripts/simulate_near_expiry.py

  # With custom Function URL
  FUNCTION_URL=http://localhost:7071/api/rotate python scripts/simulate_near_expiry.py

  # Event Grid schema mode (needs ngrok URL)
  NGROK_URL=https://abc.ngrok-free.app python scripts/simulate_near_expiry.py --eventgrid
"""
import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

import requests
from dotenv import load_dotenv
from rich.console import Console
from rich.panel import Panel

# Load .env from project root
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

console = Console()

DEFAULT_FUNCTION_URL = os.getenv("FUNCTION_URL", "http://localhost:7071/api/rotate")
SECRET_NAME = os.getenv("SECRET_NAME", "demo-db-password")
KEYVAULT_NAME = os.getenv("AZURE_KEYVAULT_NAME", "poc-keyvault")


def _build_near_expiry_event() -> dict:
    """Build a payload that matches Microsoft.KeyVault.SecretNearExpiry schema."""
    expiry_ts = int((datetime.now(timezone.utc) + timedelta(days=3)).timestamp())
    return {
        "id": str(uuid.uuid4()),
        "source": f"/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/{KEYVAULT_NAME}",
        "specversion": "1.0",
        "type": "Microsoft.KeyVault.SecretNearExpiry",
        "subject": SECRET_NAME,
        "time": datetime.now(timezone.utc).isoformat(),
        "data": {
            "Id": f"https://{KEYVAULT_NAME}.vault.azure.net/secrets/{SECRET_NAME}",
            "VaultName": KEYVAULT_NAME,
            "ObjectType": "Secret",
            "ObjectName": SECRET_NAME,
            "Version": "",
            "NBF": None,
            "EXP": expiry_ts,
        },
    }


def rotate_via_http(function_url: str, secret_name: str):
    """Call the Azure Function's HTTP trigger endpoint directly."""
    console.print(f"\n[cyan]Calling rotation endpoint:[/cyan] {function_url}")

    payload = {"secret_name": secret_name}
    try:
        resp = requests.post(function_url, json=payload, timeout=30)
        resp.raise_for_status()
        result = resp.json()

        console.print(
            Panel(
                f"[bold green]Rotation triggered successfully![/bold green]\n\n"
                f"  Secret name   : [cyan]{result.get('secret_name')}[/cyan]\n"
                f"  Rotated at    : [cyan]{result.get('rotated_at')}[/cyan]\n"
                f"  New expiry    : [cyan]{result.get('new_expiry')}[/cyan]\n"
                f"  Value prefix  : [cyan]{result.get('new_value_prefix')}[/cyan]\n\n"
                f"[dim]The demo app will detect the new secret version within "
                f"{os.getenv('SECRET_REFRESH_INTERVAL_SECONDS', '10')}s.[/dim]",
                title="Rotation Result",
                border_style="green",
            )
        )
    except requests.ConnectionError:
        console.print(
            "[bold red]Connection refused.[/bold red] "
            "Is the Azure Function running?\n"
            "  cd function && func start"
        )
        sys.exit(1)
    except requests.HTTPError as e:
        console.print(f"[bold red]HTTP error:[/bold red] {e}\n{resp.text}")
        sys.exit(1)


def rotate_via_eventgrid(ngrok_url: str, secret_name: str):
    """Post a SecretNearExpiry CloudEvent to the Function's Event Grid webhook."""
    endpoint = f"{ngrok_url.rstrip('/')}/runtime/webhooks/eventgrid?functionName=RotateSecret"
    console.print(f"\n[cyan]Posting Event Grid event to:[/cyan] {endpoint}")

    event = _build_near_expiry_event()
    event["subject"] = secret_name
    event["data"]["ObjectName"] = secret_name

    headers = {
        "Content-Type": "application/cloudevents+json",
        "aeg-event-type": "Notification",
    }

    try:
        resp = requests.post(endpoint, json=event, headers=headers, timeout=30)
        if resp.status_code == 200:
            console.print("[bold green]Event delivered successfully![/bold green]")
        else:
            console.print(f"[yellow]Response {resp.status_code}:[/yellow] {resp.text}")
    except requests.ConnectionError:
        console.print(
            "[bold red]Connection refused.[/bold red] "
            "Is ngrok running and pointing to the Function?\n"
            "  ngrok http 7071"
        )
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Simulate SecretNearExpiry for local demo")
    parser.add_argument(
        "--eventgrid",
        action="store_true",
        help="Post a real EventGrid CloudEvent (requires NGROK_URL env var)",
    )
    parser.add_argument(
        "--secret-name",
        default=SECRET_NAME,
        help=f"Secret name to rotate (default: {SECRET_NAME})",
    )
    args = parser.parse_args()

    console.print(
        Panel(
            "[bold]Secret Near-Expiry Simulation[/bold]\n\n"
            f"  Secret    : [cyan]{args.secret_name}[/cyan]\n"
            f"  Key Vault : [cyan]{KEYVAULT_NAME}[/cyan]\n"
            f"  Mode      : [cyan]{'EventGrid webhook' if args.eventgrid else 'HTTP direct'}[/cyan]",
            border_style="yellow",
        )
    )

    if args.eventgrid:
        ngrok_url = os.getenv("NGROK_URL")
        if not ngrok_url:
            console.print("[bold red]ERROR:[/bold red] NGROK_URL env var is required for --eventgrid mode")
            sys.exit(1)
        rotate_via_eventgrid(ngrok_url, args.secret_name)
    else:
        rotate_via_http(DEFAULT_FUNCTION_URL, args.secret_name)


if __name__ == "__main__":
    main()
