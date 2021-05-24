# Boomi AKS Quickstart with ARM Template

## Step 1: Enable AKS Preview

`az extension add --name aks-preview`

## Step 2: Register the AKS-IngressApplicationGatewayAddon feature

`az feature register --name AKS-IngressApplicationGatewayAddon --namespace Microsoft.ContainerService`

## Step 3: Register for Azure NetApp Files

https://docs.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-register

## Step 4: Deploy Azure ARM Template

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fvilvamani%2Fquickstart-aks-boomi-molecule%2Fmain%2Ftemplate%2Fazuredeploy.json)

https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/template-functions-resource?tabs=json#providers

# Boomi AKS Quickstart Architectures

![Boomi AKS Architecture](https://github.com/vilvamani/quickstart-aks-boomi-molecule/blob/main/images/boomi-aks-architecture.jpg)
