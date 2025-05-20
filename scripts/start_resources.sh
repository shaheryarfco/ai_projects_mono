#!/bin/bash
# Script to start Azure resources when needed

set -e

# Get the project directory
PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_NAME=$(basename "$PROJECT_DIR")
ENVIRONMENT=${1:-"dev"}  # Default to dev environment

# Source environment variables
if [ -f "$PROJECT_DIR/.env.$ENVIRONMENT" ]; then
    source "$PROJECT_DIR/.env.$ENVIRONMENT"
else
    echo "Error: Environment file .env.$ENVIRONMENT not found."
    exit 1
fi

echo "Starting Azure resources for $PROJECT_NAME ($ENVIRONMENT environment)..."

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

# Ensure resource names match Terraform
echo "Starting PostgreSQL server..."
az postgres flexible-server start \
    --name "$PROJECT_NAME-$ENVIRONMENT-psql" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg"

# Start Container Instance for MLflow
echo "Starting MLflow container instance..."
az container start \
    --name "$PROJECT_NAME-$ENVIRONMENT-mlflow" \
    --resource-group "$PROJECT_NAME-$ENVIRONMENT-rg"

echo "Resources started successfully!"
echo "MLflow tracking URI: $MLFLOW_TRACKING_URI"
