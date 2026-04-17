#!/bin/bash
# Run this script AFTER Keycloak is running to create the iam-lab realm,
# a test user, and the SAML Service Provider for Entra External ID.
#
# Usage:
#   KEYCLOAK_URL=https://<your-appgw-fqdn> ./configure-realm.sh
#
# Prerequisites: curl, jq

set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-ChangeMe123!}"
REALM="iam-lab"

# ── 1. Get admin token ───────────────────────────────────────────────────────
echo "Getting admin access token..."
TOKEN=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASS}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  | jq -r '.access_token')

AUTH="Authorization: Bearer ${TOKEN}"

# ── 2. Create realm ──────────────────────────────────────────────────────────
echo "Creating realm: ${REALM}..."
curl -sf -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"realm\": \"${REALM}\",
    \"displayName\": \"IAM Lab\",
    \"enabled\": true,
    \"registrationAllowed\": false,
    \"sslRequired\": \"external\"
  }" || echo "Realm may already exist, continuing..."

# ── 3. Create a test user ────────────────────────────────────────────────────
echo "Creating test user..."
curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "testuser@iamlab.local",
    "firstName": "Test",
    "lastName": "User",
    "enabled": true,
    "emailVerified": true,
    "credentials": [
      {
        "type": "password",
        "value": "TestPass123!",
        "temporary": false
      }
    ]
  }' || echo "User may already exist, continuing..."

# ── 4. Create SAML client (Entra External ID as SP) ─────────────────────────
# Entra External ID SAML endpoint: replace <tenant-id> with your Entra External ID tenant ID
ENTRA_TENANT_ID="${ENTRA_TENANT_ID:-<your-entra-external-id-tenant-id>}"
ENTRA_SAML_ENTITY_ID="https://login.microsoftonline.com/${ENTRA_TENANT_ID}"
ENTRA_ACS_URL="https://login.microsoftonline.com/${ENTRA_TENANT_ID}/saml2"

echo "Creating SAML client for Entra External ID..."
curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"clientId\": \"${ENTRA_SAML_ENTITY_ID}\",
    \"protocol\": \"saml\",
    \"enabled\": true,
    \"name\": \"Entra External ID (SAML SP)\",
    \"description\": \"Entra External ID acting as SAML Service Provider\",
    \"redirectUris\": [\"${ENTRA_ACS_URL}\"],
    \"attributes\": {
      \"saml.authn.statement\": \"true\",
      \"saml.server.signature\": \"true\",
      \"saml.assertion.signature\": \"true\",
      \"saml_assertion_consumer_url.post\": \"${ENTRA_ACS_URL}\",
      \"saml_assertion_consumer_url.redirect\": \"${ENTRA_ACS_URL}\",
      \"saml.force.post.binding\": \"true\",
      \"saml.client.signature\": \"false\",
      \"saml.signing.certificate\": \"\",
      \"saml_name_id_format\": \"email\",
      \"saml.signature.algorithm\": \"RSA_SHA256\"
    },
    \"protocolMappers\": [
      {
        \"name\": \"email\",
        \"protocol\": \"saml\",
        \"protocolMapper\": \"saml-user-property-mapper\",
        \"config\": {
          \"user.attribute\": \"email\",
          \"attribute.name\": \"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress\",
          \"attribute.nameformat\": \"URI Reference\",
          \"friendly.name\": \"email\"
        }
      },
      {
        \"name\": \"givenname\",
        \"protocol\": \"saml\",
        \"protocolMapper\": \"saml-user-property-mapper\",
        \"config\": {
          \"user.attribute\": \"firstName\",
          \"attribute.name\": \"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname\",
          \"attribute.nameformat\": \"URI Reference\",
          \"friendly.name\": \"givenname\"
        }
      },
      {
        \"name\": \"surname\",
        \"protocol\": \"saml\",
        \"protocolMapper\": \"saml-user-property-mapper\",
        \"config\": {
          \"user.attribute\": \"lastName\",
          \"attribute.name\": \"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname\",
          \"attribute.nameformat\": \"URI Reference\",
          \"friendly.name\": \"surname\"
        }
      }
    ]
  }" || echo "SAML client may already exist."

echo ""
echo "Done! Key Keycloak SAML endpoints for Entra configuration:"
echo "  IDP Metadata URL : ${KEYCLOAK_URL}/realms/${REALM}/protocol/saml/descriptor"
echo "  SSO URL (POST)   : ${KEYCLOAK_URL}/realms/${REALM}/protocol/saml"
echo "  SLO URL          : ${KEYCLOAK_URL}/realms/${REALM}/protocol/saml"
echo ""
echo "Add these to Entra External ID > External Identities > Custom identity providers."
