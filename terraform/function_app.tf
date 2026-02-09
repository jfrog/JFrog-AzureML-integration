# ──────────────────────────────────────────────
# Random suffix for storage account name (when var.function_app_storage_account_name is null)
# ──────────────────────────────────────────────

resource "random_string" "storage_suffix" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  function_app_storage_account_name = coalesce(var.function_app_storage_account_name, "func${random_string.storage_suffix.result}")
}

# ──────────────────────────────────────────────
# Storage Account (for Azure Functions runtime)
# ──────────────────────────────────────────────

resource "azurerm_storage_account" "function_storage" {
  name                     = local.function_app_storage_account_name
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = var.tags
}

# ──────────────────────────────────────────────
# Storage network rules (applied AFTER function app creation)
# The function app must exist and have VNet integration active before
# the storage firewall is locked down, otherwise the Azure control
# plane cannot reach storage during provisioning (→ 500).
# ──────────────────────────────────────────────

resource "azurerm_storage_account_network_rules" "function_storage_rules" {
  storage_account_id         = azurerm_storage_account.function_storage.id
  default_action             = "Deny"
  bypass                     = ["AzureServices"]
  virtual_network_subnet_ids = [local.function_app_integration_subnet_id]

  depends_on = [
    azurerm_function_app_flex_consumption.function_app
  ]
}

# ──────────────────────────────────────────────
# Blob container for Flex Consumption (host metadata and deployment)
# ──────────────────────────────────────────────

resource "azurerm_storage_container" "function_flex" {
  name                  = "function-app-flex"
  storage_account_id    = azurerm_storage_account.function_storage.id
  container_access_type = "private"
}

# ──────────────────────────────────────────────
# Private endpoint for storage (blob only)
# ──────────────────────────────────────────────

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${local.function_app_storage_account_name}-blob-pe"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  subnet_id           = local.storage_private_endpoint_subnet_id

  private_service_connection {
    name                           = "storage-blob-connection"
    private_connection_resource_id = azurerm_storage_account.function_storage.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# ──────────────────────────────────────────────
# App Service Plan (Consumption / Flex Consumption)
# Azure does not allow in-place SKU change from Dynamic (Y1) to FlexConsumption (FC1),
# so we use a distinct plan name for FC1 and create_before_destroy to create the new plan
# first, then migrate the function app, then remove the old plan.
# ──────────────────────────────────────────────

resource "azurerm_service_plan" "function_plan" {
  name                = var.function_app_sku == "FC1" ? "${var.function_app_name}-flex-plan" : "${var.function_app_name}-plan"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}


# ──────────────────────────────────────────────
# Function App (Flex Consumption, Python)
# PREREQUISITE: Register the Microsoft.App provider in the subscription:
#   az provider register -n Microsoft.App --subscription <subscription-id>
# ──────────────────────────────────────────────

resource "azurerm_function_app_flex_consumption" "function_app" {
  name                       = var.function_app_name
  resource_group_name        = data.azurerm_resource_group.rg.name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.function_plan.id
  storage_container_type     = "blobContainer"
  storage_container_endpoint = "${azurerm_storage_account.function_storage.primary_blob_endpoint}${azurerm_storage_container.function_flex.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key         = azurerm_storage_account.function_storage.primary_access_key
  runtime_name               = "python"
  runtime_version            = var.function_python_version
  virtual_network_subnet_id  = local.function_app_integration_subnet_id
  maximum_instance_count    = 50
  instance_memory_in_mb     = 2048

  site_config {}

  identity {
    type         = local.identity_id != null ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = local.identity_id != null ? [local.identity_id] : []
  }

  app_settings = {
    # Token rotation configuration (FUNCTIONS_WORKER_RUNTIME not allowed on Flex Consumption; runtime set by resource)
    KEY_VAULT_NAME                = var.key_vault_name
    ARTIFACTORY_URL               = var.artifactory_url
    JFROG_OIDC_PROVIDER_NAME      = var.jfrog_oidc_provider_name
    AZURE_AD_TOKEN_AUDIENCE       = var.azure_ad_token_audience
    ARTIFACTORY_TOKEN_SECRET_NAME = var.artifactory_token_secret_name
    AzureWebJobsStorage           = var.azure_web_jobs_storage 

    # User-assigned managed identity client ID (if applicable)
    AZURE_CLIENT_ID = local.identity_client_id != null ? local.identity_client_id : ""
  }

  tags = var.tags
}
