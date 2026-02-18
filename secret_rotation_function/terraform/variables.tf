# ──────────────────────────────────────────────
# General
# ──────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group for the Function App and related resources"
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
# Existing Azure ML workspace Key Vault
# ──────────────────────────────────────────────

variable "key_vault_name" {
  description = "Name of the existing Azure ML workspace Key Vault"
  type        = string
}

variable "key_vault_resource_group_name" {
  description = "Resource group of the existing Key Vault. When null, uses resource_group_name."
  type        = string
  default     = null
}

# ──────────────────────────────────────────────
# Existing Azure ML workspace Storage Account
# ──────────────────────────────────────────────

variable "existing_storage_account_name" {
  description = "Name of the existing Azure ML workspace storage account"
  type        = string
}

variable "existing_storage_resource_group_name" {
  description = "Resource group of the existing storage account. When null, uses resource_group_name."
  type        = string
  default     = null
}

variable "function_storage_container_name" {
  description = "Name of the dedicated blob container for the Azure Function (created in the existing storage account; not the container used by Azure ML pipelines)"
  type        = string
  default     = "azure-function-token-rotation"
}

# ──────────────────────────────────────────────
# Artifactory / token rotation
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

variable "secret_ttl" {
  description = "Secret TTL in seconds (e.g. 21600 for 6 hours). Used by the function for timer schedule."
  type        = string
  default     = "21600"
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
  default     = "3.12"
}

variable "maximum_instance_count" {
  description = "Maximum number of instances for the Flex Consumption function app"
  type        = number
  default     = 100
}

variable "instance_memory_in_mb" {
  description = "Memory allocation per instance in MB for the Flex Consumption function app"
  type        = number
  default     = 2048
}

# ──────────────────────────────────────────────
# Networking (existing customer VNet)
# ──────────────────────────────────────────────

variable "existing_vnet_name" {
  description = "Name of the existing customer VNet (from Azure ML workspace)"
  type        = string
}

variable "existing_vnet_resource_group_name" {
  description = "Resource group of the existing VNet. When null, uses resource_group_name."
  type        = string
  default     = null
}

variable "function_subnet_name" {
  description = "Name of the subnet to create for Function App VNet integration"
  type        = string
  default     = "snet-function-integration"
}

variable "function_subnet_address_prefixes" {
  description = "Address prefixes for the Function App integration subnet"
  type        = list(string)
}

variable "deployer_ip_addresses" {
  description = "CIDR ranges allowed to access Function App SCM for zip deployment (e.g. [\"1.2.3.4/32\"])"
  type        = list(string)
  default     = []
}

variable "create_private_dns_zones" {
  description = "Whether to create private DNS zones for storage/Key Vault and link them to the VNet. Set to false if the customer's Azure ML workspace already has them."
  type        = bool
  default     = true
}

