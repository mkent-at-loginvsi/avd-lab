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
  default     = "Standard_D2s_v4"
}

variable "vm_size_session_host" {
  type        = string
  description = "VM size for each AVD session host"
  default     = "Standard_D2s_v4"
}

variable "session_host_count" {
  type        = number
  description = "Number of AVD session hosts to deploy into the pooled host pool"
  default     = 2
}

variable "avd_user_object_id" {
  type        = string
  description = "Additional Entra ID object ID (user or group) to grant the published desktop and VM login to; leave blank to skip"
  default     = ""
}

variable "test_user_count" {
  type        = number
  description = "Number of Entra ID test users to create (testuser01, testuser02, ...); also the number of AD accounts if the domain controller is deployed"
  default     = 50
}

variable "test_user_password" {
  type        = string
  description = "Shared password for the Entra ID test users (must meet Entra password complexity); also used for the AD accounts when the DC is deployed"
  sensitive   = true
}

variable "deploy_domain_controller" {
  type        = bool
  description = "Also deploy a Windows Server domain controller running a standalone AD forest whose session hosts are domain-joined and whose users are synced to Entra by Cloud Sync; when false the hosts are Entra-joined with cloud test users"
  default     = false
}

variable "labmgr_tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource; populated by Lab Manager"
  default     = {}
}

variable "remote_apps" {
  type        = map(string)
  description = "RemoteApps to publish from the session hosts, as { \"Display name\" = \"C:\\\\path\\\\app.exe\" }. The program must already be installed on every session host. Empty publishes none."
  default     = {}
}
