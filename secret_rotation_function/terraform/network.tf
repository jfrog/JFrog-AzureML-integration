# All of this needs to be removed
# ──────────────────────────────────────────────
# Existing customer VNet (data source only)
# ──────────────────────────────────────────────


data "azurerm_virtual_network" "existing" {
  name                = var.existing_vnet_name
  resource_group_name = coalesce(var.existing_vnet_resource_group_name, var.resource_group_name)
}

# ──────────────────────────────────────────────
# Subnet: Function App VNet integration
# Delegation: Microsoft.App/environments (required for Flex Consumption)
# ──────────────────────────────────────────────

resource "azurerm_subnet" "function_integration" {
  name                 = var.function_subnet_name
  resource_group_name  = data.azurerm_virtual_network.existing.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  address_prefixes     = var.function_subnet_address_prefixes
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "flex-consumption-delegation"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# ──────────────────────────────────────────────
# Private DNS Zones (optional)
# Required for the function app to resolve storage/Key Vault
# private endpoint addresses. A private Azure ML workspace
# typically already has these — set create_private_dns_zones = false
# to skip.
# ──────────────────────────────────────────────

locals {
  private_dns_zones = {
    blob  = "privatelink.blob.core.windows.net"
    table = "privatelink.table.core.windows.net"
    queue = "privatelink.queue.core.windows.net"
    file  = "privatelink.file.core.windows.net"
    vault = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = var.create_private_dns_zones ? local.private_dns_zones : {}
  name                = each.value
  resource_group_name = data.azurerm_resource_group.rg.name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = var.create_private_dns_zones ? local.private_dns_zones : {}
  name                  = "link-${each.key}"
  resource_group_name   = data.azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = data.azurerm_virtual_network.existing.id

  tags = var.tags
}
