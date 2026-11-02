# Azure VM Deployment with Bicep (DEV / QA / PROD)

A modular Azure Bicep project that deploys an Ubuntu Server 22.04 LTS Gen2 VM with SSH public-key authentication. The same root template is reused for DEV, QA, and PROD through separate `.bicepparam` files.

> **Important:** This is a learning / baseline deployment, not a complete production landing zone. Review the production considerations near the end of this file before using it for workloads.

## What the project creates

- Network Security Group with inbound SSH (TCP/22) allowed only from the configured `adminCidr`.
- Virtual network and subnet, with the NSG attached to the subnet.
- Standard SKU, static IPv4 public IP.
- Network interface connected to the subnet and public IP.
- Ubuntu Server 22.04 LTS Gen2 virtual machine using SSH public-key authentication (password authentication is disabled).

The root template (`main.bicep`) orchestrates four modules. The NIC depends on the network and public IP outputs, and the VM depends on the NIC output.

## Project structure

```text
azure_bicep_vm_project/
├── main.bicep
├── README.md
├── deploy.ps1
├── parameters/
│   ├── dev.bicepparam
│   ├── qa.bicepparam
│   └── prod.bicepparam
└── modules/
    ├── network.bicep
    ├── publicIp.bicep
    ├── nic.bicep
    └── vm.bicep
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+.
- Azure CLI 2.53.0 or later and Bicep CLI 0.22.x or later for deployment with linked `.bicepparam` files. The parameter files also use `readEnvironmentVariable()`.
- An Azure subscription with permission to create resource groups, virtual networks, network security groups, public IPs, NICs, and virtual machines.
- An SSH key pair.

Check the tools:

```powershell
az version
az bicep version
```

Install or update Bicep through Azure CLI:

```powershell
az bicep install
# If Bicep is already installed and you want the latest version:
az bicep upgrade
az bicep version
```

Sign in and select the intended subscription:

```powershell
az login
az account list --output table
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
az account show --output table
```

## 1. Prepare an SSH key pair

Create an Ed25519 key pair if you do not already have one:

```powershell
ssh-keygen -t ed25519 -C "azure-bicep-vm"
```

The default public key path used by the helper script is:

```text
$HOME\.ssh\id_ed25519.pub
```

The private key is `id_ed25519` (without `.pub`). Keep it private. Only the `.pub` public key is passed to the VM deployment.

## 2. Configure the environment parameter file

Before deployment, open the parameter file you intend to use:

- `parameters/dev.bicepparam`
- `parameters/qa.bicepparam`
- `parameters/prod.bicepparam`

Update `adminCidr` to the public IPv4 address from which you will connect to the VM. Use CIDR notation, usually `/32` for one address:

```bicep
param adminCidr = 'YOUR_PUBLIC_IPV4/32'
```

Do not leave the example `203.0.113.10/32` value. That address is from a documentation-only range and is not your internet-facing IP. The helper script intentionally stops if that placeholder remains.

The `workloadName` must be 2-8 lowercase letters or digits, for example `webapp`. Bicep supports length decorators but does not provide a `@pattern()` decorator. The supplied `deploy.ps1` script checks the lowercase/digit naming rule before it creates Azure resources. If you deploy by another method, follow the same naming rule yourself.

## 3. SSH public-key handling (BCP258 fix)

`main.bicep` declares `sshPublicKey` as a required secure string. Each `.bicepparam` file assigns it by reading an environment variable:

```bicep
param sshPublicKey = readEnvironmentVariable('AZURE_BICEP_SSH_PUBLIC_KEY')
```

The deployment script reads the `.pub` file, trims the newline, and sets the process environment variable before running Azure CLI. This approach:

- Satisfies the parameter-file requirement (the parameter is assigned in the `.bicepparam` file).
- Avoids placing the key directly in the command-line arguments.
- Keeps the key content out of the repository and parameter file.
- Passes the value to the `@secure()` Bicep parameter.

Do not add the private key to any Bicep file, parameter file, script, or source control.

## 4. Compile and validate the Bicep template

Run from the project root (the folder containing `main.bicep`):

```powershell
az bicep build --file .\main.bicep
az bicep build --file .\modules\network.bicep
az bicep build --file .\modules\publicIp.bicep
az bicep build --file .\modules\nic.bicep
az bicep build --file .\modules\vm.bicep
```

The first command compiles the root template and its referenced local modules. The other commands are optional individual module checks. Fix all compiler errors before deploying.

## 5. Recommended deployment using the supplied PowerShell script

From the project root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\deploy.ps1 -Environment dev
```

The script:

1. Checks Azure CLI, the parameter file, and the SSH public key.
2. Checks the workload name and SSH source CIDR before making Azure changes.
3. Loads the SSH public key into `AZURE_BICEP_SSH_PUBLIC_KEY` for the current PowerShell process.
4. Compiles `main.bicep` (including its local modules).
5. Creates the resource group if it does not exist.
6. Runs deployment validation and What-If.
7. Waits for you to type `YES` before creating/updating the resources.
8. Displays deployment outputs.

Deploy QA or PROD by changing the environment:

```powershell
.\deploy.ps1 -Environment qa
.\deploy.ps1 -Environment prod
```

To use another public-key file:

```powershell
.\deploy.ps1 -Environment dev -SshPublicKeyPath "$HOME\.ssh\custom_key.pub"
```

You can override the resource group name or region if required:

```powershell
.\deploy.ps1 -Environment dev -ResourceGroupName rg-webapp-dev-lab -Location centralindia
```

## 6. Manual DEV deployment (without deploy.ps1)

The `.bicepparam` file contains `using '../main.bicep'`. Therefore, when deploying with this linked parameter file, specify the parameter file with `--parameters` and **do not also specify `--template-file`**.

First, create the resource group (use the same location configured in `dev.bicepparam`):

```powershell
az group create --name rg-webapp-dev --location eastus
```

Load the public key into the environment variable referenced by the parameter file:

```powershell
$env:AZURE_BICEP_SSH_PUBLIC_KEY = (Get-Content "$HOME\.ssh\id_ed25519.pub" -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($env:AZURE_BICEP_SSH_PUBLIC_KEY)) {
    throw 'SSH public key is empty.'
}
```

Validate:

```powershell
az deployment group validate `
  --name validate-webapp-dev `
  --resource-group rg-webapp-dev `
  --parameters .\parameters\dev.bicepparam
```

Preview:

```powershell
az deployment group what-if `
  --name whatif-webapp-dev `
  --resource-group rg-webapp-dev `
  --parameters .\parameters\dev.bicepparam
```

Deploy:

```powershell
az deployment group create `
  --name deploy-webapp-dev `
  --resource-group rg-webapp-dev `
  --parameters .\parameters\dev.bicepparam
```

Note that the parameter file is linked to `main.bicep`, so these commands intentionally omit `--template-file`. Microsoft documents that combining `--template-file` with a linked `.bicepparam` file can produce an error. The same pattern applies to QA and PROD: change the resource group, deployment name, and parameter file.

## 7. Verify the deployment

View the deployment outputs:

```powershell
az deployment group show `
  --resource-group rg-webapp-dev `
  --name deploy-webapp-dev `
  --query properties.outputs `
  --output json
```

List the deployed resources:

```powershell
az vm list -g rg-webapp-dev -d --output table
az network public-ip list -g rg-webapp-dev --output table
az network nic list -g rg-webapp-dev --output table
az network vnet list -g rg-webapp-dev --output table
az network nsg list -g rg-webapp-dev --output table
```

Connect to the VM from a computer whose public IPv4 address is included in `adminCidr`:

```powershell
ssh -i "$HOME\.ssh\id_ed25519" azureuser@<PUBLIC_IP>
```

Use the username configured in the environment parameter file (`azureuser` for DEV/QA and `azureadmin` for PROD).

## Troubleshooting

### BCP057: `pattern` does not exist in the current context

Bicep does not support an `@pattern()` decorator. The project removes that decorator, keeps the built-in `@minLength(2)` and `@maxLength(8)` checks, and validates the lowercase-alphanumeric convention in `deploy.ps1` instead.

### BCP258: `sshPublicKey` is missing from the params file

Check that each environment `.bicepparam` file contains:

```bicep
param sshPublicKey = readEnvironmentVariable('AZURE_BICEP_SSH_PUBLIC_KEY')
```

For manual deployment, set `$env:AZURE_BICEP_SSH_PUBLIC_KEY` before running the Azure CLI command. For scripted deployment, `deploy.ps1` sets it for you.

### Error: `Only a .bicep file is allowed with a .bicepparam file`

The parameter file already contains a `using '../main.bicep'` declaration. Remove `--template-file` from the deployment command and pass only the `.bicepparam` file after `--parameters`.

### SSH connection times out

- Confirm `adminCidr` is your current public IPv4 address with `/32` (or the intended trusted network range).
- Confirm the NSG is associated with the subnet and allows TCP/22 from that CIDR.
- Confirm the VM is running and the public IP is attached.
- If your ISP/VPN changes your public IP, update `adminCidr` and redeploy.

### SSH reports `Permission denied (publickey)`

- Use the private key that matches the public key supplied during deployment.
- Use the correct Linux username from the environment parameter file.
- Do not use the `.pub` file with SSH `-i`; pass the private key file.

### VM size or image is unavailable

A VM SKU can be unavailable in a region or subscription because of quota or capacity. Check available sizes and quotas, then adjust `vmSize` in the relevant `.bicepparam` file if needed. If the Ubuntu image SKU is unavailable in your region, select a supported Canonical Ubuntu 22.04 Gen2 image reference.

### Deployment fails after partially creating resources

Inspect the deployment error and operation details:

```powershell
az deployment group show `
  --resource-group rg-webapp-dev `
  --name deploy-webapp-dev `
  --query properties.error `
  --output json

az deployment operation group list `
  --resource-group rg-webapp-dev `
  --name deploy-webapp-dev `
  --output table
```

## Cleanup

Deleting the resource group deletes the resources in that environment and stops their associated ongoing charges:

```powershell
az group delete --name rg-webapp-dev --yes --no-wait
```

Repeat only for environments you intentionally want to remove.

## Production considerations

Before production use, consider private access or Azure Bastion, Just-in-Time VM access, Azure Backup, monitoring and alerting, patch management, disk encryption, availability architecture, policy enforcement, private networking, and cost controls. A running VM and its public IP can incur charges.

## Official references

- [Bicep file structure and supported decorators](https://learn.microsoft.com/azure/azure-resource-manager/bicep/file)
- [Create and use Bicep parameter files](https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files)
- [Deploy Bicep files with Azure CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-cli)
