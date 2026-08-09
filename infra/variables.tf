### --- New resources (VM, NIC, public IP, NSG) --- ###

variable "resource_group_name" {
  description = "Resource group to create for the VM, NIC, public IP, and NSG."
  type        = string
  default     = "rg-iis-demo"
}

variable "location" {
  description = "Azure region for the new resources. Should match your existing VNet's region."
  type        = string
  default     = "East US"
}

variable "prefix" {
  description = "Prefix used to name new resources."
  type        = string
  default     = "iisdemo"
}

variable "vm_size" {
  description = "Size of the Windows VM."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Local administrator username for the VM."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Local administrator password for the VM. Must meet Azure complexity requirements."
  type        = string
  sensitive   = true
}

variable "allowed_rdp_source" {
  description = "CIDR range allowed to RDP into the VM (lock this down to your own IP in production). Set to \"\" to skip creating the RDP rule entirely."
  type        = string
  default     = "*"
}

### --- Existing resources to reuse --- ###

variable "existing_storage_account_name" {
  description = "Name of your EXISTING storage account that will host IIS.ps1."
  type        = string
}

variable "existing_storage_account_rg" {
  description = "Resource group that contains the existing storage account."
  type        = string
}

variable "container_name" {
  description = "Blob container name to create/use inside the existing storage account for the script."
  type        = string
  default     = "scripts"
}

variable "existing_vnet_name" {
  description = "Name of your EXISTING virtual network."
  type        = string
}

variable "existing_vnet_rg" {
  description = "Resource group that contains the existing virtual network."
  type        = string
}

variable "existing_subnet_name" {
  description = "Name of the EXISTING subnet (inside the existing VNet) to deploy the VM's NIC into."
  type        = string
}

### --- Script + health check --- ###

variable "script_local_path" {
  description = "Local path to the IIS.ps1 script that will be uploaded to blob storage."
  type        = string
  default     = "./IIS.ps1"
}

variable "health_check_retries" {
  description = "How many times to poll the site URL after deployment before giving up."
  type        = number
  default     = 20
}

variable "health_check_interval_seconds" {
  description = "Seconds to wait between health check attempts."
  type        = number
  default     = 15
}
