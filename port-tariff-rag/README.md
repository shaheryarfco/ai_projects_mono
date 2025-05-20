# port-tariff-rag

This project implements a Retrieval-Augmented Generation (RAG) pipeline using LLMs and vector databases.

## Structure

- `data/`: Datasets, embeddings, and processed data
- `notebooks/`: Jupyter notebooks for exploration and prototyping
- `src/`: Source code (organized by component)
  - `rag/`: Retrieval-Augmented Generation components
  - `llm/`: Large Language Model interfaces
  - `vectordb/`: Vector database connections
  - `utils/`: Utility functions
  - `mlops/`: MLOps utilities (MLflow, CI/CD)
- `tests/`: Unit and integration tests
- `scripts/`: Automation and CLI scripts
- `configs/`: Configuration files
- `terraform/`: Infrastructure as Code for Azure deployment

## Getting Started

```bash
# Activate the virtual environment
source .venv/bin/activate  # On Linux/macOS
.venv\Scripts\activate    # On Windows

# Install dependencies
uv pip install -r requirements.txt

# Run the application
python main.py
```

## MLOps Setup

This project includes MLflow for experiment tracking and model registry.
See the terraform and scripts directories for infrastructure setup.

## Python Version
This project uses Python 3.12
