# IAM Lab — Architecture Overview

## What you are building

A CIAM (Customer Identity and Access Management) lab that demonstrates SAML 2.0 federation
between an on-premises Identity Provider (Keycloak) and a cloud CIAM platform (Entra External ID).
A small web application signs users in via OIDC through Entra, which federates authentication
to Keycloak using SAML.

```
┌────────────────────────────────────────────────────────────────────┐
│  User's Browser                                                     │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 1. Open app / click Sign In
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  Web Application  (webapp/)                                         │
│  · Static HTML + JS with Canvas UI                                  │
│  · MSAL.js — OIDC Authorization Code + PKCE flow                   │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 2. OIDC redirect (Authorization Code)
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  Entra External ID (CIAM tenant)                                    │
│  · ciamlogin.com endpoint                                           │
│  · Issues OIDC ID tokens to the web app                             │
│  · Configured with Keycloak as a custom SAML identity provider      │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 3. SAML AuthnRequest (POST binding)
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  Azure Application Gateway                                          │
│  · Public DNS: <prefix>-keycloak.<region>.cloudapp.azure.com        │
│  · TLS termination (your PFX cert)                                  │
│  · HTTP/80 → HTTPS/443 redirect                                     │
│  · Proxies to Keycloak VM on port 8080                              │
│  · Passes X-Forwarded-Proto: https so Keycloak builds correct URLs  │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 4. HTTP to Keycloak:8080
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  Azure VM — Ubuntu 22.04                                            │
│  └── Docker Compose                                                 │
│       ├── Keycloak 24 (SAML IDP)                                    │
│       │    Realm: iam-lab                                            │
│       │    SAML SP: Entra External ID entity ID                     │
│       └── PostgreSQL 15 (Keycloak database)                         │
└────────────────────────────────────────────────────────────────────┘
```

## Protocol flow (step by step)

| Step | Protocol | Direction | Description |
|------|----------|-----------|-------------|
| 1 | HTTPS | Browser → App | User loads the web app |
| 2 | OIDC Auth Code+PKCE | Browser → Entra | App redirects browser to Entra |
| 3 | SAML AuthnRequest | Entra → App Gateway → Keycloak | Entra sends SAML request to Keycloak |
| 4 | Keycloak login page | Keycloak → Browser | User enters credentials in Keycloak |
| 5 | SAML Response | Browser → Entra | Keycloak posts signed SAML assertion |
| 6 | OIDC Token | Entra → App | Entra exchanges assertion for OIDC token |
| 7 | Profile rendered | App → Browser | App displays user info from ID token |

## Key IAM concepts in this lab

### SAML 2.0
- **IDP (Identity Provider)**: Keycloak — authenticates users and issues assertions
- **SP (Service Provider)**: Entra External ID — consumes assertions to federate identity
- **SAML Assertion**: Signed XML document containing user attributes (email, name, etc.)
- **SSO URL**: Where the SP sends the AuthnRequest (Keycloak's SAML endpoint)
- **ACS URL** (Assertion Consumer Service): Where the IDP posts the SAML Response (Entra's endpoint)
- **Entity ID**: Unique identifier for the SP; Entra uses `https://login.microsoftonline.com/<tenant-id>`
- **Metadata**: XML document describing an IDP or SP — exchange this to set up federation

### OIDC / OAuth 2.0
- **Authorization Code + PKCE**: The recommended browser flow — no client secret needed
- **ID Token**: JWT containing user identity claims (sub, email, name, idp)
- **Access Token**: Used to call APIs (not needed in this lab)
- The `idp` claim in the token tells you which federated IDP authenticated the user (Keycloak)

### CIAM vs Workforce IAM
| Dimension | CIAM (this lab) | Workforce IAM |
|-----------|-----------------|---------------|
| Users | External customers | Employees |
| Scale | Millions | Thousands |
| Self-service | Registration, password reset | Helpdesk driven |
| Entra product | **Entra External ID** | Entra ID (Entra P1/P2) |
| Tenant type | External tenant | Workforce tenant |

## Component responsibilities

| Component | Role | Hosts |
|-----------|------|-------|
| Keycloak | SAML IDP — user store, authentication | Azure VM |
| Application Gateway | TLS termination, public DNS, WAF-ready | Azure PaaS |
| Entra External ID | CIAM — SAML SP + OIDC provider | Microsoft cloud |
| Web app | Relying Party — uses OIDC to sign users in | Static files |
