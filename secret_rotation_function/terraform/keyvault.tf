# ──────────────────────────────────────────────
# Existing Azure ML workspace Key Vault (data source only)
# ──────────────────────────────────────────────

data "azurerm_key_vault" "existing" {
  name                = var.key_vault_name
  resource_group_name = coalesce(var.key_vault_resource_group_name, var.resource_group_name)
}

# ──────────────────────────────────────────────
# RBAC: Grant the Function App identity access to Key Vault secrets
# ──────────────────────────────────────────────

resource "azurerm_role_assignment" "function_kv_secrets_officer" {
  scope                = data.azurerm_key_vault.existing.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_function_app_flex_consumption.function_app.identity[0].principal_id

  depends_on = [azurerm_function_app_flex_consumption.function_app]
}
