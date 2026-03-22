# (c) JFrog Ltd (2026).
# ──────────────────────────────────────────────
# Existing Azure ML workspace storage account (data source only)
# ──────────────────────────────────────────────

data "azurerm_storage_account" "existing" {
  name                = var.existing_storage_account_name
  resource_group_name = coalesce(var.existing_storage_resource_group_name, var.resource_group_name)
}

# ──────────────────────────────────────────────
# Dedicated blob container for the Azure Function only
# (not the container used by Azure ML pipelines)
# ──────────────────────────────────────────────

resource "azurerm_storage_container" "function" {
  name                  = var.function_storage_container_name
  storage_account_id    = data.azurerm_storage_account.existing.id
  container_access_type = "private"
}

# ──────────────────────────────────────────────
# RBAC: Grant the Function App identity access to the existing storage account
# (required for identity-based AzureWebJobsStorage; host uses Blob, Table, and Queue)
# ──────────────────────────────────────────────

resource "azurerm_role_assignment" "function_storage_blob" {
  scope                = data.azurerm_storage_account.existing.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_function_app_flex_consumption.function_app.identity[0].principal_id

  depends_on = [azurerm_function_app_flex_consumption.function_app]
}

resource "azurerm_role_assignment" "function_storage_table" {
  scope                = data.azurerm_storage_account.existing.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.function_app.identity[0].principal_id

  depends_on = [azurerm_function_app_flex_consumption.function_app]
}

resource "azurerm_role_assignment" "function_storage_queue" {
  scope                = data.azurerm_storage_account.existing.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.function_app.identity[0].principal_id

  depends_on = [azurerm_function_app_flex_consumption.function_app]
}

resource "azurerm_role_assignment" "function_storage_account_contributor" {
  scope                = data.azurerm_storage_account.existing.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_function_app_flex_consumption.function_app.identity[0].principal_id

  depends_on = [azurerm_function_app_flex_consumption.function_app]
}