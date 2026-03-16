# 1 — Azure Machine Learning workspace (R&R: Azure Administrator)

This module provisions the **Azure Machine Learning workspace** and supporting infrastructure used by the JFrog–Azure ML integration. It is intended to be applied **first**; the [2_secret_rotation_function](../2_secret_rotation_function) Terraform can consume its outputs for Key Vault, storage, and resource group.

## What gets created

- **Resource group** — Name: `{prefix}-rg` (e.g. `rg-*-rg` with random suffix).
- **Virtual network** and **two subnets** — Subnet 1 has service endpoints for Key Vault and Storage and delegation for `Microsoft.App/environments` (e.g. for Azure Functions VNet integration). Subnet 2 hosts the **workspace private endpoint** (private endpoint network policies disabled).
- **Key Vault** — RBAC-only (`rbac_authorization_enabled = true`). Network rules restrict access to allowed IPs and the VNet/subnets.
- **Storage account** — Standard LRS, same network rules (allowed IPs + subnets).
- **Application Insights** — For the ML workspace.
- **Machine Learning workspace** — Basic SKU, system-assigned identity, managed network (internet outbound). Optional workspace-level IP allowlist via AzAPI.
- **Private endpoint** for the ML workspace in subnet 2, with private DNS zone `privatelink.api.azureml.ms` and VNet link so workspace API traffic can use the VNet.
- **Compute cluster** — Name `azureml-poc-cluster`, with scale settings and system-assigned identity. The compute identity is granted:
  - **Key Vault Secrets User** on the workspace Key Vault
  - **Storage Blob Data Contributor** on the workspace storage account

## Prerequisites

- Azure subscription and CLI logged in (`az login`).
- Terraform >= 1.5.0.
- Sufficient permissions to create resource groups, VNets, Key Vaults, storage accounts, Application Insights, and Azure ML workspaces/compute.

## Usage

1. **Copy the example variables and set your values:**
  ```bash
   cd 1_azure_machine_learning_workspace/terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars: subscription_id, ip_rules (allowed IPs), and optionally location, prefix, environment, compute settings, tags.
  ```
2. **Initialize and apply:**
  ```bash
   terraform init
   terraform plan
   terraform apply
  ```
3. **Use outputs elsewhere** — After apply, you can pass these outputs into the secret rotation function as variables. The 2_secret_rotation_function Terraform expects (see [2_secret_rotation_function/terraform/README.md](../2_secret_rotation_function/terraform/README.md)):
  
  - `resource_group_name` ← `terraform output -raw resource_group_name`
  - `key_vault_name` ← `terraform output -raw key_vault_name`
  - `existing_storage_account_name` ← `terraform output -raw storage_account_name`
  - `function_app_integration_subnet_id` ← `terraform output -raw subnet_id_1`
 

## Main variables


| Variable                         | Description                                         | Default                 |
| -------------------------------- | --------------------------------------------------- | ----------------------- |
| `subscription_id`                | Azure subscription ID                               | (required)              |
| `resource_group_location`        | Region for the resource group                       | `"Sweden Central"`      |
| `resource_group_name_prefix`     | Prefix for the resource group name                  | `"rg"`                  |
| `environment`                    | Environment name (used in resource names)           | `"dev"`                 |
| `prefix`                         | Prefix for Key Vault and storage names              | `"ml"`                  |
| `ip_rules`                       | Allowed IPs for Key Vault and storage network rules | `["YOUR IP", "NAT IP"]` |
| `compute_cluster_min_node_count` | Min nodes for the ML compute cluster                | `0`                     |
| `compute_cluster_max_node_count` | Max nodes for the ML compute cluster                | `1`                     |
| `compute_cluster_vm_priority`    | `Dedicated` or `LowPriority`                        | `"Dedicated"`           |
| `compute_cluster_vm_size`        | VM size for compute nodes                           | `"Standard_DS3_v2"`     |
| `tags`                           | Tags applied to all resources                       | (see `variables.tf`)    |


## Outputs


| Output                                  | Description                                                 |
| --------------------------------------- | ----------------------------------------------------------- |
| `resource_group_name`                   | Name of the created resource group                          |
| `virtual_network_name`                  | Name of the VNet                                            |
| `subnet_name_1`                         | Name of subnet 1 (Key Vault/Storage/service endpoints)      |
| `subnet_id_1`                           | Resource ID of subnet 1 (for function app VNet integration) |
| `subnet_name_2`                         | Name of subnet 2 (workspace private endpoint)               |
| `key_vault_name`                        | Name of the workspace Key Vault                             |
| `storage_account_name`                  | Name of the workspace storage account                       |
| `machine_learning_workspace_name`       | Name of the ML workspace                                    |
| `machine_learning_compute_cluster_name` | Name of the compute cluster                                 |


These outputs are used by [2_secret_rotation_function](../2_secret_rotation_function) when applying with Option B (passing workspace outputs via `-var`).

## Providers

- **azurerm** (~> 4.0) — Resource group, VNet, subnets, Key Vault, storage, Application Insights, ML workspace, compute cluster, RBAC.
- **azapi** (~> 2.0) — Workspace IP allowlist (`ipAllowlist`) via `azapi_update_resource`.
- **random** (~> 3.0) — Name suffixes for resource group, Key Vault, and storage.

## Notes

- **Key Vault** uses RBAC only; assign roles (e.g. Key Vault Secrets User, Key Vault Secrets Officer) to identities that need access. The compute cluster is granted Key Vault Secrets User automatically.
- **Network rules** — Key Vault and storage default to `Deny` with access only from `ip_rules` and the specified subnet. Ensure your client IP (or NAT) is in `ip_rules` so Terraform and the Azure portal can access them.
- **terraform.tfvars** is typically in `.gitignore`; do not commit secrets or environment-specific values.
- **Workspace update 409** — If the workspace update (ipAllowlist) fails with a 409 conflict, run `terraform apply` again; the second run often succeeds once the workspace is idle.

## Cleanup

To remove all resources created by this module (resource group, VNet, Key Vault, storage, ML workspace, compute cluster, private endpoint, and private DNS):

```bash
cd terraform
terraform plan -destroy
terraform destroy
```

**In case the destroy failed**, check if there is a **Smart detector alert rule** in the Azure Resource Group. If so, remove it manually and re-run:

```bash
terraform destroy
```

If you also deployed [2_secret_rotation_function](../2_secret_rotation_function), run **terraform destroy** there first so the function app and its role assignments are removed before destroying the workspace and Key Vault. Key Vault uses soft delete by default; if you need to purge or recreate a vault with the same name, use the Azure portal or `az keyvault purge` after the retention period.