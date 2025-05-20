#!/bin/bash
# Cleanup script for Azure resources created by Terraform
# This script will clean up all resources created for the project

# Enable error tracing
set -e

# Get the project name from the current directory or parent directory
PROJECT_NAME=$(basename $(cd .. && pwd))
ENVIRONMENT=${1:-"dev"}  # Default to dev environment if not specified

# Define the shared resource group name for the environment
SHARED_RG="${PROJECT_NAME}-${ENVIRONMENT}-rg"

# Define resource names for easy reference
STORAGE_ACCT="${PROJECT_NAME//-/}storage${ENVIRONMENT}"
KEY_VAULT="${PROJECT_NAME//-/}kv${ENVIRONMENT}"
POSTGRES_SERVER="${PROJECT_NAME}-${ENVIRONMENT}-psql"
ACR_NAME="${PROJECT_NAME//-/}acr${ENVIRONMENT}"
FUNCTION_APP="${PROJECT_NAME}-${ENVIRONMENT}-function"
APP_SERVICE_PLAN="${PROJECT_NAME}-${ENVIRONMENT}-plan"
LOGIC_APP="${PROJECT_NAME}-${ENVIRONMENT}-auto-shutdown"
CONTAINER_GROUP="${PROJECT_NAME}-${ENVIRONMENT}-mlflow"

echo "This script will delete ALL resources for project $PROJECT_NAME in the $ENVIRONMENT environment."
echo "Resources to be deleted:"
echo "- Resource Group: $SHARED_RG"
echo "- Storage Account: $STORAGE_ACCT"
echo "- Key Vault: $KEY_VAULT"
echo "- PostgreSQL Server: $POSTGRES_SERVER"
echo "- Container Registry: $ACR_NAME"
echo "- Function App: $FUNCTION_APP"
echo "- App Service Plan: $APP_SERVICE_PLAN"
echo "- Logic App: $LOGIC_APP"
echo "- Container Group: $CONTAINER_GROUP"

read -p "Are you sure you want to proceed with deletion? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "Starting cleanup process..."

# Check if Terraform state exists and use it for cleanup
ENV_DIR="env/$ENVIRONMENT"
if [ -f "$ENV_DIR/terraform.tfstate" ]; then
    echo "Terraform state found. Using terraform destroy..."
    cd "$ENV_DIR" && terraform destroy -auto-approve
    echo "Terraform destroy completed."
    exit 0
fi

# If no Terraform state, perform manual cleanup
echo "No Terraform state found. Performing manual cleanup..."

# Login to Azure if not already logged in
az account show &> /dev/null || az login

# Function App
if az functionapp show --name "$FUNCTION_APP" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting Function App $FUNCTION_APP..."
    az functionapp delete --name "$FUNCTION_APP" --resource-group "$SHARED_RG" --yes || true
fi

# App Service Plan
if az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting App Service Plan $APP_SERVICE_PLAN..."
    az appservice plan delete --name "$APP_SERVICE_PLAN" --resource-group "$SHARED_RG" --yes || true
fi

# Logic App
if az logic workflow show --name "$LOGIC_APP" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting Logic App $LOGIC_APP..."
    az logic workflow delete --name "$LOGIC_APP" --resource-group "$SHARED_RG" --yes || true
fi

# Container Instance for MLflow
if az container show --name "$CONTAINER_GROUP" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting Container Group $CONTAINER_GROUP..."
    az container delete --name "$CONTAINER_GROUP" --resource-group "$SHARED_RG" --yes || true
fi

# Storage container
if az storage account show --name "$STORAGE_ACCT" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Checking for storage containers..."
    STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCT" --resource-group "$SHARED_RG" --query '[0].value' -o tsv)
    az storage container delete --name "mlflow-artifacts" --account-name "$STORAGE_ACCT" --account-key "$STORAGE_KEY" || true
fi

# Storage account
if az storage account show --name "$STORAGE_ACCT" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting storage account $STORAGE_ACCT..."
    az storage account delete --name "$STORAGE_ACCT" --resource-group "$SHARED_RG" --yes || true
fi

# Key vault
if az keyvault show --name "$KEY_VAULT" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting key vault $KEY_VAULT..."
    az keyvault delete --name "$KEY_VAULT" --resource-group "$SHARED_RG" || true
fi

# PostgreSQL server
if az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting PostgreSQL server $POSTGRES_SERVER..."
    az postgres flexible-server delete --name "$POSTGRES_SERVER" --resource-group "$SHARED_RG" --yes || true
fi

# Container registry
if az acr show --name "$ACR_NAME" --resource-group "$SHARED_RG" &> /dev/null; then
    echo "Deleting container registry $ACR_NAME..."
    az acr delete --name "$ACR_NAME" --resource-group "$SHARED_RG" --yes || true
fi

# Finally, delete the resource group if it exists
if az group show --name "$SHARED_RG" &> /dev/null; then
    echo "Deleting resource group $SHARED_RG..."
    az group delete --name "$SHARED_RG" --yes || true
fi

echo "Cleanup completed. Please check Azure portal to ensure all resources were properly removed."
