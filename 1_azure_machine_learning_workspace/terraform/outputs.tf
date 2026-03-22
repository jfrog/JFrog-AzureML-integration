# (c) JFrog Ltd (2026).
#Resource Group
output "resource_group_name" {
  description = "The name of the created resource group."
  value       = azurerm_resource_group.rg.name
}

# Virtual Network outputs
output "virtual_network_name" {
  description = "The name of the created virtual network."
  value       = azurerm_virtual_network.my_terraform_network.name
}

output "subnet_name_1" {
  description = "The name of the created subnet 1."
  value       = azurerm_subnet.my_terraform_subnet_1.name
}

output "subnet_id_1" {
  description = "Resource ID of subnet 1 (for VNet integration)."
  value       = azurerm_subnet.my_terraform_subnet_1.id
}

output "subnet_name_2" {
  description = "The name of the created subnet 2."
  value       = azurerm_subnet.my_terraform_subnet_2.name
}

#Azure Machine Learning outputs
output "key_vault_name" {
  value = azurerm_key_vault.default.name
}

output "storage_account_name" {
  value = azurerm_storage_account.default.name
}

output "machine_learning_workspace_name" {
  value = azurerm_machine_learning_workspace.default.name
}

output "machine_learning_compute_cluster_name" {
  value = azurerm_machine_learning_compute_cluster.compute.name
}