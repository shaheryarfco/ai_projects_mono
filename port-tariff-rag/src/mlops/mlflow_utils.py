import os
import mlflow
from mlflow.tracking import MlflowClient

def setup_mlflow(tracking_uri=None, experiment_name=None):
    """
    Set up MLflow tracking.
    
    Args:
        tracking_uri: MLflow tracking server URI
        experiment_name: Name of the experiment to use
    
    Returns:
        experiment_id: ID of the created or existing experiment
    """
    # Set tracking URI if provided
    if tracking_uri:
        mlflow.set_tracking_uri(tracking_uri)
    else:
        # Check if MLFLOW_TRACKING_URI is set in environment
        tracking_uri = os.getenv("MLFLOW_TRACKING_URI")
        if tracking_uri:
            mlflow.set_tracking_uri(tracking_uri)
    
    # Use project name as experiment name if not provided
    if not experiment_name:
        experiment_name = os.path.basename(os.getcwd())
    
    # Create or get experiment
    try:
        experiment_id = mlflow.create_experiment(experiment_name)
    except mlflow.exceptions.MlflowException:
        experiment_id = mlflow.get_experiment_by_name(experiment_name).experiment_id
    
    # Set the experiment as active
    mlflow.set_experiment(experiment_name)
    
    print(f"MLflow tracking URI: {mlflow.get_tracking_uri()}")
    print(f"MLflow experiment name: {experiment_name}")
    print(f"MLflow experiment ID: {experiment_id}")
    
    return experiment_id
