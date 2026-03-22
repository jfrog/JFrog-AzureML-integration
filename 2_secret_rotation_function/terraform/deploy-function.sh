#!/usr/bin/env bash
# (c) JFrog Ltd (2026).
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

# Invoke the timer-triggered function once so the Key Vault secret is updated immediately
# (otherwise it would only run on the next timer schedule)


echo "Triggering one-time run of KeyVaultSecretRotation to update the Artifactory token in Key Vault ..."
HOSTNAME="$(terraform output -raw function_app_default_hostname)"
MASTER_KEY="$(az functionapp keys list --resource-group "$RG_NAME" --name "$FUNCTION_APP_NAME" --query masterKey -o tsv 2>/dev/null || true)"
if [ -n "$MASTER_KEY" ]; then
  HTTP_CODE="$(curl -s -o /tmp/func_invoke_response.txt -w "%{http_code}" -X POST "https://${HOSTNAME}/api/KeyVaultSecretRotation" \
    -H "x-functions-key: $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d '{}')"
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
    echo "Function invoked successfully (HTTP $HTTP_CODE). Secret should be updated."
  else
    echo "Warning: Function invoke returned HTTP $HTTP_CODE. Check App Insights or logs." >&2
    [ -f /tmp/func_invoke_response.txt ] && cat /tmp/func_invoke_response.txt >&2
  fi
  rm -f /tmp/func_invoke_response.txt
else
  echo "Warning: Could not retrieve function app key; skipping one-time invoke. Secret will update on next timer run." >&2
fi
  
echo "Done."x