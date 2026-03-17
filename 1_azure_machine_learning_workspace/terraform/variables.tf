variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "resource_group_location" {
  type        = string
  default     = "Sweden Central"
  description = "Location of the resource group."
}

variable "resource_group_name_prefix" {
  type        = string
  default     = "rg"
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

variable "environment" {
  type        = string
  description = "Name of the environment"
  default     = "dev"
}


variable "prefix" {
  type        = string
  description = "Prefix of the resource name"
  default     = "ml"
}

variable "ip_rules" {
  type        = list(string)
  description = "A list of allowed IPs for Key Vault and Storage network rules"
  default     = ["YOUR IP", "NAT IP"]
}


variable "compute_cluster_min_node_count" {
  type        = number
  description = "Minimum number of nodes for the ML compute cluster scale settings."
  default     = 0
}

variable "compute_cluster_max_node_count" {
  type        = number
  description = "Maximum number of nodes for the ML compute cluster scale settings."
  default     = 1
}

variable "compute_cluster_vm_priority" {
  type        = string
  description = "VM priority for the ML compute cluster: Dedicated or LowPriority."
  default     = "Dedicated"
}

variable "compute_cluster_vm_size" {
  type        = string
  description = "VM size for the ML compute cluster (e.g. Standard_DS3_v2)."
  default     = "Standard_DS3_v2"
}

variable "compute_cluster_name" {
  type        = string
  description = "Compute cluster name."
  default     = "azureml-poc-cluster"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "jfrog-azureml-integration"
    managed_by  = "terraform"
    environment = "dev"
    application = "azureml"
  }
}