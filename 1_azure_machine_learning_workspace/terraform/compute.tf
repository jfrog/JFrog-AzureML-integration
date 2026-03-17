# Wait 120s after workspace and private endpoint (subnet_2, VNET) are ready before creating compute cluster
resource "time_sleep" "before_compute" {
  create_duration = "120s"

  depends_on = [
    azurerm_machine_learning_workspace.default,
    azurerm_private_endpoint.workspace,
    azurerm_virtual_network.my_terraform_network,
    azurerm_subnet.my_terraform_subnet_2,
  ]
}

# Azure Machine Learning
# Compute Cluster
resource "azurerm_machine_learning_compute_cluster" "compute" {
  name                          = var.compute_cluster_name
  location                      = azurerm_resource_group.rg.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.default.id
  vm_priority                   = var.compute_cluster_vm_priority
  vm_size                       = var.compute_cluster_vm_size


  identity {
    type = "SystemAssigned"
  }

  scale_settings {
    min_node_count                       = var.compute_cluster_min_node_count
    max_node_count                       = var.compute_cluster_max_node_count
    scale_down_nodes_after_idle_duration = "PT2M" # 2 minutes
  }
  tags = var.tags

  depends_on = [time_sleep.before_compute]
}

# ──────────────────────────────────────────────
# RBAC: Compute cluster identity — read workspace Key Vault, read/write workspace storage
# ──────────────────────────────────────────────

resource "azurerm_role_assignment" "compute_kv_secrets_user" {
  scope                = azurerm_key_vault.default.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_machine_learning_compute_cluster.compute.identity[0].principal_id
}

resource "azurerm_role_assignment" "compute_storage_blob_contributor" {
  scope                = azurerm_storage_account.default.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_compute_cluster.compute.identity[0].principal_id
}