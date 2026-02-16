variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "akvrotation"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "resource_name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "akvrotation"
}

variable "sql_admin_login" {
  description = "SQL administrator login"
  type        = string
  default     = "sqlAdmin"
}

variable "sql_admin_password" {
  description = "SQL administrator password"
  type        = string
  sensitive   = true
  default     = "Simple123"
}

variable "function_app_name" {
  description = "The name of the function app"
  type        = string
  default     = "akvrotation-fnapp"
}

variable "secret_name" {
  description = "The name of the secret where SQL password is stored"
  type        = string
  default     = "sqlPassword"
}

variable "repo_url" {
  description = "GitHub repository URL containing the rotation function code"
  type        = string
  default     = "https://github.com/Azure-Samples/KeyVault-Rotation-SQLPassword-Csharp.git"
}
