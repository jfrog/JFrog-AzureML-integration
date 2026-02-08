# ──────────────────────────────────────────────
# Event Grid System Topic (Key Vault events)
# ──────────────────────────────────────────────

resource "azurerm_eventgrid_system_topic" "keyvault_events" {
  name                   = "${var.key_vault_name}-events"
  resource_group_name    = data.azurerm_resource_group.rg.name
  location               = var.location
  source_resource_id = data.azurerm_key_vault.kv.id
  topic_type             = "Microsoft.KeyVault.vaults"

  tags = var.tags
}

# ──────────────────────────────────────────────
# Event Grid Subscription
# Routes SecretNearExpiry events to the Azure Function
# ──────────────────────────────────────────────

resource "azurerm_eventgrid_system_topic_event_subscription" "secret_near_expiry" {
  name                = "secret-near-expiry-rotation"
  system_topic        = azurerm_eventgrid_system_topic.keyvault_events.name
  resource_group_name = data.azurerm_resource_group.rg.name

  # Filter to only SecretNearExpiry events
  included_event_types = [
    "Microsoft.KeyVault.SecretNearExpiry"
  ]

  # Optional: filter to only the Artifactory token secret
  subject_filter {
    subject_begins_with = var.artifactory_token_secret_name
  }

  # Route events to the Azure Function
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.function_app.id}/functions/KeyVaultSecretRotation"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }
}
