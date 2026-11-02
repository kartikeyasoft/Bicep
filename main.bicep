targetScope = 'resourceGroup'

@description('Environment name used for resource naming and tagging.')
@allowed([
  'dev'
  'qa'
  'prod'
])
param environment string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Workload name: use 2-8 lowercase letters or numbers. deploy.ps1 validates this naming convention.')
@minLength(2)
@maxLength(8)
param workloadName string = 'webapp'

@description('Virtual network address space.')
param vnetAddressPrefix string

@description('Subnet address prefix.')
param subnetAddressPrefix string

@description('CIDR range allowed to connect to the VM over SSH. Replace the example documentation IP with your public IP /32.')
param adminCidr string

@description('Linux VM administrator username.')
param adminUsername string = 'azureuser'

@description('SSH public key for the Linux VM. Pass this at deployment time; never put a private key in Bicep.')
@secure()
param sshPublicKey string

@description('Linux VM size.')
param vmSize string = 'Standard_B2s'

@description('Ubuntu image version.')
param imageVersion string = 'latest'

var namePrefix = '${workloadName}-${environment}'
var commonTags = {
  environment: environment
  workload: workloadName
  managedBy: 'Bicep'
}

module network './modules/network.bicep' = {
  name: 'network-${environment}'
  params: {
    namePrefix: namePrefix
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    subnetAddressPrefix: subnetAddressPrefix
    adminCidr: adminCidr
    tags: commonTags
  }
}

module publicIp './modules/publicIp.bicep' = {
  name: 'public-ip-${environment}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: commonTags
  }
}

module nic './modules/nic.bicep' = {
  name: 'nic-${environment}'
  params: {
    namePrefix: namePrefix
    location: location
    subnetId: network.outputs.subnetId
    publicIpId: publicIp.outputs.publicIpId
    tags: commonTags
  }
}

module vm './modules/vm.bicep' = {
  name: 'vm-${environment}'
  params: {
    namePrefix: namePrefix
    location: location
    vmSize: vmSize
    nicId: nic.outputs.nicId
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    tags: commonTags
  }
}

output virtualMachineName string = vm.outputs.vmName
output publicIpAddress string = publicIp.outputs.publicIpAddress
output sshCommand string = 'ssh ${adminUsername}@${publicIp.outputs.publicIpAddress}'
output virtualNetworkName string = network.outputs.vnetName
output subnetName string = network.outputs.subnetName
output networkSecurityGroupName string = network.outputs.nsgName
