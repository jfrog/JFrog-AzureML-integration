# ──────────────────────────────────────────────
# App Service Plan (Linux Consumption Y1)
# ──────────────────────────────────────────────

resource "azurerm_service_plan" "function_plan" {
  name                = "${var.function_app_name}-plan"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = var.tags
}

# ──────────────────────────────────────────────
# Linux Function App (Python, Consumption)
# ──────────────────────────────────────────────

resource "azurerm_linux_function_app" "function_app" {
  name                          = var.function_app_name
  resource_group_name           = data.azurerm_resource_group.rg.name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.function_plan.id
  storage_account_name          = data.azurerm_storage_account.existing.name
  
  # 1. This enables Identity-based connection (Modern approach)
  storage_uses_managed_identity = true

  functions_extension_version = "~4"

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    KEY_VAULT_NAME                = var.key_vault_name
    ARTIFACTORY_URL               = var.artifactory_url
    JFROG_OIDC_PROVIDER_NAME      = var.jfrog_oidc_provider_name
    AZURE_AD_TOKEN_AUDIENCE       = var.azure_ad_token_audience
    ARTIFACTORY_TOKEN_SECRET_NAME = var.artifactory_token_secret_name
    SECRET_TTL                    = var.secret_ttl
    AZURE_CLIENT_ID               = var.azure_ad_token_audience
    AzureWebJobsStorage           = var.azure_web_jobs_storage

    # Enable Remote Build (zip deploy with --build-remote; func publish may still need storage key for upload)
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"

    # 4. FIXED: Check if this variable is correct. Usually this is the User Assigned ID client ID.
    # AZURE_CLIENT_ID             = var.azure_client_id 
  }

  site_config {
    application_stack {
      python_version = var.function_python_version
    }
  }

  tags = var.tags
}

# 5. REQUIRED: Grant the Function App permission to access storage
resource "azurerm_role_assignment" "storage_blob_data_owner" {
  scope                = data.azurerm_storage_account.existing.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.function_app.identity[0].principal_id
}