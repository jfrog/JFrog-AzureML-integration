# ──────────────────────────────────────────────
# Storage Account (required by Azure Functions)
# ──────────────────────────────────────────────

resource "azurerm_storage_account" "function_storage" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = var.tags
}

# ──────────────────────────────────────────────
# App Service Plan (Consumption / Flex Consumption)
# ──────────────────────────────────────────────

resource "azurerm_service_plan" "function_plan" {
  name                = "${var.function_app_name}-plan"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku

  tags = var.tags
}

# ──────────────────────────────────────────────
# Application Insights (monitoring)
# ──────────────────────────────────────────────

resource "azurerm_application_insights" "function_insights" {
  name                = "${var.function_app_name}-insights"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  application_type    = "web"

  tags = var.tags
}

# ──────────────────────────────────────────────
# Linux Function App (Python)
# ──────────────────────────────────────────────

resource "azurerm_linux_function_app" "function_app" {
  name                       = var.function_app_name
  resource_group_name        = data.azurerm_resource_group.rg.name
  location                   = var.location
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan.id

  site_config {
    application_stack {
      python_version = var.function_python_version
    }

    ftps_state = "Disabled"
  }

  identity {
    type = local.identity_id != null ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = local.identity_id != null ? [local.identity_id] : []
  }

  app_settings = {
    # Azure Functions runtime
    FUNCTIONS_WORKER_RUNTIME       = "python"
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.function_insights.instrumentation_key

    # Token rotation configuration
    KEY_VAULT_NAME                = var.key_vault_name
    ARTIFACTORY_URL               = var.artifactory_url
    JFROG_OIDC_PROVIDER_NAME      = var.jfrog_oidc_provider_name
    AZURE_AD_TOKEN_AUDIENCE        = var.azure_ad_token_audience
    ARTIFACTORY_TOKEN_SECRET_NAME  = var.artifactory_token_secret_name

    # User-assigned managed identity client ID (if applicable)
    AZURE_CLIENT_ID = local.identity_client_id != null ? local.identity_client_id : ""
  }

  tags = var.tags
}
