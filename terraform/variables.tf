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



variable "function_python_version" {
  description = "Python version for the Function App runtime"
  type        = string
  default     = "3.11"
}

variable "function_app_sku" {
  description = "SKU for the Function App service plan (FC1 for Flex Consumption with VNet support, Y1 for Consumption)"
  type        = string
  default     = "FC1"
}

variable "azure_web_jobs_storage" {
  description = "Storage related variable for function app"
  type        = string
}

variable "function_app_storage_account_name" {
  description = "Name of the storage account for the Function App (3-24 chars, lowercase alphanumeric, globally unique). When null, a random name (prefix 'func' + 8 random chars) is used."
  type        = string
  default     = null
}

variable "storage_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs and containers in the Function App storage account"
  type        = number
  default     = 30
}

# ──────────────────────────────────────────────
# VNet and subnets (storage private endpoint + Function App integration)
# ──────────────────────────────────────────────

variable "existing_vnet_name" {
  description = "When set, use this existing VNet (data source) instead of creating one. When null, create a new VNet."
  type        = string
  default     = null
}

variable "existing_vnet_resource_group_name" {
  description = "Resource group of the existing VNet. When null, use var.resource_group_name."
  type        = string
  default     = null
}

variable "function_app_vnet_name" {
  description = "Name of the VNet to create (used only when existing_vnet_name is null)."
  type        = string
  default     = null
}

variable "function_app_vnet_address_space" {
  description = "Address space for the VNet to create (e.g. [\"10.0.0.0/16\"]). Used only when existing_vnet_name is null."
  type        = list(string)
  default     = null
}

variable "existing_storage_private_endpoint_subnet_name" {
  description = "Name of the existing subnet for the storage private endpoint. When set with existing_function_app_integration_subnet_name, Terraform looks up both subnets and does not create any."
  type        = string
  default     = null
}

variable "existing_function_app_integration_subnet_name" {
  description = "Name of the existing subnet for Function App VNet integration. For Flex Consumption (FC1) it must be delegated to Microsoft.App/environments (Terraform cannot set this on a data-source subnet; add via Azure Portal or CLI before apply)."
  type        = string
  default     = null
}

variable "storage_private_endpoint_subnet_name" {
  description = "Name of the subnet for the storage private endpoint (used when creating the subnet)."
  type        = string
  default     = "snet-storage-private-endpoint"
}

variable "storage_private_endpoint_subnet_prefix" {
  description = "Address prefix for the storage private endpoint subnet (e.g. 10.0.1.0/24)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "function_app_integration_subnet_name" {
  description = "Name of the subnet for Function App VNet integration (used when creating the subnet)."
  type        = string
  default     = "snet-function-app"
}

variable "function_app_integration_subnet_prefix" {
  description = "Address prefix for the Function App integration subnet (e.g. 10.0.2.0/24)."
  type        = string
  default     = "10.0.2.0/24"
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
