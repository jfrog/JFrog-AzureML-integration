# (c) JFrog Ltd (2026).
# Data source for current Azure client config (tenant_id, etc.)
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = "${random_pet.prefix.id}-rg"
  tags     = var.tags
}

resource "random_pet" "prefix" {
  prefix = var.resource_group_name_prefix
  length = 2
}

resource "random_integer" "suffix" {
  min = 10000000
  max = 99999999
}