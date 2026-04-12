# =============================================================
# STEP 1 – Create Azure Resource Group + Key Vault
# =============================================================
# Prerequisites:
#   - Azure CLI installed   https://aka.ms/installazurecli
#   - Logged in:            az login
#
# Usage (from project root):
#   .\setup\01_create_resources.ps1
# =============================================================

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ── Load .env file ────────────────────────────────────────────
$envFile = Join-Path (Join-Path $PSScriptRoot "..") ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
        }
    }
} else {
    Write-Error ".env file not found. Copy .env.example to .env and fill in your values."
    exit 1
}

# ── Validate required variables ───────────────────────────────
$required = @("AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP", "AZURE_LOCATION", "AZURE_KEYVAULT_NAME")
foreach ($var in $required) {
    if (-not [System.Environment]::GetEnvironmentVariable($var, "Process")) {
        Write-Error "Missing required variable in .env: $var"
        exit 1
    }
}

$subscriptionId = $env:AZURE_SUBSCRIPTION_ID
$resourceGroup  = $env:AZURE_RESOURCE_GROUP
$location       = $env:AZURE_LOCATION
$kvName         = $env:AZURE_KEYVAULT_NAME

Write-Host ""
Write-Host "=================================================="
Write-Host " Secret Management POC – Resource Setup"
Write-Host "=================================================="
Write-Host " Subscription  : $subscriptionId"
Write-Host " Resource Group: $resourceGroup"
Write-Host " Location      : $location"
Write-Host " Key Vault     : $kvName"
Write-Host "=================================================="
Write-Host ""

# ── Set active subscription ───────────────────────────────────
Write-Host "[1/3] Setting active subscription..."
az account set --subscription $subscriptionId
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ── Resource Group ────────────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Creating Resource Group..."
az group create `
    --name $resourceGroup `
    --location $location `
    --output table
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ── Key Vault ─────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/3] Creating Azure Key Vault (Standard, soft-delete enabled)..."
az keyvault create `
    --name $kvName `
    --resource-group $resourceGroup `
    --location $location `
    --sku standard `
    --enable-rbac-authorization false `
    --output table
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "✅  Key Vault created: https://$kvName.vault.azure.net"
Write-Host ""
Write-Host "NEXT: Run  .\setup\02_create_app_registration.ps1"
