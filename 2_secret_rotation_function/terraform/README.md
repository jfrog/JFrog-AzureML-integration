# Terraform: Secret rotation function with existing workspace storage and Key Vault

This Terraform deploys the Azure Function **infrastructure** (app, plan, RBAC). It does **not** deploy the function code. Deploy the function code after apply — see **Post-install: Deploy function code** below.

- **Existing** Azure ML workspace storage account (data source only)
- **New** blob container in that account, used only by this function (not the container used by Azure ML pipelines)
- **Existing** Azure ML workspace Key Vault (data source only)
- Function app identity is granted **Storage Blob Data Contributor**, **Storage Table Data Contributor**, and **Storage Queue Data Contributor** on the existing storage account, and **Key Vault Secrets Officer** on the existing Key Vault

## Prerequisites

- Azure subscription and CLI logged in (`az login`)
- Either:
  - **Option A:** Existing resource group, storage account, and Key Vault (from your Azure ML workspace), or
  - **Option B:** The [1_azure_machine_learning_workspace](../1_azure_machine_learning_workspace) Terraform already applied, so you can pass its outputs into this module
- Terraform >= 1.5.0

## Usage

1. Copy the example variables and set your values:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your subscription ID, Artifactory URL, OIDC provider, function_app_name, etc.
   # If using Option B below, you can omit resource_group_name, key_vault_name, and existing_storage_account_name in tfvars (they will be passed via -var).
   ```

2. Initialize and apply (creates/updates the function app and RBAC only).

   **Option A — Manual values in tfvars:** Run from this directory (`2_secret_rotation_function/terraform`):
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

   **Option B — Pass values from the Azure ML workspace (1_azure_machine_learning_workspace):** From the **repository root**:
   ```bash
   cd 2_secret_rotation_function/terraform
   terraform init
   terraform plan
   terraform apply \
     -var="resource_group_name=$(cd ../../1_azure_machine_learning_workspace/terraform && terraform output -raw resource_group_name)" \
     -var="key_vault_name=$(cd ../../1_azure_machine_learning_workspace/terraform && terraform output -raw key_vault_name)" \
     -var="existing_storage_account_name=$(cd ../../1_azure_machine_learning_workspace/terraform && terraform output -raw storage_account_name)"
   ```
   Ensure `1_azure_machine_learning_workspace/terraform` has been applied at least once so the outputs exist. All other variables (subscription_id, artifactory_url, jfrog_oidc_provider_name, etc.) must still be set in `terraform.tfvars` or via additional `-var` flags.

3. **Post-install: Deploy function code** — after a successful apply, either run the script (recommended) or publish manually:

   **Option A — Script (sets storage key temporarily, publishes, then removes key):** From the repo root or from `2_secret_rotation_function/terraform`:
   ```bash
   cd 2_secret_rotation_function/terraform
   ./deploy-function.sh
   ```
   Override defaults with env vars or args: `./deploy-function.sh [resource_group] [storage_account] [function_app]`

   **Option B — Manual:** Use the same `function_app_name` as in your `terraform.tfvars` and follow the "Error creating a Blob container reference" steps in the next section.
   ```bash
   cd 2_secret_rotation_function/terraform
   func azure functionapp publish <function_app_name> --python --build local
   ```

   **Requirements:**
   - [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local) v4 (e.g. `brew install azure-functions-core-tools@4` on macOS). Ensure `func` is on your PATH or use the full path (e.g. `/opt/homebrew/bin/func`).
   - `az login` already done.
   - Local Python version should match the function app runtime (see `function_python_version` in tfvars; default 3.12).

   **If you see "Error creating a Blob container reference"** — the app uses managed identity for storage; the publish command needs a connection string to upload. Add the storage account primary key to the function app temporarily: in Azure Portal → Function App → Configuration → Application settings, add or edit `AzureWebJobsStorage` with the connection string (e.g. `DefaultEndpointsProtocol=https;AccountName=<name>;AccountKey=<key>;EndpointSuffix=core.windows.net`). Get the key with: `az storage account keys list -g <resource_group> -n <storage_account_name> --query [0].value -o tsv`. Run the publish again, then remove or rotate the key if desired.

## Note on storage roles

The function app identity is granted **Storage Blob Data Contributor**, **Storage Table Data Contributor**, and **Storage Queue Data Contributor** on the existing storage account. The Azure Functions host requires Table and Queue access for internal state and triggers.

## Creating a new function app

Every function app created by this Terraform is **new** (it is created when you run `terraform apply`). The message *"Your function app does not support remote build as it was created before August 1st, 2019"* is misleading — it is caused by Linux Consumption + managed-identity storage, not creation date.

To create a **separate** new function app (e.g. a second app or a replacement):

1. Set a different **`function_app_name`** in `terraform.tfvars` (e.g. `artifactory-token-rotation-v2`).
2. Run `terraform plan` and `terraform apply`. Terraform will create a new plan and a new function app with that name.
3. Deploy code: from `2_secret_rotation_function/terraform` run `USE_FUNC_PUBLISH=1 ./deploy-function.sh`.

To **replace** the existing app (same name, fresh resource), you would remove the old app from Terraform state and apply again, or use a new Terraform state; typically it is simpler to use a new name as above.

## Troubleshooting deployment

**Deploy from this directory:** `./deploy-function.sh` (zip deploy) or `USE_FUNC_PUBLISH=1 ./deploy-function.sh` (Functions Core Tools; uses `--build local` to avoid remote-build/storage issues).

- **"Malformed SCM_RUN_FROM_PACKAGE when uploading built content"** — Zip deploy with remote build on Linux Consumption requires the deployment system to upload the built package to blob storage. That only works when `AzureWebJobsStorage` is a **full connection string including AccountKey**. If you use an identity-only value (e.g. for `storage_uses_managed_identity`), either:
  1. Use **Functions Core Tools** so you don’t need the key: `USE_FUNC_PUBLISH=1 ./deploy-function.sh`, or  
  2. Set `AzureWebJobsStorage` (e.g. in Portal or via `terraform.tfvars` / app settings) to a full connection string: `DefaultEndpointsProtocol=https;AccountName=<name>;AccountKey=<key>;EndpointSuffix=core.windows.net`. Get the key with: `az storage account keys list -g <resource_group> -n <storage_account> --query [0].value -o tsv`.
