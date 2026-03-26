# 2 —  Secret rotation function with existing workspace storage and Key Vault

This Terraform deploys the Azure Function **infrastructure** (app, plan, RBAC). It does **not** deploy the function code. Deploy the function code after apply — see **Post-install: Deploy function code** below.


## Prerequisites (R&R: Azure Administrator)

**Components that were created in Step 1 (1_azure_machine_learning_workspace)**
- In the Azure Key Vault IAM, add **Key Vault Administrator** role to enable one-time secret creation for the relevant users or identities that deploy the Azure Function App.
- Existing resource group, storage account, and Key Vault (from your Azure ML workspace)
- Azure ML workspace storage account (data source only)
- Blob container in that account, used only by this function (not the container used by Azure ML pipelines)
- Azure ML workspace Key Vault (data source only)
- Function app identity is granted **Storage Blob Data Contributor**, **Storage Table Data Contributor**, and **Storage Queue Data Contributor** on the existing storage account, and **Key Vault Secrets Officer** on the existing Key Vault

**Additional prerequisites** 
- Azure subscription and CLI logged in (`az login`)
- Terraform >= 1.5.0

## Usage

1. Copy the example variables and set your values:

``` bash
cd 2_secret_rotation_function/terraform
cp terraform.tfvars.example terraform.tfvars
```

### Edit terraform.tfvars with your: 
* subscription ID (`subscription_id`)
* Azure Resource Group name (`resource_group_name`)
* Artifactory URL (`artifactory_url` from `$ARTIFACTORY_URL`)
* OIDC provider name (`jfrog_oidc_provider_name` from `$OIDC_PROVIDER_NAME`)
* Azure App Registration client ID (`azure_ad_token_audience` from `$APP_CLIENT_ID`)
* Workspace Key Vault name (`key_vault_name`)
* Workspace Storage Account (`existing_storage_account_name`)
* VNet subnet ID (`function_app_integration_subnet_id`)
* Deployment machine IP/s (`deployer_ip_addresses`)
* (Optional) Azure Function app name (`function_app_name`)
* (Optional) Azure Function app storage account container's name (`function_storage_container_name`)


> **Important:** Verify to add the IP/s of the deployment machine to `deployer_ip_addresses` in tfvars to enable successful function code deployment.

2. Initialize and apply (creates/updates the function app and RBAC only).


   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
 
 > **Important:** Save these values for later use:
> - `function_app_name`
> - `resource_group_name`
> - `function_app_identity_principal_id` 
You will need them later on.


3. **Continue to the next steps in the main README.md**
[JFrog Artifactory OIDC Configuration](../../README.md#4-jfrog-artifactory-oidc-configuration-rr-jfrog-administrator-or-project-admin)

---
## Cleanup

To remove the function app, its plan, the blob container created for the function, and the RBAC assignments (the existing Key Vault and storage account are not deleted):

```bash
cd 2_secret_rotation_function/terraform
terraform plan -destroy
terraform destroy
```

Run this **before** destroying the workspace. Then remove the Azure ML workspace and its resources: see [1_azure_machine_learning_workspace — Cleanup](../1_azure_machine_learning_workspace/README.md#cleanup).
