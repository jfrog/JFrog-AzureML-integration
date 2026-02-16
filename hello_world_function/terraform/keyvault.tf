data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = "${var.resource_name_prefix}-kv"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false

  tags = {
    SecurityControl = "Ignore"
  }
}

# Access policy for the Function App managed identity
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.this.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
  ]
}
