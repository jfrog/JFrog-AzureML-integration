# ──────────────────────────────────────────────
# Data sources
# ──────────────────────────────────────────────

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# ──────────────────────────────────────────────
# User-Assigned Managed Identity
# (used by the Function App for Key Vault and Azure AD access)
# ──────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "function_identity" {
  # count = var.existing_user_assigned_identity_id == null && var.user_assigned_identity_name != null ? 1 : 0

  name                = var.user_assigned_identity_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags
}

locals {
  identity_id = var.existing_user_assigned_identity_id != null ? var.existing_user_assigned_identity_id : azurerm_user_assigned_identity.function_identity.id

  identity_principal_id = var.existing_user_assigned_identity_id != null ? null : azurerm_user_assigned_identity.function_identity.principal_id

  identity_client_id = var.existing_user_assigned_identity_id != null ? null : azurerm_user_assigned_identity.function_identity.client_id
}
