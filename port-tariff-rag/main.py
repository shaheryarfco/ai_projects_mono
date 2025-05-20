import sys
import platform
import os


def main():
    print("Welcome to port-tariff-rag! Start building your RAG pipeline here.")

    # Print Python environment information
    print("\nPython Environment Information:")
    print(f"Python Version: {platform.python_version()}")
    print(f"Python Implementation: {platform.python_implementation()}")
    print(f"Python Path: {sys.executable}")

    # Check if running in virtual environment
    if hasattr(sys, "real_prefix") or (
        hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix
    ):
        print(f"Virtual Environment: Yes (Path: {sys.prefix})")
    else:
        print("Virtual Environment: No")

    # Check for MLflow configuration
    mlflow_uri = os.getenv("MLFLOW_TRACKING_URI")
    if mlflow_uri:
        print(f"MLflow Tracking URI: {mlflow_uri}")
    else:
        print(
            "MLflow not configured. Run scripts/mlflow-setup.sh after deploying infrastructure."
        )


if __name__ == "__main__":
    main()
