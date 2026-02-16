output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "sql_server_name" {
  value = azurerm_mssql_server.sql.name
}

output "sql_server_2_name" {
  value = azurerm_mssql_server.sql2.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.this.name
}

output "function_app_default_hostname" {
  value = azurerm_linux_function_app.this.default_hostname
}

output "function_app_identity_principal_id" {
  value = azurerm_linux_function_app.this.identity[0].principal_id
}
