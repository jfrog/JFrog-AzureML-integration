# 1 — Azure Machine Learning workspace (R&R: Azure Administrator)

This module provisions the **Azure Machine Learning workspace** and supporting infrastructure used by the JFrog–Azure ML integration. It is intended to be applied **first**; the [2_secret_rotation_function](../2_secret_rotation_function) Terraform can consume its outputs for Key Vault, storage, and resource group.

## What gets created

- **Resource group** — Name: `{prefix}-rg` (e.g. `rg-*-rg` with random suffix).
- **Virtual network** and **two subnets** — Subnet 1 has service endpoints for Key Vault and Storage and delegation for `Microsoft.App/environments` (e.g. for Azure Functions VNet integration). Subnet 2 is for general use.
- **Key Vault** — RBAC-only (`rbac_authorization_enabled = true`). Network rules restrict access to allowed IPs and the VNet/subnet.
- **Storage account** — Standard LRS, same network rules (allowed IPs + subnet).
- **Application Insights** — For the ML workspace.
- **Machine Learning workspace** — Basic SKU, system-assigned identity, managed network (internet outbound). Optional workspace-level IP allowlist via AzAPI.
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
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars: subscription_id, ip_rules (allowed IPs), and optionally location, prefix, environment, compute settings, tags.
   ```

2. **Initialize and apply:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Use outputs elsewhere** — After apply, you can pass outputs to the secret rotation function (see [2_secret_rotation_function/terraform/README.md](../2_secret_rotation_function/terraform/README.md)):
   ```bash
   terraform output -raw resource_group_name
   terraform output -raw key_vault_name
   terraform output -raw storage_account_name
   ```

## Main variables

| Variable | Description | Default |
|----------|-------------|--------|
| `subscription_id` | Azure subscription ID | (required) |
| `resource_group_location` | Region for the resource group | `"Sweden Central"` |
| `resource_group_name_prefix` | Prefix for the resource group name | `"rg"` |
| `environment` | Environment name (used in resource names) | `"dev"` |
| `prefix` | Prefix for Key Vault and storage names | `"ml"` |
| `ip_rules` | Allowed IPs for Key Vault and storage network rules | `["YOUR IP", "NAT IP"]` |
| `compute_cluster_min_node_count` | Min nodes for the ML compute cluster | `0` |
| `compute_cluster_max_node_count` | Max nodes for the ML compute cluster | `1` |
| `compute_cluster_vm_priority` | `Dedicated` or `LowPriority` | `"Dedicated"` |
| `compute_cluster_vm_size` | VM size for compute nodes | `"Standard_DS3_v2"` |
| `tags` | Tags applied to all resources | (see `variables.tf`) |

## Outputs

| Output | Description |
|--------|-------------|
| `resource_group_name` | Name of the created resource group |
| `virtual_network_name` | Name of the VNet |
| `subnet_name_1` | Name of subnet 1 (Key Vault/Storage/service endpoints) |
| `subnet_name_2` | Name of subnet 2 |
| `key_vault_name` | Name of the workspace Key Vault |
| `storage_account_name` | Name of the workspace storage account |
| `machine_learning_workspace_name` | Name of the ML workspace |
| `machine_learning_compute_cluster_name` | Name of the compute cluster |

These outputs are used by [2_secret_rotation_function](../2_secret_rotation_function) when applying with Option B (passing workspace outputs via `-var`).

## Providers

- **azurerm** (~> 4.0) — Resource group, VNet, subnets, Key Vault, storage, Application Insights, ML workspace, compute cluster, RBAC.
- **azapi** (~> 2.0) — Workspace IP allowlist (`ipAllowlist`) via `azapi_update_resource`.
- **random** (~> 3.0) — Name suffixes for resource group, Key Vault, and storage.

## Notes

- **Key Vault** uses RBAC only; assign roles (e.g. Key Vault Secrets User, Key Vault Secrets Officer) to identities that need access. The compute cluster is granted Key Vault Secrets User automatically.
- **Network rules** — Key Vault and storage default to `Deny` with access only from `ip_rules` and the specified subnet. Ensure your client IP (or NAT) is in `ip_rules` so Terraform and the Azure portal can access them.
- **terraform.tfvars** is typically in `.gitignore`; do not commit secrets or environment-specific values.
