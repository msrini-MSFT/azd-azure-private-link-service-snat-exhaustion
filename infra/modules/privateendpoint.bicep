param location string
param peName string
param subnetId string
param plsId string

resource pe 'Microsoft.Network/privateEndpoints@2021-02-01' = {
  name: peName
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: peName
        properties: {
          privateLinkServiceId: plsId
        }
      }
    ]
  }
}

output peId string = pe.id
// output peIp string = pe.properties.customDnsConfigs[0].ipAddresses[0] // This might not be populated for PLS, usually we look at networkInterfaces
