#!/usr/bin/env bash
# Deploy the function app to Azure using az CLI zip deploy with remote build.
# This is more reliable than `func publish` on Linux Consumption plans.
# Run from this directory (secret_rotation_function/terraform). Requires:
#   - Azure CLI (az) logged in
#   - Terraform already applied (terraform output available)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
# Function app source: parent of terraform (host.json, function_app.py, requirements.txt, etc.)
SOURCE_DIR="$(cd "$TERRAFORM_DIR/.." && pwd)"

cd "$TERRAFORM_DIR"

# Ensure Terraform has been applied
if ! terraform output -raw resource_group_name &>/dev/null; then
  echo "Error: Terraform outputs not found. Run 'terraform init' and 'terraform apply' first." >&2
  exit 1
fi

RG_NAME="$(terraform output -raw resource_group_name)"
FUNCTION_APP_NAME="$(terraform output -raw function_app_name)"

# Create zip from source directory (exclude terraform dir and other non-function files)
ZIP_FILE="$TERRAFORM_DIR/function_app.zip"
echo "Creating zip package from $SOURCE_DIR ..."
(cd "$SOURCE_DIR" && zip -r "$ZIP_FILE" . \
  -x "terraform/*" \
  -x ".funcignore" \
  -x "__pycache__/*" \
  -x ".python_packages/*" \
  -x ".venv/*" \
  -x "*.pyc" \
)

echo "Deploying to Function App: $FUNCTION_APP_NAME (resource group: $RG_NAME) ..."
az functionapp deployment source config-zip \
  --resource-group "$RG_NAME" \
  --name "$FUNCTION_APP_NAME" \
  --src "$ZIP_FILE" \
  --build-remote true \
  --timeout 600

echo "Cleaning up zip ..."
rm -f "$ZIP_FILE"

echo "Done."