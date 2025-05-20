# PowerShell script for cleaning up Azure resources created by Terraform
# This script will clean up all resources created for the project

# Get the project name from the current directory or parent directory
$ProjectName = (Get-Item (Join-Path $PSScriptRoot "..")).Name
$Environment = $args[0]
if (-not $Environment) {
    $Environment = "dev"  # Default to dev environment if not specified
}

# Define the shared resource group name for the environment
$SharedRG = "$ProjectName-$Environment-rg"

# Define resource names for easy reference
$StorageAcct = "$($ProjectName -replace '-', '')storage$Environment"
$KeyVault = "$($ProjectName -replace '-', '')kv$Environment"
$PostgresServer = "$ProjectName-$Environment-psql"
$AcrName = "$($ProjectName -replace '-', '')acr$Environment"
$FunctionApp = "$ProjectName-$Environment-function"
$AppServicePlan = "$ProjectName-$Environment-plan"
$LogicApp = "$ProjectName-$Environment-auto-shutdown"
$ContainerGroup = "$ProjectName-$Environment-mlflow"

Write-Host "This script will delete ALL resources for project $ProjectName in the $Environment environment."
Write-Host "Resources to be deleted:"
Write-Host "- Resource Group: $SharedRG"
Write-Host "- Storage Account: $StorageAcct"
Write-Host "- Key Vault: $KeyVault"
Write-Host "- PostgreSQL Server: $PostgresServer"
Write-Host "- Container Registry: $AcrName"
Write-Host "- Function App: $FunctionApp"
Write-Host "- App Service Plan: $AppServicePlan"
Write-Host "- Logic App: $LogicApp"
Write-Host "- Container Group: $ContainerGroup"

$Confirm = Read-Host "Are you sure you want to proceed with deletion? (y/n)"
if ($Confirm -ne "y" -and $Confirm -ne "Y") {
    Write-Host "Operation cancelled."
    exit 0
}

Write-Host "Starting cleanup process..."

# Check if Terraform state exists and use it for cleanup
$EnvDir = "env/$Environment"
if (Test-Path "$EnvDir/terraform.tfstate") {
    Write-Host "Terraform state found. Using terraform destroy..."
    Set-Location $EnvDir
    terraform destroy -auto-approve
    Write-Host "Terraform destroy completed."
    exit 0
}

# If no Terraform state, perform manual cleanup
Write-Host "No Terraform state found. Performing manual cleanup..."

# Login to Azure if not already logged in
try {
    $null = az account show
} catch {
    Write-Host "Logging in to Azure..."
    az login
}

# Function App
try {
    $null = az functionapp show --name $FunctionApp --resource-group $SharedRG
    Write-Host "Deleting Function App $FunctionApp..."
    az functionapp delete --name $FunctionApp --resource-group $SharedRG --yes
} catch {
    Write-Host "Function App $FunctionApp not found or already deleted."
}

# App Service Plan
try {
    $null = az appservice plan show --name $AppServicePlan --resource-group $SharedRG
    Write-Host "Deleting App Service Plan $AppServicePlan..."
    az appservice plan delete --name $AppServicePlan --resource-group $SharedRG --yes
} catch {
    Write-Host "App Service Plan $AppServicePlan not found or already deleted."
}

# Logic App
try {
    $null = az logic workflow show --name $LogicApp --resource-group $SharedRG
    Write-Host "Deleting Logic App $LogicApp..."
    az logic workflow delete --name $LogicApp --resource-group $SharedRG --yes
} catch {
    Write-Host "Logic App $LogicApp not found or already deleted."
}

# Container Instance for MLflow
try {
    $null = az container show --name $ContainerGroup --resource-group $SharedRG
    Write-Host "Deleting Container Group $ContainerGroup..."
    az container delete --name $ContainerGroup --resource-group $SharedRG --yes
} catch {
    Write-Host "Container Group $ContainerGroup not found or already deleted."
}

# Storage container
try {
    $null = az storage account show --name $StorageAcct --resource-group $SharedRG
    Write-Host "Checking for storage containers..."
    $StorageKey = az storage account keys list --account-name $StorageAcct --resource-group $SharedRG --query '[0].value' -o tsv
    az storage container delete --name "mlflow-artifacts" --account-name $StorageAcct --account-key $StorageKey
} catch {
    Write-Host "Storage account $StorageAcct not found or containers already deleted."
}

# Storage account
try {
    $null = az storage account show --name $StorageAcct --resource-group $SharedRG
    Write-Host "Deleting storage account $StorageAcct..."
    az storage account delete --name $StorageAcct --resource-group $SharedRG --yes
} catch {
    Write-Host "Storage account $StorageAcct not found or already deleted."
}

# Key vault
try {
    $null = az keyvault show --name $KeyVault --resource-group $SharedRG
    Write-Host "Deleting key vault $KeyVault..."
    az keyvault delete --name $KeyVault --resource-group $SharedRG
} catch {
    Write-Host "Key vault $KeyVault not found or already deleted."
}

# PostgreSQL server
try {
    $null = az postgres flexible-server show --name $PostgresServer --resource-group $SharedRG
    Write-Host "Deleting PostgreSQL server $PostgresServer..."
    az postgres flexible-server delete --name $PostgresServer --resource-group $SharedRG --yes
} catch {
    Write-Host "PostgreSQL server $PostgresServer not found or already deleted."
}

# Container registry
try {
    $null = az acr show --name $AcrName --resource-group $SharedRG
    Write-Host "Deleting container registry $AcrName..."
    az acr delete --name $AcrName --resource-group $SharedRG --yes
} catch {
    Write-Host "Container registry $AcrName not found or already deleted."
}

# Finally, delete the resource group if it exists
try {
    $null = az group show --name $SharedRG
    Write-Host "Deleting resource group $SharedRG..."
    az group delete --name $SharedRG --yes
} catch {
    Write-Host "Resource group $SharedRG not found or already deleted."
}

Write-Host "Cleanup completed. Please check Azure portal to ensure all resources were properly removed."
