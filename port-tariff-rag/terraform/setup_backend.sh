#!/bin/bash
# Script to set up Terraform state backend in Azure

# Create resource group for Terraform state
az group create --name "port-tariff-rag-tfstate-rg" --location "centralindia"

# Create storage account for Terraform state
az storage account create   --name "porttariffragtfstatedev"   --resource-group "port-tariff-rag-tfstate-rg"   --sku Standard_LRS   --encryption-services blob

# Create blob container for Terraform state
az storage container create   --name tfstate   --account-name "porttariffragtfstatedev"

# Get storage account key - use proper quoting and remove special characters
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "${PROJECT_NAME}-tfstate-rg" \
  --account-name "${PROJECT_NAME//-/}tfstate${ENVIRONMENT}" \
  --query '[0].value' -o tsv)

# Clean the key to ensure it's properly formatted
ACCOUNT_KEY=$(echo "$ACCOUNT_KEY" | tr -d '\r\n')

# Don't print the actual key to avoid security issues
echo "Storage account key retrieved successfully"
echo "Set the following environment variables to initialize Terraform:"
echo "export ARM_ACCESS_KEY=\$ACCOUNT_KEY"

