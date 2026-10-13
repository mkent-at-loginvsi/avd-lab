variable "location" {
  type        = string
  description = "Azure region to deploy the lab into"
  default     = "eastus"
}

variable "domain_name" {
  type        = string
  description = "Fully-qualified DNS name for the new Active Directory forest"
  default     = "corp.labmgr.local"
}

variable "admin_username" {
  type        = string
  description = "Local admin on every VM; becomes the domain admin once the DC is promoted"
  default     = "labadmin"
}

variable "admin_password" {
  type        = string
  description = "Password for admin_username; also used as the DSRM/safe-mode password during DC promotion"
  sensitive   = true
}

variable "admin_source_cidr" {
  type        = string
  description = "CIDR allowed to reach RDP (3389) and WinRM (5985) on every VM, e.g. your workstation's public IP/32"
}

variable "vm_size_dc" {
  type        = string
  description = "VM size for the domain controller"
  default     = "Standard_B2ms"
}

variable "vm_size_session_host" {
  type        = string
  description = "VM size for each AVD session host"
  default     = "Standard_D2s_v5"
}

variable "session_host_count" {
  type        = number
  description = "Number of AVD session hosts to deploy into the pooled host pool"
  default     = 2
}

variable "avd_user_object_id" {
  type        = string
  description = "Entra ID object ID (user or group) to grant access to the published desktop; leave blank to skip role assignment"
  default     = ""
}

variable "test_user_count" {
  type        = number
  description = "Number of AD test accounts to create; not used by Terraform, only declared so Lab Manager can pass it through to Ansible"
  default     = 50
}

variable "test_user_password" {
  type        = string
  description = "Shared password for the AD test accounts; not used by Terraform, only declared so Lab Manager can pass it through to Ansible"
  sensitive   = true
}

variable "labmgr_tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource; populated by Lab Manager"
  default     = {}
}
