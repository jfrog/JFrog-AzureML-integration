#!/usr/bin/env bash
# Deploy the function app to Azure using Azure Functions Core Tools (func CLI).
# Run from this directory (secret_rotation_function/terraform). Requires:
#   - Azure CLI (az) logged in
#   - Azure Functions Core Tools (func) installed: https://docs.microsoft.com/azure/azure-functions/functions-run-local
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
STORAGE_ACCOUNT_NAME="$(terraform output -raw storage_account_name)"

# func publish with remote build on Linux Consumption requires AzureWebJobsStorage to be a full connection string
echo "Setting AzureWebJobsStorage for $FUNCTION_APP_NAME (required for remote build)..."
STORAGE_KEY="$(az storage account keys list -g "$RG_NAME" -n "$STORAGE_ACCOUNT_NAME" --query '[0].value' -o tsv)"
AZURE_WEB_JOBS_STORAGE="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net"
az functionapp config appsettings set \
  --resource-group "$RG_NAME" \
  --name "$FUNCTION_APP_NAME" \
  --settings "AzureWebJobsStorage=$AZURE_WEB_JOBS_STORAGE" \
  --output none

if ! command -v func &>/dev/null; then
  echo "Error: Azure Functions Core Tools (func) not found. Install from: https://docs.microsoft.com/azure/azure-functions/functions-run-local" >&2
  exit 1
fi

echo "Publishing to Function App: $FUNCTION_APP_NAME (resource group: $RG_NAME) ..."
(cd "$SOURCE_DIR" && FUNCTIONS_WORKER_RUNTIME=python func azure functionapp publish "$FUNCTION_APP_NAME" --resource-group "$RG_NAME" --build local --debug)

echo "Done."
