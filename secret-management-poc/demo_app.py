"""
Secret Management POC – Demo Application
==========================================
This application simulates a long-running service (e.g. an API server or
worker process) that uses a secret from Azure Key Vault.

What it shows:
  1. The app starts and reads the current secret from Key Vault.
  2. It "uses" the secret every few seconds (simulated DB auth ping).
  3. While it is running, you trigger a rotation (via Event Grid or
     the simulate script).
  4. The app detects the new secret version automatically – with NO
     restart – because the SecretCache refreshes in the background.

Run:
  python demo_app.py

Then in another terminal:
  python scripts/simulate_near_expiry.py
"""
import logging
import signal
import sys
import time
from datetime import datetime, timezone

from rich.console import Console
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
from rich import box

from src.keyvault_client import secret_cache
import src.config as cfg

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("demo_app")
console = Console()

# ── Simulated application workload ───────────────────────────────────────────

_auth_attempts = 0
_auth_successes = 0
_last_used_version: str | None = None


def simulate_db_auth() -> bool:
    """
    Pretend to authenticate to a database using the current cached secret.
    In a real app this would be a connection string, API key, etc.
    Returns True on success.
    """
    global _auth_attempts, _auth_successes, _last_used_version

    _auth_attempts += 1
    current_value   = secret_cache.value
    current_version = secret_cache.version

    # Detect if the secret we are using changed since last call
    version_changed = (
        _last_used_version is not None
        and _last_used_version != current_version
    )
    _last_used_version = current_version

    # Simulate a tiny auth delay
    time.sleep(0.05)

    _auth_successes += 1
    if version_changed:
        logger.info("✅  Using NEW secret version – auth still succeeds!")
    return True


# ── Rich UI ───────────────────────────────────────────────────────────────────

def _build_table() -> Table:
    now = datetime.now(timezone.utc)

    table = Table(box=box.ROUNDED, expand=True, show_header=False)
    table.add_column("Key",   style="bold cyan",  width=30)
    table.add_column("Value", style="white")

    # Current secret info
    ver = secret_cache.version or "n/a"
    exp = secret_cache.expires_on
    exp_str = exp.strftime("%Y-%m-%d %H:%M UTC") if exp else "n/a"

    # Time until expiry
    if exp:
        delta = exp - now
        days  = delta.days
        hours = delta.seconds // 3600
        expiry_color = "red" if days < 3 else ("yellow" if days < 7 else "green")
        ttl_str = f"[{expiry_color}]{days}d {hours}h remaining[/{expiry_color}]"
    else:
        ttl_str = "n/a"

    secret_display = (secret_cache.value or "")
    masked = secret_display[:4] + "****" + secret_display[-4:] if len(secret_display) >= 8 else "****"

    rotation_count = secret_cache.rotation_count

    table.add_row("Key Vault",             cfg.KEYVAULT_NAME)
    table.add_row("Secret name",           cfg.SECRET_NAME)
    table.add_row("Secret value (masked)", masked)
    table.add_row("Secret version",        ver[:12] + "..." if len(ver) > 12 else ver)
    table.add_row("Expires on",            exp_str)
    table.add_row("Time until expiry",     ttl_str)
    table.add_row("Rotation interval",     f"{cfg.ROTATION_INTERVAL_DAYS} days")
    table.add_row("─" * 28,               "─" * 30)
    table.add_row("Cache refreshes",       str(secret_cache.refresh_count))
    table.add_row("Rotations detected",    (
        f"[bold green]{rotation_count}[/bold green]"
        if rotation_count > 0
        else "[dim]0 (waiting for rotation)[/dim]"
    ))
    table.add_row("─" * 28,               "─" * 30)
    table.add_row("DB auth attempts",      str(_auth_attempts))
    table.add_row("DB auth successes",     f"[green]{_auth_successes}[/green]")
    table.add_row("Last updated",          now.strftime("%H:%M:%S UTC"))

    return table


def _build_panel() -> Panel:
    table = _build_table()

    if secret_cache.rotation_count > 0:
        title = "[bold green]SECRET ROTATED – APP STILL RUNNING ✅[/bold green]"
        border = "green"
    else:
        title = "[bold blue]Secret Management POC – Waiting for rotation event[/bold blue]"
        border = "blue"

    instructions = Text(
        "\nTo trigger rotation ➜  python scripts/simulate_near_expiry.py\n"
        "The app will detect the new secret version automatically.\n",
        style="dim",
    )

    from rich.console import Group
    content = Group(table, instructions)
    return Panel(content, title=title, border_style=border, expand=True)


# ── Main loop ─────────────────────────────────────────────────────────────────

def main():
    console.print(
        Panel(
            "[bold]Starting Secret Management POC Demo[/bold]\n\n"
            f"  Key Vault   : [cyan]{cfg.KEYVAULT_NAME}[/cyan]\n"
            f"  Secret name : [cyan]{cfg.SECRET_NAME}[/cyan]\n"
            f"  Refresh     : every [cyan]{cfg.SECRET_REFRESH_INTERVAL_SECONDS}s[/cyan]\n",
            title="Initialising",
            border_style="yellow",
        )
    )

    # Graceful shutdown on Ctrl-C
    running = True

    def _stop(sig, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    with Live(
        _build_panel(),
        refresh_per_second=2,
        console=console,
        screen=False,
    ) as live:
        while running:
            simulate_db_auth()
            time.sleep(2)
            live.update(_build_panel())

    secret_cache.stop()
    console.print("\n[yellow]Demo stopped.[/yellow]")


if __name__ == "__main__":
    main()
