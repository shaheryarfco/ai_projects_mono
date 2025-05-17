
#!/bin/bash

# Usage: ./new_project.sh <project_name> [python_version]
# Example: ./new_project.sh rag_chatbot 3.10
# If python_version is not provided, it defaults to 3.10

set -e

PROJECT_NAME=$1
PYTHON_VERSION=${2:-"3.10"}  # Default to Python 3.10 if not specified
BASE_DEPENDENCIES="pandas numpy scikit-learn matplotlib langchain chromadb openai"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$PROJECT_NAME" ]; then
  echo "Usage: $0 <project_name> [python_version]"
  echo "Example: $0 my_project 3.11"
  exit 1
fi

echo "Creating project '$PROJECT_NAME' with Python $PYTHON_VERSION..."
cd "$REPO_ROOT"

# Create project directory and initialize with uv (if not already initialized)
uv init "$PROJECT_NAME" || true
cd "$PROJECT_NAME"

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

# Create best-practice folder structure
mkdir -p data notebooks src/rag src/llm src/vectordb src/utils tests scripts configs

# Create __init__.py files for Python packages
touch src/__init__.py src/rag/__init__.py src/llm/__init__.py src/vectordb/__init__.py src/utils/__init__.py

# Create a starter README
cat << EOF > README.md
# $PROJECT_NAME

This project implements a Retrieval-Augmented Generation (RAG) pipeline using LLMs and vector databases.

## Structure

- \`data/\`: Datasets, embeddings, and processed data
- \`notebooks/\`: Jupyter notebooks for exploration and prototyping
- \`src/\`: Source code (organized by component)
- \`tests/\`: Unit and integration tests
- \`scripts/\`: Automation and CLI scripts
- \`configs/\`: Configuration files

## Getting Started

\`\`\`bash
# Activate the virtual environment
source .venv/bin/activate  # On Linux/macOS
.venv\\Scripts\\activate    # On Windows

# Install dependencies
uv pip install -r requirements.txt
\`\`\`

## Python Version
This project uses Python $ACTUAL_PYTHON_VERSION
EOF

# Create LICENSE file
cat << EOF > LICENSE
MIT License

Copyright (c) $(date +%Y) $(whoami)

Permission is hereby granted, free of charge...
EOF

# Create a starter main.py
cat << EOF > main.py
import sys
import platform
import os
from src.rag import *
from src.llm import *
from src.vectordb import *

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

# Optionally: Set up pre-commit hooks (requires pre-commit installed globally)
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

echo "Project $PROJECT_NAME initialized with RAG/LLM best-practice structure!"
echo "Python version: $ACTUAL_PYTHON_VERSION"
echo ""
echo "To run the project:"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
  echo "  run.bat"
else
  echo "  ./run.sh"
fi
