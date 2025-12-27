param location string
param plsName string
param lbFrontendIpConfigId string
param subnetId string

resource pls 'Microsoft.Network/privateLinkServices@2021-02-01' = {
  name: plsName
  location: location
  properties: {
    loadBalancerFrontendIpConfigurations: [
      {
        id: lbFrontendIpConfigId
      }
    ]
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          primary: true
        }
      }
      {
        name: 'ipConfig2'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          primary: false
        }
      }
      {
        name: 'ipConfig3'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          primary: false
        }
      }
      {
        name: 'ipConfig4'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          primary: false
        }
      }
    ]
    visibility: {
      subscriptions: [
        subscription().subscriptionId
      ]
    }
    autoApproval: {
      subscriptions: [
        subscription().subscriptionId
      ]
    }
  }
}

output plsId string = pls.id
output plsName string = pls.name
