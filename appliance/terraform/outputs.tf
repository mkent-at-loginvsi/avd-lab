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
