# Deploy Infrastructure

## Prerequisites

- Azure CLI installed and logged in (`az login`)
- A resource group already created (or create one below)
- An SSH key pair (generate with `ssh-keygen -t ed25519`)
- OpenSSL installed (for generating the self-signed cert)

## Step 1 — Create resource group

```bash
az group create \
  --name rg-iamlab \
  --location westeurope
```

## Step 2 — Generate a self-signed TLS certificate

The Application Gateway needs a PFX certificate. For the lab, a self-signed cert is fine.
For production / public demos, use a cert from Let's Encrypt or your CA.

```bash
# Generate private key and self-signed cert (valid 1 year)
openssl req -x509 -newkey rsa:4096 \
  -keyout keycloak-key.pem \
  -out keycloak-cert.pem \
  -days 365 -nodes \
  -subj "/CN=iamlab-keycloak.westeurope.cloudapp.azure.com/O=IAM Lab"

# Bundle into PFX (Application Gateway requires PFX format)
CERT_PASS="ChangeMe123!"
openssl pkcs12 -export \
  -out keycloak.pfx \
  -inkey keycloak-key.pem \
  -in keycloak-cert.pem \
  -passout pass:${CERT_PASS}

# Base64-encode for the Bicep parameter
CERT_B64=$(base64 -w0 keycloak.pfx)
echo "Certificate base64 length: ${#CERT_B64} chars"
```

> **Note**: If you already have a domain and a Let's Encrypt cert, use that instead.
> Convert with: `openssl pkcs12 -export -out cert.pfx -inkey privkey.pem -in fullchain.pem`

## Step 3 — Copy and fill in parameters

```bash
cp infra/parameters.example.json infra/parameters.json
```

Edit `infra/parameters.json`:

```json
{
  "$schema": "...",
  "parameters": {
    "prefix":           { "value": "iamlab" },
    "location":         { "value": "westeurope" },
    "adminUsername":    { "value": "azureuser" },
    "adminSshPublicKey":{ "value": "<contents of ~/.ssh/id_ed25519.pub>" },
    "sslCertBase64":    { "value": "<CERT_B64 from Step 2>" },
    "sslCertPassword":  { "value": "ChangeMe123!" }
  }
}
```

## Step 4 — Deploy Bicep template

```bash
az deployment group create \
  --resource-group rg-iamlab \
  --template-file infra/main.bicep \
  --parameters @infra/parameters.json \
  --name iamlab-deploy
```

Deployment takes ~10 minutes (Application Gateway is the slowest resource).

## Step 5 — Get outputs

```bash
az deployment group show \
  --resource-group rg-iamlab \
  --name iamlab-deploy \
  --query properties.outputs

# You should see:
# keycloakPublicUrl  — e.g. https://iamlab-keycloak.westeurope.cloudapp.azure.com
# keycloakPublicIp   — the static IP
# keycloakPrivateIp  — VM's private IP (for SSH via bastion or VPN)
```

## Step 6 — Verify Keycloak is running

Allow ~5 minutes after deployment for the Custom Script Extension to finish installing Docker
and pulling the Keycloak image.

```bash
# From a machine that can reach the public IP (bootstrap script may need a moment)
KEYCLOAK_URL="https://iamlab-keycloak.westeurope.cloudapp.azure.com"
curl -sk "${KEYCLOAK_URL}/health/ready" | jq .
# Expected: { "status": "UP" }
```

Open `${KEYCLOAK_URL}/admin` in your browser to access the Keycloak Admin Console.
Login: `admin` / `ChangeMe123!` (change this immediately).

## Step 7 — SSH to the VM (optional)

The VM has no public IP — connect via Azure Bastion or add a jump box if needed.
Alternatively, enable Azure Bastion in the portal for secure SSH without a public IP.

```bash
# If you add a public IP for troubleshooting:
ssh azureuser@<vm-public-ip>
sudo docker-compose -f /opt/keycloak/docker-compose.yml logs -f keycloak
```

## Cost estimate (westeurope, 2024)

| Resource | SKU | ~Monthly Cost |
|----------|-----|--------------|
| VM | Standard_B2s | ~$30 |
| Application Gateway | Standard_v2 (1 unit) | ~$125 |
| Public IP | Standard | ~$4 |
| Managed disk | Premium LRS 64 GB | ~$10 |
| **Total** | | **~$169/month** |

> **Tip**: Stop the VM and Application Gateway when not in use to reduce costs.
> `az vm deallocate --resource-group rg-iamlab --name iamlab-keycloak-vm`
> Application Gateway must be deleted or stopped via its own command:
> `az network application-gateway stop --resource-group rg-iamlab --name iamlab-appgw`
