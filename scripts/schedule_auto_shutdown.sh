#!/bin/bash
# Script to schedule automatic shutdown of resources after hours

set -e

# Get the project directory
PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_NAME=$(basename "$PROJECT_DIR")
ENVIRONMENT=${1:-"dev"}  # Default to dev environment
SHUTDOWN_TIME=${2:-"19:00"}  # Default to 7 PM

# Source environment variables
if [ -f "$PROJECT_DIR/.env.$ENVIRONMENT" ]; then
    source "$PROJECT_DIR/.env.$ENVIRONMENT"
else
    echo "Error: Environment file .env.$ENVIRONMENT not found."
    exit 1
fi

if [ -z "$LOCATION" ]; then
    # Default to East US if not specified in .env file
    LOCATION="eastus"
fi

echo "Setting up auto-shutdown for $PROJECT_NAME ($ENVIRONMENT environment) at $SHUTDOWN_TIME..."

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI not found. Please install it first."
    exit 1
fi

# Verify Azure login
if ! az account show &> /dev/null; then
    echo "Not logged in to Azure. Please log in first."
    az login
fi

# Set the subscription
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# Create an Azure Automation account if it doesn't exist
AUTOMATION_ACCOUNT="$PROJECT_NAME-$ENVIRONMENT-automation"
if ! az automation account show --name "$AUTOMATION_ACCOUNT" --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg" &> /dev/null; then
    echo "Creating Azure Automation account..."
    az automation account create \
        --name "$AUTOMATION_ACCOUNT" \
        --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg" \
        --location "$LOCATION"
fi

# Create a system-assigned managed identity for the automation account
echo "Enabling system-assigned managed identity for automation account..."
az automation account update \
    --name "$AUTOMATION_ACCOUNT" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg" \
    --identity-type "SystemAssigned"

# Get the principal ID of the managed identity
PRINCIPAL_ID=$(az automation account show \
    --name "$AUTOMATION_ACCOUNT" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg" \
    --query "identity.principalId" -o tsv)

# Assign Contributor role to the automation account for the resource group
echo "Assigning Contributor role to automation account..."
az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type "ServicePrincipal" \
    --role "Contributor" \
    --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$PROJECT_NAME-$ENVIRONMENT-rg"

# Create a runbook for resource shutdown
RUNBOOK_NAME="ShutdownResources"
echo "Creating shutdown runbook..."
cat << EOF > shutdown_script.py
import os
import sys
import azure.mgmt.containerinstance
import azure.mgmt.rdbms.postgresql_flexibleservers
from azure.identity import DefaultAzureCredential
from azure.mgmt.containerinstance import ContainerInstanceManagementClient
from azure.mgmt.rdbms.postgresql_flexibleservers import PostgreSQLManagementClient

# Get environment variables
resource_group = "$PROJECT_NAME-$ENVIRONMENT-rg"
subscription_id = "$AZURE_SUBSCRIPTION_ID"
container_name = "$PROJECT_NAME-$ENVIRONMENT-mlflow"
postgres_name = "$PROJECT_NAME-$ENVIRONMENT-psql"

# Authenticate
credential = DefaultAzureCredential()

# Stop Container Instance
container_client = ContainerInstanceManagementClient(credential, subscription_id)
print(f"Stopping container instance {container_name}...")
container_client.container_groups.stop(resource_group, container_name)

# Stop PostgreSQL server
postgres_client = PostgreSQLManagementClient(credential, subscription_id)
print(f"Stopping PostgreSQL server {postgres_name}...")
postgres_client.servers.stop(resource_group, postgres_name)

print("All resources stopped successfully!")
EOF

az automation runbook create \
    --automation-account-name "$AUTOMATION_ACCOUNT" \
    --name "$RUNBOOK_NAME" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg" \
    --type "Python" \
    --content-file "shutdown_script.py"

# Publish the runbook
az automation runbook publish \
    --automation-account-name "$AUTOMATION_ACCOUNT" \
    --name "$RUNBOOK_NAME" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg"

# Create a schedule
SCHEDULE_NAME="DailyShutdown"
az automation schedule create \
    --automation-account-name "$AUTOMATION_ACCOUNT" \
    --name "$SCHEDULE_NAME" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg" \
    --frequency "Day" \
    --start-time "$SHUTDOWN_TIME" \
    --timezone "UTC"

# Link the schedule to the runbook
az automation job-schedule create \
    --automation-account-name "$AUTOMATION_ACCOUNT" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg" \
    --runbook-name "$RUNBOOK_NAME" \
    --schedule-name "$SCHEDULE_NAME"

# Clean up temporary file
rm shutdown_script.py

echo "Auto-shutdown scheduled successfully for $SHUTDOWN_TIME UTC daily!"
echo "Resources will be automatically stopped to save costs."
echo "Use './scripts/start_resources.sh $ENVIRONMENT' to start them when needed."

