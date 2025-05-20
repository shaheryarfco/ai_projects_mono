#!/bin/bash
# MLflow setup script for configuring MLflow after Azure infrastructure deployment
# This script sets up environment variables and tests the MLflow connection

set -e

# Get the project directory (parent directory)
PROJECT_DIR=$(cd .. && pwd)
PROJECT_NAME=$(basename "$PROJECT_DIR")

echo "Setting up MLflow for project: $PROJECT_NAME"

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI not found. Please install it first."
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Verify Azure login
if ! az account show &> /dev/null; then
    echo "Not logged in to Azure. Please log in first."
    az login
fi

# Check if .env file exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "Error: .env file not found in project directory."
    echo "Please run terraform-setup.sh first to deploy infrastructure and generate .env file."
    exit 1
fi

# Source the .env file to get environment variables
source "$PROJECT_DIR/.env"

# Check if MLflow tracking URI is set
if [ -z "$MLFLOW_TRACKING_URI" ]; then
    echo "Error: MLFLOW_TRACKING_URI not found in .env file."
    echo "Please check your infrastructure deployment."
    exit 1
fi

echo "MLflow tracking URI: $MLFLOW_TRACKING_URI"
echo "MLflow artifact URI: $MLFLOW_ARTIFACT_URI"

# Check if Python is installed
if ! command -v python &> /dev/null; then
    echo "Error: Python not found. Please install Python first."
    exit 1
fi

# Check if MLflow is installed
if ! python -c "import mlflow" &> /dev/null; then
    echo "MLflow not found in Python environment. Installing MLflow..."
    pip install mlflow azure-storage-blob
fi

# Create a test script to verify MLflow connection
cat << EOF > test_mlflow.py
import os
import mlflow
import sys
from datetime import datetime

# Set MLflow tracking URI from environment variable
tracking_uri = os.getenv("MLFLOW_TRACKING_URI")
if not tracking_uri:
    print("Error: MLFLOW_TRACKING_URI environment variable not set.")
    sys.exit(1)

mlflow.set_tracking_uri(tracking_uri)
print(f"MLflow tracking URI: {mlflow.get_tracking_uri()}")

# Create or get experiment
experiment_name = "${PROJECT_NAME}_test"
try:
    experiment_id = mlflow.create_experiment(experiment_name)
    print(f"Created new experiment: {experiment_name} (ID: {experiment_id})")
except mlflow.exceptions.MlflowException:
    experiment = mlflow.get_experiment_by_name(experiment_name)
    experiment_id = experiment.experiment_id
    print(f"Using existing experiment: {experiment_name} (ID: {experiment_id})")

# Set the experiment as active
mlflow.set_experiment(experiment_name)

# Start a run and log some metrics
with mlflow.start_run() as run:
    run_id = run.info.run_id
    print(f"Started MLflow run: {run_id}")
    
    # Log some parameters and metrics
    mlflow.log_param("test_param", "test_value")
    mlflow.log_metric("test_metric", 42)
    
    # Log a simple text artifact
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    artifact_path = f"test_artifact_{timestamp}.txt"
    with open(artifact_path, "w") as f:
        f.write(f"Test artifact created at {datetime.now().isoformat()}")
    
    mlflow.log_artifact(artifact_path)
    os.remove(artifact_path)
    
    print(f"Logged parameters, metrics, and artifacts to run: {run_id}")
    print(f"Run URL: {tracking_uri}/#/experiments/{experiment_id}/runs/{run_id}")

print("MLflow test completed successfully!")
EOF

# Run the test script
echo "Testing MLflow connection..."
python test_mlflow.py

# If the test was successful, create a setup script for the project
if [ $? -eq 0 ]; then
    echo "MLflow connection test successful!"
    
    # Create a script to set up MLflow environment variables
    cat << EOF > "$PROJECT_DIR/scripts/set_mlflow_env.sh"
#!/bin/bash
# Script to set MLflow environment variables

# MLflow configuration
export MLFLOW_TRACKING_URI="$MLFLOW_TRACKING_URI"
export MLFLOW_ARTIFACT_URI="$MLFLOW_ARTIFACT_URI"

# Azure Storage configuration for MLflow artifacts
export AZURE_STORAGE_ACCOUNT="$AZURE_STORAGE_ACCOUNT"
export AZURE_STORAGE_KEY="$AZURE_STORAGE_KEY"

# PostgreSQL configuration
export POSTGRES_SERVER="$POSTGRES_SERVER"
export POSTGRES_USER="$POSTGRES_USER"
export POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
export POSTGRES_DB="$POSTGRES_DB"

echo "MLflow environment variables set successfully!"
echo "MLflow tracking URI: $MLFLOW_TRACKING_URI"
EOF
    chmod +x "$PROJECT_DIR/scripts/set_mlflow_env.sh"
    
    # Create MLflow utility module
    mkdir -p src/mlops
    cat << EOF > src/mlops/mlflow_utils.py
import os
import mlflow
from mlflow.tracking import MlflowClient

def setup_mlflow(experiment_name=None):
    """
    Set up MLflow tracking.
    
    Args:
        experiment_name: Name of the experiment to use
    
    Returns:
        experiment_id: ID of the created or existing experiment
    """
    # Check if MLFLOW_TRACKING_URI is set in environment
    tracking_uri = os.getenv("MLFLOW_TRACKING_URI")
    if tracking_uri:
        mlflow.set_tracking_uri(tracking_uri)
        print(f"MLflow tracking URI: {mlflow.get_tracking_uri()}")
    else:
        print("Warning: MLFLOW_TRACKING_URI not set. Using default tracking URI.")
    
    # Use project name as experiment name if not provided
    if not experiment_name:
        experiment_name = os.path.basename(os.getcwd())
    
    # Create or get experiment
    try:
        experiment_id = mlflow.create_experiment(experiment_name)
        print(f"Created new experiment: {experiment_name} (ID: {experiment_id})")
    except mlflow.exceptions.MlflowException:
        experiment = mlflow.get_experiment_by_name(experiment_name)
        experiment_id = experiment.experiment_id
        print(f"Using existing experiment: {experiment_name} (ID: {experiment_id})")
    
    # Set the experiment as active
    mlflow.set_experiment(experiment_name)
    
    return experiment_id

def log_model_with_signature(model, model_name, X_sample, params=None, metrics=None):
    """
    Log a model to MLflow with input signature.
    
    Args:
        model: The model to log
        model_name: Name to register the model under
        X_sample: Sample input data for signature
        params: Optional dictionary of parameters to log
        metrics: Optional dictionary of metrics to log
    
    Returns:
        run_id: The ID of the MLflow run
    """
    # Log parameters if provided
    if params:
        for param_name, param_value in params.items():
            mlflow.log_param(param_name, param_value)
    
    # Log metrics if provided
    if metrics:
        for metric_name, metric_value in metrics.items():
            mlflow.log_metric(metric_name, metric_value)
    
    # Create model signature
    from mlflow.models.signature import infer_signature
    signature = infer_signature(X_sample, model.predict(X_sample))
    
    # Log the model with signature
    mlflow.sklearn.log_model(
        sk_model=model,
        artifact_path=model_name,
        signature=signature,
        registered_model_name=model_name
    )
    
    return mlflow.active_run().info.run_id

def register_model(model_uri, model_name, stage="None"):
    """
    Register a model in the MLflow Model Registry.
    
    Args:
        model_uri: URI of the model to register
        model_name: Name to register the model under
        stage: Stage to assign to the model version
    
    Returns:
        model_version: The registered model version
    """
    client = MlflowClient()
    
    # Register the model
    try:
        model_details = mlflow.register_model(model_uri, model_name)
        print(f"Registered model '{model_name}' as version {model_details.version}")
        
        # Set the stage if specified
        if stage != "None":
            client.transition_model_version_stage(
                name=model_name,
                version=model_details.version,
                stage=stage
            )
            print(f"Model '{model_name}' version {model_details.version} transitioned to {stage}")
        
        return model_details
    except Exception as e:
        print(f"Error registering model: {e}")
        return None
EOF

    # Create a sample notebook for MLflow usage
    mkdir -p "$PROJECT_DIR/notebooks"
    cat << EOF > "$PROJECT_DIR/notebooks/mlflow_example.ipynb"
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# MLflow Example Notebook\n",
    "\n",
    "This notebook demonstrates how to use MLflow for experiment tracking and model registry."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import os\n",
    "import sys\n",
    "import mlflow\n",
    "import numpy as np\n",
    "import pandas as pd\n",
    "from sklearn.datasets import load_iris\n",
    "from sklearn.model_selection import train_test_split\n",
    "from sklearn.ensemble import RandomForestClassifier\n",
    "from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score\n",
    "\n",
    "# Add the project root to the Python path\n",
    "project_root = os.path.abspath(os.path.join(os.getcwd(), '..'))\n",
    "if project_root not in sys.path:\n",
    "    sys.path.append(project_root)\n",
    "\n",
    "# Import the MLflow utility module\n",
    "from src.mlops.mlflow_utils import setup_mlflow, log_model_with_signature"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Set up MLflow\n",
    "experiment_id = setup_mlflow(experiment_name=\"${PROJECT_NAME}_example\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Load and prepare data\n",
    "iris = load_iris()\n",
    "X = iris.data\n",
    "y = iris.target\n",
    "\n",
    "# Split the data\n",
    "X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)\n",
    "\n",
    "# Create a dataframe for better visualization\n",
    "feature_names = iris.feature_names\n",
    "df = pd.DataFrame(X, columns=feature_names)\n",
    "df['target'] = y\n",
    "df.head()"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Train a model with MLflow tracking\n",
    "with mlflow.start_run(run_name=\"random_forest_example\") as run:\n",
    "    # Set parameters\n",
    "    n_estimators = 100\n",
    "    max_depth = 10\n",
    "    \n",
    "    # Log parameters\n",
    "    mlflow.log_param(\"n_estimators\", n_estimators)\n",
    "    mlflow.log_param(\"max_depth\", max_depth)\n",
    "    mlflow.log_param(\"model_type\", \"RandomForestClassifier\")\n",
    "    \n",
    "    # Train the model\n",
    "    model = RandomForestClassifier(n_estimators=n_estimators, max_depth=max_depth, random_state=42)\n",
    "    model.fit(X_train, y_train)\n",
    "    \n",
    "    # Make predictions\n",
    "    y_pred = model.predict(X_test)\n",
    "    \n",
    "    # Calculate metrics\n",
    "    accuracy = accuracy_score(y_test, y_pred)\n",
    "    precision = precision_score(y_test, y_pred, average='weighted')\n",
    "    recall = recall_score(y_test, y_pred, average='weighted')\n",
    "    f1 = f1_score(y_test, y_pred, average='weighted')\n",
    "    \n",
    "    # Log metrics\n",
    "    mlflow.log_metric(\"accuracy\", accuracy)\n",
    "    mlflow.log_metric(\"precision\", precision)\n",
    "    mlflow.log_metric(\"recall\", recall)\n",
    "    mlflow.log_metric(\"f1_score\", f1)\n",
    "    \n",
    "    # Create model signature\n",
    "    from mlflow.models.signature import infer_signature\n",
    "    signature = infer_signature(X_train, model.predict(X_train))\n",
    "    \n",
    "    # Log the model with signature\n",
    "    log_model_with_signature(\n",
    "        model=model,\n",
    "        artifact_path=\"random_forest_model\",\n",
    "        signature=signature,\n",
    "        input_example=X_train[:5]\n",
    "    )\n",
    "    \n",
    "    # Print results\n",
    "    print(f\"Run ID: {run.info.run_id}\")\n",
    "    print(f\"Accuracy: {accuracy:.4f}\")\n",
    "    print(f\"Precision: {precision:.4f}\")\n",
    "    print(f\"Recall: {recall:.4f}\")\n",
    "    print(f\"F1 Score: {f1:.4f}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Register the model in the MLflow Model Registry\n",
    "model_name = \"${PROJECT_NAME}_iris_classifier\"\n",
    "model_uri = f\"runs:/{run.info.run_id}/random_forest_model\"\n",
    "\n",
    "registered_model = mlflow.register_model(\n",
    "    model_uri=model_uri,\n",
    "    name=model_name\n",
    ")\n",
    "\n",
    "print(f\"Model registered with name: {model_name}\")\n",
    "print(f\"Model version: {registered_model.version}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Load the model from the Model Registry\n",
    "loaded_model = mlflow.pyfunc.load_model(f\"models:/{model_name}/{registered_model.version}\")\n",
    "\n",
    "# Make predictions with the loaded model\n",
    "loaded_predictions = loaded_model.predict(X_test)\n",
    "\n",
    "# Verify that the predictions match\n",
    "original_predictions = model.predict(X_test)\n",
    "predictions_match = np.array_equal(loaded_predictions, original_predictions)\n",
    "\n",
    "print(f\"Predictions from loaded model match original model: {predictions_match}\")"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.10.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    echo "Created MLflow utility module and example notebook."
    echo "To set MLflow environment variables, run: source $PROJECT_DIR/scripts/set_mlflow_env.sh"
    
    # Clean up test script
    rm test_mlflow.py
else
    echo "MLflow connection test failed. Please check your infrastructure deployment and try again."
    exit 1
fi

echo "MLflow setup complete!"
echo "You can now use MLflow for experiment tracking and model registry."
echo "See the example notebook at: $PROJECT_DIR/notebooks/mlflow_example.ipynb"


