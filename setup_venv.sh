#!/bin/bash
# setup_venv.sh


# Find Python 3.11+ (check python3.11, python3.12, python3.13, etc., then fallback to python3)
PYTHON_CMD=""
for version in python3.11 python3.12 python3.13 python3.14 python3.15 python3; do
    if command -v $version &> /dev/null; then
        # Check if version is 3.11 or higher
        VERSION_OUTPUT=$($version --version 2>&1)
        VERSION_NUM=$(echo "$VERSION_OUTPUT" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        MAJOR=$(echo "$VERSION_NUM" | cut -d. -f1)
        MINOR=$(echo "$VERSION_NUM" | cut -d. -f2)
        
        if [ "$MAJOR" -eq 3 ] && [ "$MINOR" -ge 11 ]; then
            PYTHON_CMD=$version
            echo "Found Python $VERSION_NUM at: $(which $version)"
            break
        fi
    fi
done

# Check if Python 3.11+ is available
if [ -z "$PYTHON_CMD" ]; then
    echo "Python 3.11+ not found. Please install it first."
    exit 1
fi

# Create virtual environment
$PYTHON_CMD -m venv .venv

# Activate and install dependencies
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "Virtual environment created and dependencies installed!"
echo "To activate: source .venv/bin/activate"