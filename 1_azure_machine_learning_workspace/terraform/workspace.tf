
# Dependent resources for Azure Machine Learning
resource "azurerm_application_insights" "default" {
  name                = "${random_pet.prefix.id}-appi"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}

resource "azurerm_key_vault" "default" {
  name                        = "${var.prefix}${var.environment}${random_integer.suffix.result}kv"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  rbac_authorization_enabled  = true
  public_network_access_enabled = true
  purge_protection_enabled    = true
  soft_delete_retention_days = 7
    network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.ip_rules
    virtual_network_subnet_ids = [azurerm_subnet.my_terraform_subnet_1.id,azurerm_subnet.my_terraform_subnet_2.id]
  }
   tags = var.tags

   depends_on = [azurerm_virtual_network.my_terraform_network]
}

resource "azurerm_storage_account" "default" {
  name                            = "${var.prefix}${var.environment}${random_integer.suffix.result}st"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  public_network_access_enabled     = true
  network_rules {
    bypass                     = ["AzureServices"]
    default_action             = "Deny"
    ip_rules                   = var.ip_rules
    virtual_network_subnet_ids = [azurerm_subnet.my_terraform_subnet_1.id,azurerm_subnet.my_terraform_subnet_2.id]
  }
  blob_properties {
    delete_retention_policy {
      days = 7 # Retention period in days (1 to 365); policy is enabled when days is set
    }
  }
  tags = var.tags
  depends_on = [azurerm_virtual_network.my_terraform_network]
}

# Machine Learning workspace (uses existing container registry via var.container_registry_id)
resource "azurerm_machine_learning_workspace" "default" {
  name                          = "${random_pet.prefix.id}-mlw"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  application_insights_id       = azurerm_application_insights.default.id
  key_vault_id                  = azurerm_key_vault.default.id
  storage_account_id            = azurerm_storage_account.default.id
  public_network_access_enabled = true
  sku_name                      = "Basic"

  identity {
    type = "SystemAssigned"
  }
    managed_network {
    isolation_mode                = "AllowInternetOutbound"
    provision_on_creation_enabled = false
  }
    tags = var.tags
}

resource "azapi_update_resource" "update_workspace" {
  type        = "Microsoft.MachineLearningServices/workspaces@2024-04-01-preview"
  resource_id = azurerm_machine_learning_workspace.default.id
  body = {
    properties = {
      ipAllowlist = var.ip_rules
    }
  }

  depends_on = [azurerm_private_endpoint.workspace]
}

# ──────────────────────────────────────────────
# Private endpoint for ML workspace (subnet-2)
# ──────────────────────────────────────────────

resource "azurerm_private_dns_zone" "aml" {
  name                = "privatelink.api.azureml.ms"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml" {
  name                  = "${random_pet.prefix.id}-aml-dns-vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.aml.name
  virtual_network_id    = azurerm_virtual_network.my_terraform_network.id
}

resource "azurerm_private_endpoint" "workspace" {
  name                = "${random_pet.prefix.id}-mlw-pe"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.my_terraform_subnet_2.id

  private_service_connection {
    name                           = "${random_pet.prefix.id}-mlw-psc"
    private_connection_resource_id = azurerm_machine_learning_workspace.default.id
    subresource_names              = ["amlworkspace"]
    is_manual_connection            = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.aml.id]
  }

  tags = var.tags
}