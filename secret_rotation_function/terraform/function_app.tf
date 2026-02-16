
# ──────────────────────────────────────────────
# App Service Plan (Linux Flex Consumption FC1)
# ──────────────────────────────────────────────

resource "azurerm_service_plan" "function_plan" {
  name                = "${var.function_app_name}-plan"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "FC1"

  tags = merge(var.tags, { SecurityControl = "ignore" })
}

# ──────────────────────────────────────────────
# Flex Consumption Function App (Python)
# ──────────────────────────────────────────────

resource "azurerm_function_app_flex_consumption" "function_app" {
  name                = var.function_app_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.function_plan.id

  # Storage — connection-string auth for deployment container
  storage_container_type          = "blobContainer"
  storage_container_endpoint      = "${data.azurerm_storage_account.existing.primary_blob_endpoint}${var.function_storage_container_name}"
  storage_authentication_type     = "StorageAccountConnectionString"
  storage_access_key              = data.azurerm_storage_account.existing.primary_access_key

  runtime_name    = "python"
  runtime_version = var.function_python_version

  maximum_instance_count = var.maximum_instance_count
  instance_memory_in_mb  = var.instance_memory_in_mb

  identity {
    type = "SystemAssigned"
  }

  site_config {
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }

  app_settings = {
    KEY_VAULT_NAME                = var.key_vault_name
    ARTIFACTORY_URL               = var.artifactory_url
    JFROG_OIDC_PROVIDER_NAME      = var.jfrog_oidc_provider_name
    AZURE_AD_TOKEN_AUDIENCE       = var.azure_ad_token_audience
    ARTIFACTORY_TOKEN_SECRET_NAME = var.artifactory_token_secret_name
    SECRET_TTL                    = var.secret_ttl
    AZURE_CLIENT_ID               = var.azure_ad_token_audience
    AzureWebJobsStorage           = data.azurerm_storage_account.existing.primary_connection_string
  }

  tags = merge(var.tags, { SecurityControl = "ignore" })
}
