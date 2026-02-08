



# ──────────────────────────────────────────────
# Azure Key Vault
# ──────────────────────────────────────────────
data "azurerm_key_vault" "kv" {
  name                = var.key_vault_name
  resource_group_name = data.azurerm_resource_group.rg.name
}


# ──────────────────────────────────────────────
# RBAC: Grant the Function App identity access to Key Vault secrets
# ──────────────────────────────────────────────

# The Function App system-assigned identity needs to get and set secrets
resource "azurerm_role_assignment" "function_kv_secrets_officer" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_linux_function_app.function_app.identity[0].principal_id
}

# Grant the deploying user/service principal access to manage secrets (for initial setup)
#resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
#  scope                = data.azurerm_key_vault.kv.id
#  role_definition_name = "Key Vault Secrets Officer"
#  principal_id         = data.azurerm_client_config.current.object_id
#}

## TODO: haiza check if can be remove
# If a user-assigned identity is used, also grant it Key Vault access
resource "azurerm_role_assignment" "user_identity_kv_secrets_officer" {

  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = local.identity_principal_id
}