# Configure Keycloak

After the VM is running and Keycloak is healthy, run the setup script to create the realm,
test user, and SAML client for Entra External ID.

## Step 1 — Run configure-realm.sh

```bash
export KEYCLOAK_URL="https://iamlab-keycloak.westeurope.cloudapp.azure.com"
export ADMIN_USER="admin"
export ADMIN_PASS="ChangeMe123!"
export ENTRA_TENANT_ID="<your-entra-external-id-tenant-id>"   # from Step 1 of doc 04

chmod +x keycloak/configure-realm.sh
./keycloak/configure-realm.sh
```

This creates:
- Realm `iam-lab`
- Test user `testuser` / `TestPass123!`
- SAML client representing Entra External ID as the Service Provider

## Step 2 — Verify via Admin Console

1. Open `${KEYCLOAK_URL}/admin` → login
2. Switch to realm **iam-lab** (top-left dropdown)
3. Go to **Clients** → you should see the Entra entity ID as a SAML client
4. Go to **Users** → `testuser` should be there

## Step 3 — Download Keycloak SAML Metadata

This XML document is what you upload to Entra External ID.

```bash
curl -sk "${KEYCLOAK_URL}/realms/iam-lab/protocol/saml/descriptor" \
  -o keycloak-idp-metadata.xml

# Inspect it — look for:
# - entityID (Keycloak's IDP entity ID)
# - SingleSignOnService Location (SSO URL)
# - X509Certificate (signing cert)
cat keycloak-idp-metadata.xml
```

## Step 4 — Understand the SAML Client configuration

Open the SAML client in the Keycloak Admin Console and explore these settings:

| Setting | Value | Why |
|---------|-------|-----|
| Client ID | `https://login.microsoftonline.com/<tenant>` | Entra's entity ID |
| Valid Redirect URIs | `https://login.microsoftonline.com/<tenant>/saml2` | Entra's ACS URL |
| Name ID format | email | Entra maps this to the user's UPN |
| Sign assertions | ON | Entra validates the signature |
| KC_PROXY=edge | (in docker env) | Tells Keycloak App Gateway terminates TLS |

## Step 5 — Protocol Mappers

The SAML client is pre-configured with these attribute mappers:

| Claim | Source | SAML Attribute URI |
|-------|--------|--------------------|
| email | user.email | `.../claims/emailaddress` |
| given_name | user.firstName | `.../claims/givenname` |
| surname | user.lastName | `.../claims/surname` |

Entra reads `emailaddress` to identify the user. You can add more mappers
(e.g., groups, roles) from **Clients → [client] → Mappers → Add mapper**.

## Useful Keycloak URLs

| Purpose | URL |
|---------|-----|
| Admin Console | `${KEYCLOAK_URL}/admin` |
| Realm home | `${KEYCLOAK_URL}/realms/iam-lab` |
| SAML IDP Metadata | `${KEYCLOAK_URL}/realms/iam-lab/protocol/saml/descriptor` |
| SAML SSO (POST) | `${KEYCLOAK_URL}/realms/iam-lab/protocol/saml` |
| Health check | `${KEYCLOAK_URL}/health/ready` |
| Metrics | `${KEYCLOAK_URL}/metrics` |

## Changing the admin password (do this first!)

```bash
# Via Admin Console: top-right → Manage account → Change password
# Or via CLI inside the VM:
ssh azureuser@<vm-ip>
docker exec -it keycloak_keycloak_1 \
  /opt/keycloak/bin/kcadm.sh set-password \
  -r master --username admin --new-password '<NewStrongPass>'
```
