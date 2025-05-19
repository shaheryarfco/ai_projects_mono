#!/bin/bash
# Terraform setup script for Azure infrastructure deployment
# This script creates and configures Azure resources for ML projects

set -e

# Get the project name from the current directory or parent directory
PROJECT_NAME=$(basename $(cd .. && pwd))
ENVIRONMENT=${1:-"dev"}  # Default to dev environment if not specified
LOCATION=${2:-"eastus"}  # Default to East US if not specified

echo "Setting up Terraform for project: $PROJECT_NAME ($ENVIRONMENT environment)"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Azure CLI not found. Please install it first."
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if jq is installed (needed for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo "jq not found. Installing jq..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew install jq
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        sudo apt-get update && sudo apt-get install -y jq
    else
        echo "Please install jq manually: https://stedolan.github.io/jq/download/"
        exit 1
    fi
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Terraform not found. Installing Terraform..."
    
    # Create bin directory if it doesn't exist
    mkdir -p bin
    
    # Download Terraform
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    fi
    
    TERRAFORM_VERSION="1.8.3"
    TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"
    
    echo "Downloading Terraform from $TERRAFORM_URL"
    curl -s -o terraform.zip "$TERRAFORM_URL"
    unzip -q terraform.zip -d bin
    rm terraform.zip
    
    # Add bin to PATH for this session
    export PATH="$PWD/bin:$PATH"
    
    echo "Terraform installed successfully."
fi

# Login to Azure if not already logged in
az account show &> /dev/null || az login

# Get subscription list
echo "Available subscriptions:"
az account list --output table

# Prompt for subscription selection
read -p "Enter the subscription ID to use: " SUBSCRIPTION_ID
az account set --subscription "$SUBSCRIPTION_ID"
echo "Using subscription: $SUBSCRIPTION_ID"

# Create terraform directory structure
mkdir -p modules/storage modules/compute modules/database

# Create variables.tf
cat << EOF > variables.tf
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

variable "admin_username" {
  description = "Admin username for database"
  default     = "psqladmin"
}

variable "admin_password" {
  description = "Admin password for database"
  default     = "H@Sh1CoR3!"  # In production, use a secret from Key Vault
  sensitive   = true
}
EOF

# Create main.tf
cat << EOF > main.tf
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "\${var.project_name}-\${var.environment}-rg"
  location = var.location
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "\${replace(var.project_name, "-", "")}storage\${var.environment}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Storage Container for MLflow Artifacts
resource "azurerm_storage_container" "mlflow_artifacts" {
  name                  = "mlflow-artifacts"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# Storage Container for Data
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# Azure Container Registry for storing Docker images
resource "azurerm_container_registry" "acr" {
  name                = "\${replace(var.project_name, "-", "")}acr\${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Azure Database for PostgreSQL (for MLflow backend)
resource "azurerm_postgresql_server" "postgres" {
  name                = "\${var.project_name}-\${var.environment}-psql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  
  sku_name = "B_Gen5_1"  # Basic tier, Gen5, 1 vCore
  
  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true
  
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
  version                      = "11"
  ssl_enforcement_enabled      = true
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# PostgreSQL Database for MLflow
resource "azurerm_postgresql_database" "mlflow_db" {
  name                = "mlflow"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.postgres.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
}

# PostgreSQL Firewall Rule to allow Azure services
resource "azurerm_postgresql_firewall_rule" "azure_services" {
  name                = "AllowAzureServices"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.postgres.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# Container Instance for MLflow Tracking Server
resource "azurerm_container_group" "mlflow" {
  name                = "\${var.project_name}-\${var.environment}-mlflow"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  dns_name_label      = "\${var.project_name}-\${var.environment}-mlflow"
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
      "MLFLOW_SERVER_DEFAULT_ARTIFACT_ROOT" = "wasbs://\${azurerm_storage_container.mlflow_artifacts.name}@\${azurerm_storage_account.storage.name}.blob.core.windows.net/"
      "AZURE_STORAGE_ACCESS_KEY"            = azurerm_storage_account.storage.primary_access_key
      "MLFLOW_BACKEND_STORE_URI"            = "postgresql://\${var.admin_username}:\${var.admin_password}@\${azurerm_postgresql_server.postgres.fqdn}:5432/\${azurerm_postgresql_database.mlflow_db.name}"
    }
    
    commands = [
      "mlflow",
      "server",
      "--host",
      "0.0.0.0",
      "--port",
      "5000",
      "--backend-store-uri",
      "postgresql://\${var.admin_username}:\${var.admin_password}@\${azurerm_postgresql_server.postgres.fqdn}:5432/\${azurerm_postgresql_database.mlflow_db.name}",
      "--default-artifact-root",
      "wasbs://\${azurerm_storage_container.mlflow_artifacts.name}@\${azurerm_storage_account.storage.name}.blob.core.windows.net/"
    ]
  }
}
EOF

# Create outputs.tf
cat << EOF > outputs.tf
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
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
  value = azurerm_postgresql_server.postgres.fqdn
}

output "mlflow_tracking_uri" {
  value = "http://\${azurerm_container_group.mlflow.fqdn}:5000"
}

output "mlflow_artifact_uri" {
  value = "wasbs://\${azurerm_storage_container.mlflow_artifacts.name}@\${azurerm_storage_account.storage.name}.blob.core.windows.net/"
}
EOF

# Create .env.template file
cat << EOF > .env.template
# Azure Storage
AZURE_STORAGE_ACCOUNT=\${storage_account_name}
AZURE_STORAGE_KEY=\${storage_account_key}

# MLflow
MLFLOW_TRACKING_URI=\${mlflow_tracking_uri}
MLFLOW_ARTIFACT_URI=\${mlflow_artifact_uri}

# PostgreSQL
POSTGRES_SERVER=\${postgres_server_fqdn}
POSTGRES_USER=\${admin_username}
POSTGRES_PASSWORD=\${admin_password}
POSTGRES_DB=mlflow

# Container Registry
ACR_LOGIN_SERVER=\${container_registry_login_server}
ACR_USERNAME=\${acr_username}
ACR_PASSWORD=\${acr_password}
EOF

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Generate a plan
echo "Generating Terraform plan..."
terraform plan -out=tfplan

# Ask user if they want to apply the plan
read -p "Do you want to apply the Terraform plan? (y/n): " APPLY_PLAN

if [[ "$APPLY_PLAN" == "y" || "$APPLY_PLAN" == "Y" ]]; then
    echo "Applying Terraform plan..."
    terraform apply tfplan
    
    # Generate .env file from outputs
    echo "Generating .env file..."
    terraform output -json | jq -r 'to_entries | .[] | "\(.key)=\(.value.value)"' > ../.env
    
    echo "Infrastructure deployment complete!"
    echo "MLflow tracking URI: $(terraform output -raw mlflow_tracking_uri)"
    echo ""
    echo "Run the following command to set up MLflow environment variables:"
    echo "cd ../scripts && ./mlflow-setup.sh"
else
    echo "Terraform plan not applied. You can apply it later with 'terraform apply tfplan'"
fi

# Create a helper script to destroy resources
cat << EOF > destroy.sh
#!/bin/bash
# Script to destroy all Azure resources created by Terraform

echo "WARNING: This will destroy all Azure resources created for $PROJECT_NAME ($ENVIRONMENT environment)"
read -p "Are you sure you want to continue? (y/n): " CONFIRM

if [[ "\$CONFIRM" == "y" || "\$CONFIRM" == "Y" ]]; then
    terraform destroy -auto-approve
    echo "All resources destroyed successfully."
else
    echo "Operation cancelled."
fi
EOF
chmod +x destroy.sh

echo "Terraform setup complete!"
echo "To destroy resources in the future, run: ./destroy.sh"
