# Secret Management POC – Microsoft Entra ID + Azure Key Vault + Event Grid

A fully local-runnable demo showing **automated secret rotation** using native Azure services.

---

## Architecture

```
┌─────────────────────┐   SecretNearExpiry event   ┌──────────────────────┐
│  Azure Key Vault    │ ─────────────────────────► │  Azure Event Grid    │
│  (stores secret,    │                             │  (System Topic on    │
│   expiry = 30 days) │                             │   Key Vault)         │
└─────────────────────┘                             └──────────┬───────────┘
         ▲                                                     │ webhook
         │ set new secret                                      ▼
         │                                          ┌──────────────────────┐
         └──────────────────────────────────────────│  Azure Function      │
                                                    │  (rotation_function) │
                                                    │  runs locally via    │
                                                    │  func start + ngrok  │
                                                    └──────────────────────┘

┌─────────────────────┐
│  Demo App           │  ── reads cached secret every 10s ──►  Key Vault
│  (demo_app.py)      │  ── shows rotation detected with NO restart
└─────────────────────┘
```

**Key services (all free-tier / pay-as-you-go, very low cost):**

| Service | Purpose | Cost |
|---|---|---|
| Azure Key Vault Standard | Store & version secrets | ~$0.03 / 10k ops |
| Azure Event Grid | Receive SecretNearExpiry, fire webhook | First 100k ops/month **free** |
| Azure Function | Rotate the secret on event | First 1M executions/month **free** |
| Entra ID App Registration | Service Principal identity | **Free** |

---

## Prerequisites

| Tool | Install |
|---|---|
| Python 3.11+ | https://python.org |
| Azure CLI | https://aka.ms/installazurecli |
| Azure Functions Core Tools v4 | https://aka.ms/azfunc-install |
| ngrok (for Event Grid webhook) | https://ngrok.com/download |

---

## Step-by-Step Setup

### 1 – Clone & install Python deps

```bash
git clone <this-repo>
cd secret-management-poc

python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

pip install -r requirements.txt
```

### 2 – Create your `.env`

```bash
cp .env.example .env
```

Fill in `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`, `AZURE_KEYVAULT_NAME`.

### 3 – Login to Azure & create resources

```bash
az login
bash setup/01_create_resources.sh
```

This creates:
- A Resource Group
- An Azure Key Vault (Standard, soft-delete enabled)

### 4 – Create Entra ID App Registration

```bash
bash setup/02_create_app_registration.sh
```

This creates:
- An App Registration in Entra ID
- A Service Principal with Key Vault access policy
- **Automatically writes** `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` into your `.env`

### 5 – Seed the initial secret

```bash
bash setup/04_seed_secret.sh
```

Creates `demo-db-password` in Key Vault with a **30-day expiry**.

### 6 – Start the Azure Function locally

In **Terminal 1**:
```bash
cd function
cp local.settings.json.example local.settings.json
# Fill in the same values as your .env
func start
```

You should see:
```
Functions:
  RotateSecret: eventGridTrigger
  rotate_http: [POST] http://localhost:7071/api/rotate
```

### 7 – Expose the Function via ngrok

In **Terminal 2**:
```bash
ngrok http 7071
```

Copy the `https://xxxx.ngrok-free.app` URL.

### 8 – Connect Event Grid to your Function

```bash
NGROK_URL=https://xxxx.ngrok-free.app bash setup/03_configure_event_grid.sh
```

This creates:
- An Event Grid **System Topic** on your Key Vault
- An **Event Subscription** that sends `SecretNearExpiry` events to your Function

### 9 – Start the Demo App

In **Terminal 3**:
```bash
python demo_app.py
```

You will see a live dashboard showing the current secret, its version, expiry, and auth activity.

---

## Demo: Triggering a Rotation

The real rotation fires automatically when Key Vault emits a `SecretNearExpiry` event (Azure sends this ~30 days before expiry).

For the demo, **simulate it immediately**:

```bash
# Terminal 4
python scripts/simulate_near_expiry.py
```

**What happens:**
1. The script calls the Azure Function's HTTP endpoint.
2. The Function generates a new random secret and writes it to Key Vault with a fresh 30-day expiry.
3. Within 10 seconds, the Demo App's cache refreshes and detects the new version.
4. The dashboard turns green: **"SECRET ROTATED – APP STILL RUNNING ✅"**

No restart of the demo app is needed.

---

## Optional: Simulate via real Event Grid webhook

If you want to exercise the full Event Grid flow:

```bash
NGROK_URL=https://xxxx.ngrok-free.app python scripts/simulate_near_expiry.py --eventgrid
```

This posts a properly formatted `Microsoft.KeyVault.SecretNearExpiry` CloudEvent to Event Grid's webhook endpoint on the Function.

---

## Check Secret Status

```bash
python scripts/check_status.py
```

Shows version history, expiry, and masked secret value.

---

## File Structure

```
secret-management-poc/
├── .env.example                    # Environment variable template
├── requirements.txt                # Demo app dependencies
├── demo_app.py                     # Main demo – live rotation dashboard
│
├── src/
│   ├── config.py                   # Loads .env, exposes typed config
│   └── keyvault_client.py          # Key Vault client + background cache
│
├── function/                       # Azure Function (rotation handler)
│   ├── function_app.py             # Event Grid + HTTP triggers
│   ├── host.json                   # Function host config
│   ├── requirements.txt            # Function dependencies
│   └── local.settings.json.example # Local dev settings template
│
├── setup/
│   ├── 01_create_resources.sh      # Create RG + Key Vault
│   ├── 02_create_app_registration.sh  # Entra ID App Reg + access policy
│   ├── 03_configure_event_grid.sh  # System Topic + Event Subscription
│   └── 04_seed_secret.sh           # Create initial secret with expiry
│
└── scripts/
    ├── simulate_near_expiry.py     # Trigger rotation for demo
    └── check_status.py             # View secret metadata + version history
```

---

## How Rotation Works

```
Key Vault emits SecretNearExpiry
        │
        ▼
Event Grid System Topic receives event
        │
        ▼
Event Subscription delivers CloudEvent to Function webhook
        │
        ▼
Azure Function (RotateSecret):
  1. Reads ObjectName from event data
  2. Generates new_value = secrets.token_hex(16)   # 128 bits entropy
  3. Sets new expiry = now + ROTATION_INTERVAL_DAYS
  4. Calls KeyVaultClient.set_secret(name, new_value, expires_on=new_expiry)
        │
        ▼
Demo App's SecretCache (background thread):
  - Every SECRET_REFRESH_INTERVAL_SECONDS, calls get_secret()
  - Compares version ID to previous cached version
  - If different → logs "ROTATION DETECTED", updates cache
  - App continues using new secret transparently
```

---

## Cleanup

```bash
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
az ad app delete --id $AZURE_CLIENT_ID
```
