# ──────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────

output "resource_group_name" {
  description = "Name of the resource group"
  value       = data.azurerm_resource_group.rg.name
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_function_app_flex_consumption.function_app.id
}

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_function_app_flex_consumption.function_app.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_function_app_flex_consumption.function_app.default_hostname
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App system-assigned managed identity"
  value       = azurerm_function_app_flex_consumption.function_app.identity[0].principal_id
}

output "storage_account_name" {
  description = "Name of the existing storage account used by the function app"
  value       = data.azurerm_storage_account.existing.name
}

output "storage_container_name" {
  description = "Name of the dedicated blob container for the function (in the existing storage account)"
  value       = azurerm_storage_container.function.name
}

output "key_vault_id" {
  description = "Resource ID of the existing Key Vault"
  value       = data.azurerm_key_vault.existing.id
}

output "key_vault_uri" {
  description = "URI of the existing Key Vault"
  value       = data.azurerm_key_vault.existing.vault_uri
}
