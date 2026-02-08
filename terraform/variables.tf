# ──────────────────────────────────────────────
# General
# ──────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "jfrog-azureml-integration"
    managed_by  = "terraform"
    environment = "production"
  }
}

# ──────────────────────────────────────────────
# Key Vault
# ──────────────────────────────────────────────

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
}

variable "key_vault_sku" {
  description = "SKU name for Key Vault (standard or premium)"
  type        = string
  default     = "standard"
}

variable "secret_expiry_days" {
  description = "Number of days until the Artifactory token secret expires (used for initial secret creation)"
  type        = number
  default     = 90
}

variable "near_expiry_days_before" {
  description = "Number of days before expiry to trigger the SecretNearExpiry event"
  type        = number
  default     = 30
}

# ──────────────────────────────────────────────
# Artifactory
# ──────────────────────────────────────────────

variable "artifactory_url" {
  description = "Base URL of the JFrog Artifactory instance (e.g. https://myorg.jfrog.io)"
  type        = string
}

variable "jfrog_oidc_provider_name" {
  description = "Name of the OIDC provider configured in JFrog Platform for Azure AD token exchange"
  type        = string
}

variable "azure_ad_token_audience" {
  description = "Audience (scope) for the Azure AD token, typically api://<app-registration-client-id>"
  type        = string
}

variable "artifactory_token_secret_name" {
  description = "Name of the Key Vault secret that stores the Artifactory access token"
  type        = string
  default     = "artifactory-access-token"
}

variable "artifactory_username_secret_name" {
  description = "Name of the Key Vault secret that stores the Artifactory username"
  type        = string
  default     = "artifactory-username"
}

# ──────────────────────────────────────────────
# Function App
# ──────────────────────────────────────────────

variable "function_app_name" {
  description = "Name of the Azure Function App"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the storage account for the Function App"
  type        = string
}

variable "function_python_version" {
  description = "Python version for the Function App runtime"
  type        = string
  default     = "3.11"
}

variable "function_app_sku" {
  description = "SKU for the Function App service plan (FC1 for Flex Consumption, Y1 for Consumption)"
  type        = string
  default     = "Y1"
}

# ──────────────────────────────────────────────
# Identity (optional user-assigned managed identity)
# ──────────────────────────────────────────────

variable "user_assigned_identity_name" {
  description = "Name of the user-assigned managed identity for the Function App"
  type        = string
  default     = null
}

variable "existing_user_assigned_identity_id" {
  description = "Resource ID of an existing user-assigned managed identity. If set, a new identity will not be created."
  type        = string
  default     = null
}
