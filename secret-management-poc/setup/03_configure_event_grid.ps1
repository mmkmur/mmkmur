# =============================================================
# STEP 3 – Configure Azure Event Grid System Topic on Key Vault
#          Subscribe it to the local Azure Function via ngrok
#
# Flow:
#   Key Vault ──(SecretNearExpiry)──► Event Grid
#             ──(webhook)──► Azure Function (local via ngrok)
#             ──(rotates secret)──► Key Vault
# =============================================================
# Prerequisites:
#   - Azure Function running:  cd function; func start
#   - ngrok running:           ngrok http 7071
#
# Usage:
#   $env:NGROK_URL = "https://abc123.ngrok-free.app"
#   .\setup\03_configure_event_grid.ps1
# =============================================================

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ── Load .env ─────────────────────────────────────────────────
$envFile = Join-Path $PSScriptRoot ".." ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
        }
    }
} else {
    Write-Error ".env file not found."
    exit 1
}

# ── Validate NGROK_URL ────────────────────────────────────────
if (-not $env:NGROK_URL) {
    Write-Host ""
    Write-Host "ERROR: NGROK_URL is not set." -ForegroundColor Red
    Write-Host ""
    Write-Host "Start ngrok in another terminal:"
    Write-Host "  ngrok http 7071"
    Write-Host ""
    Write-Host "Then run this script with:"
    Write-Host '  $env:NGROK_URL = "https://xxxx.ngrok-free.app"'
    Write-Host "  .\setup\03_configure_event_grid.ps1"
    exit 1
}

$subscriptionId = $env:AZURE_SUBSCRIPTION_ID
$resourceGroup  = $env:AZURE_RESOURCE_GROUP
$location       = $env:AZURE_LOCATION
$kvName         = $env:AZURE_KEYVAULT_NAME
$ngrokUrl       = $env:NGROK_URL.TrimEnd("/")

$topicName        = "evgt-$kvName"
$subscriptionName = "sub-secret-rotation"

# Function Event Grid webhook endpoint
$functionEndpoint = "$ngrokUrl/runtime/webhooks/eventgrid?functionName=RotateSecret"

# Get the Key Vault resource ID
$kvResourceId = az keyvault show `
    --name $kvName `
    --resource-group $resourceGroup `
    --query id --output tsv
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "=================================================="
Write-Host " Event Grid – System Topic Setup"
Write-Host "=================================================="
Write-Host " Key Vault    : $kvName"
Write-Host " Topic name   : $topicName"
Write-Host " Webhook URL  : $functionEndpoint"
Write-Host "=================================================="
Write-Host ""

# ── Register Event Grid provider ──────────────────────────────
Write-Host "[1/3] Registering Microsoft.EventGrid provider..."
az provider register --namespace Microsoft.EventGrid --wait
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "      Done."

# ── Create System Topic ───────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Creating Event Grid System Topic on Key Vault..."
az eventgrid system-topic create `
    --name $topicName `
    --resource-group $resourceGroup `
    --source $kvResourceId `
    --topic-type "microsoft.keyvault.vaults" `
    --location $location `
    --output table
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ── Create Event Subscription ─────────────────────────────────
Write-Host ""
Write-Host "[3/3] Creating Event Subscription (SecretNearExpiry → Function)..."
az eventgrid system-topic event-subscription create `
    --name $subscriptionName `
    --resource-group $resourceGroup `
    --system-topic-name $topicName `
    --endpoint-type webhook `
    --endpoint $functionEndpoint `
    --included-event-types "Microsoft.KeyVault.SecretNearExpiry" `
    --output table
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "✅  Event Grid configured."
Write-Host "    Topic        : $topicName"
Write-Host "    Subscription : $subscriptionName"
Write-Host "    Triggers on  : Microsoft.KeyVault.SecretNearExpiry"
Write-Host "    Delivers to  : $functionEndpoint"
Write-Host ""
Write-Host "NEXT: Run  .\setup\04_seed_secret.ps1"
