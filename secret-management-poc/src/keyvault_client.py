"""
Key Vault client with a background-refresh secret cache.

Why a cache?
  Calling Key Vault on every secret use adds latency and costs money.
  Instead we keep a local copy and refresh it every N seconds.
  When the rotation function writes a new version, the cache picks it
  up on the next refresh – no application restart needed.

Thread safety:
  A RLock protects all reads/writes to the cached values.
  The refresh runs on a daemon thread so it dies with the process.
"""
import logging
import threading
from datetime import datetime, timezone
from typing import Optional

from azure.identity import ClientSecretCredential
from azure.keyvault.secrets import SecretClient, KeyVaultSecret

import src.config as cfg

logger = logging.getLogger(__name__)


class SecretCache:
    """
    Maintains a single cached secret from Azure Key Vault.
    Refreshes itself in the background every `refresh_interval` seconds.
    """

    def __init__(self, refresh_interval: int = cfg.SECRET_REFRESH_INTERVAL_SECONDS):
        self._lock = threading.RLock()
        self._value: Optional[str] = None
        self._version: Optional[str] = None
        self._expires_on: Optional[datetime] = None
        self._last_fetched: Optional[datetime] = None
        self._refresh_count: int = 0
        self._rotation_detected: int = 0   # incremented when version changes

        credential = ClientSecretCredential(
            tenant_id=cfg.AZURE_TENANT_ID,
            client_id=cfg.AZURE_CLIENT_ID,
            client_secret=cfg.AZURE_CLIENT_SECRET,
        )
        self._client = SecretClient(vault_url=cfg.KEYVAULT_URL, credential=credential)

        # Fetch immediately so the first call to .value never returns None
        self._fetch()

        # Background refresh thread
        self._stop = threading.Event()
        t = threading.Thread(
            target=self._loop,
            args=(refresh_interval,),
            name="secret-refresh",
            daemon=True,
        )
        t.start()

    # ── Public properties ─────────────────────────────────────────────────────

    @property
    def value(self) -> str:
        with self._lock:
            return self._value

    @property
    def version(self) -> Optional[str]:
        with self._lock:
            return self._version

    @property
    def expires_on(self) -> Optional[datetime]:
        with self._lock:
            return self._expires_on

    @property
    def last_fetched(self) -> Optional[datetime]:
        with self._lock:
            return self._last_fetched

    @property
    def refresh_count(self) -> int:
        with self._lock:
            return self._refresh_count

    @property
    def rotation_count(self) -> int:
        """How many times we have detected a new secret version since startup."""
        with self._lock:
            return self._rotation_detected

    def stop(self):
        """Cleanly stop the background thread (call on app shutdown)."""
        self._stop.set()

    # ── Internal ──────────────────────────────────────────────────────────────

    def _fetch(self):
        try:
            secret: KeyVaultSecret = self._client.get_secret(cfg.SECRET_NAME)
            with self._lock:
                old_version = self._version
                self._value      = secret.value
                self._version    = secret.properties.version
                self._expires_on = secret.properties.expires_on
                self._last_fetched = datetime.now(timezone.utc)
                self._refresh_count += 1

                if old_version is not None and old_version != self._version:
                    self._rotation_detected += 1
                    logger.info(
                        "[ROTATION DETECTED] Secret '%s' version changed: %s → %s",
                        cfg.SECRET_NAME,
                        old_version[:8],
                        self._version[:8],
                    )
        except Exception as exc:
            logger.error("Failed to refresh secret from Key Vault: %s", exc)

    def _loop(self, interval: int):
        while not self._stop.wait(interval):
            self._fetch()


# Module-level singleton – import this everywhere in the demo app
secret_cache = SecretCache()
