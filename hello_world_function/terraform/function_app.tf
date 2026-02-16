# --- Storage Account for Function App ---

resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "function" {
  name                     = "${random_string.storage_suffix.result}azfunctions"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    SecurityControl = "Ignore"
  }
}

# --- App Service Plan (Consumption / Dynamic) ---

resource "azurerm_service_plan" "this" {
  name                = var.function_app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

# --- Application Insights ---

resource "azurerm_application_insights" "this" {
  name                = var.function_app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  application_type    = "web"
}

# --- Function App ---

resource "azurerm_linux_function_app" "this" {
  name                       = var.function_app_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  service_plan_id            = azurerm_service_plan.this.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      dotnet_version = "6.0"
    }
  }

  app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"            = "~4"
    "FUNCTIONS_WORKER_RUNTIME"               = "dotnet"
    "APPINSIGHTS_INSTRUMENTATIONKEY"         = azurerm_application_insights.this.instrumentation_key
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.function.primary_connection_string
    "WEBSITE_CONTENTSHARE"                   = lower(var.function_app_name)
  }

  tags = {
    SecurityControl = "Ignore"
  }
}

# --- Source Control Deployment ---

resource "azurerm_app_service_source_control" "this" {
  app_id   = azurerm_linux_function_app.this.id
  repo_url = var.repo_url
  branch   = "main"
}
