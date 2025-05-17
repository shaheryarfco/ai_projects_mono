import sys
import platform
import os
from src.rag import *
from src.llm import *
from src.vectordb import *

def main():
    print("Welcome to port_tariff! Start building your RAG pipeline here.")
    
    # Print Python environment information
    print("\nPython Environment Information:")
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
