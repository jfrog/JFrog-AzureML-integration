#!/usr/bin/env bash
# Deploy the function app code to Azure using config-zip.
# Run from this directory (secret_rotation_function/terraform). Requires:
#   - Azure CLI (az) logged in
#   - Terraform already applied (terraform output available)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
# Function app source: parent of terraform (host.json, function_app.py, requirements.txt, etc.)
SOURCE_DIR="$(cd "$TERRAFORM_DIR/.." && pwd)"
ZIP_PATH="${ZIP_PATH:-$TERRAFORM_DIR/function_deploy.zip}"

cd "$TERRAFORM_DIR"

# Ensure Terraform has been applied
if ! terraform output -raw resource_group_name &>/dev/null; then
  echo "Error: Terraform outputs not found. Run 'terraform init' and 'terraform apply' first." >&2
  exit 1
fi

RG_NAME="$(terraform output -raw resource_group_name)"
FUNCTION_APP_NAME="$(terraform output -raw function_app_name)"

echo "Building deployment zip from $SOURCE_DIR ..."
# Package only app files so remote build gets a clean layout (no local .python_packages/terraform).
# Add any new app-level .py or config here if needed.
(cd "$SOURCE_DIR" && zip -r -q "$ZIP_PATH" host.json function_app.py requirements.txt)

echo "Deploying to Function App: $FUNCTION_APP_NAME (resource group: $RG_NAME) ..."
az functionapp deployment source config-zip \
  --resource-group "$RG_NAME" \
  --name "$FUNCTION_APP_NAME" \
  --src "$ZIP_PATH" \
  --build-remote true \
  --timeout 600 --debug || true

echo "Done."
