
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
  purge_protection_enabled    = false
    network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.ip_rules
    virtual_network_subnet_ids = [azurerm_subnet.my_terraform_subnet_1.id]
  }
   tags = var.tags
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
    virtual_network_subnet_ids = [azurerm_subnet.my_terraform_subnet_1.id]
  }
  tags = var.tags
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
}