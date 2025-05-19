
#!/bin/bash

# Usage: ./new_project.sh <project_name> [python_version]
# Example: ./new_project.sh rag_chatbot 3.10
# If python_version is not provided, it defaults to 3.10

set -e

PROJECT_NAME=$1
PYTHON_VERSION=${2:-"3.10"}  # Default to Python 3.10 if not specified
BASE_DEPENDENCIES="pandas numpy scikit-learn matplotlib langchain chromadb openai mlflow azure-storage-blob psycopg2-binary"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "Error: 'uv' package manager not found."
    echo "Please install uv first: pip install uv"
    exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
  echo "Usage: $0 <project_name> [python_version]"
  echo "Example: $0 my_project 3.11"
  exit 1
fi

# Check if project directory already exists
if [ -d "$REPO_ROOT/$PROJECT_NAME" ]; then
  echo "Error: Directory '$PROJECT_NAME' already exists."
  echo "Please choose a different project name or remove the existing directory."
  exit 1
fi

echo "Creating project '$PROJECT_NAME' with Python $PYTHON_VERSION..."
cd "$REPO_ROOT"

# Create project directory and initialize with uv (if not already initialized)
uv init "$PROJECT_NAME" || true
cd "$PROJECT_NAME"

# Setup Python environment
setup_python_environment() {
  # Create a virtual environment with the specified Python version
  if command -v python$PYTHON_VERSION &> /dev/null; then
    echo "Using python$PYTHON_VERSION to create virtual environment..."
    uv venv --python python$PYTHON_VERSION
  elif command -v python3 &> /dev/null; then
    # Try to use python3 and check version
    PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if [[ "$PY_VERSION" == "$PYTHON_VERSION" ]]; then
      echo "Using python3 (version $PY_VERSION) to create virtual environment..."
      uv venv --python python3
    else
      echo "Warning: Python $PYTHON_VERSION not found. Using default Python version."
      echo "Some packages may not install correctly with incompatible Python versions."
      uv venv
    fi
  else
    echo "Warning: Python $PYTHON_VERSION not found. Using default Python version."
    echo "Some packages may not install correctly with incompatible Python versions."
    uv venv
  fi

  # Ensure .python-version matches the Python version used
  # Get the actual Python version from the created environment
  ACTUAL_PYTHON_VERSION=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  echo "$ACTUAL_PYTHON_VERSION" > .python-version
  echo "Created virtual environment with Python $ACTUAL_PYTHON_VERSION"

  # Also update pyproject.toml to match
  sed -i "s/requires-python = \">=.*/requires-python = \">=$ACTUAL_PYTHON_VERSION\"/g" pyproject.toml

  # Install base dependencies using uv add with --active flag
  uv add --active $BASE_DEPENDENCIES
  
  return 0
}

# Create project structure
create_project_structure() {
  # Create best-practice folder structure
  mkdir -p data notebooks src/rag src/llm src/vectordb src/utils src/mlops tests scripts configs terraform

  # Create __init__.py files for Python packages
  touch src/__init__.py src/rag/__init__.py src/llm/__init__.py src/vectordb/__init__.py src/utils/__init__.py src/mlops/__init__.py
  
  return 0
}

# Create basic project files
create_project_files() {
  # Create a starter README
  cat << EOF > README.md
# $PROJECT_NAME

This project implements a Retrieval-Augmented Generation (RAG) pipeline using LLMs and vector databases.

## Structure

- \`data/\`: Datasets, embeddings, and processed data
- \`notebooks/\`: Jupyter notebooks for exploration and prototyping
- \`src/\`: Source code (organized by component)
  - \`rag/\`: Retrieval-Augmented Generation components
  - \`llm/\`: Large Language Model interfaces
  - \`vectordb/\`: Vector database connections
  - \`utils/\`: Utility functions
  - \`mlops/\`: MLOps utilities (MLflow, CI/CD)
- \`tests/\`: Unit and integration tests
- \`scripts/\`: Automation and CLI scripts
- \`configs/\`: Configuration files
- \`terraform/\`: Infrastructure as Code for Azure deployment

## Getting Started

\`\`\`bash
# Activate the virtual environment
source .venv/bin/activate  # On Linux/macOS
.venv\\Scripts\\activate    # On Windows

# Install dependencies
uv pip install -r requirements.txt

# Run the application
python main.py
\`\`\`

## MLOps Setup

This project includes MLflow for experiment tracking and model registry.
See the terraform and scripts directories for infrastructure setup.

## Python Version
This project uses Python $ACTUAL_PYTHON_VERSION
EOF

  # Create LICENSE file
  cat << EOF > LICENSE
MIT License

Copyright (c) $(date +%Y) $(whoami)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

  # Create a starter main.py that passes linting
  cat << EOF > main.py
import sys
import platform
import os

def main():
    print("Welcome to $PROJECT_NAME! Start building your RAG pipeline here.")
    
    # Print Python environment information
    print("\\nPython Environment Information:")
    print(f"Python Version: {platform.python_version()}")
    print(f"Python Implementation: {platform.python_implementation()}")
    print(f"Python Path: {sys.executable}")
    
    # Check if running in virtual environment
    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        print(f"Virtual Environment: Yes (Path: {sys.prefix})")
    else:
        print("Virtual Environment: No")
    
    # Check for MLflow configuration
    mlflow_uri = os.getenv("MLFLOW_TRACKING_URI")
    if mlflow_uri:
        print(f"MLflow Tracking URI: {mlflow_uri}")
    else:
        print("MLflow not configured. Run scripts/mlflow-setup.sh after deploying infrastructure.")

if __name__ == "__main__":
    main()
EOF

  # Create a .gitignore
  cat << EOF > .gitignore
# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*.so

# Virtual environments
.venv/
env/
venv/

# Data and outputs
data/
outputs/
*.db

# Jupyter Notebook checkpoints
.ipynb_checkpoints/

# OS files
.DS_Store
Thumbs.db

# uv/poetry/pipenv files
uv.lock

# Terraform
terraform/.terraform/
terraform/.terraform.lock.hcl
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/.terraform.tfstate.lock.info

# Environment variables
.env

# MLflow
mlruns/

# IDE specific
.vscode/
.idea/
EOF

  # Create requirements.txt with base dependencies
  echo "$BASE_DEPENDENCIES" | tr ' ' '\n' > requirements.txt

  # Create run scripts for convenience
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows batch file
    cat << EOF > run.bat
@echo off
.venv\\Scripts\\activate
python main.py
EOF
    echo "Created run.bat for Windows"
  else
    # Bash script for Unix-like systems
    cat << EOF > run.sh
#!/bin/bash
source .venv/bin/activate
python main.py
EOF
    chmod +x run.sh
    echo "Created run.sh for Unix-like systems"
  fi
  
  return 0
}

# Create Docker configuration
create_docker_files() {
  # Create Dockerfile
  cat << EOF > Dockerfile
FROM python:${ACTUAL_PYTHON_VERSION}-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["python", "main.py"]
EOF

  # Create docker-compose.yml
  cat << EOF > docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    volumes:
      - ./data:/app/data
    environment:
      - PYTHONUNBUFFERED=1
      - MLFLOW_TRACKING_URI=\${MLFLOW_TRACKING_URI}
    ports:
      - "8000:8000"
  
  # Uncomment to run MLflow locally for development
  # mlflow:
  #   image: ghcr.io/mlflow/mlflow:latest
  #   ports:
  #     - "5000:5000"
  #   volumes:
  #     - ./mlruns:/mlruns
  #   command: mlflow server --host 0.0.0.0 --backend-store-uri sqlite:///mlruns/mlflow.db --default-artifact-root ./mlruns
EOF

  # Add .dockerignore
  cat << EOF > .dockerignore
.venv/
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
env/
.git/
.gitignore
.env
terraform/
EOF
  
  return 0
}

# Create MLOps utilities
create_mlops_files() {
  # Create MLflow utility module
  mkdir -p src/mlops
  cat << EOF > src/mlops/mlflow_utils.py
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
EOF

  # Create setup script templates
  mkdir -p scripts
  
  # Create MLflow setup script template
  cat << EOF > scripts/mlflow-setup.sh
#!/bin/bash
# This script will be implemented to configure MLflow after infrastructure deployment
echo "MLflow setup script template - implement me!"
EOF
  chmod +x scripts/mlflow-setup.sh
  
  # Create Terraform setup script template
  mkdir -p terraform
  cat << EOF > terraform/terraform-setup.sh
#!/bin/bash
# This script will be implemented to deploy Azure infrastructure
echo "Terraform setup script template - implement me!"
EOF
  chmod +x terraform/terraform-setup.sh
  
  return 0
}

# Create pre-commit hooks
setup_pre_commit() {
  if command -v pre-commit &> /dev/null; then
    cat << EOF > .pre-commit-config.yaml
repos:
  - repo: https://github.com/psf/black
    rev: 24.3.0
    hooks:
      - id: black
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.4.0
    hooks:
      - id: ruff
EOF
    pre-commit install
    echo "Pre-commit hooks installed."
  else
    echo "pre-commit not found. Skipping pre-commit hook setup."
  fi
  
  return 0
}

# Execute all setup functions
setup_python_environment
create_project_structure
create_project_files
create_docker_files
create_mlops_files
setup_pre_commit

echo "Project $PROJECT_NAME initialized with RAG/LLM best-practice structure!"
echo "Python version: $ACTUAL_PYTHON_VERSION"
echo ""
echo "To run the project:"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
  echo "  run.bat"
else
  echo "  ./run.sh"
fi
echo ""
echo "Next steps:"
echo "  1. Implement terraform/terraform-setup.sh to deploy Azure infrastructure"
echo "  2. Implement scripts/mlflow-setup.sh to configure MLflow"
