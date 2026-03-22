# (c) JFrog Ltd (2026).
# ──────────────────────────────────────────────
# Data sources
# ──────────────────────────────────────────────

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}
