
# ──────────────────────────────────────────────
# App Service Plan (Linux Flex Consumption FC1)
# ──────────────────────────────────────────────

resource "azurerm_service_plan" "function_plan" {
  name                = "${var.function_app_name}-plan"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "FC1"

  tags = var.tags
}

# ──────────────────────────────────────────────
# Flex Consumption Function App (Python)
# ──────────────────────────────────────────────

resource "azurerm_function_app_flex_consumption" "function_app" {
  name                = var.function_app_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.function_plan.id

  # Storage — managed identity auth for deployment container
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${data.azurerm_storage_account.existing.primary_blob_endpoint}${var.function_storage_container_name}"
  storage_authentication_type = "SystemAssignedIdentity"

  runtime_name    = "python"
  runtime_version = var.function_python_version

  maximum_instance_count = var.maximum_instance_count
  instance_memory_in_mb  = var.instance_memory_in_mb

  # VNet integration for private outbound access to storage & Key Vault
  # TODO: Switch to the subnet that will be created as data source
  # Note: user can choose either to bootstrap AML workspace or to bring their own workspace
  virtual_network_subnet_id = azurerm_subnet.function_integration.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }

    # SCM: restrict to deployer IPs for zip deployment
    # TODO: Keep it, pass it via variable and add it to the README
    scm_use_main_ip_restriction       = false
    scm_ip_restriction_default_action = length(var.deployer_ip_addresses) > 0 ? "Deny" : "Allow"

    dynamic "scm_ip_restriction" {
      for_each = var.deployer_ip_addresses
      content {
        name       = "deployer-${scm_ip_restriction.key}"
        ip_address = scm_ip_restriction.value
        action     = "Allow"
        priority   = 100 + scm_ip_restriction.key
      }
    }

    # Main site: keep open (HTTP trigger must remain callable)
    ip_restriction_default_action = "Allow"
  }

  app_settings = {
    KEY_VAULT_NAME                   = var.key_vault_name
    ARTIFACTORY_URL                  = var.artifactory_url
    JFROG_OIDC_PROVIDER_NAME         = var.jfrog_oidc_provider_name
    AZURE_AD_TOKEN_AUDIENCE          = var.azure_ad_token_audience
    ARTIFACTORY_TOKEN_SECRET_NAME    = var.artifactory_token_secret_name
    SECRET_TTL                       = var.secret_ttl
    AZURE_CLIENT_ID                  = var.azure_ad_token_audience
    AzureWebJobsStorage__accountName = data.azurerm_storage_account.existing.name
    WEBSITE_VNET_ROUTE_ALL           = "1"
    WEBSITE_CONTENTOVERVNET          = "1"
  }

  tags = var.tags
}
