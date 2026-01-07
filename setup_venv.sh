#!/bin/bash
# setup_venv.sh
export PIP_CONFIG_FILE=$(pwd)/pip.conf
# Check if Python 3.11+ is available
if ! command -v python3.11 &> /dev/null; then
    echo "Python 3.11+ not found. Please install it first."
    exit 1
fi

# Create virtual environment
python3.11 -m venv .venv

# Activate and install dependencies
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "Virtual environment created and dependencies installed!"
echo "To activate: source .venv/bin/activate"