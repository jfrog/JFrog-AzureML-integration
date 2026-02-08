# ──────────────────────────────────────────────
# VNet and Subnets (for storage private endpoint and Function App integration)
# Supports: new VNet, existing VNet + create subnets, existing VNet + existing subnets
# ──────────────────────────────────────────────

# Create new VNet when existing_vnet_name is null
resource "azurerm_virtual_network" "vnet" {
  count               = var.existing_vnet_name == null ? 1 : 0
  name                = var.function_app_vnet_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  address_space       = var.function_app_vnet_address_space

  tags = var.tags
}

# Look up existing VNet when existing_vnet_name is set
data "azurerm_virtual_network" "existing" {
  count               = var.existing_vnet_name != null ? 1 : 0
  name                = var.existing_vnet_name
  resource_group_name = coalesce(var.existing_vnet_resource_group_name, var.resource_group_name)
}

# Effective VNet name, resource group, and id (created or existing)
locals {
  vnet_name                = var.existing_vnet_name != null ? data.azurerm_virtual_network.existing[0].name : azurerm_virtual_network.vnet[0].name
  vnet_resource_group_name = var.existing_vnet_name != null ? data.azurerm_virtual_network.existing[0].resource_group_name : azurerm_virtual_network.vnet[0].resource_group_name
  vnet_id                  = var.existing_vnet_name != null ? data.azurerm_virtual_network.existing[0].id : azurerm_virtual_network.vnet[0].id
}

# Create private-endpoint subnet when not using existing subnets
resource "azurerm_subnet" "storage_private_endpoint" {
  count                = (var.existing_vnet_name == null || var.existing_storage_private_endpoint_subnet_name == null) ? 1 : 0
  name                 = var.storage_private_endpoint_subnet_name
  resource_group_name  = local.vnet_resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.storage_private_endpoint_subnet_prefix]
}

# Create Function App integration subnet when not using existing subnets.
# Flex Consumption (FC1) requires delegation to Microsoft.App/environments.
# Prerequisite: register the Microsoft.App resource provider in the subscription
# (e.g. az provider register -n Microsoft.App); Terraform does not register it.
resource "azurerm_subnet" "function_app" {
  count                = (var.existing_vnet_name == null || var.existing_function_app_integration_subnet_name == null) ? 1 : 0
  name                 = var.function_app_integration_subnet_name
  resource_group_name  = local.vnet_resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.function_app_integration_subnet_prefix]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "func-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Look up existing private-endpoint subnet when existing VNet and subnet name are set
data "azurerm_subnet" "storage_private_endpoint" {
  count                = var.existing_vnet_name != null && var.existing_storage_private_endpoint_subnet_name != null ? 1 : 0
  name                 = var.existing_storage_private_endpoint_subnet_name
  virtual_network_name = local.vnet_name
  resource_group_name  = local.vnet_resource_group_name
}

# Look up existing Function App integration subnet when existing VNet and subnet name are set.
# For Flex Consumption (FC1) that subnet must already have delegation Microsoft.App/environments.
# Terraform cannot change a subnet that is only read via data source. Add delegation once, e.g.:
#   az network vnet subnet update \
#     --resource-group <vnet-resource-group> \
#     --vnet-name <vnet-name> \
#     --name <existing_function_app_integration_subnet_name> \
#     --delegations Microsoft.App/environments
data "azurerm_subnet" "function_app" {
  count                = var.existing_vnet_name != null && var.existing_function_app_integration_subnet_name != null ? 1 : 0
  name                 = var.existing_function_app_integration_subnet_name
  virtual_network_name = local.vnet_name
  resource_group_name  = local.vnet_resource_group_name
}

# Effective subnet IDs for private endpoint and Function App (created or existing)
locals {
  storage_private_endpoint_subnet_id = var.existing_vnet_name != null && var.existing_storage_private_endpoint_subnet_name != null ? data.azurerm_subnet.storage_private_endpoint[0].id : azurerm_subnet.storage_private_endpoint[0].id
  function_app_integration_subnet_id = var.existing_vnet_name != null && var.existing_function_app_integration_subnet_name != null ? data.azurerm_subnet.function_app[0].id : azurerm_subnet.function_app[0].id
}
