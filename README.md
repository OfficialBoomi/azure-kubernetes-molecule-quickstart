# Boomi AKS Quickstart with ARM Template

## Note: Kindly purge the Azure KeyVault post destroy the Quickstart Infrastructure.

## Step 1: Enable AKS Preview

### Install the extension
`az extension add -n aks-preview`

### Update the extension to ensure the latest version is installed
`az extension update -n aks-preview`

## Step 2: Register the AKS-IngressApplicationGatewayAddon feature

`az feature register --name AKS-IngressApplicationGatewayAddon --namespace Microsoft.ContainerService`

## Step 3: Register for Azure NetApp Files

https://docs.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-register

## Step 4: Deploy Azure ARM Template

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fvilvamani%2Fquickstart-aks-boomi-molecule%2Fmain%2Ftemplate%2Fazuredeploy.json)

https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/template-functions-resource?tabs=json#providers

# Boomi AKS Quickstart Architectures

![Boomi AKS Architecture](https://github.com/Ganesh-Yeole/quickstart-aks-boomi-molecule/blob/main/images/boomi-aks-architecture.jpg)

## Azure Resources Required
1. Managed Identity(User Assigned Identities)
2. Public IP Addresses - 2
3. Network SecurityGroups - 1
4. Virtual Networks - 1
5. NetApp Accounts - 1
6. KeyVault - 1
7. Application Gateways - 1
8. AKS Managed Clusters - 1
9. Network Interfaces - 1
10. Virtual Machines - 1

AKS Cluster Recommendation

| Environment   | AKS VM Size      | vCPU | Memory: GiB   | No. of System Node   | No. of user Node   |
| ------------- | ---------------- | ---- | ------------- | -------------------- | ------------------ |
| Development   | Standard_D4_v4   | 4    | 16            | 1                    | 1                  |
| Development   | Standard_D4_v4   | 4    | 16            | 2                    | 2                  |
| Dev Test      | Standard_D4_v4   | 4    | 16            | 2                    | 2                  |
| Prod Test     | Standard_D16_v4  | 16   | 64            | 2                    | 3                  |
| **Production**    | Standard_D16_v4  | 16   | 64            | 2                    | 3                  |
| **High Throughput Production**    | Standard_D32_v4  | 32   | 128           | 2                    | 3                  |
