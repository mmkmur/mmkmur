param location string
param prefix string
param appgwSubnetId string
param keycloakPrivateIp string

// Self-signed cert for the lab — replace with a real cert for production.
// Generate with: openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
// Then: openssl pkcs12 -export -out cert.pfx -inkey key.pem -in cert.pem -passout pass:ChangeMe123!
// Then base64 encode: base64 -w0 cert.pfx
@description('Base64-encoded PFX certificate for the HTTPS listener')
@secure()
param sslCertBase64 string

@description('Password for the PFX certificate')
@secure()
param sslCertPassword string

var appgwName = '${prefix}-appgw'
var publicIpName = '${prefix}-appgw-pip'

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${prefix}-keycloak'
    }
  }
}

resource appgw 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: appgwName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'appgw-ip-config'
        properties: { subnet: { id: appgwSubnetId } }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-ip'
        properties: { publicIPAddress: { id: publicIp.id } }
      }
    ]
    frontendPorts: [
      { name: 'port-443', properties: { port: 443 } }
      { name: 'port-80',  properties: { port: 80 } }
    ]
    sslCertificates: [
      {
        name: 'keycloak-ssl-cert'
        properties: {
          data: sslCertBase64
          password: sslCertPassword
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'keycloak-backend-pool'
        properties: {
          backendAddresses: [{ ipAddress: keycloakPrivateIp }]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'keycloak-http-settings'
        properties: {
          port: 8080
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 60
          // Keycloak needs the original host header for SAML redirect URLs
          hostName: publicIp.properties.dnsSettings.fqdn
          pickHostNameFromBackendAddress: false
          probe: { id: resourceId('Microsoft.Network/applicationGateways/probes', appgwName, 'keycloak-health-probe') }
        }
      }
    ]
    probes: [
      {
        name: 'keycloak-health-probe'
        properties: {
          protocol: 'Http'
          host: keycloakPrivateIp
          path: '/health/ready'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          port: 8080
        }
      }
    ]
    httpListeners: [
      {
        name: 'https-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appgwName, 'appgw-frontend-ip')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appgwName, 'port-443')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appgwName, 'keycloak-ssl-cert')
          }
        }
      }
      {
        name: 'http-redirect-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appgwName, 'appgw-frontend-ip')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appgwName, 'port-80')
          }
          protocol: 'Http'
        }
      }
    ]
    redirectConfigurations: [
      {
        name: 'http-to-https'
        properties: {
          redirectType: 'Permanent'
          targetListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appgwName, 'https-listener')
          }
          includePath: true
          includeQueryString: true
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'https-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appgwName, 'https-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appgwName, 'keycloak-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appgwName, 'keycloak-http-settings')
          }
        }
      }
      {
        name: 'http-redirect-rule'
        properties: {
          ruleType: 'Basic'
          priority: 200
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appgwName, 'http-redirect-listener')
          }
          redirectConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/redirectConfigurations', appgwName, 'http-to-https')
          }
        }
      }
    ]
  }
}

output appGatewayPublicFqdn string = publicIp.properties.dnsSettings.fqdn
output appGatewayPublicIp string = publicIp.properties.ipAddress
