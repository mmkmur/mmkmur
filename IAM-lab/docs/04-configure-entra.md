# Configure Entra External ID

Entra External ID is Microsoft's CIAM platform. You'll create a free external tenant,
register your web app, and configure Keycloak as a federated SAML IDP.

## Step 1 — Create an Entra External ID tenant

1. Go to **portal.azure.com** → search "Entra External ID"
2. Click **Create a new external tenant** (free tier available)
3. Choose a tenant name, e.g. `iamlab` → your domain will be `iamlab.onmicrosoft.com`
4. Note the **Tenant ID** (GUID) — you'll use this in all config steps

> Free tier: 50,000 Monthly Active Users — more than enough for a lab.

## Step 2 — Register the web application

In your external tenant:

1. Go to **App registrations** → **New registration**
2. Fill in:
   - Name: `IAM Lab Web App`
   - Supported account types: **Accounts in this organizational directory only**
   - Redirect URI: `Single-page application (SPA)` → `http://localhost:8000/index.html`
     (add your production URL later)
3. Click **Register**
4. Note the **Application (client) ID** — update `webapp/app.js` with this value
5. Go to **Authentication** → add additional redirect URIs for production:
   - `https://<your-production-domain>/index.html`

## Step 3 — Configure custom SAML identity provider (Keycloak)

In your external tenant:

1. Go to **External Identities** → **All identity providers**
2. Click **+ New SAML/WS-Fed identity provider**
3. Fill in using your Keycloak metadata:

| Field | Value |
|-------|-------|
| Name | Keycloak (On-Prem IDP) |
| Identity provider type | SAML |
| Metadata URL | `https://<appgw-fqdn>/realms/iam-lab/protocol/saml/descriptor` |

   Or fill in manually:
   
| Field | Value |
|-------|-------|
| Entity ID | `https://<appgw-fqdn>/realms/iam-lab` |
| SAML SSO URL | `https://<appgw-fqdn>/realms/iam-lab/protocol/saml` |
| SAML logout URL | `https://<appgw-fqdn>/realms/iam-lab/protocol/saml` |
| Certificate | Paste the X509Certificate from Keycloak metadata |

4. Under **Identity provider claims mapping**:

| Entra attribute | SAML claim from Keycloak |
|-----------------|--------------------------|
| User ID | `emailaddress` (URI format) |
| Display name | (leave blank or map `name`) |
| Email | `emailaddress` |
| First name | `givenname` |
| Last name | `surname` |

5. Click **Save**

## Step 4 — Enable the IDP in a User Flow

User flows define the sign-in/sign-up experience:

1. Go to **User flows** → **New user flow**
2. Select **Sign in and sign up**
3. Name it: `B2C_1_susi` (or any name)
4. Under **Identity providers** → check **Keycloak (On-Prem IDP)**
5. Click **Create**

## Step 5 — Link the User Flow to your App

1. In **User flows** → select your flow → **Applications**
2. Click **Add application** → select **IAM Lab Web App**

## Step 6 — Update webapp/app.js

Replace the placeholders in `webapp/app.js`:

```js
authority: "https://iamlab.ciamlogin.com/iamlab.onmicrosoft.com",
//                   ^^^^^^                ^^^^^^
//                   tenant name           tenant domain

clientId: "<YOUR_APP_CLIENT_ID>",
```

> **Note**: Entra External ID uses `ciamlogin.com` (not `login.microsoftonline.com`)
> for OIDC endpoints. This is specific to external (CIAM) tenants.

## Step 7 — Test the flow end-to-end

```bash
# Serve the web app locally
cd webapp
python3 -m http.server 8000
# Open http://localhost:8000
```

Click **Sign in with Entra External ID**:

1. Browser → Entra External ID login page
2. Click **Keycloak (On-Prem IDP)**
3. Redirected to Keycloak (via App Gateway)
4. Login: `testuser` / `TestPass123!`
5. Redirected back → see your profile with claims

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| SAML signature error in Entra | Cert in metadata ≠ cert Keycloak signs with | Re-download metadata after Keycloak restarts |
| Redirect URI mismatch | App registration redirect URIs missing | Add URI in App registrations → Authentication |
| `invalid_client` from MSAL | Wrong clientId in app.js | Double-check App (client) ID |
| App Gateway returns 502 | Keycloak not running / health probe failing | SSH to VM, check `docker-compose logs keycloak` |
| Keycloak shows wrong URLs in SAML | Missing `KC_PROXY=edge` or wrong host header | Verify docker-compose env and App Gateway backend settings |

## What the `idp` claim tells you

After sign-in, the OIDC ID token issued by Entra contains:
```json
{
  "idp": "https://iamlab-keycloak.westeurope.cloudapp.azure.com/realms/iam-lab",
  "email": "testuser@iamlab.local",
  ...
}
```
The `idp` claim proves the user authenticated via Keycloak, not directly in Entra.
Your app can use this to distinguish federated vs. local users.
