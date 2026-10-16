# Optional Windows 11 launcher machine in the appliance's subnet. It reaches the appliance over
# the private network, and you reach it with RDP from admin_source_cidr. Uses vm_admin_username /
# vm_admin_password, like the appliance VM.
#
# Windows 11 Pro on Azure needs a Windows client license that entitles you to run it there
# (e.g. Microsoft 365 E3/E5, Business Premium, or Windows VDA); license_type tells Azure you
# have one. Remove it if you don't.

resource "azurerm_public_ip" "launcher" {
  count               = var.deploy_launcher ? 1 : 0
  name                = "pip-launcher-${random_id.suffix.hex}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.labmgr_tags
}

resource "azurerm_network_interface" "launcher" {
  count               = var.deploy_launcher ? 1 : 0
  name                = "nic-launcher-${random_id.suffix.hex}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  tags                = var.labmgr_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.launcher[0].id
  }
}

# The subnet's NSG only opens 443/22 for the appliance; the launcher also needs RDP. A separate
# rule resource keeps the appliance NSG definition untouched when the launcher is off.
resource "azurerm_network_security_rule" "launcher_rdp" {
  count                       = var.deploy_launcher ? 1 : 0
  name                        = "AllowRDPFromAdmin"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = var.admin_source_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.resource_group_name
  network_security_group_name = azurerm_network_security_group.lab.name
}

resource "azurerm_windows_virtual_machine" "launcher" {
  count                 = var.deploy_launcher ? 1 : 0
  name                  = "vm-launcher"
  computer_name         = "le-launcher"
  location              = local.resource_group_location
  resource_group_name   = local.resource_group_name
  size                  = var.launcher_vm_size
  admin_username        = var.vm_admin_username
  admin_password        = var.vm_admin_password
  network_interface_ids = [azurerm_network_interface.launcher[0].id]
  license_type          = "Windows_Client"
  tags                  = var.labmgr_tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-pro"
    version   = "latest"
  }
}
