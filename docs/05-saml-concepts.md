# SAML 2.0 — Concepts You'll See in This Lab

## What is SAML?

SAML (Security Assertion Markup Language) is an XML-based open standard for exchanging
authentication and authorization data between parties. Version 2.0 (2005) is the current standard.

The core idea: **prove to one system that another trusted system already authenticated the user**.

## The Three Roles

```
Browser ←──────────────────────────────────────────────────────→
   │                                                              │
   │                                                              │
   ▼                                                              ▼
Service Provider (SP)           Identity Provider (IDP)
"I need to know who you are"    "I know who this user is"
e.g. Entra External ID          e.g. Keycloak
```

- **IDP** (Identity Provider): Authenticates users and issues SAML Assertions
- **SP** (Service Provider): Consumes assertions to grant access (doesn't authenticate directly)
- **Principal**: The user being authenticated

In this lab:
- **IDP** = Keycloak (on-prem, via Application Gateway)
- **SP** = Entra External ID (CIAM)
- **Relying Party** = your web app (uses OIDC with Entra, not SAML directly)

## The SAML Assertion (the key artifact)

A SAML Assertion is a signed XML document. Example (simplified):

```xml
<saml:Assertion>
  <!-- WHO issued this assertion -->
  <saml:Issuer>https://keycloak.example.com/realms/iam-lab</saml:Issuer>

  <!-- SIGNATURE — prevents tampering -->
  <ds:Signature>...</ds:Signature>

  <!-- WHO the assertion is about -->
  <saml:Subject>
    <saml:NameID Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress">
      testuser@iamlab.local
    </saml:NameID>
  </saml:Subject>

  <!-- WHEN it's valid (prevents replay attacks) -->
  <saml:Conditions
    NotBefore="2024-01-15T10:00:00Z"
    NotOnOrAfter="2024-01-15T10:05:00Z">
    <saml:AudienceRestriction>
      <!-- Only THIS SP can use this assertion -->
      <saml:Audience>https://login.microsoftonline.com/<tenant-id></saml:Audience>
    </saml:AudienceRestriction>
  </saml:Conditions>

  <!-- ATTRIBUTES about the user -->
  <saml:AttributeStatement>
    <saml:Attribute Name=".../claims/emailaddress">
      <saml:AttributeValue>testuser@iamlab.local</saml:AttributeValue>
    </saml:Attribute>
    <saml:Attribute Name=".../claims/givenname">
      <saml:AttributeValue>Test</saml:AttributeValue>
    </saml:Attribute>
  </saml:AttributeStatement>
</saml:Assertion>
```

## SP-Initiated vs IDP-Initiated SSO

**SP-Initiated** (what this lab uses — the normal case):
1. User visits the SP (Entra)
2. SP sends `AuthnRequest` to IDP
3. IDP authenticates user
4. IDP posts `Response` (with Assertion) back to SP

**IDP-Initiated**:
1. User goes directly to IDP
2. IDP creates assertion without a prior request
3. IDP posts `Response` to SP
> Less secure (no `InResponseTo` correlation), often disabled

## Bindings — How messages travel

| Binding | How | Used for |
|---------|-----|---------|
| **HTTP POST** | HTML form auto-submit | SAML Response (assertion back to SP) |
| **HTTP Redirect** | URL with deflate+base64 encoded XML | AuthnRequest (smaller messages) |
| **SOAP** | Web service call | Back-channel, ECP |

In this lab: AuthnRequest via HTTP Redirect, Response via HTTP POST.

## The Metadata document

Both SP and IDP publish a metadata XML document that describes:
- Entity ID (unique name)
- Public certificate (for signature verification)
- Endpoints (SSO URL, ACS URL, SLO URL)
- Supported bindings and name ID formats

Federation is set up by exchanging metadata. In this lab:
- Keycloak's metadata: `https://<appgw-fqdn>/realms/iam-lab/protocol/saml/descriptor`
- You paste this into Entra External ID during IDP configuration

## Security in SAML

| Mechanism | Purpose |
|-----------|---------|
| XML Signature (signing) | Ensures assertion wasn't tampered with |
| XML Encryption (optional) | Hides assertion content from browser |
| `NotBefore/NotOnOrAfter` | Limits assertion replay window (typically 5 min) |
| `InResponseTo` | Correlates Response to a specific AuthnRequest (prevents unsolicited assertions) |
| `Audience` restriction | Ensures assertion is only usable by the intended SP |

## SAML vs OIDC — When to use which?

| Dimension | SAML 2.0 | OIDC / OAuth 2.0 |
|-----------|----------|-------------------|
| Format | XML | JSON (JWT) |
| Age | 2005 | 2014 |
| Complexity | High | Lower |
| Browser support | Good (form POST) | Good (redirects) |
| Mobile/SPA | Poor | Excellent |
| Enterprise legacy | Dominant | Growing |
| IDP federation | Common | Common |

**Rule of thumb**: Use OIDC for new apps. Use SAML when integrating with enterprise IDPs
that only support SAML (common with on-prem systems like ADFS, Keycloak in enterprise setups).

This lab deliberately uses SAML for the Keycloak↔Entra federation because:
1. It's what you'll encounter with on-prem / legacy IDPs in the real world
2. SAML is required for many enterprise SSO integrations
3. It teaches you how OIDC and SAML can coexist (Entra speaks OIDC to the app, SAML to Keycloak)

## Debugging SAML

### Browser tools
- **SAML-tracer** (Firefox/Chrome extension): Decodes SAML messages in real time
- F12 → Network → filter `saml` — look for form POSTs with `SAMLResponse` parameter

### Decode a SAMLResponse manually
```bash
# SAMLResponse is base64-encoded (and sometimes deflate-compressed for Redirect binding)
echo "<SAMLResponse value>" | base64 -d | xmllint --format -
```

### Check Keycloak logs
```bash
ssh azureuser@<vm-ip>
docker logs keycloak_keycloak_1 --tail=50 -f
# Look for SAML client matching, assertion creation, signature
```

### Common errors
| Error | Meaning |
|-------|---------|
| `Issuer not found` | Entity ID mismatch between SP config and actual request |
| `Signature validation failed` | Wrong certificate configured, or cert expired |
| `AudienceRestriction` failed | Assertion's Audience doesn't match SP entity ID |
| `NotOnOrAfter in the past` | Clock skew between IDP and SP (keep clocks synced!) |
