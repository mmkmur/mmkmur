# IAM Lab — SAML Federation with Keycloak + Entra External ID

A hands-on lab for learning Customer Identity and Access Management (CIAM) and SAML 2.0
federation. Deploy Keycloak on an Azure VM, expose it via Application Gateway, and federate
it with Entra External ID so users can sign into a web app.

## Architecture

```
Browser → Web App (OIDC) → Entra External ID (SAML SP) → App Gateway → Keycloak VM (SAML IDP)
```

| Component | Role | Technology |
|-----------|------|-----------|
| Web app | Relying Party — OIDC sign-in | HTML + MSAL.js |
| Entra External ID | CIAM — OIDC provider + SAML SP | Microsoft cloud |
| Application Gateway | TLS termination + reverse proxy | Azure PaaS |
| Keycloak | On-prem SAML IDP + user store | Docker on Azure VM |

## Quick Start

```
Step 1 → docs/02-deploy-infrastructure.md    Deploy Azure VM + App Gateway
Step 2 → docs/03-configure-keycloak.md       Create realm, users, SAML client
Step 3 → docs/04-configure-entra.md          Create External ID tenant + IDP config
Step 4 → edit webapp/app.js                  Add your tenant ID and client ID
Step 5 → python3 -m http.server 8000         Serve webapp locally and test
```

## Repository structure

```
infra/
  main.bicep                  Azure deployment entry point
  parameters.example.json     Template — copy to parameters.json
  modules/
    network.bicep             VNet, subnets, NSGs
    vm.bicep                  Ubuntu VM + bootstrap extension
    appgateway.bicep          Application Gateway (TLS, routing)

keycloak/
  docker-compose.yml          Local dev compose (start-dev mode)
  bootstrap.sh                VM first-boot install script
  configure-realm.sh          Creates realm, user, SAML client via API

webapp/
  index.html                  Sign-in page with Canvas UI
  app.js                      MSAL.js OIDC authentication
  styles.css                  Dark theme styles

docs/
  01-architecture.md          Architecture + IAM concepts overview
  02-deploy-infrastructure.md Step-by-step Azure deployment
  03-configure-keycloak.md    Keycloak realm and SAML setup
  04-configure-entra.md       Entra External ID + user flow setup
  05-saml-concepts.md         SAML 2.0 learning reference
```

## What you will learn

- **SAML 2.0**: SP-initiated SSO, AuthnRequest, SAML Assertions, bindings, metadata exchange
- **OIDC / OAuth 2.0**: Authorization Code + PKCE flow, ID tokens, MSAL.js
- **CIAM vs Workforce IAM**: Why Entra External ID exists as a separate product
- **Federation patterns**: How OIDC and SAML coexist in a real architecture
- **Azure networking**: Application Gateway as a reverse proxy with TLS termination
- **Keycloak**: Realm management, protocol mappers, SAML client configuration

## Local development (no Azure needed)

```bash
# Start Keycloak locally
docker-compose -f keycloak/docker-compose.yml up -d

# Configure realm (targets localhost:8080)
export KEYCLOAK_URL=http://localhost:8080
export ADMIN_PASS=admin
export ENTRA_TENANT_ID=<your-tenant-id>
./keycloak/configure-realm.sh

# Serve web app
cd webapp && python3 -m http.server 8000
```

Note: For local Keycloak, Entra cannot reach it (no public URL). Use the full Azure deployment
for end-to-end SAML federation testing, or use ngrok to expose Keycloak during development.
