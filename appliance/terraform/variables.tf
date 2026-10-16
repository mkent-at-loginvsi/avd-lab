variable "location" {
  type        = string
  description = "Azure region to deploy the lab into"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name; when create_resource_group is true, empty generates rg-leappliance-<suffix>, otherwise it must name an existing group"
  default     = ""
}

variable "create_resource_group" {
  type        = bool
  description = "Create the resource group (true) or deploy into an existing one named resource_group_name (false); an existing group is never deleted by destroy"
  default     = true
}

variable "vhd_source_url" {
  type        = string
  description = "https URL the appliance VHD can be downloaded from (Login VSI Azure VHD download link, or a SAS URL to a copy you host); Azure copies it server-side into the lab's storage account"
  sensitive   = true

  validation {
    condition     = can(regex("^https://", var.vhd_source_url))
    error_message = "vhd_source_url must be an https:// URL."
  }
}

variable "appliance_admin_password" {
  type        = string
  description = "Password for the appliance's admin/root accounts; Base64-encoded (ASCII) and delivered via cloud-init"
  sensitive   = true

  validation {
    condition     = can(regex("^[\\x20-\\x7E]+$", var.appliance_admin_password))
    error_message = "appliance_admin_password must be printable ASCII only (the appliance expects an ASCII-encoded Base64 password)."
  }
}

variable "dns_hostname" {
  type        = string
  description = "Hostname of the VM and its public DNS name: <dns_hostname>.<location>.cloudapp.azure.com. Empty generates le-<suffix>."
  default     = "leappliance"

  validation {
    condition     = var.dns_hostname == "" || can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.dns_hostname))
    error_message = "dns_hostname must be 2-63 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "appliance_domain_name" {
  type        = string
  description = "Domain name configured on the appliance during first run. Empty uses the regional zone (<location>.cloudapp.azure.com); the appliance's address is then <dns_hostname>.<zone>."
  default     = ""
}

variable "vm_admin_username" {
  type        = string
  description = "Azure VM admin account; separate from the appliance admin"
  default     = "azureadministrator"
}

variable "vm_admin_password" {
  type        = string
  description = "Password for vm_admin_username"
  sensitive   = true
}

variable "admin_source_cidr" {
  type        = string
  description = "CIDR allowed to reach the appliance on HTTPS (443) and SSH (22), e.g. your workstation's public IP/32"
}

variable "vm_size" {
  type        = string
  description = "VM size; appliance minimum is 4 vCPU / 8 GB RAM and the size must support Generation 1 VMs"
  default     = "Standard_D4s_v4"
}

variable "labmgr_tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource; populated by Lab Manager"
  default     = {}
}

variable "deploy_launcher" {
  type        = bool
  description = "Also deploy a Windows 11 launcher VM in the appliance's network (RDP from admin_source_cidr)"
  default     = false
}

variable "launcher_vm_size" {
  type        = string
  description = "Launcher VM size. Windows 11 needs at least 2 vCPU / 4 GB and a Gen 2 capable size."
  default     = "Standard_B2s"
}
