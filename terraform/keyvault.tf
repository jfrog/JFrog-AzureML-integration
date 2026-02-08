# Try to fetch existing Key Vault
data "azurerm_key_vault" "existing" {
  name                = "my-keyvault-name"
  resource_group_name = "my-resource-group"
  
  # This will fail if not found, so we handle it
  count = can(data.azurerm_key_vault.existing) ? 1 : 0
}
# Get current Azure client configuration

# Try to fetch existing Storage Account
data "azurerm_storage_account" "existing" {
  name                = "mystorageaccount123"
  resource_group_name = "my-resource-group"
  
  # Handle gracefully if not found
  count = try(data.azurerm_storage_account.existing.id, null) != null ? 1 : 0
}

# Create Storage Account only if it doesn't exist
resource "azurerm_storage_account" "storage" {
  count = length(data.azurerm_storage_account.existing) == 0 ? 1 : 0
  
  name                     = "mystorageaccount123"
  resource_group_name      = "my-resource-group"
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = {
    environment = "dev"
    managed_by  = "terraform"
  }
}

# ──────────────────────────────────────────────
# Azure Key Vault
# ──────────────────────────────────────────────

resource "azurerm_key_vault" "kv" {
  count                      = length(data.azurerm_key_vault.existing) == 0 ? 1 : 0
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  rbac_authorization_enabled = true

  tags = var.tags
}

# ──────────────────────────────────────────────
# RBAC: Grant the Function App identity access to Key Vault secrets
# ──────────────────────────────────────────────

# The Function App system-assigned identity needs to get and set secrets
resource "azurerm_role_assignment" "function_kv_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_linux_function_app.function_app.identity[0].principal_id
}

# Grant the deploying user/service principal access to manage secrets (for initial setup)
resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# If a user-assigned identity is used, also grant it Key Vault access
resource "azurerm_role_assignment" "user_identity_kv_secrets_officer" {
  count = local.identity_principal_id != null ? 1 : 0

  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = local.identity_principal_id
}