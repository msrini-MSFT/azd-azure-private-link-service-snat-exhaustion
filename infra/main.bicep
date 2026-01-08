param location string = resourceGroup().location
param environmentName string
param adminUsername string = 'azureuser'
param principalId string = ''

// Generate unique passwords for each VM using parameter defaults
@secure()
param serverVmPassword string = newGuid()
@secure()
param clientVm1Password string = newGuid()
@secure()
param clientVm2Password string = newGuid()

// Tags that should be applied to all resources
var tags = {
  'azd-env-name': environmentName
  'securityControl': 'ignore'
}

// Client NSG
module clientNsg 'modules/nsg.bicep' = {
  name: 'clientNsg'
  params: {
    location: location
    nsgName: '${environmentName}-client-nsg'
    tags: tags
  }
}

// Server NSG
module serverNsg 'modules/nsg.bicep' = {
  name: 'serverNsg'
  params: {
    location: location
    nsgName: '${environmentName}-server-nsg'
    tags: tags
  }
}

module kv 'modules/keyvault.bicep' = {
  name: 'kv'
  params: {
    location: location
    vaultName: 'kv-${uniqueString(resourceGroup().id)}'
    tenantId: subscription().tenantId
    adminUsername: adminUsername
    serverVmPassword: serverVmPassword
    clientVm1Password: clientVm1Password
    clientVm2Password: clientVm2Password
    principalId: principalId
    tags: tags
  }
}

// Provider Resources
module natGateway 'modules/natgateway.bicep' = {
  name: 'natGateway'
  params: {
    location: location
    natGatewayName: '${environmentName}-provider-natgw'
    publicIpName: '${environmentName}-provider-natgw-pip'
    tags: tags
  }
}

module providerVnet 'modules/vnet.bicep' = {
  name: 'providerVnet'
  params: {
    location: location
    vnetName: '${environmentName}-provider-vnet'
    addressPrefix: '172.16.0.0/16'
    subnets: [
      {
        name: 'server-subnet'
        addressPrefix: '172.16.1.0/24'
        natGatewayId: natGateway.outputs.natGatewayId
        privateLinkServiceNetworkPolicies: 'Disabled'
      }
    ]
    tags: tags
  }
}

module lb 'modules/loadbalancer.bicep' = {
  name: 'lb'
  params: {
    location: location
    lbName: '${environmentName}-provider-lb'
    subnetId: providerVnet.outputs.subnetIds[0].id
    tags: tags
  }
}

var serverCustomData = '''#cloud-config
package_upgrade: true
packages:
  - nginx
write_files:
  - content: |
      Hello from PLS Provider
    path: /var/www/html/index.html
runcmd:
  - systemctl restart nginx
'''

resource serverPip 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${environmentName}-server-vm-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

module serverVm 'modules/vm.bicep' = {
  name: 'serverVm'
  params: {
    location: location
    vmName: '${environmentName}-server-vm'
    subnetId: providerVnet.outputs.subnetIds[0].id
    adminUsername: adminUsername
    adminPassword: serverVmPassword
    backendPoolId: lb.outputs.backendPoolId
    customData: serverCustomData
    publicIpId: serverPip.id
    nsgId: serverNsg.outputs.nsgId
    tags: tags
  }
}

module pls 'modules/privatelinkservice.bicep' = {
  name: 'pls'
  params: {
    location: location
    plsName: '${environmentName}-provider-pls'
    lbFrontendIpConfigId: lb.outputs.frontendIpConfigId
    subnetId: providerVnet.outputs.subnetIds[0].id
    tags: tags
  }
}

// Client Resources
module clientVnet 'modules/vnet.bicep' = {
  name: 'clientVnet'
  params: {
    location: location
    vnetName: '${environmentName}-client-vnet'
    addressPrefix: '10.0.0.0/16'
    subnets: [
      {
        name: 'pe-subnet'
        addressPrefix: '10.0.1.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
      }
      {
        name: 'vm-subnet'
        addressPrefix: '10.0.2.0/24'
        networkSecurityGroupId: clientNsg.outputs.nsgId
      }
    ]
    tags: tags
  }
}

module pe1 'modules/privateendpoint.bicep' = {
  name: 'pe1'
  params: {
    location: location
    peName: '${environmentName}-client-pe-1'
    subnetId: clientVnet.outputs.subnetIds[0].id
    plsId: pls.outputs.plsId
    tags: tags
  }
}

module pe2 'modules/privateendpoint.bicep' = {
  name: 'pe2'
  params: {
    location: location
    peName: '${environmentName}-client-pe-2'
    subnetId: clientVnet.outputs.subnetIds[0].id
    plsId: pls.outputs.plsId
    tags: tags
  }
}

module pe3 'modules/privateendpoint.bicep' = {
  name: 'pe3'
  params: {
    location: location
    peName: '${environmentName}-client-pe-3'
    subnetId: clientVnet.outputs.subnetIds[0].id
    plsId: pls.outputs.plsId
    tags: tags
  }
}

module pe4 'modules/privateendpoint.bicep' = {
  name: 'pe4'
  params: {
    location: location
    peName: '${environmentName}-client-pe-4'
    subnetId: clientVnet.outputs.subnetIds[0].id
    plsId: pls.outputs.plsId
    tags: tags
  }
}

resource clientPip 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${environmentName}-client-vm-1-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

var clientCustomData = '''#cloud-config
package_upgrade: true
packages:
  - hping3
  - netcat
  - python3
write_files:
  - content: |
      import socket
      import sys
      import time
      import resource
      import threading

      # Usage: python3 exhaust_snat.py <TARGET_IPS_COMMA_SEPARATED> <PORT> <CONNECTIONS_PER_IP>

      def set_limits():
          # Increase the number of open files allowed
          soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
          print(f"Current limits: soft={soft}, hard={hard}")
          try:
              resource.setrlimit(resource.RLIMIT_NOFILE, (hard, hard))
              print(f"New limits: {resource.getrlimit(resource.RLIMIT_NOFILE)}")
          except Exception as e:
              print(f"Failed to set limits: {e}")

      def connect_to_target(target_ip, target_port, count, results):
          sockets = []
          print(f"Thread starting: Establishing {count} connections to {target_ip}:{target_port}...")
          
          for i in range(count):
              try:
                  s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                  s.connect((target_ip, target_port))
                  s.send(b"GET / HTTP/1.1\\r\\nHost: localhost\\r\\n")
                  sockets.append(s)
                  
                  if i % 500 == 0:
                      print(f"[{target_ip}] Established {i} connections...")
                      sys.stdout.flush()
                      
              except OSError as e:
                  print(f"[{target_ip}] Error at connection {i}: {e}")
                  if e.errno == 99 or e.errno == 24: 
                      print(f"[{target_ip}] Hit system limit.")
                      break
                  time.sleep(0.1)
              except Exception as e:
                  print(f"[{target_ip}] Unexpected error: {e}")
                  break
          
          print(f"[{target_ip}] Finished. Holding {len(sockets)} connections open.")
          results.extend(sockets)
          
          # Keep thread alive
          while True:
              time.sleep(10)

      if __name__ == "__main__":
          if len(sys.argv) < 2:
              print(f"Usage: {sys.argv[0]} <TARGET_IPS_COMMA_SEPARATED> [PORT] [CONNECTIONS_PER_IP]")
              sys.exit(1)
              
          target_ips = sys.argv[1].split(',')
          port = int(sys.argv[2]) if len(sys.argv) > 2 else 80
          conns_per_ip = int(sys.argv[3]) if len(sys.argv) > 3 else 15000
          
          set_limits()
          
          all_sockets = []
          threads = []
          
          for ip in target_ips:
              t = threading.Thread(target=connect_to_target, args=(ip, port, conns_per_ip, all_sockets))
              t.daemon = True
              t.start()
              threads.append(t)
              
          print(f"Started {len(threads)} threads. Press Ctrl+C to stop.")
          
          try:
              while True:
                  time.sleep(1)
          except KeyboardInterrupt:
              print("Stopping...")
    path: /home/azureuser/exhaust_snat.py
    permissions: '0644'
runcmd:
  - echo "* soft nofile 65535" >> /etc/security/limits.conf
  - echo "* hard nofile 65535" >> /etc/security/limits.conf
  - echo "root soft nofile 65535" >> /etc/security/limits.conf
  - echo "root hard nofile 65535" >> /etc/security/limits.conf
  - sysctl -w fs.file-max=100000
  - sysctl -w net.ipv4.ip_local_port_range="1024 65535"
'''

module clientVm1 'modules/vm.bicep' = {
  name: 'clientVm1'
  params: {
    location: location
    vmName: '${environmentName}-client-vm-1'
    subnetId: clientVnet.outputs.subnetIds[1].id
    adminUsername: adminUsername
    adminPassword: clientVm1Password
    customData: clientCustomData
    publicIpId: clientPip.id
    nsgId: clientNsg.outputs.nsgId
    tags: tags
  }
}

resource clientPip2 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${environmentName}-client-vm-2-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

module clientVm2 'modules/vm.bicep' = {
  name: 'clientVm2'
  params: {
    location: location
    vmName: '${environmentName}-client-vm-2'
    subnetId: clientVnet.outputs.subnetIds[1].id
    adminUsername: adminUsername
    adminPassword: clientVm2Password
    customData: clientCustomData
    publicIpId: clientPip2.id
    nsgId: clientNsg.outputs.nsgId
    tags: tags
  }
}

output keyVaultName string = kv.outputs.keyVaultName
output clientVm1PublicIp string = clientPip.properties.ipAddress
output clientVm2PublicIp string = clientPip2.properties.ipAddress
output serverVmPublicIp string = serverPip.properties.ipAddress
output adminUsername string = adminUsername
