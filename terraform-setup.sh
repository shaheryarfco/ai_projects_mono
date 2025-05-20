#!/bin/bash
# Terraform setup script for Azure infrastructure deployment
# This script creates and configures Azure resources for ML projects

# Enable error tracing and exit on error
set -e

# Get the project name from the current directory or parent directory
PROJECT_NAME=$(basename $(cd .. && pwd))
ENVIRONMENT=${1:-"dev"}  # Default to dev environment if not specified
LOCATION=${2:-"centralindia"}  # Default to Central India if not specified

# Define the shared resource group name for the environment
SHARED_RG="ai-projects-${ENVIRONMENT}-rg"

# Define resource names for easy reference
STORAGE_ACCT="${PROJECT_NAME//-/}storage${ENVIRONMENT}"
KEY_VAULT="${PROJECT_NAME//-/}kv${ENVIRONMENT}"
POSTGRES_SERVER="${PROJECT_NAME}-${ENVIRONMENT}-psql"
ACR_NAME="${PROJECT_NAME//-/}acr${ENVIRONMENT}"

# Trap function to clean up resources on error
cleanup_on_error() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "Error detected (exit code $exit_code). Cleaning up resources..."
        
        # Check if we're in the middle of a Terraform apply
        if [ -f "$ENV_DIR/terraform.tfstate" ]; then
            echo "Attempting to destroy partially created resources..."
            cd "$ENV_DIR" && terraform destroy -auto-approve || true
        else
            # Manual cleanup of resources that might have been created
            echo "Manually cleaning up resources..."
            
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
        fi
        
        echo "Cleanup completed. Please check Azure portal to ensure all resources were properly removed."
    fi
    
    exit $exit_code
}

# Set up trap to call cleanup function on error
trap cleanup_on_error ERR INT TERM

echo "Setting up Terraform for project: $PROJECT_NAME ($ENVIRONMENT environment)"
echo "Using shared resource group: $SHARED_RG"

# Add cleanup option at the beginning of the script
echo "Would you like to clean up any existing resources for this project before proceeding? (y/n): "
read CLEANUP_RESOURCES

if [[ "$CLEANUP_RESOURCES" == "y" || "$CLEANUP_RESOURCES" == "Y" ]]; then
    echo "Cleaning up resources for project $PROJECT_NAME in $ENVIRONMENT environment..."
    
    # Check if the resource group exists
    if az group show --name "$SHARED_RG" &> /dev/null; then
        echo "Deleting project-specific resources from $SHARED_RG..."
        
        # Delete project-specific resources by name pattern
        # Storage account
        if az storage account show --name "$STORAGE_ACCT" --resource-group "$SHARED_RG" &> /dev/null; then
            echo "Deleting storage account $STORAGE_ACCT..."
            az storage account delete --name "$STORAGE_ACCT" --resource-group "$SHARED_RG" --yes
        fi
        
        # Key vault
        if az keyvault show --name "$KEY_VAULT" --resource-group "$SHARED_RG" &> /dev/null; then
            echo "Deleting key vault $KEY_VAULT..."
            az keyvault delete --name "$KEY_VAULT" --resource-group "$SHARED_RG"
        fi
        
        # PostgreSQL server
        if az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$SHARED_RG" &> /dev/null; then
            echo "Deleting PostgreSQL server $POSTGRES_SERVER..."
            az postgres flexible-server delete --name "$POSTGRES_SERVER" --resource-group "$SHARED_RG" --yes
        fi
        
        # Container registry
        if az acr show --name "$ACR_NAME" --resource-group "$SHARED_RG" &> /dev/null; then
            echo "Deleting container registry $ACR_NAME..."
            az acr delete --name "$ACR_NAME" --resource-group "$SHARED_RG" --yes
        fi
        
        echo "Project-specific resources cleaned up."
    else
        echo "Creating shared resource group $SHARED_RG..."
        az group create --name "$SHARED_RG" --location "$LOCATION"
    fi
    
    echo "Cleanup completed."
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Azure CLI not found. Please install it first."
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' not found. Please install it first."
    echo "Ubuntu/Debian: sudo apt-get install jq"
    echo "macOS: brew install jq"
    echo "Windows: choco install jq"
    exit 1
fi

# Login to Azure if not already logged in
az account show &> /dev/null || az login

# Get subscription list
echo "Available subscriptions:"
az account list --output table

# Prompt for subscription selection based on environment
if [ "$ENVIRONMENT" == "prod" ]; then
    echo "PRODUCTION ENVIRONMENT SELECTED!"
    echo "Please select the PRODUCTION subscription:"
else
    echo "Development environment selected."
    echo "Please select the development subscription:"
fi

read -p "Enter the subscription ID to use for $ENVIRONMENT: " SUBSCRIPTION_ID
az account set --subscription "$SUBSCRIPTION_ID"
echo "Using subscription: $SUBSCRIPTION_ID for $ENVIRONMENT environment"

# Create environment-specific directory
ENV_DIR="env/$ENVIRONMENT"
mkdir -p "$ENV_DIR"

# Create backend.tf for remote state storage
cat << EOF > "$ENV_DIR/backend.tf"
terraform {
  backend "local" {
    path = "${PROJECT_NAME}-${ENVIRONMENT}.tfstate"
  }
}
EOF

# Create variables.tf with environment-specific defaults
if [ "$ENVIRONMENT" == "prod" ]; then
  SKU_TIER="Standard"
  INSTANCE_SIZE="Standard_B1s"
  POSTGRES_SKU="GP_Standard_B1s"
else
  SKU_TIER="Basic"
  INSTANCE_SIZE="Standard_B1s"
  POSTGRES_SKU="B_Standard_B1s"
fi

cat << EOF > "$ENV_DIR/variables.tf"
variable "project_name" {
  description = "Name of the project"
  default     = "$PROJECT_NAME"
}

variable "location" {
  description = "Azure region"
  default     = "$LOCATION"
}

variable "environment" {
  description = "Environment (dev, test, prod)"
  default     = "$ENVIRONMENT"
}

variable "shared_resource_group" {
  description = "Shared resource group for all projects in this environment"
  default     = "$SHARED_RG"
}

variable "admin_username" {
  description = "Admin username for database"
  default     = "psqladmin"
}

variable "admin_password" {
  description = "Admin password for database"
  default     = "H@Sh1CoR3!"  # In production, use a secret from Key Vault
  sensitive   = true
}

# Environment-specific variables
variable "sku_tier" {
  description = "SKU tier for resources"
  default     = "$SKU_TIER"
}

variable "instance_size" {
  description = "Size of compute instances"
  default     = "$INSTANCE_SIZE"
}

variable "postgres_sku" {
  description = "SKU for PostgreSQL"
  default     = "$POSTGRES_SKU"
}
EOF

# Ask which resources to deploy
echo "Which resources would you like to deploy? (Enter comma-separated list)"
echo "Options: all, storage, postgres, keyvault, container_registry, function_app, logic_app, mlflow, none"
read -p "Resources to deploy (default: all): " RESOURCES_TO_DEPLOY

# Default to all if empty
RESOURCES_TO_DEPLOY=${RESOURCES_TO_DEPLOY:-"all"}

# Create main.tf with selected resources
cat << EOF > "$ENV_DIR/main.tf"
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id = "$SUBSCRIPTION_ID"
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Use existing shared resource group or create if it doesn't exist
resource "azurerm_resource_group" "shared_rg" {
  name     = var.shared_resource_group
  location = var.location
  
  # Only create if it doesn't exist
  lifecycle {
    prevent_destroy = true
  }
  
  tags = {
    Environment = var.environment
    Project     = "shared"
  }
}
EOF

# Add resources based on selection
if [[ "$RESOURCES_TO_DEPLOY" == "all" || "$RESOURCES_TO_DEPLOY" == *"keyvault"* ]]; then
  cat << EOF >> "$ENV_DIR/main.tf"
# Key Vault
resource "azurerm_key_vault" "kv" {
  name                = "\${replace(var.project_name, "-", "")}kv\${var.environment}"
  location            = azurerm_resource_group.shared_rg.location
  resource_group_name = azurerm_resource_group.shared_rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Set access policies as needed
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Get", "List", "Create", "Delete", "Update",
    ]
    
    secret_permissions = [
      "Get", "List", "Set", "Delete",
    ]
  }
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
EOF
fi

if [[ "$RESOURCES_TO_DEPLOY" == "all" || "$RESOURCES_TO_DEPLOY" == *"storage"* ]]; then
  cat << EOF >> "$ENV_DIR/main.tf"
# Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "\${replace(var.project_name, "-", "")}storage\${var.environment}"
  resource_group_name      = azurerm_resource_group.shared_rg.name
  location                 = azurerm_resource_group.shared_rg.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "LRS" : "LRS"  # Changed from GRS to LRS for cost savings
  
  # Enable hierarchical namespace for cost optimization
  is_hns_enabled = true
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Storage containers
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "mlflow_artifacts" {
  name                  = "mlflow-artifacts"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}
EOF
fi

if [[ "$RESOURCES_TO_DEPLOY" == "all" || "$RESOURCES_TO_DEPLOY" == *"container_registry"* ]]; then
  cat << EOF >> "$ENV_DIR/main.tf"
# Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "\${replace(var.project_name, "-", "")}acr\${var.environment}"
  resource_group_name = azurerm_resource_group.shared_rg.name
  location            = azurerm_resource_group.shared_rg.location
  sku                 = "Basic"
  admin_enabled       = true
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
EOF
fi

if [[ "$RESOURCES_TO_DEPLOY" == "all" || "$RESOURCES_TO_DEPLOY" == *"postgres"* ]]; then
  cat << EOF >> "$ENV_DIR/main.tf"
# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "\${var.project_name}-\${var.environment}-psql"
  resource_group_name    = azurerm_resource_group.shared_rg.name
  location               = azurerm_resource_group.shared_rg.location
  version                = "13"
  administrator_login    = var.admin_username
  administrator_password = var.admin_password
  storage_mb             = 32768
  sku_name               = "B_Standard_B1s"  # Using B-series which requires fewer vCPUs
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Database for MLflow
resource "azurerm_postgresql_flexible_server_database" "mlflow_db" {
  name      = "mlflow"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
EOF
fi

if [[ "$RESOURCES_TO_DEPLOY" == "all" || "$RESOURCES_TO_DEPLOY" == *"function_app"* ]]; then
  cat << EOF >> "$ENV_DIR/main.tf"
# Azure Function App for serverless compute
resource "azurerm_service_plan" "app_service_plan" {
  name                = "\${var.project_name}-\${var.environment}-plan"
  location            = azurerm_resource_group.shared_rg.location
  resource_group_name = azurerm_resource_group.shared_rg.name
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan - only pay when functions execute
}

resource "azurerm_linux_function_app" "function_app" {
  name                       = "\${var.project_name}-\${var.environment}-function"
  location                   = azurerm_resource_group.shared_rg.location
  resource_group_name        = azurerm_resource_group.shared_rg.name
  service_plan_id            = azurerm_service_plan.app_service_plan.id
  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.10"
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "AZURE_STORAGE_CONNECTION_STRING" = azurerm_storage_account.storage.primary_connection_string
  }
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
EOF
fi

if [[ "$RESOURCES_TO_DEPLOY" == "all" || "$RESOURCES_TO_DEPLOY" == *"logic_app"* ]]; then
  cat << EOF >> "$ENV_DIR/main.tf"
# Logic App for automation
resource "azurerm_logic_app_workflow" "auto_shutdown" {
  name                = "\${var.project_name}-\${var.environment}-auto-shutdown"
  location            = azurerm_resource_group.shared_rg.location
  resource_group_name = azurerm_resource_group.shared_rg.name
  
  # Logic Apps are consumption-based - only pay when they run
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
EOF
fi

if [[ "$RESOURCES_TO_DEPLOY" == "all" || "$RESOURCES_TO_DEPLOY" == *"mlflow"* ]]; then
  cat << 'EOF' >> "$ENV_DIR/main.tf"
# Container Instance for MLflow
resource "azurerm_container_group" "mlflow" {
  name                = "${var.project_name}-${var.environment}-mlflow"
  location            = azurerm_resource_group.shared_rg.location
  resource_group_name = azurerm_resource_group.shared_rg.name
  ip_address_type     = "Public"
  dns_name_label      = "${var.project_name}-${var.environment}-mlflow"
  os_type             = "Linux"

  container {
    name   = "mlflow"
    image  = "ghcr.io/mlflow/mlflow:latest"
    cpu    = "1.0"
    memory = "1.5"

    ports {
      port     = 5000
      protocol = "TCP"
    }

    environment_variables = {
      "MLFLOW_BACKEND_STORE_URI" = "postgresql://${var.admin_username}:${var.admin_password}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/${azurerm_postgresql_flexible_server_database.mlflow_db.name}"
      "MLFLOW_DEFAULT_ARTIFACT_ROOT" = "wasbs://${azurerm_storage_container.mlflow_artifacts.name}@${azurerm_storage_account.storage.name}.blob.core.windows.net/"
      "AZURE_STORAGE_ACCESS_KEY" = azurerm_storage_account.storage.primary_access_key
    }

    commands = [
      "mlflow", "server", 
      "--host", "0.0.0.0",
      "--port", "5000",
      "--backend-store-uri", "postgresql://${var.admin_username}:${var.admin_password}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/${azurerm_postgresql_flexible_server_database.mlflow_db.name}",
      "--default-artifact-root", "wasbs://${azurerm_storage_container.mlflow_artifacts.name}@${azurerm_storage_account.storage.name}.blob.core.windows.net/"
    ]
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
EOF
fi

# Create outputs.tf
cat << 'EOF' > "$ENV_DIR/outputs.tf"
output "resource_group_name" {
  value = azurerm_resource_group.shared_rg.name
}

output "environment" {
  value = var.environment
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "storage_account_key" {
  value     = azurerm_storage_account.storage.primary_access_key
  sensitive = true
}

output "container_registry_name" {
  value = azurerm_container_registry.acr.name
}

output "container_registry_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "postgres_server_fqdn" {
  value = azurerm_postgresql_flexible_server.postgres.fqdn
}

output "mlflow_tracking_uri" {
  value = "http://${azurerm_container_group.mlflow.fqdn}:5000"
}

output "mlflow_artifact_uri" {
  value = "wasbs://${azurerm_storage_container.mlflow_artifacts.name}@${azurerm_storage_account.storage.name}.blob.core.windows.net/"
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
}
EOF

# Create environment-specific .env file template
cat << EOF > "$ENV_DIR/.env.template"
# Environment: $ENVIRONMENT
ENVIRONMENT=$ENVIRONMENT
AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID

# Azure Storage
AZURE_STORAGE_ACCOUNT=\${storage_account_name}
AZURE_STORAGE_KEY=\${storage_account_key}

# MLflow
MLFLOW_TRACKING_URI=\${mlflow_tracking_uri}
MLFLOW_ARTIFACT_URI=\${mlflow_artifact_uri}

# PostgreSQL
POSTGRES_SERVER=\${postgres_server_fqdn}
POSTGRES_USER=$admin_username
POSTGRES_PASSWORD=$admin_password
POSTGRES_DB=mlflow

# Key Vault
KEY_VAULT_NAME=\${key_vault_name}
KEY_VAULT_URI=\${key_vault_uri}
EOF

# Create a setup script for Terraform state backend
cat << EOF > setup_backend.sh
#!/bin/bash
# Script to set up Terraform state backend in Azure

# Create resource group for Terraform state
az group create --name "${PROJECT_NAME}-tfstate-rg" --location "$LOCATION"

# Create storage account for Terraform state
az storage account create \
  --name "${PROJECT_NAME//-/}tfstate${ENVIRONMENT}" \
  --resource-group "${PROJECT_NAME}-tfstate-rg" \
  --sku Standard_LRS \
  --encryption-services blob

# Create blob container for Terraform state
az storage container create \
  --name tfstate \
  --account-name "${PROJECT_NAME//-/}tfstate${ENVIRONMENT}"

# Get storage account key - use proper quoting and remove special characters
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "${PROJECT_NAME}-tfstate-rg" \
  --account-name "${PROJECT_NAME//-/}tfstate${ENVIRONMENT}" \
  --query '[0].value' -o tsv)

# Clean the key to ensure it's properly formatted
ACCOUNT_KEY=$(echo "$ACCOUNT_KEY" | tr -d '\r\n')

echo "Storage account key: $ACCOUNT_KEY"
echo "Set the following environment variables to initialize Terraform:"
echo "export ARM_ACCESS_KEY=$ACCOUNT_KEY"
EOF
chmod +x setup_backend.sh

# Ask if user wants to set up remote state backend
read -p "Do you want to set up a remote state backend in Azure for $ENVIRONMENT? (y/n): " SETUP_BACKEND

if [[ "$SETUP_BACKEND" == "y" || "$SETUP_BACKEND" == "Y" ]]; then
    echo "Setting up Terraform state backend..."
    ./setup_backend.sh
    
    # Export the storage account key for Terraform - with proper quoting
    export ARM_ACCESS_KEY="$ACCOUNT_KEY"
    
    # Update backend.tf to use Azure
    cat << EOF > "$ENV_DIR/backend.tf"
terraform {
  backend "azurerm" {
    resource_group_name  = "${PROJECT_NAME}-tfstate-rg"
    storage_account_name = "${PROJECT_NAME//-/}tfstate${ENVIRONMENT}"
    container_name       = "tfstate"
    key                  = "${PROJECT_NAME}-${ENVIRONMENT}.tfstate"
  }
}
EOF
    
    # Reinitialize Terraform with the new backend
    echo "Reinitializing Terraform with Azure backend..."
    terraform init -reconfigure
fi

# Make sure the environment directory exists and has the necessary files
if [ ! -d "$ENV_DIR" ]; then
  echo "Error: Environment directory $ENV_DIR does not exist."
  exit 1
fi

# Change to the environment directory
cd "$ENV_DIR"

# Initialize Terraform
echo "Initializing Terraform for $ENVIRONMENT environment..."
terraform init

# Generate a plan
echo "Generating Terraform plan for $ENVIRONMENT environment..."
terraform plan -out=tfplan

# Ask user if they want to apply the plan
read -p "Do you want to apply the Terraform plan for $ENVIRONMENT? (y/n): " APPLY_PLAN

if [[ "$APPLY_PLAN" == "y" || "$APPLY_PLAN" == "Y" ]]; then
    echo "Applying Terraform plan for $ENVIRONMENT environment..."
    terraform apply tfplan
    
    # Generate .env file from outputs
    echo "Generating .env file for $ENVIRONMENT environment..."
    terraform output -json | jq -r 'to_entries | .[] | "\(.key)=\(.value.value)"' > ../../.env.$ENVIRONMENT
    
    echo "Infrastructure deployment complete for $ENVIRONMENT environment!"
    echo "Environment-specific .env file created at: ../../.env.$ENVIRONMENT"
    
    # Create a symlink to the current environment .env file
    ln -sf .env.$ENVIRONMENT ../../.env
    echo "Created symlink .env -> .env.$ENVIRONMENT"
else
    echo "Terraform plan not applied. You can apply it later with 'terraform apply tfplan'"
fi

# Create a helper script to destroy resources
cat << EOF > destroy.sh
#!/bin/bash
# Script to destroy all Azure resources created by Terraform for $ENVIRONMENT environment

echo "WARNING: This will destroy all Azure resources created for $PROJECT_NAME ($ENVIRONMENT environment)"
read -p "Are you sure you want to continue? (y/n): " CONFIRM

if [[ "\$CONFIRM" == "y" || "\$CONFIRM" == "Y" ]]; then
    terraform destroy -auto-approve
    echo "All resources for $ENVIRONMENT environment destroyed successfully."
else
    echo "Operation cancelled."
fi
EOF
chmod +x destroy.sh

echo "Terraform setup complete for $ENVIRONMENT environment!"
echo "To destroy resources in the future, run: ./env/$ENVIRONMENT/destroy.sh"
