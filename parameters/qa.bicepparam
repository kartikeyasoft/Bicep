using '../main.bicep'

param environment = 'qa'
param location = 'eastus'
param workloadName = 'webapp'
param vnetAddressPrefix = '10.20.0.0/16'
param subnetAddressPrefix = '10.20.1.0/24'

// Replace with your own public IP in CIDR format, for example 203.0.113.10/32.
param adminCidr = '203.0.113.10/32'
param adminUsername = 'azureuser'
param vmSize = 'Standard_B2s'

// The deployment helper loads the SSH public key into this process environment variable.
param sshPublicKey = readEnvironmentVariable('AZURE_BICEP_SSH_PUBLIC_KEY')
