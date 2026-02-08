# ──────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = data.azurerm_key_vault.kv.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       =  data.azurerm_key_vault.kv.vault_uri
}

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.function_app.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.function_app.default_hostname
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App system-assigned managed identity"
  value       = azurerm_linux_function_app.function_app.identity[0].principal_id
}

output "event_grid_system_topic_id" {
  description = "Resource ID of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.keyvault_events.id
}




