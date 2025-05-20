# Port Tariff RAG - Terraform Infrastructure

This directory contains Terraform configurations for deploying the infrastructure required for the Port Tariff RAG project.

## Setup

The `terraform-setup.sh` script automates the process of setting up the Terraform environment and deploying the infrastructure. It creates the necessary Azure resources based on your selections.

### Prerequisites

- Azure CLI installed and configured
- Terraform installed
- jq installed (for JSON processing)

### Running the Setup

```bash
# For Linux/macOS
./terraform-setup.sh [environment] [location]

# For Windows PowerShell
bash terraform-setup.sh [environment] [location]
```

Parameters:
- `environment`: The environment to deploy (default: "dev")
- `location`: The Azure region to deploy to (default: "eastus")

## Cleanup

If you need to clean up resources, you can use the provided cleanup scripts:

### Using Terraform Destroy (Recommended)

If you have the Terraform state files, the best way to clean up is to use Terraform's destroy command:

```bash
cd env/dev  # or the environment you deployed to
terraform destroy
```

### Using the Cleanup Scripts

If Terraform state is not available or if you need to force cleanup:

#### For Linux/macOS:

```bash
# Clean up dev environment
./cleanup.sh dev

# Clean up prod environment
./cleanup.sh prod
```

#### For Windows:

```powershell
# Clean up dev environment
.\cleanup.ps1 dev

# Clean up prod environment
.\cleanup.ps1 prod
```

## Handling Failed Deployments

If a Terraform deployment fails, the `terraform-setup.sh` script includes error handling that will attempt to clean up any partially created resources. However, if this automatic cleanup fails, you can use the cleanup scripts to manually remove resources.

## Resource Groups

The infrastructure is organized into the following resource groups:

- `port-tariff-rag-dev-rg`: Contains all resources for the dev environment
- `port-tariff-rag-prod-rg`: Contains all resources for the prod environment
- `port-tariff-rag-tfstate-rg`: Contains the storage account for Terraform state (if remote state is enabled)

## Resources Created

The Terraform configuration creates the following resources:

- Resource Group
- Storage Account
- PostgreSQL Flexible Server
- Key Vault
- Container Registry
- Function App
- Logic App
- MLflow Container Instance

## Troubleshooting

### Common Issues

1. **Quota Limits**: If you encounter quota limit errors, try deploying to a different region or request a quota increase.

2. **Name Conflicts**: If resource names are already taken, modify the project name or environment name.

3. **Authentication Issues**: Ensure you're logged in to Azure CLI with the correct subscription selected.

4. **Terraform State Issues**: If Terraform state is corrupted, use the cleanup scripts to remove resources and start fresh.

### Getting Help

If you encounter issues not covered here, please check the Azure documentation or Terraform documentation for more information.
