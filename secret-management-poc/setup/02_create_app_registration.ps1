# =============================================================
# STEP 2 - Create Microsoft Entra ID App Registration
#          and grant it Key Vault access
# =============================================================
# Usage: .\setup\02_create_app_registration.ps1
# =============================================================

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# Load .env
$envFile = Join-Path (Join-Path $PSScriptRoot "..") ".env"
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

$kvName        = $env:AZURE_KEYVAULT_NAME
$resourceGroup = $env:AZURE_RESOURCE_GROUP
$appName       = "sp-secret-poc"

Write-Host ""
Write-Host "=================================================="
Write-Host " Entra ID - App Registration"
Write-Host "=================================================="
Write-Host " App name  : $appName"
Write-Host " Key Vault : $kvName"
Write-Host "=================================================="
Write-Host ""

# [1/4] Create App Registration
Write-Host "[1/4] Creating App Registration in Entra ID..."
$appJson  = az ad app create --display-name $appName --output json | ConvertFrom-Json
$clientId = $appJson.appId
Write-Host "      Client ID: $clientId"

# [2/4] Create Service Principal
Write-Host ""
Write-Host "[2/4] Creating Service Principal..."
az ad sp create --id $clientId --output none
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# [3/4] Create client secret (2-year validity)
Write-Host ""
Write-Host "[3/4] Creating client secret (valid 2 years)..."
$credJson      = az ad app credential reset --id $clientId --years 2 --output json | ConvertFrom-Json
$clientSecret  = $credJson.password
$tenantId      = $credJson.tenant

Write-Host "      Tenant ID     : $tenantId"
Write-Host "      Client ID     : $clientId"
Write-Host "      Client Secret : [hidden - will be written to .env]"

# [4/4] Grant Key Vault access policy
Write-Host ""
Write-Host "[4/4] Granting Key Vault access policy (get, list, set, delete)..."
az keyvault set-policy `
    --name $kvName `
    --spn $clientId `
    --secret-permissions get list set delete `
    --output none
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Write credentials back into .env
Write-Host ""
Write-Host "Writing credentials to .env ..."

$envPath = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") ".env")
$content = Get-Content $envPath -Raw

@{
    AZURE_TENANT_ID     = $tenantId
    AZURE_CLIENT_ID     = $clientId
    AZURE_CLIENT_SECRET = $clientSecret
}.GetEnumerator() | ForEach-Object {
    $key = $_.Key
    $val = $_.Value
    if ($content -match "(?m)^$key=.*$") {
        $content = $content -replace "(?m)^$key=.*$", "$key=$val"
    } else {
        $content += "`n$key=$val"
    }
}

Set-Content -Path $envPath -Value $content -NoNewline
Write-Host "  .env updated."

Write-Host ""
Write-Host "App Registration complete."
Write-Host "    Service Principal : $appName"
Write-Host "    Client ID         : $clientId"
Write-Host ""
Write-Host "NEXT: Run  .\setup\03_configure_event_grid.ps1"
