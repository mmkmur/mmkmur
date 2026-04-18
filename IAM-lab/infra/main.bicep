targetScope = 'resourceGroup'

@description('Prefix for all resource names')
param prefix string = 'iamlab'

@description('Azure region')
param location string = resourceGroup().location

@description('SSH admin username for the Keycloak VM')
param adminUsername string = 'azureuser'

@description('SSH public key for the Keycloak VM')
param adminSshPublicKey string

@description('Base64-encoded PFX certificate for Application Gateway HTTPS listener')
@secure()
param sslCertBase64 string

@description('Password of the PFX certificate')
@secure()
param sslCertPassword string

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    prefix: prefix
  }
}

module vm 'modules/vm.bicep' = {
  name: 'keycloak-vm'
  params: {
    location: location
    prefix: prefix
    vmSubnetId: network.outputs.vmSubnetId
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
  }
}

module appgw 'modules/appgateway.bicep' = {
  name: 'appgateway'
  params: {
    location: location
    prefix: prefix
    appgwSubnetId: network.outputs.appgwSubnetId
    keycloakPrivateIp: vm.outputs.vmPrivateIp
    sslCertBase64: sslCertBase64
    sslCertPassword: sslCertPassword
  }
}

output keycloakPublicUrl string = 'https://${appgw.outputs.appGatewayPublicFqdn}'
output keycloakPublicIp string = appgw.outputs.appGatewayPublicIp
output keycloakPrivateIp string = vm.outputs.vmPrivateIp
