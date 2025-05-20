#!/bin/bash
# Script to set up Terraform state backend in Azure

# Create resource group for Terraform state
az group create --name "port-tariff-rag-tfstate-rg" --location "centralindia"

# Create storage account for Terraform state
az storage account create   --name "porttariffragtfstatedev"   --resource-group "port-tariff-rag-tfstate-rg"   --sku Standard_LRS   --encryption-services blob

# Create blob container for Terraform state
az storage container create   --name tfstate   --account-name "porttariffragtfstatedev"

# Get storage account key
ACCOUNT_KEY=/XhQwsZlHKRK9KnNUSKMvUcUih17Irnwaw4omyg3KdhDglfoqJdtyU1ivSSfwL5L1amQ+nVEh3iZ+ASt5Rtmpw==

echo "Storage account key: $ACCOUNT_KEY"
echo "Set the following environment variables to initialize Terraform:"
echo "export ARM_ACCESS_KEY=$ACCOUNT_KEY"
