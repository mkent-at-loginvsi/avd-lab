output "resource_group_name" {
  description = "Resource group holding every resource in this lab instance"
  value       = local.resource_group_name
}

output "appliance_public_ip" {
  description = "Public IP of the Login Enterprise appliance"
  value       = azurerm_public_ip.appliance.ip_address
}

output "appliance_fqdn" {
  description = "Public DNS name of the appliance"
  value       = azurerm_public_ip.appliance.fqdn
}

output "appliance_url" {
  description = "Login Enterprise web UI (self-signed certificate until you replace it)"
  value       = "https://${azurerm_public_ip.appliance.fqdn}"
}

output "launcher_public_ip" {
  description = "Public IP of the Windows 11 launcher (empty when deploy_launcher is false)"
  value       = var.deploy_launcher ? azurerm_public_ip.launcher[0].ip_address : ""
}

output "launcher_private_ip" {
  description = "Private IP of the launcher inside the appliance's network"
  value       = var.deploy_launcher ? azurerm_network_interface.launcher[0].private_ip_address : ""
}
