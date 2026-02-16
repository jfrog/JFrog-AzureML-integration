#!/usr/bin/env bash
# Deploy the function app to Azure using Azure Functions Core Tools (func CLI).
# Uses --build local to package dependencies on-device and upload via the
# management API (no storage keys needed).
# Run from this directory (secret_rotation_function/terraform). Requires:
#   - Azure CLI (az) logged in
#   - Azure Functions Core Tools (func) installed
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

if ! command -v func &>/dev/null; then
  echo "Error: Azure Functions Core Tools (func) not found. Install from: https://docs.microsoft.com/azure/azure-functions/functions-run-local" >&2
  exit 1
fi

echo "Publishing to Function App: $FUNCTION_APP_NAME (resource group: $RG_NAME) ..."
(cd "$SOURCE_DIR" && func azure functionapp publish "$FUNCTION_APP_NAME" --python --build local --debug)

echo "Done."
