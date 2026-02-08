# ──────────────────────────────────────────────────────
# Import existing resources into Terraform state
# ──────────────────────────────────────────────────────
#
# If any of the resources below already exist in Azure,
# uncomment the relevant import block and set the correct
# resource ID. Then run:
#
#   terraform plan
#
# Terraform will adopt the existing resource into its state
# instead of trying to create a new one.
#
# After a successful import you can leave the block in place
# (it is idempotent) or remove it.
# ──────────────────────────────────────────────────────

# import {
#   to = azurerm_key_vault.kv
#   id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/providers/Microsoft.KeyVault/vaults/<KV_NAME>"
# }

# import {
#   to = azurerm_storage_account.function_storage
#   id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/providers/Microsoft.Storage/storageAccounts/<STORAGE_NAME>"
# }

# import {
#   to = azurerm_service_plan.function_plan
#   id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/providers/Microsoft.Web/serverFarms/<PLAN_NAME>"
# }

# import {
#   to = azurerm_application_insights.function_insights
#   id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/providers/Microsoft.Insights/components/<INSIGHTS_NAME>"
# }

# import {
#   to = azurerm_linux_function_app.function_app
#   id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/providers/Microsoft.Web/sites/<FUNCTION_APP_NAME>"
# }

# import {
#   to = azurerm_eventgrid_system_topic.keyvault_events
#   id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/providers/Microsoft.EventGrid/systemTopics/<TOPIC_NAME>"
# }

# import {
#   to = azurerm_eventgrid_system_topic_event_subscription.secret_near_expiry
#   id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/providers/Microsoft.EventGrid/systemTopics/<TOPIC_NAME>/eventSubscriptions/<SUBSCRIPTION_NAME>"
# }
