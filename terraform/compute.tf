locals {
  enable_winrm_command = join(" ; ", [
    "Enable-PSRemoting -Force",
    "Set-Item -Path WSMan:\\localhost\\Service\\Auth\\Basic -Value $true",
    "Set-Item -Path WSMan:\\localhost\\Service\\AllowUnencrypted -Value $true",
    "New-NetFirewallRule -Name WinRM5985 -DisplayName 'WinRM 5985' -Protocol TCP -LocalPort 5985 -Direction Inbound -Action Allow -ErrorAction SilentlyContinue",
  ])
}

# --- Domain controller ---

resource "azurerm_public_ip" "dc" {
  name                = "pip-dc-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.labmgr_tags
}

resource "azurerm_network_interface" "dc" {
  name                = "nic-dc-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.labmgr_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.dc_private_ip
    public_ip_address_id          = azurerm_public_ip.dc.id
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                  = "vm-dc"
  computer_name         = "DC01"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.vm_size_dc
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc.id]
  tags                  = var.labmgr_tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "dc_winrm" {
  name                       = "enable-winrm"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -NonInteractive -Command \"${local.enable_winrm_command}\""
  })
}

# --- AVD session hosts ---

resource "azurerm_public_ip" "session_host" {
  count               = var.session_host_count
  name                = "pip-sh-${count.index}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.labmgr_tags
}

resource "azurerm_network_interface" "session_host" {
  count               = var.session_host_count
  name                = "nic-sh-${count.index}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.labmgr_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.session_host_ips[count.index]
    public_ip_address_id          = azurerm_public_ip.session_host[count.index].id
  }
}

resource "azurerm_windows_virtual_machine" "session_host" {
  count                 = var.session_host_count
  name                  = "vm-sh-${count.index}"
  computer_name         = "SH${count.index}"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.vm_size_session_host
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.session_host[count.index].id]
  tags                  = var.labmgr_tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-23h2-avd"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "session_host_winrm" {
  count                      = var.session_host_count
  name                       = "enable-winrm"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -NonInteractive -Command \"${local.enable_winrm_command}\""
  })
}
