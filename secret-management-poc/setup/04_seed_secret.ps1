# =============================================================
# STEP 4 – Create the initial secret in Key Vault
#          with a 30-day expiry so Event Grid fires near-expiry
# =============================================================
# Usage: .\setup\04_seed_secret.ps1
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

$kvName         = $env:AZURE_KEYVAULT_NAME
$secretName     = if ($env:SECRET_NAME) { $env:SECRET_NAME } else { "demo-db-password" }
$rotationDays   = if ($env:ROTATION_INTERVAL_DAYS) { [int]$env:ROTATION_INTERVAL_DAYS } else { 30 }

# Compute expiry date = now + rotationDays (ISO-8601 UTC)
$expiryDate = (Get-Date).ToUniversalTime().AddDays($rotationDays).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Generate a random 32-character hex secret (128 bits entropy)
$bytes        = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$initialValue = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""

Write-Host ""
Write-Host "=================================================="
Write-Host " Seeding initial secret"
Write-Host "=================================================="
Write-Host " Key Vault   : $kvName"
Write-Host " Secret name : $secretName"
Write-Host " Expiry      : $expiryDate  ($rotationDays days from now)"
Write-Host " Value       : [hidden]"
Write-Host "=================================================="
Write-Host ""

az keyvault secret set `
    --vault-name $kvName `
    --name $secretName `
    --value $initialValue `
    --expires $expiryDate `
    --description "Demo DB password – managed by secret rotation POC" `
    --output table
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "✅  Secret seeded successfully."
Write-Host "    Key Vault will emit SecretNearExpiry before the expiry date."
Write-Host ""
Write-Host "To verify the secret:"
Write-Host "  az keyvault secret show --vault-name $kvName --name $secretName"
Write-Host ""
Write-Host "NEXT STEPS:"
Write-Host "  1. Start the Function:  cd function; func start"
Write-Host "  2. Start ngrok:         ngrok http 7071"
Write-Host "  3. Configure Event Grid:"
Write-Host '     $env:NGROK_URL = "https://xxxx.ngrok-free.app"'
Write-Host "     .\setup\03_configure_event_grid.ps1"
Write-Host "  4. Start demo app:      python demo_app.py"
Write-Host "  5. Trigger rotation:    python scripts\simulate_near_expiry.py"
