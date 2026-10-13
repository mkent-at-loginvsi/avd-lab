locals {
  dc_host = {
    (azurerm_windows_virtual_machine.dc.name) = {
      ansible_host                         = azurerm_public_ip.dc.ip_address
      ansible_user                         = var.admin_username
      ansible_password                     = var.admin_password
      ansible_connection                   = "winrm"
      ansible_winrm_transport              = "basic"
      ansible_port                         = 5985
      ansible_winrm_server_cert_validation = "ignore"
    }
  }

  session_host_hosts = {
    for idx in range(var.session_host_count) :
    azurerm_windows_virtual_machine.session_host[idx].name => {
      ansible_host                         = azurerm_public_ip.session_host[idx].ip_address
      ansible_user                         = var.admin_username
      ansible_password                     = var.admin_password
      ansible_connection                   = "winrm"
      ansible_winrm_transport              = "basic"
      ansible_port                         = 5985
      ansible_winrm_server_cert_validation = "ignore"
    }
  }
}

output "ansible_inventory" {
  description = "Ansible JSON inventory consumed by Lab Manager after terraform apply"
  sensitive   = true
  value = {
    all = {
      children = {
        domain_controllers = {
          hosts = local.dc_host
        }
        session_hosts = {
          hosts = local.session_host_hosts
        }
      }
      vars = {
        domain_name            = var.domain_name
        avd_registration_token = azurerm_virtual_desktop_host_pool_registration_info.lab.token
      }
    }
  }
}

output "resource_group_name" {
  description = "Resource group holding every resource in this lab instance"
  value       = azurerm_resource_group.lab.name
}

output "avd_workspace_name" {
  description = "AVD workspace name, for reference when connecting a client"
  value       = azurerm_virtual_desktop_workspace.lab.name
}
