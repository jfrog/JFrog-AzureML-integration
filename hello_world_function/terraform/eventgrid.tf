# Event Grid subscription for Key Vault SecretNearExpiry events

resource "azurerm_eventgrid_system_topic" "keyvault" {
  name                   = "${var.resource_name_prefix}-kv-topic"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  source_arm_resource_id = azurerm_key_vault.this.id
  topic_type             = "Microsoft.KeyVault.vaults"
}

resource "azurerm_eventgrid_system_topic_event_subscription" "secret_near_expiry" {
  name                = "${azurerm_key_vault.this.name}-${var.secret_name}-${var.function_app_name}"
  system_topic        = azurerm_eventgrid_system_topic.keyvault.name
  resource_group_name = azurerm_resource_group.this.name

  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.this.id}/functions/AKVSQLRotation"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  subject_filter {
    subject_begins_with = var.secret_name
    subject_ends_with   = var.secret_name
  }

  included_event_types = [
    "Microsoft.KeyVault.SecretNearExpiry",
  ]

  depends_on = [
    azurerm_app_service_source_control.this,
  ]
}
